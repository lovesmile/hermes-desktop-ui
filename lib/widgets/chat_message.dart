import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatMessageWidget extends StatelessWidget {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<Map<String, dynamic>>? toolCalls;
  final List<Map<String, String>>? attachments;

  const ChatMessageWidget({
    super.key,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.toolCalls,
    this.attachments,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.6)),
              ),
              child: Center(
                child: Text('⚡',
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: GestureDetector(
              onSecondaryTapUp: (details) => _showCopyMenu(context, details),
              onLongPress: () => _showCopyMenu(context, null),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isUser ? 615 : 715,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: isUser
                      ? Color.lerp(scheme.surfaceContainerHigh, Colors.black, 0.12)!
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 8 : 2),
                    topRight: Radius.circular(isUser ? 2 : 8),
                    bottomLeft: const Radius.circular(8),
                    bottomRight: const Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Attachment chips
                    if (attachments != null && attachments!.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: attachments!.map((att) {
                          final name = att['name'] ?? '';
                          final mime = att['mime'] ?? '';
                          final isImage = mime.startsWith('image/');
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isImage ? Icons.image : Icons.attach_file,
                                  size: 14,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(name,
                                  style: TextStyle(fontSize: 11, color: scheme.primary),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    MarkdownBody(
                      data: content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          height: 1.6,
                        ),
                        code: TextStyle(
                          color: scheme.tertiary,
                          fontSize: 13,
                          fontFamily: 'JetBrainsMono',
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        h1: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                        h2: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                        h3: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(
                                  color: scheme.primary, width: 3)),
                          color: scheme.surfaceContainerLow,
                        ),
                        tableHead: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                        tableBody: TextStyle(
                            color: textColor, fontSize: 14),
                        listBullet: TextStyle(color: scheme.primary),
                        listBulletPadding: const EdgeInsets.only(right: 4),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: scheme.outlineVariant,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (toolCalls != null && toolCalls!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...toolCalls!.map((tc) => _ToolCallCard(tc: tc)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _formatTimestamp(timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text('U',
                    style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showCopyMenu(BuildContext context, TapUpDetails? details) {
    final renderBox = context.findRenderObject() as RenderBox;
    final pos = details?.globalPosition ?? renderBox.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          child: SizedBox(
            width: 100,
            child: Row(
              children: [
                Icon(Icons.copy, size: 16, color: Theme.of(context).colorScheme.onSurface),
                const SizedBox(width: 8),
                Text('复制', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
        );
      }
    });
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dt.year, dt.month, dt.day);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (msgDate == today) return time;
    final yesterday = today.subtract(const Duration(days: 1));
    if (msgDate == yesterday) return '昨天 $time';
    if (dt.year == now.year) return '${dt.month}/${dt.day} $time';
    return '${dt.year}/${dt.month}/${dt.day} $time';
  }
}

class _ToolCallCard extends StatelessWidget {
  final Map<String, dynamic> tc;

  const _ToolCallCard({required this.tc});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = tc['name'] ?? tc['function'] ?? '未知工具';
    final params = tc['arguments'] ?? tc['params'] ?? '{}';
    final result = tc['result'];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.code, size: 14, color: scheme.primary),
          ),
          title: Text(
            '🔧 $name',
            style: TextStyle(
              fontSize: 12,
              color: scheme.primary,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '参数: $params',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '结果: ${result.toString().length > 200 ? '${result.toString().substring(0, 200)}...' : result}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.primary,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
