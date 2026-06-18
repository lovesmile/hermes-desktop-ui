import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'connection_manager.dart';

class HermesFileService {
  final ConnectionManager _cm;
  HermesFileService([ConnectionManager? cm]) : _cm = cm ?? ConnectionManager();

  // ── home cache ──

  static String? _cachedHome;
  static ConnectionMode? _cachedHomeMode;

  static void clearCache() {
    _cachedHome = null;
    _cachedHomeMode = null;
  }

  // ── helpers ──

  /// 跨平台取路径的最后一段（兼容 / 和 \）
  static String _basename(String p) =>
      p.split(RegExp(r'[/\\]')).last;

  String _embeddedHermesHome() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return '$home/.hermes';
  }

  Future<String> _shell(String cmd) async {
    final r = await _cm.runShell(cmd, allowFailure: true);
    return r.stdout;
  }

  // ── read / write ──

  Future<String> readText(String path) async {
    final bytes = await readBytes(path);
    return bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List?> readBytes(String path) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded:
        try {
          return await File(path).readAsBytes();
        } catch (_) {
          return null;
        }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        try {
          final out = await _shell('base64 "$path" 2>/dev/null || true');
          final b64 = out.replaceAll(RegExp(r'\s+'), '');
          return b64.isEmpty ? null : base64Decode(b64);
        } catch (_) {
          return null;
        }
      }
    }
  }

  Future<bool> writeBytes(String path, Uint8List bytes) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded:
        try {
          await File(path).writeAsBytes(bytes);
          return true;
        } catch (_) {
          return false;
        }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        try {
          final b64 = base64Encode(bytes);
          final r = await _cm.runShell('echo "$b64" | base64 -d > "$path"');
          return r.exitCode == 0;
        } catch (_) {
          return false;
        }
      }
    }
  }

  Future<bool> writeText(String path, String content) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded:
        try {
          await File(path).writeAsString(content);
          return true;
        } catch (_) {
          return false;
        }
      case ConnectionMode.local:
      case ConnectionMode.remote:
        return writeBytes(path, Uint8List.fromList(utf8.encode(content)));
    }
  }

  // ── path resolution ──

  Future<String> resolveHomeDir() async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded:
        return Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            '';
      case ConnectionMode.remote: {
        // pwd 不需要 shell 展开，SSH 连接的默认工作目录就是远程用户 home
        final r = await _cm.runShell('pwd');
        return r.stdout.isEmpty ? '/home/unknown' : r.stdout;
      }
      case ConnectionMode.local: {
        final r = await _cm.runShell('echo \$HOME');
        return r.stdout.isEmpty ? '~' : r.stdout;
      }
    }
  }

  Future<String> resolveHermesHome() async {
    final mode = _cm.state.mode;
    // connecting 过渡态不缓存，等真实 mode 确定后再缓存（避免本地路径被当作远程路径缓存）
    if (_cachedHome != null && _cachedHomeMode == mode && _cm.state.status.index < 2) return _cachedHome!;
    final home = switch (mode) {
      ConnectionMode.embedded => _embeddedHermesHome(),
      ConnectionMode.local || ConnectionMode.remote =>
        '${await resolveHomeDir()}/.hermes',
    };
    _cachedHome = home;
    _cachedHomeMode = mode;
    return home;
  }

  // ── skills ──

  Future<List<Map<String, String>>> getSkills() async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded:
        return _getSkillsLocal();
      case ConnectionMode.local:
        return _parseSkillsOutput(
            await _shell(_scanSkillsCmd(await resolveHermesHome())));
      case ConnectionMode.remote:
        return _parseSkillsOutput(await _shell(
            _scanSkillsCmd(await resolveHermesHome())));
    }
  }

  /// 批量读取 config.yaml + 扫描技能（local/remote 只需 1 次 SSH 往返）
  Future<({String config, List<Map<String, String>> skills})> readConfigAndSkills() async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        final home = _embeddedHermesHome();
        return (
          config: await readText('$home/config.yaml'),
          skills: await _getSkillsLocal(),
        );
      }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        final home = await resolveHermesHome();
        final isRemote = _cm.state.mode == ConnectionMode.remote;
        final skillsCmd = isRemote
            ? _scanSkillsCmd(home)
            : _scanSkillsCmd(home);
        final combined = await _shell(
          'cat "$home/config.yaml" 2>/dev/null || echo "config not found"; '
          'echo "===SKILLS==="; $skillsCmd',
        );
        final parts = combined.split('===SKILLS===');
        return (
          config: parts.isNotEmpty ? parts[0].trim() : 'config not found',
          skills: parts.length > 1 ? _parseSkillsOutput(parts[1]) : <Map<String, String>>[],
        );
      }
    }
  }

  /// 生成扫描技能元信息的 bash 命令（local 直用，remote 转义 $ 后用）
  String _scanSkillsCmd(String hermesHome) =>
      'find "$hermesHome/skills" -name "SKILL.md" -maxdepth 4 2>/dev/null | '
      'while IFS= read -r p; do '
      'n=\$(grep -m1 "^name:" "\$p" 2>/dev/null | sed "s/^name: *//"); '
      'd=\$(grep -m1 "^description:" "\$p" 2>/dev/null | sed "s/^description: *//"); '
      'echo "\$p||\$n||\$d"; done';

  /// local/remote 共用：按行解析路径||名称||描述
  List<Map<String, String>> _parseSkillsOutput(String raw) {
    final skills = <Map<String, String>>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final parts = t.split('||');
      if (parts.isEmpty) continue;
      final skillPath = parts[0].substring(0, parts[0].lastIndexOf('/'));
      final rawName = parts.length > 1 ? parts[1] : '';
      final rawDesc = parts.length > 2 ? parts[2] : '';
      skills.add({
        'name': rawName.isNotEmpty
            ? rawName.replaceAll("'", '').replaceAll('"', '').trim()
            : skillPath.split('/').last,
        'description': rawDesc.replaceAll("'", '').replaceAll('"', '').trim(),
        'path': skillPath,
      });
    }
    return skills;
  }

  Future<List<Map<String, String>>> _getSkillsLocal() async {
    final skills = <Map<String, String>>[];
    try {
      final dir = Directory('${_embeddedHermesHome()}/skills');
      if (!await dir.exists()) return skills;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('SKILL.md')) {
          try {
            final content = await entity.readAsString();
            if (content.isEmpty) continue;
            skills.add({
              'name': _extractYamlField(content, 'name') ?? _basename(entity.parent.path),
              'description': _extractYamlField(content, 'description') ?? '',
              'path': entity.parent.path,
            });
          } catch (_) {}
        }
      }
    } catch (_) {}
    return skills;
  }

  String? _extractYamlField(String content, String field) {
    for (final line in content.split('\n')) {
      if (line.trim().startsWith('$field:')) {
        return line.substring(line.indexOf(':') + 1).trim().replaceAll('"', '').replaceAll("'", "");
      }
    }
    return null;
  }

  Future<int> countSkills() async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        try {
          final dir = Directory('${_embeddedHermesHome()}/skills');
          if (!await dir.exists()) return 0;
          int count = 0;
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File && entity.path.endsWith('SKILL.md')) count++;
          }
          return count;
        } catch (_) {
          return 0;
        }
      }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        final hermesHome = await resolveHermesHome();
        final out = await _shell(
            'find "$hermesHome/skills" -name "SKILL.md" -maxdepth 4 2>/dev/null | wc -l');
        return int.tryParse(out) ?? 0;
      }
    }
  }

  // ── logs ──

  Future<int> getLogsSize() async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        try {
          final dir = Directory('${_embeddedHermesHome()}/logs');
          if (!await dir.exists()) return 0;
          int total = 0;
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) total += await entity.length();
          }
          return total;
        } catch (_) {
          return 0;
        }
      }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        final hermesHome = await resolveHermesHome();
        final out = await _shell(
            'du -sb "$hermesHome/logs" 2>/dev/null | cut -f1 || echo 0');
        return int.tryParse(out) ?? 0;
      }
    }
  }

  // ── file system ──

  Future<List<String>> listFiles(String dir) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        try {
          final d = Directory(dir);
          if (!await d.exists()) return [];
          final entries = await d.list().toList();
          entries.sort((a, b) => a.path.compareTo(b.path));
          return entries.map((e) => _basename(e.path)).toList();
        } catch (_) {
          return [];
        }
      }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        final out = await _shell('ls -1A "$dir" 2>/dev/null || true');
        return out
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
      }
    }
  }

  Future<bool> dirExists(String path) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded:
        return Directory(path).existsSync();
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        final out = await _shell('test -d "$path" && echo YES || echo NO');
        return out == 'YES';
      }
    }
  }

  Future<int> fileSize(String path) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        try {
          return await File(path).length();
        } catch (_) {
          return 0;
        }
      }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        final out = await _shell('stat -c%s "$path" 2>/dev/null || echo 0');
        return int.tryParse(out) ?? 0;
      }
    }
  }

  /// 批量获取文件列表+元信息（避免 N+1 SSH 往返）
  Future<List<({String name, bool isDir, int size})>> listFilesWithDetails(
      String path) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        try {
          final d = Directory(path);
          if (!await d.exists()) return [];
          final entries = await d.list().toList();
          entries.sort((a, b) => a.path.compareTo(b.path));
          return entries.map((e) {
            final stat = FileStat.statSync(e.path);
            return (
              name: _basename(e.path),
              isDir: stat.type == FileSystemEntityType.directory,
              size: stat.size,
            );
          }).toList();
        } catch (_) {
          return [];
        }
      }
      case ConnectionMode.local: {
        final out = await _shell(
            'ls -1A "$path" 2>/dev/null | while IFS= read -r n; do '
            'full="$path/\$n"; '
            'if [ -d "\$full" ]; then echo "D|\$n|"; '
            'else s=\$(stat -c%s "\$full" 2>/dev/null || echo 0); echo "F|\$n|\$s"; fi; done');
        return _parseFileEntries(out);
      }
      case ConnectionMode.remote: {
        final out = await _shell(
            'ls -1A "$path" 2>/dev/null | while IFS= read -r n; do '
            'full="$path/\$n"; '
            'if [ -d "\$full" ]; then echo "D|\$n|"; '
            'else s=\$(stat -c%s "\$full" 2>/dev/null || echo 0); echo "F|\$n|\$s"; fi; done'
                );
        return _parseFileEntries(out);
      }
    }
  }

  /// 解析 ls + while 循环输出的 D|name|size / F|name|size 行
  List<({String name, bool isDir, int size})> _parseFileEntries(String raw) =>
      raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) {
        final parts = l.split('|');
        final isDir = parts[0] == 'D';
        return (
          name: parts.length > 1 ? parts[1] : '',
          isDir: isDir,
          size: !isDir && parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
        );
      }).toList();

  // ── script discovery ──

  /// 在标准位置搜索脚本（$HERMES_HOME/scripts/ 或 scripts/）
  Future<String> findScript(String scriptName) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        final home = _embeddedHermesHome();
        final candidates = [
          '$home/scripts/$scriptName',
          'scripts/$scriptName',
        ];
        for (final p in candidates) {
          if (await File(p).exists()) return p;
        }
        throw Exception('找不到 $scriptName 脚本');
      }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        final hermesHome = await resolveHermesHome();
        final out = await _shell(
          'ls "${hermesHome}/scripts/${scriptName}" 2>/dev/null || '
          'ls "scripts/${scriptName}" 2>/dev/null || echo ""',
        );
        final path = out.trim();
        if (path.isEmpty) throw Exception('找不到 $scriptName 脚本');
        if (!path.startsWith('/')) return '${hermesHome}/scripts/${scriptName}';
        return path;
      }
    }
  }

  // ── directory operations ──

  Future<bool> deleteDir(String path) async {
    switch (_cm.state.mode) {
      case ConnectionMode.embedded: {
        try {
          final dir = Directory(path);
          if (!await dir.exists()) return false;
          await dir.delete(recursive: true);
          return true;
        } catch (_) {
          return false;
        }
      }
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        try {
          final r = await _cm.runShell(
              'rm -rf "$path" 2>/dev/null && echo OK || echo FAIL');
          return r.stdout.trim() == 'OK';
        } catch (_) {
          return false;
        }
      }
    }
  }
}
