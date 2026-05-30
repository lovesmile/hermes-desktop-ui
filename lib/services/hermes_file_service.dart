import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'connection_manager.dart';

class HermesFileService {
  final ConnectionManager _cm;
  HermesFileService([ConnectionManager? cm]) : _cm = cm ?? ConnectionManager();

  // ── helpers ──

  bool get _isEmbedded => _cm.state.mode == ConnectionMode.embedded;

  /// 跨平台取路径的最后一段（兼容 / 和 \）
  static String _basename(String p) =>
      p.split(RegExp(r'[/\\]')).last;

  String _embeddedHermesHome() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return '$home/.hermes';
  }

  // ── read / write ──

  Future<String> readText(String path) async {
    if (_isEmbedded) {
      try {
        return await File(path).readAsString();
      } catch (_) {
        return '';
      }
    }
    final bytes = await readBytes(path);
    return bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List?> readBytes(String path) async {
    if (_isEmbedded) {
      try {
        return await File(path).readAsBytes();
      } catch (_) {
        return null;
      }
    }
    try {
      final result = await _cm.runShell('base64 "$path" 2>/dev/null || true');
      final b64 = result.stdout.replaceAll(RegExp(r'\s+'), '');
      return b64.isEmpty ? null : base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeBytes(String path, Uint8List bytes) async {
    if (_isEmbedded) {
      try {
        await File(path).writeAsBytes(bytes);
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      final b64 = base64Encode(bytes);
      final r = await _cm.runShell('echo "$b64" | base64 -d > "$path"');
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeText(String path, String content) async {
    if (_isEmbedded) {
      try {
        await File(path).writeAsString(content);
        return true;
      } catch (_) {
        return false;
      }
    }
    return writeBytes(path, Uint8List.fromList(utf8.encode(content)));
  }

  // ── path resolution ──

  Future<String> resolveHomeDir() async {
    if (_isEmbedded) {
      return Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
    }
    final r = await _cm.runShell('echo \$HOME');
    return r.stdout.isEmpty ? '~' : r.stdout;
  }

  Future<String> resolveHermesHome() async {
    if (_isEmbedded) {
      return _embeddedHermesHome();
    }
    final home = await resolveHomeDir();
    return '$home/.hermes';
  }

  // ── skills ──

  Future<List<Map<String, String>>> getSkills() async {
    if (_isEmbedded) return _getSkillsLocal();
    final skills = <Map<String, String>>[];
    try {
      final hermesHome = await resolveHermesHome();
      final out = await _cm.runShell(
          'find "$hermesHome/skills" -name "SKILL.md" -maxdepth 4 2>/dev/null');
      final paths = out.stdout
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty);
      for (final p in paths) {
        final content = await readText(p);
        if (content.isEmpty) continue;
        final skillPath = p.substring(0, p.lastIndexOf('/'));
        skills.add({
          'name': _extractYamlField(content, 'name') ?? skillPath.split('/').last,
          'description': _extractYamlField(content, 'description') ?? '',
          'path': skillPath,
        });
      }
    } catch (_) {}
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
              'name': _extractYamlField(content, 'name') ?? _basename(entity.parent.path),              'description': _extractYamlField(content, 'description') ?? '',
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
    if (_isEmbedded) {
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
    final hermesHome = await resolveHermesHome();
    final r = await _cm.runShell(
        'find "$hermesHome/skills" -name "SKILL.md" -maxdepth 4 2>/dev/null | wc -l');
    return int.tryParse(r.stdout) ?? 0;
  }

  // ── logs ──

  Future<int> getLogsSize() async {
    if (_isEmbedded) {
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
    final hermesHome = await resolveHermesHome();
    final r = await _cm.runShell(
        'du -sb "$hermesHome/logs" 2>/dev/null | cut -f1 || echo 0');
    return int.tryParse(r.stdout) ?? 0;
  }

  // ── file system ──

  Future<List<String>> listFiles(String dir) async {
    if (_isEmbedded) {
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
    final r =
        await _cm.runShell('ls -1A "$dir" 2>/dev/null || true');
    return r.stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  Future<bool> dirExists(String path) async {
    if (_isEmbedded) {
      return Directory(path).existsSync();
    }
    final r =
        await _cm.runShell('test -d "$path" && echo YES || echo NO');
    return r.stdout == 'YES';
  }

  Future<int> fileSize(String path) async {
    if (_isEmbedded) {
      try {
        return await File(path).length();
      } catch (_) {
        return 0;
      }
    }
    final r =
        await _cm.runShell('stat -c%s "$path" 2>/dev/null || echo 0');
    return int.tryParse(r.stdout) ?? 0;
  }

  // ── script discovery ──

  /// 在标准位置搜索脚本（$HERMES_HOME/scripts/ 或 scripts/）
  Future<String> findScript(String scriptName) async {
    if (_isEmbedded) {
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
    final hermesHome = await resolveHermesHome();
    final r = await _cm.runShell(
      'ls "${hermesHome}/scripts/${scriptName}" 2>/dev/null || '
      'ls "scripts/${scriptName}" 2>/dev/null || echo ""',
      allowFailure: true,
    );
    final path = r.stdout.trim();
    if (path.isEmpty) throw Exception('找不到 $scriptName 脚本');
    if (!path.startsWith('/')) return '${hermesHome}/scripts/${scriptName}';
    return path;
  }

  // ── directory operations ──

  /// 递归删除目录（按模式适配）
  Future<bool> deleteDir(String path) async {
    if (_isEmbedded) {
      try {
        final dir = Directory(path);
        if (!await dir.exists()) return false;
        await dir.delete(recursive: true);
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      final r = await _cm.runShell(
          'rm -rf "$path" 2>/dev/null && echo OK || echo FAIL');
      return r.stdout.trim() == 'OK';
    } catch (_) {
      return false;
    }
  }
}
