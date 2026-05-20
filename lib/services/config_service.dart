import 'dart:convert';
import 'dart:io';

import '../models/platform_config.dart';

/// 直接读取 Hermes 配置文件
class ConfigService {
  final String hermesHome;

  ConfigService({String? hermesHome})
      : hermesHome = hermesHome ?? '${Platform.environment['HOME'] ?? '/home/tian'}/.hermes';

  String get configPath => '$hermesHome/config.yaml';
  String get envPath => '$hermesHome/.env';
  String get authPath => '$hermesHome/auth.json';
  String get logsDir => '$hermesHome/logs';

  Future<String> readConfig() async {
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
    try {
      await File(configPath).writeAsString(content);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isGatewayRunning() async {
    try {
      final result = await HttpClient()
          .getUrl(Uri.parse('http://localhost:8642/api/health'))
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

  Future<Map<String, Map<String, String>>> getAuthProviders() async {
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
    final platforms = <PlatformConfig>[];
    final platformNames = [
      'telegram', 'discord', 'slack', 'whatsapp',
      'feishu', 'wecom', 'matrix', 'wechat',
    ];

    for (final name in platformNames) {
      final configured = config.contains('$name:') && !config.contains('$name: {}');
      final hasToken = config.contains('token') || config.contains('app_id') || config.contains('secret');
      final displayName = _platformDisplayName(name);
      platforms.add(PlatformConfig(
        name: displayName,
        configured: configured && hasToken,
        status: configured && hasToken ? 'connected' : 'disconnected',
      ));
    }

    return platforms;
  }

  Future<String> getLogContent(String source, {int lines = 200}) async {
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
      default: return name;
    }
  }
}
