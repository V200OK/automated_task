import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

class AutomatedTaskException implements Exception {
  AutomatedTaskException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AutomationRunResult {
  const AutomationRunResult({
    required this.installLink,
    required this.qrCodeLink,
    required this.qrFilePath,
    required this.responseFilePath,
    required this.preparedApkPath,
  });

  final String installLink;
  final String qrCodeLink;
  final String qrFilePath;
  final String responseFilePath;
  final String preparedApkPath;
}

Future<AutomationRunResult> runAutomatedTask({
  required String configPath,
  List<String> arguments = const [],
  http.Client? client,
  DateTime Function()? nowProvider,
  Duration pollInterval = const Duration(seconds: 3),
  int maxPollAttempts = 10,
  bool openQr = false,
}) async {
  final httpClient = client ?? http.Client();
  final ownsClient = client == null;

  try {
    final configFile = File(configPath);
    if (!configFile.existsSync()) {
      throw AutomatedTaskException('config.yaml not found at $configPath');
    }

    final config = loadYaml(await configFile.readAsString());
    if (config is! YamlMap) {
      throw AutomatedTaskException('Invalid config format in $configPath');
    }

    final argumentMap = _parseArguments(arguments);

    final prefix = (argumentMap['prefix'] ?? '').toString();
    final apkPath = config['build_apk_path']?.toString();
    final outputDirPath = config['output_dir']?.toString();
    final token = config['diawi_token']?.toString();
    final webhook = config['teams_webhook']?.toString();

    if (apkPath == null || apkPath.isEmpty || !File(apkPath).existsSync()) {
      throw AutomatedTaskException('Invalid build_apk_path');
    }

    if (outputDirPath == null || outputDirPath.isEmpty) {
      throw AutomatedTaskException('Missing output_dir');
    }

    if (token == null || token.isEmpty) {
      throw AutomatedTaskException('Missing diawi_token');
    }

    if (webhook == null || webhook.isEmpty) {
      throw AutomatedTaskException('Missing teams_webhook');
    }

    final now = nowProvider?.call() ?? DateTime.now();
    final dateTime = DateFormat('dd_MMM_HH_mm').format(now);

    final uploadFileName = prefix.isEmpty
        ? '$dateTime.apk'
        : '${prefix}_$dateTime.apk';
    final outputFileName = 'diawi_res_$dateTime.json';
    final qrFileName = 'qrcode_$dateTime.png';

    final outputDir = Directory(outputDirPath);
    if (outputDir.existsSync()) {
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    final copiedApk = await File(
      apkPath,
    ).copy(path.join(outputDir.path, uploadFileName));

    final request =
        http.MultipartRequest('POST', Uri.parse('https://upload.diawi.com'))
          ..fields['token'] = token
          ..files.add(
            await http.MultipartFile.fromPath('file', copiedApk.path),
          );

    final uploadResponse = await httpClient.send(request);
    final body = await uploadResponse.stream.bytesToString();

    final responseFilePath = path.join(outputDir.path, outputFileName);
    await File(responseFilePath).writeAsString(body);

    final uploadJson = jsonDecode(body);
    if (uploadJson is! Map<String, dynamic>) {
      throw AutomatedTaskException('Invalid Diawi upload response: $body');
    }

    final job = uploadJson['job']?.toString();
    if (job == null || job.isEmpty) {
      throw AutomatedTaskException('Upload failed: $body');
    }

    String? installLink;
    String? qrCode;

    for (var i = 0; i < maxPollAttempts; i++) {
      await Future.delayed(pollInterval);

      final statusUri = Uri.parse(
        'https://upload.diawi.com/status?token=$token&job=$job',
      );
      final statusResponse = await httpClient.get(statusUri);
      final statusJson = jsonDecode(statusResponse.body);

      if (statusJson is! Map<String, dynamic>) {
        continue;
      }

      installLink = statusJson['link']?.toString();
      qrCode = statusJson['qrcode']?.toString();

      if (installLink != null && installLink.isNotEmpty) {
        break;
      }
    }

    if (installLink == null ||
        installLink.isEmpty ||
        qrCode == null ||
        qrCode.isEmpty) {
      throw AutomatedTaskException('Processing not finished. Try again later.');
    }

    final qrBytes = await httpClient.readBytes(Uri.parse(qrCode));
    final qrFilePath = path.join(outputDir.path, qrFileName);
    await File(qrFilePath).writeAsBytes(qrBytes);

    final payload = {
      'type': 'message',
      'attachments': [
        {
          'contentType': 'application/vnd.microsoft.card.adaptive',
          'content': {
            r'$schema': 'http://adaptivecards.io/schemas/adaptive-card.json',
            'type': 'AdaptiveCard',
            'version': '1.2',
            'body': [
              {
                'type': 'TextBlock',
                'text': 'New Build Ready!',
                'weight': 'Bolder',
                'size': 'Large',
              },
              {
                'type': 'TextBlock',
                'text': 'Scan QR to Install:',
                'weight': 'Bolder',
              },
              {'type': 'Image', 'url': qrCode},
              {
                'type': 'ActionSet',
                'actions': [
                  {
                    'type': 'Action.OpenUrl',
                    'title': 'Open Build',
                    'url': installLink,
                  },
                  {'type': 'Action.OpenUrl', 'title': 'Open QR', 'url': qrCode},
                ],
              },
            ],
          },
        },
      ],
    };

    await httpClient.post(
      Uri.parse(webhook),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (openQr) {
      await _openFile(qrFilePath);
    }

    return AutomationRunResult(
      installLink: installLink,
      qrCodeLink: qrCode,
      qrFilePath: qrFilePath,
      responseFilePath: responseFilePath,
      preparedApkPath: copiedApk.path,
    );
  } finally {
    if (ownsClient) {
      httpClient.close();
    }
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  final result = <String, String>{};

  for (final arg in arguments) {
    final parts = arg.split('=');
    if (parts.length == 2) {
      result[parts[0]] = parts[1];
    }
  }

  return result;
}

Future<void> _openFile(String filePath) async {
  if (Platform.isWindows) {
    await Process.run('start', [filePath], runInShell: true);
  } else if (Platform.isMacOS) {
    await Process.run('open', [filePath]);
  } else {
    await Process.run('xdg-open', [filePath]);
  }
}
