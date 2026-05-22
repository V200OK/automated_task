import 'dart:io';

import 'package:automated_task/automated_task.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) async {
  final scriptDir = File(Platform.script.toFilePath()).parent.parent.path;
  final configPath = p.join(scriptDir, 'config.yaml');
  try {
    final result = await runAutomatedTask(
      configPath: configPath,
      arguments: arguments,
      openQr: true,
    );

    print('Install link: ${result.installLink}');
    print('QR code: ${result.qrCodeLink}');
    print('Saved QR: ${result.qrFilePath}');
  } on AutomatedTaskException catch (error) {
    stderr.writeln('Error: $error');
    exit(1);
  } catch (error) {
    stderr.writeln('Unexpected error: $error');
    exit(1);
  }
}
