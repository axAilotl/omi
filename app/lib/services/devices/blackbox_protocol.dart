import 'dart:typed_data';

class BlackboxProtocol {
  static const String serviceUuid = '30295790-4301-eabd-2904-2849adfeae43';
  static const String commandCharacteristicUuid = '30295791-4301-eabd-2904-2849adfeae43';

  static const int protocolVersion = 1;
  static const int commandSnapshot = 0x01;
  static const int commandStartTrace = 0x02;
  static const int commandStopTrace = 0x03;
  static const int commandReadTrace = 0x04;
  static const int commandClearTrace = 0x05;
  static const int responseAck = 0x80;
  static const int responseSnapshot = 0x81;
  static const int responseTrace = 0x82;

  static List<int> snapshotCommand([int counterStart = 0]) => [commandSnapshot, counterStart];

  static const List<String> counterNames = [
    'boot',
    'ble_connect',
    'ble_connect_error',
    'ble_disconnect',
    'link_setup_attempt',
    'link_setup_error',
    'audio_frame',
    'audio_queue_full',
    'audio_tx_slot_timeout',
    'audio_notify_accepted',
    'audio_notify_completed',
    'audio_notify_enomem',
    'audio_notify_eagain',
    'audio_notify_ebusy',
    'audio_notify_enotconn',
    'audio_notify_other_error',
    'storage_accepted',
    'storage_rejected',
    'frame_retained',
    'frame_dropped',
    'mic_buffer',
    'mic_read_error',
    'voice_gate_open',
    'voice_gate_close',
    'aad_wake',
    'aad_sleep',
    'sd_write_queued',
    'sd_write_rejected',
    'sd_health_degraded',
    'sd_health_terminal',
    'sync_info',
    'sync_read',
    'sync_advance',
    'sync_stop',
    'sync_done',
    'sync_error',
    'sync_bytes',
    'diagnostic_request',
    'diagnostic_busy',
  ];

  static const List<String> eventNames = [
    'unknown',
    'boot',
    'ble_connected',
    'ble_connect_error',
    'ble_disconnected',
    'link_params',
    'phy',
    'data_length',
    'mtu',
    'link_setup_error',
    'audio_queue_full',
    'audio_tx_timeout',
    'audio_notify_error',
    'storage_rejected',
    'frame_retained',
    'frame_dropped',
    'mic_read_error',
    'voice_gate_open',
    'voice_gate_close',
    'aad_wake',
    'aad_sleep',
    'sd_health',
    'sync_info',
    'sync_read',
    'sync_advance',
    'sync_stop',
    'sync_done',
    'sync_error',
    'trace_started',
    'trace_stopped',
  ];

