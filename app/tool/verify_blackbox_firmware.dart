import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:omi/utils/blackbox_firmware_artifact.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run tool/verify_blackbox_firmware.dart <artifact.zip>');
    exitCode = 64;
    return;
  }

  final artifact = File(arguments.single);
  if (!await artifact.exists()) {
    stderr.writeln('artifact not found: ${artifact.path}');
    exitCode = 66;
    return;
  }

  try {
    final verification = BlackboxFirmwareArtifactVerifier.verify(
      fileName: path.basename(artifact.path),
      zipBytes: await artifact.readAsBytes(),
    );
    stdout.writeln('verified ${verification.summary}');
  } on FormatException catch (error) {
    stderr.writeln('verification failed: ${error.message}');
    exitCode = 65;
  }
}
