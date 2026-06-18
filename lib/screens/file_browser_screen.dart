import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../config/theme.dart';
import '../services/connection_manager.dart';
import '../services/hermes_file_service.dart';
import '../services/gateway_service.dart';

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
  ConnStatus _lastConnStatus = ConnStatus.disconnected;

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

  // 目录缓存 { path → items }，避免回退/前进重复加载
  final _dirCache = <String, List<FileItem>>{};

  // ── helpers ──

  /// 跨平台获取父目录路径（优先 /，兼容 \）
  static String _parentPath(String path) {
    if (path.isEmpty) return path;
    var idx = path.lastIndexOf('/');
    if (idx <= 0) idx = path.lastIndexOf('\\');
    if (idx <= 0) return path;
    // Windows 盘符根目录 C:\ → 不再向上
    if (idx == 2 && path.length > 2 && path[1] == ':') return path;
    return path.substring(0, idx);
  }

  /// 跨平台取路径最后一段
  static String _basename(String path) =>
      path.split(RegExp(r'[/\\]')).last;

  /// 跨平台判断是否为根目录（不可再向上）
  static bool _canGoUp(String path) =>
      path.isNotEmpty && _parentPath(path) != path;

  // ── lifecycle ──

  @override
  void initState() {
    super.initState();
    _isLocal = _cm.state.mode == ConnectionMode.local;
    _resolveHome();
    GatewayService().refreshNotifier.addListener(_onModeChanged);
    _cm.stateNotifier.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    GatewayService().refreshNotifier.removeListener(_onModeChanged);
    _cm.stateNotifier.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    final current = _cm.state.status;
    if (current == ConnStatus.connected && _lastConnStatus != ConnStatus.connected) {
      _dirCache.clear();
      _isLocal = _cm.state.mode == ConnectionMode.local;
      _previewPath = null;
      _resolveHome();
    }
    _lastConnStatus = current;
  }

  void _onModeChanged() {
    _dirCache.clear();
    _isLocal = _cm.state.mode == ConnectionMode.local;
    _previewPath = null;
    _resolveHome();
  }

  Future<void> _resolveHome() async {
    // connecting 过渡态不加载，避免用错误路径缓存数据
    if (_cm.state.status != ConnStatus.connected) return;
    _dirCache.clear();
    setState(() => _loading = true);
    try {
      final home = await _fileService.resolveHermesHome();
      _currentPath = _parentPath(home);
      await _loadDir();
    } catch (e) {
      // fallback
      _currentPath = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '/home';
      await _loadDir();
    }
  }

  Future<void> _loadDir({bool forceRefresh = false}) async {
    if (forceRefresh) _dirCache.remove(_currentPath);

    // 命中缓存 → 直接显示，不转圈
    final cached = _dirCache[_currentPath];
    if (cached != null) {
      setState(() { _items = cached; _error = ''; _loading = false; });
      return;
    }

    setState(() => _loading = true);
    try {
      final entries = await _fileService.listFilesWithDetails(_currentPath);
      final dirs = <FileItem>[];
      final files = <FileItem>[];

      for (final e in entries) {
        final full = '$_currentPath/${e.name}';
        final item = FileItem(name: e.name, path: full, isDir: e.isDir, size: e.size);
        if (e.isDir) {
          dirs.add(item);
        } else {
          files.add(item);
        }
      }

      dirs.sort((a, b) => a.name.compareTo(b.name));
      files.sort((a, b) => a.name.compareTo(b.name));

      final items = [...dirs, ...files];
      _dirCache[_currentPath] = items; // 写入缓存

      setState(() {
        _items = items;
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
    if (_currentPath.isEmpty) return;
    final parent = _parentPath(_currentPath);
    if (parent != _currentPath) {
      _currentPath = parent;
      await _loadDir();
    }
  }

  static const _maxPreviewSize = 1024 * 1024; // 1 MB
  static const _binaryExtensions = <String>{
    '.exe', '.dll', '.so', '.dylib', '.bin', '.obj', '.lib',
    '.zip', '.tar', '.gz', '.7z', '.rar',
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.svg',
    '.mp3', '.mp4', '.avi', '.mov', '.wav', '.flac',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx',
    '.db', '.sqlite', '.o', '.pyc', '.class',
  };

  Future<void> _previewFile(String path) async {
    // 检查扩展名
    final ext = path.split(RegExp(r'[/\\]')).last.split('.').last.toLowerCase();
    if (_binaryExtensions.contains('.$ext')) {
      setState(() {
        _previewPath = path;
        _previewLoading = false;
        _previewContent = '⚠️ 二进制文件无法预览';
      });
      return;
    }

    // 检查文件大小
    final itemIx = _items.indexWhere((e) => e.path == path);
    final itemSize = itemIx >= 0 ? _items[itemIx].size : 0;
    if (itemSize > _maxPreviewSize) {
      setState(() {
        _previewPath = path;
        _previewLoading = false;
        _previewContent = '⚠️ 文件过大（${_formatSize(itemSize)}），超过预览上限（${_formatSize(_maxPreviewSize)}）';
      });
      return;
    }

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

  /// 上传文件到当前目录
  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要上传的文件',
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    final bytes = await File(file.path!).readAsBytes();
    final dest = '$_currentPath/${file.name}';
    try {
      final ok = await _fileService.writeBytes(dest, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '已上传到 $dest' : '上传失败')),
        );
        if (ok) _loadDir();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    }
  }

  /// 本地模式（WSL）：在 Windows 资源管理器中打开文件所在位置
  Future<void> _openInExplorer() async {
    if (_previewPath == null) return;
    final distro = _cm.wslDistro;
    // /home/<user>/.hermes/... → \\wsl.localhost\<distro>\home\<user>\.hermes\...
    final winPath = _previewPath!
        .replaceAll('/', '\\')
        .replaceFirst(r'\home', '\\\\wsl.localhost\\$distro\\home');
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
    final fileName = _basename(_previewPath!);
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
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _uploadFile,
            tooltip: '上传文件',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDir(forceRefresh: true),
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
                  onTap: _canGoUp(_currentPath) ? _goUp : null,
                  child: Icon(
                    Icons.arrow_upward,
                    size: 18,
                    color: _canGoUp(_currentPath)
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
                        fontFamily: 'JetBrainsMono',
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
                                    onPressed: () => _loadDir(forceRefresh: true),
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
                                  _basename(_previewPath!),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // 下载（所有模式）
                              IconButton(
                                icon: Icon(Icons.download_outlined,
                                    size: 16, color: cs.primary),
                                onPressed: _downloadFile,
                                tooltip: '下载',
                                visualDensity: VisualDensity.compact,
                              ),
                              // 本地模式额外支持"在资源管理器中显示"
                              if (_isLocal)
                                IconButton(
                                  icon: Icon(Icons.folder_open_outlined,
                                      size: 16, color: cs.primary),
                                  onPressed: _openInExplorer,
                                  tooltip: '在资源管理器中显示',
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
                                      fontFamily: 'JetBrainsMono',
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
