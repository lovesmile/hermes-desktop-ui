import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/connection_manager.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _cm = ConnectionManager();

  String _currentPath = '';
  List<_FileItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final path = _currentPath.isEmpty ? r'$HOME' : r'$HOME/' + _currentPath;
      final cmd =
          "p=\"$path\"; ls -1A \"\$p\" 2>/dev/null | while IFS= read -r name; do "
          "  [ -z \"\$name\" ] && continue; "
          "  full=\"\$p/\$name\"; "
          "  if [ -d \"\$full\" ]; then "
          "    echo \"d|0||\$name\"; "
          "  elif [ -f \"\$full\" ]; then "
          "    size=\$(stat -c '%s' \"\$full\" 2>/dev/null || echo 0); "
          "    mtime=\$(stat -c '%Y' \"\$full\" 2>/dev/null || echo ''); "
          "    if [ -n \"\$mtime\" ] && [ \"\$mtime\" != \"0\" ]; then "
          "      mtime=\$(date -d \"@\$mtime\" '+%Y-%m-%d %H:%M' 2>/dev/null || echo ''); "
          "    else "
          "      mtime=''; "
          "    fi; "
          "    echo \"-|\$size|\$mtime|\$name\"; "
          "  fi; "
          "done";

      String rawOutput;
      if (_cm.state.mode == ConnectionMode.remote) {
        rawOutput = await _cm.execRemote(cmd);
      } else {
        final r = await _cm.execBash(cmd);
        rawOutput = r.stdout as String;
      }

      final items = <_FileItem>[];
      for (final line in rawOutput.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        // 格式: d|0||name  或  -|1234|2025-05-24 10:00|name
        final sep = t.indexOf('|');
        if (sep < 0) continue;
        final type = t.substring(0, sep);
        final rest = t.substring(sep + 1);
        final parts = rest.split('|');
        if (parts.length < 3) continue;
        final sizeStr = parts[0];
        final mtimeStr = parts[1];
        // 文件名可能含 |，剩下全是文件名
        final name = parts.sublist(2).join('|');
        items.add(_FileItem(
          name: name,
          isDir: type == 'd',
          size: int.tryParse(sizeStr) ?? 0,
          mtime: mtimeStr,
        ));
      }
      // 排序：文件夹在前，字母序
      items.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.compareTo(b.name);
      });
      if (mounted) setState(() { _items = items; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _enterDir(String name) {
    _currentPath = _currentPath.isEmpty ? name : '$_currentPath/$name';
    _loadFiles();
  }

  void _goBack() {
    final parts = _currentPath.split('/');
    parts.removeLast();
    _currentPath = parts.join('/');
    _loadFiles();
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPath.isEmpty ? '~/' : '~/$_currentPath'),
        actions: [
          if (_currentPath.isNotEmpty)
            IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _goBack, tooltip: '上级'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles, tooltip: '刷新'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: cs.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      FilledButton.tonal(onPressed: _loadFiles, child: const Text('重试')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(child: Text('空目录', style: TextStyle(color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final icon = item.isDir
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined;
                        final iconColor = item.isDir ? AppTheme.warning : AppTheme.primary;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: InkWell(
                            onTap: item.isDir ? () => _enterDir(item.name) : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(icon, color: iconColor, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                        if (!item.isDir && item.size > 0)
                                          Text(_fmtSize(item.size),
                                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  if (item.mtime.isNotEmpty)
                                    Text(item.mtime,
                                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _FileItem {
  final String name;
  final bool isDir;
  final int size;
  final String mtime;
  const _FileItem({required this.name, required this.isDir, this.size = 0, this.mtime = ''});
}
