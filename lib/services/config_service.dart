import 'dart:convert';
import 'dart:io';

import '../models/platform_config.dart';
import 'connection_manager.dart';

/// 直接读取 Hermes 配置文件
/// 支持 local/remote 双模式，远程时通过 SSH 读取首尔服务器文件
class ConfigService {
  final String hermesHome;

  ConfigService({String? hermesHome})
      : hermesHome = hermesHome ?? resolveHermesHome();

  String _mode = 'local';

  /// 切换连接模式
  void setMode(String mode) {
    _mode = mode;
  }

  bool get _isRemote => _mode != 'local';

  static String resolveHermesHome() {
    // 优先环境变量
    final envHome = Platform.environment['HERMES_HOME'];
    if (envHome != null && envHome.isNotEmpty) return envHome;

    // 检查 WSL 路径
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final wslPath = '$home/.hermes';
      if (Directory(wslPath).existsSync()) return wslPath;
    }

    // 检查 WSL UNC 路径
    const uncPath = r'\\wsl.localhost\Ubuntu\home\tian\.hermes';
    if (Directory(uncPath).existsSync()) return uncPath;

    // 检查 Windows 用户目录
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      final winPath = '$userProfile\\.hermes';
      if (Directory(winPath).existsSync()) return winPath;
    }

    // 最后 fallback：使用 HOME 环境变量
    if (home != null && home.isNotEmpty) return '$home/.hermes';
    return '~/.hermes';
  }

  String get configPath => '$hermesHome/config.yaml';
  String get envPath => '$hermesHome/.env';
  String get authPath => '$hermesHome/auth.json';
  String get logsDir => '$hermesHome/logs';
  String get desktopConfigPath => '$hermesHome/desktop_config.json';

  static const String defaultGatewayUrl = 'http://localhost:8642';

  /// 读取桌面应用配置（Gateway URL 等）
  Future<Map<String, dynamic>> readDesktopConfig() async {
    try {
      final file = File(desktopConfigPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          return decoded.cast<String, dynamic>();
        }
      }
    } catch (_) {}
    return {};
  }

  /// 保存桌面应用配置
  Future<bool> writeDesktopConfig(Map<String, dynamic> data) async {
    try {
      await File(desktopConfigPath).writeAsString(jsonEncode(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取 Gateway URL（带缓存提升性能）
  String? _cachedGatewayUrl;
  Future<String> getGatewayUrl() async {
    if (_cachedGatewayUrl != null) return _cachedGatewayUrl!;
    final config = await readDesktopConfig();
    final url = config['gateway_url'] as String?;
    _cachedGatewayUrl = (url != null && url.isNotEmpty) ? url : defaultGatewayUrl;
    return _cachedGatewayUrl!;
  }

  /// 保存 Gateway URL
  Future<bool> setGatewayUrl(String url) async {
    _cachedGatewayUrl = url;
    final config = await readDesktopConfig();
    config['gateway_url'] = url;
    return writeDesktopConfig(config);
  }

  Future<String> readConfig() async {
    if (_isRemote) {
      try {
        final result = await ConnectionManager().execRemote('cat /home/ubuntu/.hermes/config.yaml');
        return result.isEmpty ? '配置文件不存在' : result;
      } catch (_) {
        return '配置文件不存在';
      }
    }
    try {
      final file = File(configPath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '配置文件不存在';
    } catch (e) {
      return '读取配置失败: $e';
    }
  }

  Future<bool> writeConfig(String content) async {
    if (_isRemote) return false; // 远程模式只读
    try {
      await File(configPath).writeAsString(content);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isGatewayRunning() async {
    try {
      final url = await getGatewayUrl();
      final result = await HttpClient()
          .getUrl(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 3));
      final response = await result.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> getEnvVars() async {
    final env = <String, String>{};
    try {
      final file = File(envPath);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final eq = trimmed.indexOf('=');
          if (eq > 0) {
            var key = trimmed.substring(0, eq).trim();
            var value = trimmed.substring(eq + 1).trim();
            // Remove quotes
            if ((value.startsWith('"') && value.endsWith('"')) ||
                (value.startsWith("'") && value.endsWith("'"))) {
              value = value.substring(1, value.length - 1);
            }
            env[key] = value;
          }
        }
      }
    } catch (_) {}
    return env;
  }

  /// 读取 .env 文件的原始内容
  Future<String> readEnvFile() async {
    if (_isRemote) {
      try {
        final result = await ConnectionManager().execRemote('cat /home/ubuntu/.hermes/.env');
        return result.isEmpty ? '# 环境变量文件为空\n' : result;
      } catch (_) {
        return '# 环境变量文件为空\n';
      }
    }
    try {
      final file = File(envPath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '# 环境变量文件为空\n';
    } catch (e) {
      return '读取失败: $e';
    }
  }

  /// 写入 .env 文件
  Future<bool> writeEnvFile(String content) async {
    if (_isRemote) return false;
    try {
      await File(envPath).writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Map<String, String>>> getAuthProviders() async {
    if (_isRemote) {
      try {
        final content = await ConnectionManager().execRemote('cat /home/ubuntu/.hermes/auth.json');
        if (content.isEmpty) return {};
        final json = jsonDecode(content);
        if (json is! Map) return {};
        final providers = <String, Map<String, String>>{};
        json.forEach((key, value) {
          if (value is Map) {
            providers[key.toString()] =
                value.map((k, v) => MapEntry(k.toString(), v.toString()));
          }
        });
        return providers;
      } catch (_) {
        return {};
      }
    }
    final providers = <String, Map<String, String>>{};
    try {
      final file = File(authPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value is Map) {
              providers[key.toString()] =
                  value.map((k, v) => MapEntry(k.toString(), v.toString()));
            }
          });
        }
      }
    } catch (_) {}
    return providers;
  }

  /// 读取已安装的技能列表
  Future<List<Map<String, String>>> getSkills() async {
    if (_isRemote) {
      return _getRemoteSkills();
    }
    final skills = <Map<String, String>>[];
    try {
      final skillsDir = Directory('$hermesHome/skills');
      if (await skillsDir.exists()) {
        await for (final category in skillsDir.list()) {
          if (category is Directory) {
            await for (final skillDir in category.list()) {
              if (skillDir is Directory) {
                final skillMd = File('${skillDir.path}/SKILL.md');
                if (await skillMd.exists()) {
                  final content = await skillMd.readAsString();
                  final name = _extractYamlField(content, 'name') ?? skillDir.path.split('/').last;
                  final desc = _extractYamlField(content, 'description') ?? '';
                  final version = _extractYamlField(content, 'version') ?? '';
                  skills.add({
                    'name': name,
                    'description': desc,
                    'version': version,
                    'path': skillDir.path,
                  });
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    // Sort by name
    skills.sort((a, b) => a['name']!.compareTo(b['name']!));
    return skills;
  }

  /// 通过 SSH 读取远程技能列表
  Future<List<Map<String, String>>> _getRemoteSkills() async {
    final skills = <Map<String, String>>[];
    try {
      final cm = ConnectionManager();
      final catsOut = await cm.execRemote('ls -1 /home/ubuntu/.hermes/skills/ 2>/dev/null || true');
      final categories = catsOut.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (final cat in categories) {
        final skillsOut = await cm.execRemote('ls -1 /home/ubuntu/.hermes/skills/$cat/ 2>/dev/null || true');
        final skillNames = skillsOut.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        for (final skillName in skillNames) {
          final mdContent = await cm.execRemote('cat /home/ubuntu/.hermes/skills/$cat/$skillName/SKILL.md 2>/dev/null || true');
          if (mdContent.isEmpty) continue;
          final name = _extractYamlField(mdContent, 'name') ?? skillName;
          final desc = _extractYamlField(mdContent, 'description') ?? '';
          final version = _extractYamlField(mdContent, 'version') ?? '';
          skills.add({
            'name': name,
            'description': desc,
            'version': version,
            'path': '/home/ubuntu/.hermes/skills/$cat/$skillName',
          });
        }
      }
    } catch (_) {}
    skills.sort((a, b) => a['name']!.compareTo(b['name']!));
    return skills;
  }

  /// 解析 SKILL.md 的 YAML 字段
  String? _extractYamlField(String content, String field) {
    final lines = content.split('\n');
    bool inFrontmatter = false;
    for (final line in lines) {
      if (line.trim() == '---') {
        inFrontmatter = !inFrontmatter;
        continue;
      }
      if (inFrontmatter && line.startsWith('$field:')) {
        return line.substring('$field:'.length).trim().replaceAll('"', '');
      }
    }
    return null;
  }

  Future<List<PlatformConfig>> getPlatformConfigs() async {
    // 从 config.yaml 中解析平台配置
    final config = await readConfig();
    // 微信凭证存在 .env 里（WEIXIN_ACCOUNT_ID/TOKEN），额外读取
    final env = await getEnvVars();
    final hasWechatEnv = (env['WEIXIN_ACCOUNT_ID'] ?? '').isNotEmpty &&
        (env['WEIXIN_TOKEN'] ?? '').isNotEmpty;

    final platforms = <PlatformConfig>[];
    final platformNames = [
      'telegram', 'discord', 'slack', 'whatsapp',
      'feishu', 'wecom', 'matrix', 'wechat',
      'signal', 'email', 'dingtalk', 'qqbot',
      'homeassistant', 'webhook', 'sms', 'mattermost',
      'yuanbao',
    ];

    for (final name in platformNames) {
      bool configured;
      if (name == 'wechat') {
        configured = hasWechatEnv;
      } else {
        configured = config.contains('$name:') && !config.contains('$name: {}');
        if (configured) {
          configured = config.contains('token') || config.contains('app_id') || config.contains('secret');
        }
      }
      final displayName = _platformDisplayName(name);
      platforms.add(PlatformConfig(
        name: displayName,
        configured: configured,
        status: configured ? 'connected' : 'disconnected',
      ));
    }

    return platforms;
  }

  Future<String> getLogContent(String source, {int lines = 200}) async {
    if (_isRemote) {
      try {
        final result = await ConnectionManager().execRemote('tail -n $lines /home/ubuntu/.hermes/logs/$source.log 2>/dev/null || echo "日志文件不存在"');
        return result.isEmpty ? '日志文件不存在' : result;
      } catch (_) {
        return '日志文件不存在';
      }
    }
    try {
      final file = File('$logsDir/$source.log');
      if (await file.exists()) {
        final content = await file.readAsString();
        final allLines = content.split('\n');
        final recent = allLines.length > lines
            ? allLines.sublist(allLines.length - lines)
            : allLines;
        return recent.join('\n');
      }
      return '日志文件不存在';
    } catch (e) {
      return '读取日志失败: $e';
    }
  }

  String _platformDisplayName(String name) {
    switch (name) {
      case 'telegram': return 'Telegram';
      case 'discord': return 'Discord';
      case 'slack': return 'Slack';
      case 'whatsapp': return 'WhatsApp';
      case 'feishu': return '飞书';
      case 'wecom': return '企业微信';
      case 'matrix': return 'Matrix';
      case 'wechat': return '微信';
      case 'signal': return 'Signal';
      case 'email': return '邮件';
      case 'dingtalk': return '钉钉';
      case 'qqbot': return 'QQ 机器人';
      case 'homeassistant': return 'Home Assistant';
      case 'webhook': return 'Webhook';
      case 'sms': return 'SMS';
      case 'mattermost': return 'Mattermost';
      case 'yuanbao': return '元宝';
      default: return name;
    }
  }
}
