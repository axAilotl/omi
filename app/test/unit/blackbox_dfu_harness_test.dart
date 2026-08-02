import 'package:flutter_test/flutter_test.dart';

import 'package:omi/pages/settings/blackbox_dfu_harness.dart';
import 'package:omi/pages/settings/blackbox_export_harness.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/services/wals/wal.dart';

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
