import 'dart:convert';
import 'dart:io';


import '../models/platform_config.dart';
import 'connection_manager.dart';
import 'gateway_service.dart';
import 'hermes_file_service.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._();
  factory ConfigService() => _instance;
  ConfigService._();

  static const String defaultGatewayUrl = 'http://localhost:8642';

  static String resolveDesktopConfigPath() {
    final userHome =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    return '$userHome\\.hermes\\desktop_config.json';
  }

  static String resolveHermesHome() {
    final envHome = Platform.environment['HERMES_HOME'];
    if (envHome != null && envHome.isNotEmpty) return envHome;

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final wslPath = '$home/.hermes';
      if (Directory(wslPath).existsSync()) return wslPath;
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      final winPath = '$userProfile\\.hermes';
      if (Directory(winPath).existsSync()) return winPath;
      return winPath;
    }

    return '.hermes';
  }

  static Future<void> ensureInitialized() async {
    final path = resolveDesktopConfigPath();
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
  }

  Future<Map<String, dynamic>> readDesktopConfig() async {
    try {
      final file = File(resolveDesktopConfigPath());
      if (await file.exists()) {
        return jsonDecode(await file.readAsString());
      }
    } catch (_) {}
    return {};
  }

  Future<bool> writeDesktopConfig(Map<String, dynamic> data) async {
    try {
      final file = File(resolveDesktopConfigPath());
      await file.writeAsString(jsonEncode(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> getGatewayUrl() async {
    final config = await readDesktopConfig();
    return config['gateway_url'] as String? ?? defaultGatewayUrl;
  }

  Future<bool> setGatewayUrl(String url) async {
    final config = await readDesktopConfig();
    config['gateway_url'] = url;
    return writeDesktopConfig(config);
  }

  Future<String> readConfig() async {
    final home = resolveHermesHome();
    if (ConnectionManager().state.mode == ConnectionMode.embedded) {
      try {
        final file = File('$home/config.yaml');
        return await file.exists() ? await file.readAsString() : 'config not found';
      } catch (_) {
        return 'config not found';
      }
    }
    final h = await HermesFileService().resolveHermesHome();
    final res = await ConnectionManager().runShell(
      'cat "$h/config.yaml" 2>/dev/null || echo "config not found"',
      allowFailure: true,
    );
    return res.stdout;
  }

  Future<bool> writeConfig(String content) async {
    final home = resolveHermesHome();
    if (ConnectionManager().state.mode == ConnectionMode.embedded) {
      try {
        await File('$home/config.yaml').writeAsString(content);
        return true;
      } catch (_) {
        return false;
      }
    }
    final h = await HermesFileService().resolveHermesHome();
    final b64 = base64Encode(utf8.encode(content));
    final res = await ConnectionManager().runShell(
      'echo "$b64" | base64 -d > "$h/config.yaml"',
      allowFailure: true,
    );
    return res.exitCode == 0;
  }

  Future<String> readEnvFile() async {
    final home = resolveHermesHome();
    if (ConnectionManager().state.mode == ConnectionMode.embedded) {
      try {
        final file = File('$home/.env');
        return await file.exists() ? await file.readAsString() : '# .env not found';
      } catch (_) {
        return '# .env not found';
      }
    }
    final h = await HermesFileService().resolveHermesHome();
    final res = await ConnectionManager().runShell(
      'cat "$h/.env" 2>/dev/null || echo "# .env not found"',
      allowFailure: true,
    );
    return res.stdout;
  }

  Future<bool> writeEnvFile(String content) async {
    final home = resolveHermesHome();
    if (ConnectionManager().state.mode == ConnectionMode.embedded) {
      try {
        await File('$home/.env').writeAsString(content);
        return true;
      } catch (_) {
        return false;
      }
    }
    final h = await HermesFileService().resolveHermesHome();
    final b64 = base64Encode(utf8.encode(content));
    final res = await ConnectionManager().runShell(
      'echo "$b64" | base64 -d > "$h/.env"',
      allowFailure: true,
    );
    return res.exitCode == 0;
  }

  Future<Map<String, String>> getEnvVars() async {
    final content = await readEnvFile();
    final env = <String, String>{};
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final eq = t.indexOf('=');
      if (eq > 0) {
        env[t.substring(0, eq).trim()] =
            t.substring(eq + 1).trim().replaceAll('"', '').replaceAll("'", '');
      }
    }
    return env;
  }

  Future<List<Map<String, String>>> getSkills() async =>
      HermesFileService().getSkills();

  Future<String> getLogContent(String source, {int lines = 200}) async {
    final home = resolveHermesHome();
    if (ConnectionManager().state.mode == ConnectionMode.embedded) {
      try {
        final file = File('$home/logs/$source.log');
        if (!await file.exists()) return 'log not found';
        final all = await file.readAsLines();
        final tail = all.length > lines ? all.sublist(all.length - lines) : all;
        return tail.join('\n');
      } catch (_) {
        return 'log not found';
      }
    }
    final h = await HermesFileService().resolveHermesHome();
    final res = await ConnectionManager().runShell(
      'tail -n $lines "$h/logs/$source.log" 2>/dev/null || echo "log not found"',
      allowFailure: true,
    );
    return res.stdout;
  }

  /// 各平台必须填写的凭证字段 — 只有这些字段有实际值时才算"已配置"
  static const Map<String, List<String>> _platformCredFields = {
    'telegram': ['bot_token'],
    'discord': ['bot_token'],
    'slack': ['bot_token'],
    'whatsapp': ['phone_number_id', 'access_token'],
    'feishu': ['app_id', 'app_secret'],
    'wecom': ['corp_id', 'agent_id', 'secret'],
    'matrix': ['access_token'],
    'signal': ['signal_'],
    'email': ['smtp_host', 'smtp_user'],
    'dingtalk': ['dingtalk_'],
    'qqbot': ['qqbot_'],
  };

  /// 内部名称 → UI 显示名称
  static const Map<String, String> _platformDisplayNames = {
    'telegram': 'Telegram',
    'discord': 'Discord',
    'slack': 'Slack',
    'whatsapp': 'WhatsApp',
    'feishu': '飞书',
    'wecom': '企业微信',
    'matrix': 'Matrix',
    'wechat': '微信',
    'signal': 'Signal',
    'email': '邮件',
    'dingtalk': '钉钉',
    'qqbot': 'QQ 机器人',
  };
Future<List<PlatformConfig>> getPlatformConfigs() async {
    final config = await readConfig();
    final env = await getEnvVars();
    final hasWechat = (env['WEIXIN_ACCOUNT_ID'] ?? '').isNotEmpty;
    final platformNames = _platformCredFields.keys.toList()..add('wechat');

    Map<String, dynamic> statusMap = {};
    try {
      final status = await GatewayService().getStatus();
      statusMap = status['platforms'] ?? {};
    } catch (_) {}

    return platformNames.map((name) {
      bool configured;
      if (name == 'wechat') {
        configured = hasWechat;
      } else {
        final keyFields = _platformCredFields[name] ?? [];
        configured = keyFields.any((f) {
          final match = RegExp('^\\s+$f:\\s*(.*?)\\s*\$', multiLine: true)
              .firstMatch(config);
          if (match == null) return false;
          final val = match.group(1) ?? '';
          return val.isNotEmpty && val != "''" && val != '""';
        });
      }
      var status = 'disconnected';
      if (configured) {
        final live = statusMap[name];
        if (live == 'running' || live == 'connected') status = 'connected';
      }
      return PlatformConfig(
        name: _platformDisplayNames[name] ?? name,
        configured: configured,
        status: status,
      );
    }).toList();
  }
}
