import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/pages/settings/blackbox_dfu_harness.dart';
import 'package:omi/pages/settings/blackbox_export_harness.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/services/wals/wal.dart';
import 'package:omi/utils/blackbox_firmware_artifact.dart';

void main() {
  test('internal DFU harness accepts only its exact opt-in URI', () {
    expect(
      BlackboxDfuHarnessPolicy.matches(Uri.parse('omi://blackbox/dfu'), enabled: true),
      isTrue,
    );
    expect(
      BlackboxDfuHarnessPolicy.matches(Uri.parse('omi://blackbox/dfu'), enabled: false),
      isFalse,
    );
    expect(
      BlackboxDfuHarnessPolicy.matches(Uri.parse('omi://blackbox/clear'), enabled: true),
      isFalse,
    );
    expect(
      BlackboxDfuHarnessPolicy.matches(Uri.parse('https://blackbox/dfu'), enabled: true),
      isFalse,
    );
  });

  test('internal DFU harness claims a duplicated cold-start link once', () {
    final gate = BlackboxDfuLaunchGate(enabled: true);
    final uri = Uri.parse('omi://blackbox/dfu');

    expect(gate.claim(uri), isTrue);
    expect(gate.claim(uri), isFalse);
  });

  test('internal DFU harness accepts physical GATT when live audio is unhealthy', () {
    final device = BtDevice(name: 'Omi', id: 'cv1', type: DeviceType.omi, rssi: -40);

    expect(BlackboxDfuHarnessPolicy.canStart(device, hasGattConnection: true), isTrue);
    expect(BlackboxDfuHarnessPolicy.canStart(device, hasGattConnection: false), isFalse);
    expect(
      BlackboxDfuHarnessPolicy.canStart(
        BtDevice(name: 'Other', id: 'other', type: DeviceType.limitless, rssi: -40),
        hasGattConnection: true,
      ),
      isFalse,
    );
  });

  test('build-specific DFU preflight verifies filename, ZIP, manifest, image hashes, and MCUboot header', () {
    final fixture = _firmwareFixture();
    final result = BlackboxFirmwareArtifactVerifier.verify(
      fileName: fixture.expectation.fileName,
      zipBytes: fixture.zipBytes,
      expectation: fixture.expectation,
    );

    expect(result.version, '3.0.30+110');
    expect(result.zipSha256, fixture.expectation.zipSha256);
    expect(result.summary, contains('ZIP ${fixture.expectation.zipSha256.substring(0, 8)}'));
  });

  test('DFU preflight rejects same-name artifacts with different bytes or identity metadata', () {
    final fixture = _firmwareFixture();
    final tampered = Uint8List.fromList(fixture.zipBytes)..[fixture.zipBytes.length ~/ 2] ^= 0x01;

    expect(
      () => BlackboxFirmwareArtifactVerifier.verify(
        fileName: fixture.expectation.fileName,
        zipBytes: tampered,
        expectation: fixture.expectation,
      ),
      throwsFormatException,
    );
    expect(
      () => BlackboxFirmwareArtifactVerifier.verify(
        fileName: 'wrong.zip',
        zipBytes: fixture.zipBytes,
        expectation: fixture.expectation,
      ),
      throwsFormatException,
    );

    final wrongVersion = _copyExpectation(
      fixture.expectation,
      manifestVersion: '3.0.30+106',
    );
    expect(
      () => BlackboxFirmwareArtifactVerifier.verify(
        fileName: wrongVersion.fileName,
        zipBytes: fixture.zipBytes,
        expectation: wrongVersion,
      ),
      throwsFormatException,
    );
  });

  test('internal export harness accepts only its exact opt-in URI', () {
    expect(
      BlackboxExportHarnessPolicy.matches(Uri.parse('omi://blackbox/export'), enabled: true),
      isTrue,
    );
    expect(
      BlackboxExportHarnessPolicy.matches(Uri.parse('omi://blackbox/export'), enabled: false),
      isFalse,
    );
    expect(
      BlackboxExportHarnessPolicy.matches(Uri.parse('omi://blackbox/dfu'), enabled: true),
      isFalse,
    );
    expect(
      BlackboxExportHarnessPolicy.matches(Uri.parse('https://blackbox/export'), enabled: true),
      isFalse,
    );
  });

  test('internal export harness can inspect an unhealthy audio path', () {
    expect(
      BlackboxExportHarnessPolicy.shouldAttemptTransport(
        hasConnectedDevice: true,
        audioPathReady: false,
      ),
      isTrue,
    );
    expect(
      BlackboxExportHarnessPolicy.shouldAttemptTransport(
        hasConnectedDevice: false,
        audioPathReady: false,
      ),
      isFalse,
    );
  });

  test('internal export harness claims a duplicated cold-start link once', () {
    final gate = BlackboxExportLaunchGate(enabled: true);
    final uri = Uri.parse('omi://blackbox/export');

    expect(gate.claim(uri), isTrue);
    expect(gate.claim(uri), isFalse);
  });

  test('internal export sorts dynamically sourced WALs with a typed comparator', () {
    final later = Wal(
      timerStart: 20,
      codec: BleAudioCodec.opus,
      seconds: 1,
    );
    final earlier = Wal(
      timerStart: 10,
      codec: BleAudioCodec.opus,
      seconds: 1,
    );

    expect(
      sortedBlackboxExportWals(<Object?>[later, earlier]),
      <Wal>[earlier, later],
    );
  });
}

