import 'package:flutter/material.dart';
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFF00E5FF)],
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
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isUser ? 600 : 700,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : AppTheme.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: Border.all(
                  color: isUser
                      ? AppTheme.primary.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: isUser ? Colors.white : Colors.white,
                        fontSize: 14,
                        height: 1.6,
                      ),
                      code: TextStyle(
                        color: AppTheme.secondary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        backgroundColor: Colors.black26,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      h1: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                      h2: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                      h3: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                            left: BorderSide(
                                color: AppTheme.primary, width: 3)),
                        color: Colors.white.withValues(alpha: 0.03),
                      ),
                      listBullet: TextStyle(color: AppTheme.primary),
                      listBulletPadding: const EdgeInsets.only(right: 4),
                      horizontalRuleDecoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Tool calls
                  if (toolCalls != null && toolCalls!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...toolCalls!.map((tc) => _ToolCallCard(tc: tc)),
                  ],
                  // Timestamp
                  const SizedBox(height: 6),
                  Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.person, color: Colors.white70, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
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
    final name = tc['name'] ?? tc['function'] ?? '未知工具';
    final params = tc['arguments'] ?? tc['params'] ?? '{}';
    final result = tc['result'];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.code, size: 14, color: AppTheme.primary),
          ),
          title: Text(
            '🔧 $name',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFBB86FC),
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
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '结果: ${result.toString().length > 200 ? '${result.toString().substring(0, 200)}...' : result}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4CAF50),
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
