import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const String currentBlackboxFirmwareArtifactName = 'Omi_CV1_Blackbox_OTA_3.0.30_build110_SHA8ad0dad0.zip';

const BlackboxFirmwareArtifactExpectation currentBlackboxFirmwareArtifact = BlackboxFirmwareArtifactExpectation(
  fileName: currentBlackboxFirmwareArtifactName,
  zipSha256: '8ad0dad061fe637b922d5ed6667a4ac0713ebbe9539fa03ab0744b45e0dcabec',
  manifestVersion: '3.0.30+110',
  applicationFileName: 'omi.signed.bin',
  applicationSize: 264532,
  applicationSha256: '561ed42eb008440f840d0d3594b0d9cba4a516749511b0858aa8a80cc676bedf',
  networkFileName: 'ipc_radio.bin',
  networkSize: 175092,
  networkSha256: '39df96b86c94ed55dc06d282ca2d4b6c2b3103aa9f64456f8848d650d6dbe9c0',
  applicationVersionMajor: 3,
  applicationVersionMinor: 0,
  applicationVersionRevision: 30,
  applicationVersionBuild: 110,
);

class BlackboxFirmwareArtifactExpectation {
  const BlackboxFirmwareArtifactExpectation({
    required this.fileName,
    required this.zipSha256,
    required this.manifestVersion,
    required this.applicationFileName,
    required this.applicationSize,
    required this.applicationSha256,
    required this.networkFileName,
    required this.networkSize,
    required this.networkSha256,
    required this.applicationVersionMajor,
    required this.applicationVersionMinor,
    required this.applicationVersionRevision,
    required this.applicationVersionBuild,
  });

  final String fileName;
  final String zipSha256;
  final String manifestVersion;
  final String applicationFileName;
  final int applicationSize;
  final String applicationSha256;
  final String networkFileName;
  final int networkSize;
  final String networkSha256;
  final int applicationVersionMajor;
  final int applicationVersionMinor;
  final int applicationVersionRevision;
  final int applicationVersionBuild;
}

class BlackboxFirmwareArtifactVerification {
  const BlackboxFirmwareArtifactVerification({
    required this.version,
    required this.zipSha256,
    required this.applicationSha256,
    required this.networkSha256,
  });

  final String version;
  final String zipSha256;
  final String applicationSha256;
  final String networkSha256;

  String get summary =>
      '$version • ZIP ${zipSha256.substring(0, 8)} • app ${applicationSha256.substring(0, 8)} • net ${networkSha256.substring(0, 8)}';
}

class BlackboxFirmwareArtifactVerifier {
  static const int _mcubootMagic = 0x96f3b83d;
  static const Set<String> _expectedMembers = {
    'manifest.json',
    'omi.signed.bin',
    'ipc_radio.bin',
  };

  static BlackboxFirmwareArtifactVerification verify({
    required String fileName,
    required Uint8List zipBytes,
    BlackboxFirmwareArtifactExpectation expectation = currentBlackboxFirmwareArtifact,
  }) {
    if (fileName != expectation.fileName) {
      throw FormatException('Unexpected firmware filename: $fileName');
    }

    final zipHash = sha256.convert(zipBytes).toString();
    if (zipHash != expectation.zipSha256) {
      throw FormatException('Firmware ZIP SHA-256 mismatch: $zipHash');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    } catch (error) {
      throw FormatException('Firmware ZIP is unreadable: $error');
    }

    final memberNames = archive.files.where((entry) => entry.isFile).map((entry) => entry.name).toSet();
    if (memberNames.length != _expectedMembers.length || !memberNames.containsAll(_expectedMembers)) {
      throw FormatException('Unexpected firmware ZIP members: ${memberNames.toList()..sort()}');
    }

    final manifestBytes = _requiredMember(archive, 'manifest.json');
    final Map<String, dynamic> manifest;
    try {
      manifest = Map<String, dynamic>.from(jsonDecode(utf8.decode(manifestBytes)) as Map);
    } catch (error) {
      throw FormatException('Firmware manifest is invalid: $error');
    }
    if (manifest['format-version'] != 1 || manifest['name'] != 'omi') {
      throw const FormatException('Firmware manifest identity is invalid');
    }
    final files = manifest['files'];
    if (files is! List || files.length != 2) {
      throw const FormatException('Firmware manifest must contain exactly two images');
    }

    final applicationManifest = _manifestEntry(files, expectation.applicationFileName);
    final networkManifest = _manifestEntry(files, expectation.networkFileName);
    if (applicationManifest['version_MCUBOOT'] != expectation.manifestVersion ||
        applicationManifest['image_index'] != '0' ||
        applicationManifest['size'] != expectation.applicationSize) {
      throw const FormatException('Application manifest identity mismatch');
    }
    if (networkManifest['image_index'] != '1' || networkManifest['size'] != expectation.networkSize) {
      throw const FormatException('Network manifest identity mismatch');
    }

    final applicationBytes = _requiredMember(archive, expectation.applicationFileName);
    final networkBytes = _requiredMember(archive, expectation.networkFileName);
    if (applicationBytes.length != expectation.applicationSize || networkBytes.length != expectation.networkSize) {
      throw const FormatException('Firmware image size mismatch');
    }

    final applicationHash = sha256.convert(applicationBytes).toString();
    final networkHash = sha256.convert(networkBytes).toString();
    if (applicationHash != expectation.applicationSha256) {
      throw FormatException('Application SHA-256 mismatch: $applicationHash');
    }
    if (networkHash != expectation.networkSha256) {
      throw FormatException('Network SHA-256 mismatch: $networkHash');
    }

    _verifyMcubootHeader(applicationBytes, expectation);
    return BlackboxFirmwareArtifactVerification(
      version: expectation.manifestVersion,
      zipSha256: zipHash,
      applicationSha256: applicationHash,
      networkSha256: networkHash,
    );
  }

  static Uint8List _requiredMember(Archive archive, String name) {
    final member = archive.find(name);
    final bytes = member?.readBytes();
    if (member == null || !member.isFile || bytes == null) {
      throw FormatException('Firmware ZIP is missing $name');
    }
    return bytes;
  }

  static Map<String, dynamic> _manifestEntry(List<dynamic> files, String fileName) {
    for (final value in files) {
      if (value is Map && value['file'] == fileName) {
        return Map<String, dynamic>.from(value);
      }
    }
    throw FormatException('Firmware manifest is missing $fileName');
  }

  static void _verifyMcubootHeader(
    Uint8List applicationBytes,
    BlackboxFirmwareArtifactExpectation expectation,
  ) {
    if (applicationBytes.length < 28) {
      throw const FormatException('Application image is shorter than the MCUboot header');
    }
    final header = ByteData.sublistView(applicationBytes);
    if (header.getUint32(0, Endian.little) != _mcubootMagic) {
      throw const FormatException('Application MCUboot magic mismatch');
    }
    final major = header.getUint8(20);
    final minor = header.getUint8(21);
    final revision = header.getUint16(22, Endian.little);
    final build = header.getUint32(24, Endian.little);
    if (major != expectation.applicationVersionMajor ||
        minor != expectation.applicationVersionMinor ||
        revision != expectation.applicationVersionRevision ||
        build != expectation.applicationVersionBuild) {
      throw FormatException('Application MCUboot version mismatch: $major.$minor.$revision+$build');
    }
  }
}
