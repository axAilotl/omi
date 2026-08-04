import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi/services/devices/blackbox_protocol.dart';

void main() {
  test('snapshot parser preserves link, power, and named counter fields', () {
    final bytes = ByteData(52 + BlackboxProtocol.counterNames.length * 4);
    bytes.setUint8(0, BlackboxProtocol.responseSnapshot);
    bytes.setUint8(1, BlackboxProtocol.protocolVersion);
    bytes.setUint8(2, 1);
    bytes.setUint8(3, BlackboxProtocol.counterNames.length);
    bytes.setUint32(4, 7, Endian.little);
    bytes.setUint32(8, 0xA5, Endian.little);
    bytes.setUint32(12, 123456, Endian.little);
    bytes.setUint32(16, 40, Endian.little);
    bytes.setUint32(20, 55, Endian.little);
    bytes.setUint32(24, 3, Endian.little);
    bytes.setUint16(28, 15, Endian.little);
    bytes.setUint16(30, 12, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 600, Endian.little);
    bytes.setUint16(36, 498, Endian.little);
    bytes.setUint16(38, 251, Endian.little);
    bytes.setUint16(40, 251, Endian.little);
    bytes.setUint8(42, 2);
    bytes.setUint8(43, 2);
    bytes.setUint16(44, 3980, Endian.little);
    bytes.setUint8(46, 63);
    bytes.setUint8(47, 1);
    bytes.setUint8(48, 1);
    bytes.setUint8(49, 1);
    bytes.setUint8(50, 0);
    for (var i = 0; i < BlackboxProtocol.counterNames.length; i++) {
      bytes.setUint32(52 + i * 4, 1000 + i, Endian.little);
    }

    final snapshot = BlackboxProtocol.parseSnapshot(bytes.buffer.asUint8List());
    expect(snapshot, isNotNull);
    expect(snapshot!.traceEnabled, isTrue);
    expect(snapshot.hasMoreCounters, isFalse);
    expect(snapshot.bootCount, 7);
    expect(snapshot.connectionIntervalMs, 15.0);
    expect(snapshot.supervisionTimeoutMs, 6000);
    expect(snapshot.mtu, 498);
    expect(snapshot.batteryMillivolts, 3980);
    expect(snapshot.charging, isTrue);
    expect(snapshot.counters['audio_queue_full'], 1007);
    expect(snapshot.counters['diagnostic_busy'], 1038);
    expect(snapshot.counters['sync_snapshot_prefix_served'], 1040);
    expect(snapshot.counters['sync_snapshot_commit_failure'], 1041);
  });

  test('snapshot counter pages preserve their offset for MTU-safe merging', () {
    final bytes = ByteData(60);
    bytes.setUint8(0, BlackboxProtocol.responseSnapshot);
    bytes.setUint8(1, BlackboxProtocol.protocolVersion);
    bytes.setUint8(2, 3);
    bytes.setUint8(3, 2);
    bytes.setUint8(51, 30);
    bytes.setUint32(52, 41, Endian.little);
    bytes.setUint32(56, 42, Endian.little);

    final snapshot = BlackboxProtocol.parseSnapshot(bytes.buffer.asUint8List());
    expect(snapshot, isNotNull);
    expect(snapshot!.hasMoreCounters, isTrue);
    expect(snapshot.counterStart, 30);
    expect(snapshot.nextCounterIndex, 32);
    expect(snapshot.counters, {'sync_info': 41, 'sync_read': 42});
    expect(BlackboxProtocol.snapshotCommand(30), [BlackboxProtocol.commandSnapshot, 30]);
  });

  test('trace parser keeps signed errors and pagination identity', () {
    final bytes = ByteData(60);
    bytes.setUint8(0, BlackboxProtocol.responseTrace);
    bytes.setUint8(1, BlackboxProtocol.protocolVersion);
    bytes.setUint8(2, 2);
    bytes.setUint8(3, 3);
    bytes.setUint32(4, 9, Endian.little);
    bytes.setUint32(8, 11, Endian.little);
    bytes.setUint32(12, 20, Endian.little);
    bytes.setUint32(16, 8, Endian.little);
    bytes.setUint32(20, 9, Endian.little);
    bytes.setUint32(24, 100, Endian.little);
    bytes.setUint16(28, 12, Endian.little);
    bytes.setUint16(30, 0, Endian.little);
    bytes.setInt32(32, -12, Endian.little);
    bytes.setInt32(36, 2, Endian.little);
    bytes.setUint32(40, 10, Endian.little);
    bytes.setUint32(44, 110, Endian.little);
    bytes.setUint16(48, 26, Endian.little);
    bytes.setUint16(50, 0, Endian.little);
    bytes.setInt32(52, 0, Endian.little);
    bytes.setInt32(56, 1234, Endian.little);

    final page = BlackboxProtocol.parseTracePage(bytes.buffer.asUint8List());
    expect(page, isNotNull);
    expect(page!.hasMore, isTrue);
    expect(page.cursorOverwritten, isTrue);
    expect(page.events.map((event) => event.sequence), [9, 10]);
    expect(page.events.first.name, 'audio_notify_error');
    expect(page.events.first.arg0, -12);
    expect(page.events.last.name, 'sync_done');
  });

  test('trace parser names microphone recovery evidence', () {
    final bytes = ByteData(40);
    bytes.setUint8(0, BlackboxProtocol.responseTrace);
    bytes.setUint8(1, BlackboxProtocol.protocolVersion);
    bytes.setUint8(2, 1);
    bytes.setUint32(20, 12, Endian.little);
    bytes.setUint32(24, 900, Endian.little);
    bytes.setUint16(28, 30, Endian.little);
    bytes.setInt32(32, 0, Endian.little);
    bytes.setInt32(36, 6400, Endian.little);

    final page = BlackboxProtocol.parseTracePage(bytes.buffer.asUint8List());
    expect(page, isNotNull);
    expect(page!.events.single.name, 'mic_recovery');
    expect(page.events.single.arg0, 0);
    expect(page.events.single.arg1, 6400);
  });

  test('trace parser names advertising recovery evidence', () {
    final bytes = ByteData(40);
    bytes.setUint8(0, BlackboxProtocol.responseTrace);
    bytes.setUint8(1, BlackboxProtocol.protocolVersion);
    bytes.setUint8(2, 1);
    bytes.setUint32(20, 13, Endian.little);
    bytes.setUint32(24, 1200, Endian.little);
    bytes.setUint16(28, 31, Endian.little);
    bytes.setInt32(32, 0, Endian.little);
    bytes.setInt32(36, -12, Endian.little);

    final page = BlackboxProtocol.parseTracePage(bytes.buffer.asUint8List());
    expect(page, isNotNull);
    expect(page!.events.single.name, 'ble_advertising_recovery');
    expect(page.events.single.arg0, 0);
    expect(page.events.single.arg1, -12);
  });

  test('truncated payloads fail closed', () {
    expect(BlackboxProtocol.parseSnapshot([BlackboxProtocol.responseSnapshot, 1]), isNull);
    expect(BlackboxProtocol.parseTracePage([BlackboxProtocol.responseTrace, 1, 2]), isNull);
    expect(BlackboxProtocol.parseAck([BlackboxProtocol.responseAck, 1]), isNull);
  });
}
