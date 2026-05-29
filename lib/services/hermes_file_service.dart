import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'connection_manager.dart';

class HermesFileService {
  final ConnectionManager _cm;
  HermesFileService([ConnectionManager? cm]) : _cm = cm ?? ConnectionManager();

  Future<String> readText(String path) async {
    final bytes = await readBytes(path);
    return bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List?> readBytes(String path) async {
    try {
      final result = await _cm.runShell('base64 "$path" 2>/dev/null || true');
      final b64 = result.stdout.replaceAll(RegExp(r'\s+'), '');
      return b64.isEmpty ? null : base64Decode(b64);
    } catch (_) { return null; }
  }

  Future<bool> writeBytes(String path, Uint8List bytes) async {
    try {
      final b64 = base64Encode(bytes);
      final r = await _cm.runShell('echo "$b64" | base64 -d > "$path"');
      return r.exitCode == 0;
    } catch (_) { return false; }
  }

  Future<bool> writeText(String path, String content) async => writeBytes(path, Uint8List.fromList(utf8.encode(content)));

  Future<String> resolveHomeDir() async {
    final r = await _cm.runShell('echo \$HOME');
    return r.stdout.isEmpty ? '~' : r.stdout;
  }

  Future<String> resolveHermesHome() async {
    final home = await resolveHomeDir();
    return '$home/.hermes';
  }

  Future<List<Map<String, String>>> getSkills() async {
    final skills = <Map<String, String>>[];
    try {
      final hermesHome = await resolveHermesHome();
      final out = await _cm.runShell('find "$hermesHome/skills" -name "SKILL.md" -maxdepth 4 2>/dev/null');
      final paths = out.stdout.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty);
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

  String? _extractYamlField(String content, String field) {
    for (final line in content.split('\n')) {
      if (line.trim().startsWith('$field:')) {
        return line.substring(line.indexOf(':') + 1).trim().replaceAll('"', '').replaceAll("'", "");
      }
    }
    return null;
  }

  Future<int> countSkills() async {
    final hermesHome = await resolveHermesHome();
    final r = await _cm.runShell('find "$hermesHome/skills" -name "SKILL.md" -maxdepth 4 2>/dev/null | wc -l');
    return int.tryParse(r.stdout) ?? 0;
  }

  Future<int> getLogsSize() async {
    final hermesHome = await resolveHermesHome();
    final r = await _cm.runShell('du -sb "$hermesHome/logs" 2>/dev/null | cut -f1 || echo 0');
    return int.tryParse(r.stdout) ?? 0;
  }

  Future<List<String>> listFiles(String dir) async {
    final r = await _cm.runShell('ls -1A "$dir" 2>/dev/null || true');
    return r.stdout.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  Future<bool> dirExists(String path) async {
    final r = await _cm.runShell('test -d "$path" && echo YES || echo NO');
    return r.stdout == 'YES';
  }

  Future<int> fileSize(String path) async {
    final r = await _cm.runShell('stat -c%s "$path" 2>/dev/null || echo 0');
    return int.tryParse(r.stdout) ?? 0;
  }
}
