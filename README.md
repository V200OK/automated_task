# automated_task

Automates Android APK distribution by:

- uploading an APK to Diawi
- polling Diawi for install link + QR code
- saving JSON/QR output artifacts
- posting an adaptive card to a Microsoft Teams webhook

## Config

Copy `config.example.yaml` to `config.yaml` in the package root and fill values:

```yaml
build_apk_path: /absolute/path/to/app.apk
output_dir: /absolute/path/to/output
diawi_token: your-diawi-token
teams_webhook: https://your-teams-webhook-url
```

## CLI usage

```bash
dart run bin/automated_task.dart prefix=dev
```

## Library usage

```dart
import 'package:automated_task/automated_task.dart';

Future<void> main() async {
  final result = await runAutomatedTask(
	configPath: 'automated_task_config.yaml',
	arguments: const ['prefix=dev'],
  );

  print(result.installLink);
}
```

## Development

```bash
dart format .
dart analyze
dart test
```
