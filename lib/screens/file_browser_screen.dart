import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../config/theme.dart';
import '../services/connection_manager.dart';
import '../services/hermes_file_service.dart';

/// 文件浏览器 — 根目录为用户 home（~），通过 [HermesFileService] 统一走 shell。
/// 本地模式（WSL）支持"在资源管理器中显示"；远程模式（SSH）支持"下载"。
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final _fileService = HermesFileService();
  final _cm = ConnectionManager();

  String _currentPath = '';
  bool _loading = true;
  String _error = '';

  // 当前目录内容
  List<FileItem> _items = [];

  // 文件预览
  String? _previewPath;
  String _previewContent = '';
  bool _previewLoading = false;

  // 连接模式：local（WSL）或 remote（SSH）
  bool _isLocal = true;

  @override
  void initState() {
    super.initState();
    _isLocal = _cm.state.mode == ConnectionMode.local;
    _resolveHome();
  }

  Future<void> _resolveHome() async {
    setState(() => _loading = true);
    try {
      final home = await _fileService.resolveHermesHome();
      final parent = home.substring(0, home.lastIndexOf('/'));
      _currentPath = parent; // ~/.hermes 的上层即 ~
      await _loadDir();
    } catch (e) {
      // fallback
      _currentPath = '/home/tian';
      await _loadDir();
    }
  }

  Future<void> _loadDir() async {
    setState(() => _loading = true);
    try {
      final entries = await _fileService.listFiles(_currentPath);
      final dirs = <FileItem>[];
      final files = <FileItem>[];

      for (final name in entries) {
        final full = '$_currentPath/$name';
        final isDir = await _fileService.dirExists(full);
        final size = isDir ? 0 : await _fileService.fileSize(full);
        final item = FileItem(name: name, path: full, isDir: isDir, size: size);
        if (isDir) {
          dirs.add(item);
        } else {
          files.add(item);
        }
      }

      dirs.sort((a, b) => a.name.compareTo(b.name));
      files.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _items = [...dirs, ...files];
        _loading = false;
        _error = '';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '读取目录失败: $e';
        _items = [];
      });
    }
  }

  Future<void> _enterDir(String path) async {
    _currentPath = path;
    await _loadDir();
  }

  Future<void> _goUp() async {
    final parent = _currentPath.contains('/')
        ? _currentPath.substring(0, _currentPath.lastIndexOf('/'))
        : _currentPath;
    if (parent.isNotEmpty && parent != _currentPath) {
      _currentPath = parent.isEmpty ? '/' : parent;
      await _loadDir();
    }
  }

  Future<void> _previewFile(String path) async {
    setState(() {
      _previewPath = path;
      _previewLoading = true;
      _previewContent = '';
    });
    try {
      final content = await _fileService.readText(path);
      setState(() {
        _previewContent = content.isNotEmpty ? content : '（空文件）';
        _previewLoading = false;
      });
    } catch (e) {
      setState(() {
        _previewContent = '读取失败: $e';
        _previewLoading = false;
      });
    }
  }

  /// 本地模式：在 Windows 资源管理器中打开文件所在位置
  Future<void> _openInExplorer() async {
    if (_previewPath == null) return;
    // /home/tian/.hermes/... → \\wsl.localhost\Ubuntu\home\tian\.hermes\...
    final winPath =
        _previewPath!.replaceAll('/', '\\').replaceFirst('\\home', '\\\\wsl.localhost\\Ubuntu\\home');
    try {
      await Process.run('explorer.exe', ['/select,$winPath']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开资源管理器失败: $e')),
        );
      }
    }
  }

  /// 远程模式：下载文件到本地 Windows
  Future<void> _downloadFile() async {
    if (_previewPath == null) return;
    final fileName = _previewPath!.split('/').last;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '下载文件',
      fileName: fileName,
    );
    if (result == null) return; // 用户取消

    try {
      final content = await _fileService.readText(_previewPath!);
      await File(result).writeAsString(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载到 $result')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件浏览'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDir,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: _resolveHome,
            tooltip: '回到 Home',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── 面包屑导航 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _currentPath.contains('/') ? _goUp : null,
                  child: Icon(
                    Icons.arrow_upward,
                    size: 18,
                    color: _currentPath.contains('/')
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _currentPath,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 主区域：文件列表 + 预览面板（左右分栏） ──
          Expanded(
            child: Row(
              children: [
                // 文件列表（左）
                Expanded(
                  flex: _previewPath != null ? 1 : 1,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error.isNotEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline, size: 48,
                                      color: cs.error),
                                  const SizedBox(height: 12),
                                  Text(_error,
                                      style: TextStyle(color: cs.error)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _loadDir,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('重试'),
                                  ),
                                ],
                              ),
                            )
                          : _items.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.folder_off_outlined, size: 48,
                                          color: cs.onSurfaceVariant),
                                      const SizedBox(height: 12),
                                      Text('空目录',
                                          style: TextStyle(
                                              color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                )
                              : _buildFileList(cs),
                ),

                // 预览面板（右）
                if (_previewPath != null)
                  Container(
                    width: 440,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      border:
                          Border(left: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Column(
                      children: [
                        // 标题栏：文件名 + 操作按钮
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            border: Border(
                                bottom:
                                    BorderSide(color: cs.outlineVariant)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.description_outlined, size: 16,
                                  color: cs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _previewPath!.split('/').last,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // 本地 → 资源管理器；远程 → 下载
                              if (_isLocal)
                                IconButton(
                                  icon: Icon(Icons.folder_open_outlined,
                                      size: 16, color: cs.primary),
                                  onPressed: _openInExplorer,
                                  tooltip: '在资源管理器中显示',
                                  visualDensity: VisualDensity.compact,
                                )
                              else
                                IconButton(
                                  icon: Icon(Icons.download_outlined,
                                      size: 16, color: cs.primary),
                                  onPressed: _downloadFile,
                                  tooltip: '下载',
                                  visualDensity: VisualDensity.compact,
                                ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () =>
                                    setState(() => _previewPath = null),
                                visualDensity: VisualDensity.compact,
                                tooltip: '关闭预览',
                              ),
                            ],
                          ),
                        ),
                        // 文件内容
                        Expanded(
                          child: _previewLoading
                              ? const Center(
                                  child: CircularProgressIndicator())
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: SelectableText(
                                    _previewContent,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: cs.onSurface,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final isSelected = item.path == _previewPath;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          selected: isSelected,
          selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
          leading: Icon(
            item.isDir
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
            size: 20,
            color:
                item.isDir ? AppTheme.warning : cs.onSurfaceVariant,
          ),
          title: Text(
            item.name,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: item.isDir
              ? null
              : Text(
                  _formatSize(item.size),
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
          trailing: item.isDir
              ? Icon(Icons.chevron_right,
                  size: 18, color: cs.onSurfaceVariant)
              : IconButton(
                  icon: Icon(Icons.visibility_outlined,
                      size: 18, color: cs.primary),
                  onPressed: () => _previewFile(item.path),
                  tooltip: '预览',
                  visualDensity: VisualDensity.compact,
                ),
          onTap: item.isDir
              ? () => _enterDir(item.path)
              : () => _previewFile(item.path),
        );
      },
    );
  }
}

class FileItem {
  final String name;
  final String path;
  final bool isDir;
  final int size;

  FileItem({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
  });
}
