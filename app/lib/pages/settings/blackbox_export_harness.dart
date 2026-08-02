import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:omi/gen/pigeon_communicator.g.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/services/devices/blackbox_diagnostics_client.dart';
import 'package:omi/services/services.dart';
import 'package:omi/services/wals/wal.dart';
import 'package:omi/utils/logger.dart';

const String blackboxExportArtifactName = 'omi-blackbox-export-latest.json';

List<Wal> sortedBlackboxExportWals(Iterable<Object?> values) {
  final wals = List<Wal>.from(values);
  wals.sort((Wal left, Wal right) => left.timerStart.compareTo(right.timerStart));
  return wals;
}

class BlackboxExportHarnessPolicy {
  static bool matches(Uri uri, {required bool enabled}) {
    return enabled && uri.scheme == 'omi' && uri.host == 'blackbox' && uri.path == '/export';
  }
}

class BlackboxExportLaunchGate {
  final bool enabled;
  bool _claimed = false;

  BlackboxExportLaunchGate({required this.enabled});

  bool claim(Uri uri) {
    if (_claimed || !BlackboxExportHarnessPolicy.matches(uri, enabled: enabled)) return false;
    _claimed = true;
    return true;
  }
}

class BlackboxExportHarnessPage extends StatefulWidget {
  const BlackboxExportHarnessPage({super.key});

  @override
  State<BlackboxExportHarnessPage> createState() => _BlackboxExportHarnessPageState();
}

class _BlackboxExportHarnessPageState extends State<BlackboxExportHarnessPage> {
  String _status = 'Waiting for the paired CV1';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_export()));
  }

  Future<void> _export() async {
    try {
      final provider = context.read<DeviceProvider>();
      for (var attempt = 0; attempt < 60 && mounted; attempt++) {
        if (provider.isConnected && provider.connectedDevice != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!mounted) return;
      final device = provider.connectedDevice;
      if (!provider.isConnected || device == null || device.type.name != 'omi') {
        throw StateError('The exact paired Omi CV1 did not connect within 30 seconds');
      }

      setState(() => _status = 'Reading firmware and black-box trace');
      final connection = await ServiceManager.instance().device.ensureConnection(device.id);
      if (connection == null) throw StateError('The paired Omi CV1 connection was unavailable');
      final resolvedDevice = await device.getDeviceInfo(connection);
      final client = BlackboxDiagnosticsClient(connection);
      final snapshot = await client.snapshot();
      if (snapshot == null) {
        throw StateError('The connected firmware does not expose the OBBX v1 diagnostics service');
      }
      final events = await client.readAllEvents();
      final ringStatus = await connection.getRingStatus();
      final rawAppWals = await ServiceManager.instance().wal.getSyncs().phone.getAllWals();
      final appWals = sortedBlackboxExportWals(rawAppWals as Iterable<Object?>);
      final statusCounts = <String, int>{};
      final conversationCounts = <String, int>{};
      for (final wal in appWals) {
        statusCounts.update(wal.status.name, (count) => count + 1, ifAbsent: () => 1);
        conversationCounts.update(
          wal.conversationId ?? 'unbound',
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      final recentWals = appWals.length > 500 ? appWals.sublist(appWals.length - 500) : appWals;

      BleDeviceDiagnostics? mobileDiagnostics;
      String? mobileDiagnosticsError;
      try {
        mobileDiagnostics = await BleHostApi().getDeviceDiagnostics(device.id);
      } catch (error) {
        mobileDiagnosticsError = error.toString();
      }

      final data = <String, Object?>{
        'format': 'omi-cv1-blackbox-export-v1',
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'collector_platform': Platform.operatingSystem,
        'collector_os_version': Platform.operatingSystemVersion,
        'device_id': device.id,
        'firmware': resolvedDevice.firmwareRevision,
        'hardware': resolvedDevice.hardwareRevision,
        'battery': provider.batteryLevel,
        'mobile_ble': mobileDiagnostics == null
            ? null
            : {
                'connected_at': mobileDiagnostics.connectedAt,
                'reconnection_count': mobileDiagnostics.reconnectionCount,
                'fail_to_connect_count': mobileDiagnostics.failToConnectCount,
                'disconnect_history': mobileDiagnostics.disconnectHistory
                    .map(
                      (event) => {
                        'ts': event.timestamp,
                        'reason': event.reason,
                        'code': event.reasonCode,
                        'manual': event.isManual,
                        'event_type': event.eventType,
                        'last_rssi': event.lastRssi,
                        'connection_duration_ms': event.connectionDurationMs,
                        'app_state': event.appState,
                        'time_to_reconnect_ms': event.timeToReconnectMs,
                        'rssi_trend': event.rssiTrend,
                      },
                    )
                    .toList(),
              },
        'mobile_ble_error': mobileDiagnosticsError,
        'pendant_blackbox': snapshot.toJson(),
        'pendant_blackbox_events': events.map((event) => event.toJson()).toList(),
        'pendant_ring_status': ringStatus == null
            ? null
            : {
                'used_bytes': ringStatus.usedBytes,
                'unread_packets': ringStatus.unreadPackets,
                'free_bytes': ringStatus.freeBytes,
                'rtc_valid': ringStatus.rtcValid,
              },
        'app_capture_wals': {
          'total': appWals.length,
          'status_counts': statusCounts,
          'conversation_counts': conversationCounts,
          'recent_limit': 500,
          'recent': recentWals.map((wal) => wal.toJson()).toList(),
        },
      };

      final documents = await getApplicationDocumentsDirectory();
      final file = File('${documents.path}/$blackboxExportArtifactName');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      Logger.debug('CV1 black-box export complete: ${file.path}');
      if (mounted) setState(() => _status = 'Export complete: $blackboxExportArtifactName');
    } catch (error) {
      Logger.debug('CV1 black-box export failed: $error');
      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = 'Export failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('CV1 Black-box Export')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status, style: const TextStyle(color: Colors.white, fontSize: 18)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
