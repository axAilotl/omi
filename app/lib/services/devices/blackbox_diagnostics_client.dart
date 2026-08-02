import 'dart:async';

import 'package:omi/services/devices/blackbox_protocol.dart';
import 'package:omi/services/devices/connectors/device_connection.dart';

class BlackboxDiagnosticsClient {
  final DeviceConnection connection;

  const BlackboxDiagnosticsClient(this.connection);

  Future<List<int>> _request(List<int> command, bool Function(List<int>) matches) async {
    final completer = Completer<List<int>>();
    final stream = connection.transport.getCharacteristicStream(
      BlackboxProtocol.serviceUuid,
      BlackboxProtocol.commandCharacteristicUuid,
    );
    late final StreamSubscription<List<int>> subscription;
    subscription = stream.listen((value) {
      if (!completer.isCompleted && matches(value)) completer.complete(value);
    });
    try {
      await connection.transport.writeCharacteristic(
        BlackboxProtocol.serviceUuid,
        BlackboxProtocol.commandCharacteristicUuid,
        command,
      );
      return await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      await subscription.cancel();
    }
  }

  Future<BlackboxSnapshot?> snapshot() async {
    try {
      BlackboxSnapshot? snapshot;
      final counters = <String, int>{};
      var counterStart = 0;
      for (var pageNumber = 0; pageNumber < 8; pageNumber++) {
        final value = await _request(BlackboxProtocol.snapshotCommand(counterStart), (value) {
          final page = BlackboxProtocol.parseSnapshot(value);
          return page != null && page.counterStart == counterStart;
        });
        final page = BlackboxProtocol.parseSnapshot(value);
        if (page == null) return null;
        snapshot ??= page;
        counters.addAll(page.counters);
        if (!page.hasMoreCounters) {
          return snapshot.withCounters(counters, hasMore: false, start: 0);
        }
        if (page.nextCounterIndex <= counterStart) return null;
        counterStart = page.nextCounterIndex;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> startTrace({Duration ttl = const Duration(hours: 12)}) async {
    return _ack(BlackboxProtocol.startTraceCommand(ttl), BlackboxProtocol.commandStartTrace);
  }

  Future<bool> stopTrace() async {
    return _ack(const [BlackboxProtocol.commandStopTrace], BlackboxProtocol.commandStopTrace);
  }

  Future<bool> clearTrace() async {
    return _ack(const [BlackboxProtocol.commandClearTrace], BlackboxProtocol.commandClearTrace);
  }

  Future<bool> _ack(List<int> command, int expectedCommand) async {
    try {
      final value = await _request(command, (value) {
        final ack = BlackboxProtocol.parseAck(value);
        return ack != null && ack.command == expectedCommand;
      });
      final ack = BlackboxProtocol.parseAck(value);
      return ack != null && ack.status == 0;
    } catch (_) {
      return false;
    }
  }

  Future<List<BlackboxEvent>> readAllEvents() async {
    final events = <BlackboxEvent>[];
    var cursor = 0;
    for (var pageNumber = 0; pageNumber < 100; pageNumber++) {
      final value = await _request(
        BlackboxProtocol.readTraceCommand(cursor),
        (value) => value.isNotEmpty && value[0] == BlackboxProtocol.responseTrace,
      );
      final page = BlackboxProtocol.parseTracePage(value);
      if (page == null) throw const FormatException('Invalid black-box trace page');
      events.addAll(page.events);
      if (!page.hasMore) return events;
      if (page.nextSequence <= cursor) throw StateError('Black-box trace cursor did not advance');
      cursor = page.nextSequence;
    }
    throw StateError('Black-box trace exceeded the bounded 100-page export');
  }
}
