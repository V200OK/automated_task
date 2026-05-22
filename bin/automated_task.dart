import 'dart:io';

import 'package:automated_task/automated_task.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) async {
  /// Config needs to be in the same directory as the script, so we can reliably find it regardless of where the script is run from.
  // final scriptDir = File(Platform.script.toFilePath()).parent.parent.path;
  // final configPath = p.join(scriptDir, 'config.yaml');

  /// Updated to use the current working directory, which is more intuitive for users running the script from their project root.
  final currentDir = Directory.current.path;
  final configPath = p.join(currentDir, 'automated_task_config.yaml');
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
