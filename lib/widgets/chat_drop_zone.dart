import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// 包裹输入区的拖拽区域
/// 拖入文件时显示半透明遮罩提示，松开后回调 onFileDropped
class ChatDropZone extends StatefulWidget {
  final Widget child;
  final ValueChanged<List<Map<String, String>>> onFileDropped;

  const ChatDropZone({
    super.key,
    required this.child,
    required this.onFileDropped,
  });

  @override
  State<ChatDropZone> createState() => _ChatDropZoneState();
}

class _ChatDropZoneState extends State<ChatDropZone> {
  bool _isDragOver = false;

  Future<void> _onDrop(List<XFile> files) async {
    setState(() => _isDragOver = false);

    final results = <Map<String, String>>[];
    for (final xf in files) {
      final file = File(xf.path);
      if (!await file.exists()) continue;
      try {
        final bytes = await file.readAsBytes();
        final b64 = base64Encode(bytes);
        final name = xf.name;
        final ext = name.split('.').last.toLowerCase();
        final mime = _guessMime(ext);
        results.add({'name': name, 'path': xf.path, 'mime': mime, 'b64': b64});
      } catch (e) {
        debugPrint('ChatDropZone: 读取文件失败 [${xf.path}]: $e');
      }
    }
    if (results.isNotEmpty) {
      widget.onFileDropped(results);
    }
  }

  String _guessMime(String ext) {
    const mimeMap = {
      'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'svg': 'image/svg+xml', 'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain', 'csv': 'text/csv', 'json': 'application/json',
      'md': 'text/markdown', 'py': 'text/x-python', 'js': 'text/javascript',
      'html': 'text/html', 'css': 'text/css',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
      'zip': 'application/zip', 'gz': 'application/gzip',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
      onDragDone: (detail) => _onDrop(detail.files),
      child: Stack(
        children: [
          widget.child,
          if (_isDragOver)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.primary,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_upload_outlined,
                          size: 40, color: scheme.primary),
                      const SizedBox(height: 8),
                      Text('释放文件以添加附件',
                          style: TextStyle(color: scheme.primary, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