class _FirmwareFixture {
  const _FirmwareFixture({required this.zipBytes, required this.expectation});

  final Uint8List zipBytes;
  final BlackboxFirmwareArtifactExpectation expectation;
}

_FirmwareFixture _firmwareFixture() {
  final application = Uint8List(64);
  final header = ByteData.sublistView(application);
  header
    ..setUint32(0, 0x96f3b83d, Endian.little)
    ..setUint16(8, 32, Endian.little)
    ..setUint32(12, 32, Endian.little)
    ..setUint8(20, 3)
    ..setUint8(21, 0)
    ..setUint16(22, 30, Endian.little)
    ..setUint32(24, 110, Endian.little);
  final network = Uint8List.fromList(List<int>.generate(24, (index) => index));
  final manifest = jsonEncode({
    'format-version': 1,
    'name': 'omi',
    'files': [
      {
        'file': 'omi.signed.bin',
        'image_index': '0',
        'version_MCUBOOT': '3.0.30+110',
        'size': application.length,
      },
      {
        'file': 'ipc_radio.bin',
        'image_index': '1',
        'size': network.length,
      },
    ],
  });
  final archive = Archive()
    ..add(ArchiveFile.string('manifest.json', manifest))
    ..add(ArchiveFile.bytes('omi.signed.bin', application))
    ..add(ArchiveFile.bytes('ipc_radio.bin', network));
  final zipBytes = ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2026, 8, 4));
  final expectation = BlackboxFirmwareArtifactExpectation(
    fileName: 'fixture-build110.zip',
    zipSha256: sha256.convert(zipBytes).toString(),
    manifestVersion: '3.0.30+110',
    applicationFileName: 'omi.signed.bin',
    applicationSize: application.length,
    applicationSha256: sha256.convert(application).toString(),
    networkFileName: 'ipc_radio.bin',
    networkSize: network.length,
    networkSha256: sha256.convert(network).toString(),
    applicationVersionMajor: 3,
    applicationVersionMinor: 0,
    applicationVersionRevision: 30,
    applicationVersionBuild: 110,
  );
  return _FirmwareFixture(zipBytes: zipBytes, expectation: expectation);
}

BlackboxFirmwareArtifactExpectation _copyExpectation(
  BlackboxFirmwareArtifactExpectation source, {
  String? manifestVersion,
}) =>
    BlackboxFirmwareArtifactExpectation(
      fileName: source.fileName,
      zipSha256: source.zipSha256,
      manifestVersion: manifestVersion ?? source.manifestVersion,
      applicationFileName: source.applicationFileName,
      applicationSize: source.applicationSize,
      applicationSha256: source.applicationSha256,
      networkFileName: source.networkFileName,
      networkSize: source.networkSize,
      networkSha256: source.networkSha256,
      applicationVersionMajor: source.applicationVersionMajor,
      applicationVersionMinor: source.applicationVersionMinor,
      applicationVersionRevision: source.applicationVersionRevision,
      applicationVersionBuild: source.applicationVersionBuild,
    );
