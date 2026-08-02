import 'dart:async';

import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:omi/pages/home/firmware_mixin.dart';
import 'package:omi/providers/device_provider.dart';

const bool blackboxDfuHarnessEnabled = bool.fromEnvironment('OMI_BLACKBOX_HARNESS');
const String blackboxDfuArtifactName = 'omi-cv1-3.0.30-blackbox.zip';

class BlackboxDfuHarnessPolicy {
  static bool matches(Uri uri, {required bool enabled}) {
    return enabled && uri.scheme == 'omi' && uri.host == 'blackbox' && uri.path == '/dfu';
  }
}

class BlackboxDfuLaunchGate {
  final bool enabled;
  bool _claimed = false;

  BlackboxDfuLaunchGate({required this.enabled});

  bool claim(Uri uri) {
    if (_claimed || !BlackboxDfuHarnessPolicy.matches(uri, enabled: enabled)) return false;
    _claimed = true;
    return true;
  }
}

class BlackboxDfuHarnessPage extends StatefulWidget {
  const BlackboxDfuHarnessPage({super.key});

  @override
  State<BlackboxDfuHarnessPage> createState() => _BlackboxDfuHarnessPageState();
}

class _BlackboxDfuHarnessPageState extends State<BlackboxDfuHarnessPage> with FirmwareMixin {
  String _status = 'Waiting for the paired CV1';
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    if (_started || !blackboxDfuHarnessEnabled) return;
    _started = true;

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

      final documents = await getApplicationDocumentsDirectory();
      final artifactPath = '${documents.path}/$blackboxDfuArtifactName';
      setState(() => _status = 'Flashing $blackboxDfuArtifactName to ${device.name}');
      await startMCUDfu(device, zipFilePath: artifactPath);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = 'Flash failed before completion';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('CV1 Black-box DFU')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isInstalled ? 'Firmware installed' : _status,
                style: const TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            if (isInstalling) ...[
              LinearProgressIndicator(value: installProgress > 0 ? installProgress / 100 : null),
              const SizedBox(height: 8),
              Text('$installProgress%', style: const TextStyle(color: Colors.white70)),
            ],
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }
}