  static Uint8List startTraceCommand(Duration ttl) {
    final seconds = ttl.inSeconds.clamp(1, 24 * 60 * 60);
    final data = ByteData(5);
    data.setUint8(0, commandStartTrace);
    data.setUint32(1, seconds, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List readTraceCommand(int sequence) {
    final data = ByteData(5);
    data.setUint8(0, commandReadTrace);
    data.setUint32(1, sequence, Endian.little);
    return data.buffer.asUint8List();
  }

  static BlackboxAck? parseAck(List<int> value) {
    if (value.length < 12 || value[0] != responseAck || value[1] != protocolVersion) return null;
    final data = ByteData.sublistView(Uint8List.fromList(value));
    return BlackboxAck(
      command: data.getUint8(2),
      status: data.getInt8(3),
      traceEnabled: data.getUint8(4) & 1 != 0,
      nextSequence: data.getUint32(8, Endian.little),
    );
  }

  static BlackboxSnapshot? parseSnapshot(List<int> value) {
    if (value.length < 52 || value[0] != responseSnapshot || value[1] != protocolVersion) return null;
    final data = ByteData.sublistView(Uint8List.fromList(value));
    final counterCount = data.getUint8(3);
    if (counterCount > counterNames.length || value.length < 52 + (counterCount * 4)) return null;
    final counters = <String, int>{};
    for (var i = 0; i < counterCount; i++) {
      final counterIndex = data.getUint8(51) + i;
      if (counterIndex >= counterNames.length) return null;
      counters[counterNames[counterIndex]] = data.getUint32(52 + (i * 4), Endian.little);
    }
    return BlackboxSnapshot(
      traceEnabled: data.getUint8(2) & 1 != 0,
      hasMoreCounters: data.getUint8(2) & 2 != 0,
      counterStart: data.getUint8(51),
      bootCount: data.getUint32(4, Endian.little),
      resetReason: data.getUint32(8, Endian.little),
      uptimeMs: data.getUint32(12, Endian.little),
      traceOldestSequence: data.getUint32(16, Endian.little),
      traceNextSequence: data.getUint32(20, Endian.little),
      traceOverwrittenEvents: data.getUint32(24, Endian.little),
      traceEventCount: data.getUint16(28, Endian.little),
      connectionIntervalUnits: data.getUint16(30, Endian.little),
      connectionLatency: data.getUint16(32, Endian.little),
      supervisionTimeoutUnits: data.getUint16(34, Endian.little),
      mtu: data.getUint16(36, Endian.little),
      txDataLength: data.getUint16(38, Endian.little),
      rxDataLength: data.getUint16(40, Endian.little),
      txPhy: data.getUint8(42),
      rxPhy: data.getUint8(43),
      batteryMillivolts: data.getUint16(44, Endian.little),
      batteryPercentage: data.getUint8(46),
      charging: data.getUint8(47) != 0,
      sdPowered: data.getUint8(48) != 0,
      sdReady: data.getUint8(49) != 0,
      sdHealth: data.getUint8(50),
      counters: counters,
    );
  }

  static BlackboxTracePage? parseTracePage(List<int> value) {
    if (value.length < 20 || value[0] != responseTrace || value[1] != protocolVersion) return null;
    final data = ByteData.sublistView(Uint8List.fromList(value));
    final count = data.getUint8(2);
    if (value.length < 20 + (count * 20)) return null;
    final events = <BlackboxEvent>[];
    for (var i = 0; i < count; i++) {
      final offset = 20 + (i * 20);
      final eventId = data.getUint16(offset + 8, Endian.little);
      events.add(
        BlackboxEvent(
          sequence: data.getUint32(offset, Endian.little),
          uptimeMs: data.getUint32(offset + 4, Endian.little),
          eventId: eventId,
          name: eventId < eventNames.length ? eventNames[eventId] : 'event_$eventId',
          flags: data.getUint16(offset + 10, Endian.little),
          arg0: data.getInt32(offset + 12, Endian.little),
          arg1: data.getInt32(offset + 16, Endian.little),
        ),
      );
    }
    final flags = data.getUint8(3);
    return BlackboxTracePage(
      events: events,
      hasMore: flags & 1 != 0,
      cursorOverwritten: flags & 2 != 0,
      oldestSequence: data.getUint32(4, Endian.little),
      nextSequence: data.getUint32(8, Endian.little),
      globalNextSequence: data.getUint32(12, Endian.little),
      overwrittenEvents: data.getUint32(16, Endian.little),
    );
  }
}

class BlackboxAck {
  final int command;
  final int status;
  final bool traceEnabled;
  final int nextSequence;

  const BlackboxAck({
    required this.command,
    required this.status,
    required this.traceEnabled,
    required this.nextSequence,
  });
}

class BlackboxSnapshot {
  final bool traceEnabled;
  final bool hasMoreCounters;
  final int counterStart;
  final int bootCount;
  final int resetReason;
  final int uptimeMs;
  final int traceOldestSequence;
  final int traceNextSequence;
  final int traceOverwrittenEvents;
  final int traceEventCount;
  final int connectionIntervalUnits;
  final int connectionLatency;
  final int supervisionTimeoutUnits;
  final int mtu;
  final int txDataLength;
  final int rxDataLength;
  final int txPhy;
  final int rxPhy;
  final int batteryMillivolts;
  final int batteryPercentage;
  final bool charging;
  final bool sdPowered;
  final bool sdReady;
  final int sdHealth;
  final Map<String, int> counters;

  const BlackboxSnapshot({
    required this.traceEnabled,
    required this.hasMoreCounters,
    required this.counterStart,
    required this.bootCount,
    required this.resetReason,
    required this.uptimeMs,
    required this.traceOldestSequence,
    required this.traceNextSequence,
    required this.traceOverwrittenEvents,
    required this.traceEventCount,
    required this.connectionIntervalUnits,
    required this.connectionLatency,
    required this.supervisionTimeoutUnits,
    required this.mtu,
    required this.txDataLength,
    required this.rxDataLength,
    required this.txPhy,
    required this.rxPhy,
    required this.batteryMillivolts,
    required this.batteryPercentage,
    required this.charging,
    required this.sdPowered,
    required this.sdReady,
    required this.sdHealth,
    required this.counters,
  });

  int get nextCounterIndex => counterStart + counters.length;

  BlackboxSnapshot withCounters(Map<String, int> mergedCounters, {required bool hasMore, required int start}) {
    return BlackboxSnapshot(
      traceEnabled: traceEnabled,
      hasMoreCounters: hasMore,
      counterStart: start,
      bootCount: bootCount,
      resetReason: resetReason,
      uptimeMs: uptimeMs,
      traceOldestSequence: traceOldestSequence,
      traceNextSequence: traceNextSequence,
      traceOverwrittenEvents: traceOverwrittenEvents,
      traceEventCount: traceEventCount,
      connectionIntervalUnits: connectionIntervalUnits,
      connectionLatency: connectionLatency,
      supervisionTimeoutUnits: supervisionTimeoutUnits,
      mtu: mtu,
      txDataLength: txDataLength,
      rxDataLength: rxDataLength,
      txPhy: txPhy,
      rxPhy: rxPhy,
      batteryMillivolts: batteryMillivolts,
      batteryPercentage: batteryPercentage,
      charging: charging,
      sdPowered: sdPowered,
      sdReady: sdReady,
      sdHealth: sdHealth,
      counters: mergedCounters,
    );
  }

  double get connectionIntervalMs => connectionIntervalUnits * 1.25;
  int get supervisionTimeoutMs => supervisionTimeoutUnits * 10;

  Map<String, Object> toJson() => {
        'trace_enabled': traceEnabled,
        'counter_pages_complete': !hasMoreCounters,
        'boot_count': bootCount,
        'reset_reason': resetReason,
        'uptime_ms': uptimeMs,
        'trace_oldest_sequence': traceOldestSequence,
        'trace_next_sequence': traceNextSequence,
        'trace_overwritten_events': traceOverwrittenEvents,
        'trace_event_count': traceEventCount,
        'connection_interval_units': connectionIntervalUnits,
        'connection_interval_ms': connectionIntervalMs,
        'connection_latency': connectionLatency,
        'supervision_timeout_units': supervisionTimeoutUnits,
        'supervision_timeout_ms': supervisionTimeoutMs,
        'mtu': mtu,
        'tx_data_length': txDataLength,
        'rx_data_length': rxDataLength,
        'tx_phy': txPhy,
        'rx_phy': rxPhy,
        'battery_millivolts': batteryMillivolts,
        'battery_percentage': batteryPercentage,
        'charging': charging,
        'sd_powered': sdPowered,
        'sd_ready': sdReady,
        'sd_health': sdHealth,
        'counters': counters,
      };
}

class BlackboxEvent {
  final int sequence;
  final int uptimeMs;
  final int eventId;
  final String name;
  final int flags;
  final int arg0;
  final int arg1;

  const BlackboxEvent({
    required this.sequence,
    required this.uptimeMs,
    required this.eventId,
    required this.name,
    required this.flags,
    required this.arg0,
    required this.arg1,
  });

  Map<String, Object> toJson() => {
        'sequence': sequence,
        'uptime_ms': uptimeMs,
        'event_id': eventId,
        'event': name,
        'flags': flags,
        'arg0': arg0,
        'arg1': arg1,
      };
}

class BlackboxTracePage {
  final List<BlackboxEvent> events;
  final bool hasMore;
  final bool cursorOverwritten;
  final int oldestSequence;
  final int nextSequence;
  final int globalNextSequence;
  final int overwrittenEvents;

  const BlackboxTracePage({
    required this.events,
    required this.hasMore,
    required this.cursorOverwritten,
    required this.oldestSequence,
    required this.nextSequence,
    required this.globalNextSequence,
    required this.overwrittenEvents,
  });
}
