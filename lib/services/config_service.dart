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

  void setMode(String mode) {}

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
    final home = await HermesFileService().resolveHermesHome();
    final res = await ConnectionManager().runShell(
      'cat "$home/config.yaml" 2>/dev/null || echo "config not found"',
      allowFailure: true,
    );
    return res.stdout;
  }

  Future<bool> writeConfig(String content) async {
    final home = await HermesFileService().resolveHermesHome();
    final b64 = base64Encode(utf8.encode(content));
    final res = await ConnectionManager().runShell(
      'echo "$b64" | base64 -d > "$home/config.yaml"',
      allowFailure: true,
    );
    return res.exitCode == 0;
  }

  Future<String> readEnvFile() async {
    final home = await HermesFileService().resolveHermesHome();
    final res = await ConnectionManager().runShell(
      'cat "$home/.env" 2>/dev/null || echo "# .env not found"',
      allowFailure: true,
    );
    return res.stdout;
  }

  Future<bool> writeEnvFile(String content) async {
    final home = await HermesFileService().resolveHermesHome();
    final b64 = base64Encode(utf8.encode(content));
    final res = await ConnectionManager().runShell(
      'echo "$b64" | base64 -d > "$home/.env"',
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
    final home = await HermesFileService().resolveHermesHome();
    final res = await ConnectionManager().runShell(
      'tail -n $lines "$home/logs/$source.log" 2>/dev/null || echo "log not found"',
      allowFailure: true,
    );
    return res.stdout;
  }

  Future<List<PlatformConfig>> getPlatformConfigs() async {
    final config = await readConfig();
    final env = await getEnvVars();
    final hasWechat = (env['WEIXIN_ACCOUNT_ID'] ?? '').isNotEmpty;
    final platformNames = [
      'telegram',
      'discord',
      'slack',
      'whatsapp',
      'feishu',
      'wecom',
      'matrix',
      'wechat',
      'signal',
      'email',
      'dingtalk',
      'qqbot'
    ];

    Map<String, dynamic> statusMap = {};
    try {
      final status = await GatewayService().getStatus();
      statusMap = status['platforms'] ?? {};
    } catch (_) {}

    return platformNames.map((name) {
      final configured = name == 'wechat' ? hasWechat : config.contains('$name:');
      var status = 'disconnected';
      if (configured) {
        final live = statusMap[name];
        if (live == 'running' || live == 'connected') status = 'connected';
      }
      return PlatformConfig(name: name, configured: configured, status: status);
    }).toList();
  }
}
