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
    switch (ConnectionManager().state.mode) {
      case ConnectionMode.embedded:
        try {
          final file = File('${resolveHermesHome()}/config.yaml');
          return await file.exists() ? await file.readAsString() : 'config not found';
        } catch (_) {
          return 'config not found';
        }
      case ConnectionMode.remote:
        if (ConnectionManager().state.status != ConnStatus.connected) {
          return '# 未连接';
        }
        final rh = await HermesFileService().resolveHermesHome();
        final rr = await ConnectionManager().runShell(
          'cat "$rh/config.yaml" 2>/dev/null || echo "config not found"',
          allowFailure: true,
        );
        return rr.stdout;
      case ConnectionMode.local:
        final lh = await HermesFileService().resolveHermesHome();
        final lr = await ConnectionManager().runShell(
          'cat "$lh/config.yaml" 2>/dev/null || echo "config not found"',
          allowFailure: true,
        );
        return lr.stdout;
    }
  }

  Future<bool> writeConfig(String content) async {
    switch (ConnectionManager().state.mode) {
      case ConnectionMode.embedded:
        try {
          await File('${resolveHermesHome()}/config.yaml').writeAsString(content);
          return true;
        } catch (_) {
          return false;
        }
      case ConnectionMode.remote:
        if (ConnectionManager().state.status != ConnStatus.connected) return false;
        final rh = await HermesFileService().resolveHermesHome();
        final rb64 = base64Encode(utf8.encode(content));
        final rr = await ConnectionManager().runShell(
          'echo "$rb64" | base64 -d > "$rh/config.yaml"',
          allowFailure: true,
        );
        return rr.exitCode == 0;
      case ConnectionMode.local:
        final lh = await HermesFileService().resolveHermesHome();
        final lb64 = base64Encode(utf8.encode(content));
        final lr = await ConnectionManager().runShell(
          'echo "$lb64" | base64 -d > "$lh/config.yaml"',
          allowFailure: true,
        );
        return lr.exitCode == 0;
    }
  }

  Future<String> readEnvFile() async {
    switch (ConnectionManager().state.mode) {
      case ConnectionMode.embedded:
        try {
          final file = File('${resolveHermesHome()}/.env');
          return await file.exists() ? await file.readAsString() : '# .env not found';
        } catch (_) {
          return '# .env not found';
        }
      case ConnectionMode.remote:
        if (ConnectionManager().state.status != ConnStatus.connected) {
          return '# 未连接';
        }
        final rh = await HermesFileService().resolveHermesHome();
        final rr = await ConnectionManager().runShell(
          'cat "$rh/.env" 2>/dev/null || echo "# .env not found"',
          allowFailure: true,
        );
        return rr.stdout;
      case ConnectionMode.local:
        final lh = await HermesFileService().resolveHermesHome();
        final lr = await ConnectionManager().runShell(
          'cat "$lh/.env" 2>/dev/null || echo "# .env not found"',
          allowFailure: true,
        );
        return lr.stdout;
    }
  }

  Future<bool> writeEnvFile(String content) async {
    switch (ConnectionManager().state.mode) {
      case ConnectionMode.embedded:
        try {
          await File('${resolveHermesHome()}/.env').writeAsString(content);
          return true;
        } catch (_) {
          return false;
        }
      case ConnectionMode.remote:
        if (ConnectionManager().state.status != ConnStatus.connected) return false;
        final rh = await HermesFileService().resolveHermesHome();
        final rb64 = base64Encode(utf8.encode(content));
        final rr = await ConnectionManager().runShell(
          'echo "$rb64" | base64 -d > "$rh/.env"',
          allowFailure: true,
        );
        return rr.exitCode == 0;
      case ConnectionMode.local:
        final lh = await HermesFileService().resolveHermesHome();
        final lb64 = base64Encode(utf8.encode(content));
        final lr = await ConnectionManager().runShell(
          'echo "$lb64" | base64 -d > "$lh/.env"',
          allowFailure: true,
        );
        return lr.exitCode == 0;
    }
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

  /// 批量读取配置 + 技能（local/remote 只需 1 次 SSH 往返）
  Future<({String config, List<Map<String, String>> skills})> readConfigAndSkills() async =>
      HermesFileService().readConfigAndSkills();

  /// 解析模型配置（model / provider / base_url），供仪表盘和设置页复用
  Future<Map<String, String>> readModelConfig() async {
    final config = await readConfig();
    String model = '-';
    String provider = '-';
    String baseUrl = '-';
    String? currentSection;
    for (final line in config.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      if (line.length - line.trimLeft().length == 0 && t.endsWith(':') && !t.startsWith('-')) {
        currentSection = t.substring(0, t.length - 1);
        continue;
      }
      if (currentSection == 'model' && line.length - line.trimLeft().length > 0) {
        if (t.startsWith('default:')) {
          model = t.substring(t.indexOf(':') + 1).trim();
        } else if (t.startsWith('provider:')) {
          provider = t.substring(t.indexOf(':') + 1).trim();
        } else if (t.startsWith('base_url:') || t.startsWith('baseUrl:')) {
          baseUrl = t.substring(t.indexOf(':') + 1).trim();
        }
      }
      // 根级 base_url 兼容
      if (line.length - line.trimLeft().length == 0 &&
          (t.startsWith('base_url:') || t.startsWith('baseUrl:')) && baseUrl == '-') {
        baseUrl = t.substring(t.indexOf(':') + 1).trim();
      }
    }
    return {'model': model, 'provider': provider, 'base_url': baseUrl};
  }

  Future<String> getLogContent(String source, {int lines = 200}) async {
    switch (ConnectionManager().state.mode) {
      case ConnectionMode.embedded:
        try {
          final file = File('${resolveHermesHome()}/logs/$source.log');
          if (!await file.exists()) return 'log not found';
          final all = await file.readAsLines();
          final tail = all.length > lines ? all.sublist(all.length - lines) : all;
          return tail.join('\n');
        } catch (_) {
          return 'log not found';
        }
      case ConnectionMode.remote:
        if (ConnectionManager().state.status != ConnStatus.connected) {
          return 'log not found';
        }
        final rh = await HermesFileService().resolveHermesHome();
        final rr = await ConnectionManager().runShell(
          'tail -n $lines "$rh/logs/$source.log" 2>/dev/null || echo "log not found"',
          allowFailure: true,
        );
        return rr.stdout;
      case ConnectionMode.local:
        final lh = await HermesFileService().resolveHermesHome();
        final lr = await ConnectionManager().runShell(
          'tail -n $lines "$lh/logs/$source.log" 2>/dev/null || echo "log not found"',
          allowFailure: true,
        );
        return lr.stdout;
    }
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

  /// 内部名称 → gateway /api/status 中的平台键名
  static String _gatewayPlatformKey(String name) {
    // gateway 使用 weixin，内部使用 wechat
    if (name == 'wechat') return 'weixin';
    // 其他平台键名相同
    return name;
  }

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
      statusMap = status['gateway_platforms'] ?? status['platforms'] ?? {};
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
        // gateway 可能使用不同的平台键名
        final statusName = _gatewayPlatformKey(name);
        final live = statusMap[name] ?? statusMap[statusName];
        if (live is Map) {
          final s = live['state'] as String?;
          if (s == 'connected' || s == 'running') status = 'connected';
        } else if (live == 'running' || live == 'connected') {
          status = 'connected';
        }
      }
      return PlatformConfig(
        name: _platformDisplayNames[name] ?? name,
        configured: configured,
        status: status,
      );
    }).toList();
  }
}
