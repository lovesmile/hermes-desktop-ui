import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../models/session.dart';
import '../widgets/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _gateway = GatewayService();
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _searchController = TextEditingController();

  List<Session> _sessions = [];
  Session? _activeSession;
  List<_Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String _streamingContent = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _gateway.disconnectChat();
    _scrollController.dispose();
    _inputController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final sessions = await _gateway.getSessions();
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _selectSession(Session session) {
    setState(() {
      _activeSession = session;
      _messages = [];
      _streamingContent = '';
    });
    // TODO: load session messages from API
  }

  void _newChat() {
    setState(() {
      _activeSession = null;
      _messages = [];
      _streamingContent = '';
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    _inputController.clear();
    final msg = _Message(text: text, isUser: true, timestamp: DateTime.now());
    setState(() {
      _messages.add(msg);
      _sending = true;
      _streamingContent = '';
    });

    try {
      final stream = _gateway.chatStream(text,
          sessionId: _activeSession?.id);
      await for (final chunk in stream) {
        if (!mounted) break;
        setState(() => _streamingContent += chunk);
        _scrollToBottom();
      }
      if (_streamingContent.isNotEmpty) {
        setState(() {
          _messages.add(_Message(
            text: _streamingContent,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _streamingContent = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_Message(
            text: '⚠️ 发送失败: $e',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ));
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Session> get _filteredSessions {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _sessions;
    return _sessions
        .where((s) => s.title.toLowerCase().contains(q))
        .toList();
  }

  Map<String, List<Session>> get _groupedSessions {
    final groups = <String, List<Session>>{};
    for (final s in _filteredSessions) {
      groups.putIfAbsent(s.source, () => []).add(s);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_activeSession?.title ?? '新对话'),
        actions: [
          if (_activeSession != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _newChat,
              tooltip: '新对话',
            ),
        ],
      ),
      body: Row(
        children: [
          // Session sidebar
          SizedBox(
            width: 280,
            child: Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '搜索会话...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                // New chat button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _newChat,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新对话'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(
                            color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Session list
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _sessions.isEmpty
                          ? const Center(
                              child: Text('暂无会话',
                                  style: TextStyle(color: Colors.white38)))
                          : ListView(
                              children: _buildSessionGroups(),
                            ),
                ),
              ],
            ),
          ),
          // Divider
          Container(
            width: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          // Chat area
          Expanded(
            child: Column(
              children: [
                // Messages
                Expanded(
                  child: _messages.isEmpty && _streamingContent.isEmpty
                      ? _buildEmptyChat()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _messages.length +
                              (_streamingContent.isNotEmpty ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i < _messages.length) {
                              final m = _messages[i];
                              return ChatMessageWidget(
                                content: m.text,
                                isUser: m.isUser,
                                timestamp: m.timestamp,
                                toolCalls: m.toolCalls,
                              );
                            }
                            return ChatMessageWidget(
                              content: _streamingContent,
                              isUser: false,
                              timestamp: DateTime.now(),
                            );
                          },
                        ),
                ),
                // Input area
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A1A),
                    border: Border(
                      top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          enabled: !_sending,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: _sending ? 'AI 回复中...' : '输入消息...\nEnter 发送 · Shift+Enter 换行',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        child: IconButton(
                          onPressed: _sending ? null : _sendMessage,
                          icon: _sending
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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

  List<Widget> _buildSessionGroups() {
    final groups = _groupedSessions;
    final sourceLabels = {
      'cli': '终端',
      'telegram': 'Telegram',
      'discord': 'Discord',
      'slack': 'Slack',
    };

    return groups.entries.map((entry) {
      final label = sourceLabels[entry.key] ?? entry.key;
      final sessions = entry.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white38,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sessions.length}',
                  style: const TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ],
            ),
          ),
          ...sessions.map((s) => _SessionItem(
                session: s,
                selected: _activeSession?.id == s.id,
                onTap: () => _selectSession(s),
                onDelete: () => _deleteSession(s.id),
              )),
        ],
      );
    }).toList();
  }

  Future<void> _deleteSession(String id) async {
    try {
      await _gateway.deleteSession(id);
      setState(() {
        _sessions.removeWhere((s) => s.id == id);
        if (_activeSession?.id == id) _newChat();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_outlined,
              size: 64, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Text(
            '选择一个会话或开始新对话',
            style: TextStyle(fontSize: 16, color: Colors.white38),
          ),
          const SizedBox(height: 8),
          Text(
            '与 Hermes AI 聊天，管理你的对话',
            style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.25)),
          ),
        ],
      ),
    );
  }
}

class _Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final List<Map<String, dynamic>>? toolCalls;

  _Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.toolCalls,
  });
}

class _SessionItem extends StatelessWidget {
  final Session session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionItem({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? AppTheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          onLongPress: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除会话'),
                content: Text('确定删除「${session.title}」？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消')),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onDelete();
                    },
                    child: Text('删除',
                        style: TextStyle(color: AppTheme.error)),
                  ),
                ],
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primary : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : Colors.white70,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (session.preview != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          session.preview!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
