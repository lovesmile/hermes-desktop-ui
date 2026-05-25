import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'connection_manager.dart';

/// 统一文件操作层：本地（WSL bash）或远程（SSH），通过 [ConnectionManager.runShell] 执行。
/// 不依赖 dart:io，适用于 WSL Ubuntu / 内嵌 Hermes / 云服务器 / macOS。
class HermesFileService {
  final ConnectionManager _cm;

  HermesFileService([ConnectionManager? cm]) : _cm = cm ?? ConnectionManager();

  /// 读取文件全部内容。返回空字符串表示文件不存在或为空。
  Future<String> readText(String path) async {
    try {
      final result = await _cm.runShell('cat "$path" 2>/dev/null || true');
      return result.stdout;
    } catch (e) {
      debugPrint('HermesFileService.readText error: $e');
      return '';
    }
  }

  /// 按行读取文件，取最后 [limit] 行。
  Future<String> readTail(String path, {int limit = 200}) async {
    try {
      final result = await _cm.runShell('tail -n $limit "$path" 2>/dev/null || true');
      return result.stdout;
    } catch (e) {
      return '';
    }
  }

  /// 写入文件（覆盖）。用 base64 避免 shell 转义问题。
  Future<bool> writeText(String path, String content) async {
    try {
      final b64 = base64Encode(utf8.encode(content));
      await _cm.runShell('echo "$b64" | base64 -d > "$path" 2>/dev/null');
      return true;
    } catch (e) {
      debugPrint('HermesFileService.writeText error: $e');
      return false;
    }
  }

  /// 追加内容到文件
  Future<bool> appendText(String path, String content) async {
    try {
      final b64 = base64Encode(utf8.encode(content));
      await _cm.runShell('echo "$b64" | base64 -d >> "$path" 2>/dev/null');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 文件是否存在
  Future<bool> exists(String path) async {
    try {
      final result = await _cm.runShell('test -f "$path" && echo YES || echo NO');
      return result.stdout.trim() == 'YES';
    } catch (_) {
      return false;
    }
  }

  /// 目录是否存在
  Future<bool> dirExists(String path) async {
    try {
      final result = await _cm.runShell('test -d "$path" && echo YES || echo NO');
      return result.stdout.trim() == 'YES';
    } catch (_) {
      return false;
    }
  }

  /// 删除文件
  Future<bool> delete(String path) async {
    try {
      await _cm.runShell('rm -f "$path"');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 列目录，返回文件名列表（不含路径）
  Future<List<String>> listFiles(String dirPath) async {
    try {
      final result = await _cm.runShell('ls -1A "$dirPath" 2>/dev/null || true');
      if (result.stdout.trim().isEmpty) return [];
      return result.stdout.split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 列出目录下所有子目录
  Future<List<String>> listDirs(String dirPath) async {
    try {
      final result = await _cm.runShell(
          'find "$dirPath" -maxdepth 1 -type d 2>/dev/null | tail -n +2 || true');
      if (result.stdout.trim().isEmpty) return [];
      return result.stdout.split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => l.split('/').last)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 递归遍历目录，返回所有文件的完整路径
  Future<List<String>> listFilesRecursive(String dirPath, {String pattern = '*'}) async {
    try {
      final result = await _cm.runShell(
          'find "$dirPath" -type f -name "$pattern" 2>/dev/null | sort || true');
      if (result.stdout.trim().isEmpty) return [];
      return result.stdout.split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取文件大小（字节）
  Future<int> fileSize(String path) async {
    try {
      final result = await _cm.runShell('stat -c%s "$path" 2>/dev/null || echo 0');
      return int.tryParse(result.stdout.trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 解析 Hermes Home 路径
  Future<String> resolveHermesHome() async {
    // 优先：hermes env HERMES_HOME
    try {
      final result = await _cm.runShell(
          'hermes env HERMES_HOME 2>/dev/null || echo ""');
      final home = result.stdout.trim();
      if (home.isNotEmpty) return home;
    } catch (_) {}

    // 其次：echo $HERMES_HOME
    try {
      final result = await _cm.runShell('echo \$HERMES_HOME');
      final home = result.stdout.trim();
      if (home.isNotEmpty) return home;
    } catch (_) {}

    // 最后：默认路径
    try {
      final result = await _cm.runShell('echo \$HOME');
      final home = result.stdout.trim();
      if (home.isNotEmpty) return '$home/.hermes';
    } catch (_) {}

    return '~/.hermes';
  }

  /// 轻量获取技能数量（不读 SKILL.md）
  Future<int> countSkills() async {
    try {
      final home = await resolveHermesHome();
      final result = await _cm.runShell(
          'ls -1A "$home/skills"/*/*/SKILL.md 2>/dev/null | wc -l || echo 0');
      return int.tryParse(result.stdout.trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 获取技能列表（解析 ~/.hermes/skills/ 下所有 SKILL.md）
  Future<List<Map<String, String>>> getSkills() async {
    final skills = <Map<String, String>>[];
    try {
      final home = await resolveHermesHome();
      final skillsDir = '$home/skills';
      if (!await dirExists(skillsDir)) return skills;

      final categories = await listDirs(skillsDir);
      for (final cat in categories) {
        final catDir = '$skillsDir/$cat';
        final entries = await listFiles(catDir);
        for (final entry in entries) {
          final skillDir = '$catDir/$entry';
          if (!await dirExists(skillDir)) continue;
          final mdContent = await readText('$skillDir/SKILL.md');
          if (mdContent.isEmpty) continue;

          final name = _extractYamlField(mdContent, 'name') ?? entry;
          final desc = _extractYamlField(mdContent, 'description') ?? '';
          final version = _extractYamlField(mdContent, 'version') ?? '';
          skills.add({
            'name': name,
            'description': desc,
            'version': version,
            'path': skillDir,
          });
        }
      }
    } catch (e) {
      debugPrint('HermesFileService.getSkills error: $e');
    }
    skills.sort((a, b) => a['name']!.compareTo(b['name']!));
    return skills;
  }

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

  /// 获取日志文件内容（source = agent / gateway / errors）
  Future<String> getLogContent(String source, {int lines = 200}) async {
    try {
      final home = await resolveHermesHome();
      final path = '$home/logs/$source.log';
      return await readTail(path, limit: lines);
    } catch (e) {
      return '读取日志失败: $e';
    }
  }

  /// 获取日志文件总大小（字节）
  Future<int> getLogsSize() async {
    try {
      final home = await resolveHermesHome();
      final logDir = '$home/logs';
      if (!await dirExists(logDir)) return 0;
      final result = await _cm.runShell(
          'du -sb "$logDir" 2>/dev/null | cut -f1 || echo 0');
      return int.tryParse(result.stdout.trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
