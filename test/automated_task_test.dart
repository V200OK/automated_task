import 'dart:convert';
import 'dart:io';

import 'package:automated_task/automated_task.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('runAutomatedTask uploads apk and saves artifacts', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'automated_task_test_',
    );
    addTearDown(() async => tempDir.delete(recursive: true));

    final apkFile = File('${tempDir.path}/app.apk');
    await apkFile.writeAsBytes([1, 2, 3, 4]);

    final outputDir = Directory('${tempDir.path}/out');
    final configFile = File('${tempDir.path}/config.yaml');
    await configFile.writeAsString('''
build_apk_path: ${apkFile.path}
output_dir: ${outputDir.path}
diawi_token: fake-token
teams_webhook: https://example.com/webhook
''');

    final mockClient = MockClient((request) async {
      if (request.url.toString() == 'https://upload.diawi.com' &&
          request.method == 'POST') {
        return http.Response(jsonEncode({'job': 'job-123'}), 200);
      }

      if (request.url.toString().contains('https://upload.diawi.com/status') &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'link': 'https://diawi.com/install/abc',
            'qrcode': 'https://example.com/qr.png',
          }),
          200,
        );
      }

      if (request.url.toString() == 'https://example.com/qr.png' &&
          request.method == 'GET') {
        return http.Response.bytes([9, 9, 9], 200);
      }

      if (request.url.toString() == 'https://example.com/webhook' &&
          request.method == 'POST') {
        return http.Response('ok', 200);
      }

      return http.Response('not found', 404);
    });

    final result = await runAutomatedTask(
      configPath: configFile.path,
      arguments: const ['prefix=dev'],
      client: mockClient,
      nowProvider: () => DateTime(2026, 5, 22, 14, 45),
      pollInterval: Duration.zero,
      maxPollAttempts: 1,
      openQr: false,
    );

    expect(result.installLink, 'https://diawi.com/install/abc');
    expect(result.qrCodeLink, 'https://example.com/qr.png');
    expect(File(result.qrFilePath).existsSync(), isTrue);
    expect(File(result.responseFilePath).existsSync(), isTrue);
  });
}
