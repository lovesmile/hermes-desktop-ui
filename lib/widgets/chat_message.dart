import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../config/theme.dart';

class ChatMessageWidget extends StatelessWidget {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<Map<String, dynamic>>? toolCalls;

  const ChatMessageWidget({
    super.key,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.toolCalls,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isUser
        ? scheme.primaryContainer.withValues(alpha: 0.6)
        : scheme.surfaceContainerHigh;
    final textColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    final borderColor = isUser
        ? scheme.primary.withValues(alpha: 0.2)
        : scheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6750A4), Color(0xFFD0BCFF)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('H',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: GestureDetector(
              onSecondaryTapUp: (details) => _showCopyMenu(context, details),
              onLongPress: () => _showCopyMenu(context, null),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isUser ? 600 : 700,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isUser ? 14 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 14),
                  ),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          fontFamily: 'monospace',
                          backgroundColor: isDark ? Colors.white10 : Colors.black12,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        h1: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                        h2: TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.bold),
                        h3: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(
                                  color: scheme.primary, width: 3)),
                          color: scheme.surfaceContainerLow,
                        ),
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
            const SizedBox(width: 10),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.person, color: scheme.onPrimaryContainer, size: 18),
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
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
              fontFamily: 'monospace',
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
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '结果: ${result.toString().length > 200 ? '${result.toString().substring(0, 200)}...' : result}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.primary,
                        fontFamily: 'monospace',
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
