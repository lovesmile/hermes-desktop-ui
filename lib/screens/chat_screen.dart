import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/config_service.dart';
import '../models/session.dart';
import '../widgets/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _gateway = GatewayService();
  final _configService = ConfigService();
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _searchController = TextEditingController();

  List<Session> _sessions = [];
  List<Session> _displayedSessions = [];
  Session? _activeSession;
  List<_Message> _messages = [];
  List<_Message> _allLoadedMessages = []; // 完整消息列表
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingMoreMessages = false;
  bool _sending = false;
  bool _loadingMessages = false;
  String _streamingContent = '';
  bool _searching = false;

  // 消息分页
  static const int _messagePageSize = 30;
  int _messageStartIndex = 0;
  bool _messageHasMore = false;

  // 消息缓存 — 避免重复读 JSON
  final Map<String, List<_Message>> _messageCache = {};

  // 置顶会话
  final Set<String> _pinnedSessionIds = {};

  int _sessionPage = 0;
  static const int _sessionPageSize = 10;
  bool _sessionHasMore = true;
  final _sessionScrollController = ScrollController();

  // Skills for / command
  List<Map<String, String>> _skills = [];
  bool _skillSuggestionsVisible = false;
  String _skillFilter = '';
  final _skillNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadSkills();
    _inputController.addListener(_onInputChanged);
    _sessionScrollController.addListener(_onSessionScroll);
    _scrollController.addListener(_onMessageScroll);
  }

  @override
  void dispose() {
    _gateway.disconnectChat();
    _scrollController.dispose();
    _sessionScrollController.dispose();
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _searchController.dispose();
    _skillNode.dispose();
    super.dispose();
  }

  void _onMessageScroll() {
    // 向上滚动到顶部附近时加载更多历史消息
    if (_scrollController.position.pixels <= 200 &&
        _messageHasMore &&
        !_loadingMoreMessages &&
        !_loadingMessages &&
        !_sending) {
      _loadMoreMessages();
    }
  }

  void _onSessionScroll() {
    if (_sessionScrollController.position.pixels >=
            _sessionScrollController.position.maxScrollExtent - 200 &&
        _sessionHasMore &&
        !_loadingMore) {
      _loadMoreSessions();
    }
  }

  void _onInputChanged() {
    final text = _inputController.text;
    if (text.startsWith('/') && !_sending) {
      final filter = text.substring(1).toLowerCase();
      setState(() {
        _skillSuggestionsVisible = true;
        _skillFilter = filter;
      });
    } else {
      setState(() => _skillSuggestionsVisible = false);
    }
  }

  void _insertSkill(String skillName) {
    _inputController.text = '/$skillName ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    setState(() => _skillSuggestionsVisible = false);
    _skillNode.requestFocus();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final sessions = await _gateway.getSessions();
      setState(() {
        _sessions = sessions;
        _sessionPage = 0;
        _sessionHasMore = sessions.length > _sessionPageSize;
        _displayedSessions = sessions.take(_sessionPageSize).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _loadMoreSessions() {
    if (!_sessionHasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    _sessionPage++;
    final start = _sessionPage * _sessionPageSize;
    final end = start + _sessionPageSize;
    final more = _sessions.length > start
        ? _sessions.sublist(start, end > _sessions.length ? _sessions.length : end)
        : <Session>[];
    setState(() {
      _displayedSessions.addAll(more);
      _sessionHasMore = _sessions.length > _displayedSessions.length;
      _loadingMore = false;
    });
  }

  List<Session> get _filteredSessions {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _displayedSessions;
    setState(() => _sessionHasMore = false);
    return _sessions
        .where((s) => s.title.toLowerCase().contains(q))
        .toList();
  }
  Future<void> _loadSkills() async {
    try {
      final skills = await _configService.getSkills();
      if (mounted) setState(() => _skills = skills);
    } catch (_) {}
  }

  Future<void> _loadSessionMessages() async {
    if (_activeSession == null) return;

    // 检查缓存
    final cached = _messageCache[_activeSession!.id];
    if (cached != null) {
      _applyMessagePagination(cached);
      return;
    }

    setState(() => _loadingMessages = true);
    try {
      final rawMessages = await _gateway.getSessionMessages(_activeSession!.id);
      final messages = <_Message>[];
      for (final m in rawMessages) {
        final role = m['role'] as String? ?? 'user';
        if (role == 'tool') continue;
        final content = m['content'];
        if (role == 'assistant' && (content == null || (content is String && content.isEmpty))) {
          continue;
        }
        String text;
        if (content is String) {
          text = content;
          text = text.replaceAll('\\n', '\n');
          text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
          text = text.split('\n').map((l) => l.trim()).join('\n');
        } else if (content is Map) {
          text = content.toString();
        } else {
          text = content?.toString() ?? '';
        }
        if (text.trim().isEmpty) continue;
        messages.add(_Message(
          text: text,
          isUser: role == 'user',
          timestamp: DateTime.now(),
        ));
      }
      // 写入缓存
      _messageCache[_activeSession!.id] = messages;
      _applyMessagePagination(messages);
    } catch (_) {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  void _applyMessagePagination(List<_Message> all) {
    _allLoadedMessages = all;
    final total = all.length;
    final start = total > _messagePageSize ? total - _messagePageSize : 0;
    final display = all.sublist(start);
    if (mounted) {
      setState(() {
        _allLoadedMessages = all;
        _messages = display;
        _messageStartIndex = start;
        _messageHasMore = start > 0;
        _loadingMessages = false;
        _loadingMoreMessages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _loadMoreMessages() {
    if (!_messageHasMore || _loadingMoreMessages) return;
    setState(() => _loadingMoreMessages = true);

    final newStart = (_messageStartIndex - _messagePageSize).clamp(0, _allLoadedMessages.length);
    final moreMessages = _allLoadedMessages.sublist(newStart, _messageStartIndex);
    
    setState(() {
      _messages.insertAll(0, moreMessages);
      _messageStartIndex = newStart;
      _messageHasMore = newStart > 0;
      _loadingMoreMessages = false;
    });

    // 保持滚动位置不变（加载更旧消息后用户看到的还是当前内容）
    if (_scrollController.hasClients && moreMessages.isNotEmpty) {
      final estimatedHeight = moreMessages.length * 60.0; // 估算每条消息高度
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.pixels + estimatedHeight);
        }
      });
    }
  }

  void _selectSession(Session session) {
    // 如果已选中相同会话，不做任何事
    if (_activeSession?.id == session.id) return;
    setState(() {
      _activeSession = session;
      _messages = [];
      _streamingContent = '';
    });
    // 检查缓存，有就直接显示
    final cached = _messageCache[session.id];
    if (cached != null) {
      _applyMessagePagination(cached);
    } else {
      _loadSessionMessages();
    }
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

  void _togglePin(String id) {
    setState(() {
      if (_pinnedSessionIds.contains(id)) {
        _pinnedSessionIds.remove(id);
      } else {
        _pinnedSessionIds.add(id);
      }
    });
  }

  Map<String, List<Session>> get _groupedSessions {
    final groups = <String, List<Session>>{};
    // 置顶的排在最前面
    final pinned = <Session>[];
    final unpinned = <Session>[];
    for (final s in _filteredSessions) {
      if (_pinnedSessionIds.contains(s.id)) {
        pinned.add(s);
      } else {
        unpinned.add(s);
      }
    }
    if (pinned.isNotEmpty) {
      groups['pin'] = pinned;
    }
    if (unpinned.isNotEmpty) {
      for (final s in unpinned) {
        groups.putIfAbsent(s.source, () => []).add(s);
      }
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
                      icon: Icon(Icons.add, size: 18),
                      label: Text('新对话'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(
                            color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                // Session list
                Expanded(
                  child: _loading
                      ? Center(child: CircularProgressIndicator())
                      : _sessions.isEmpty
                          ? Center(
                              child: Text('暂无会话',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                          : ListView(
                              controller: _sessionScrollController,
                              children: [
                                ..._buildSessionGroups(),
                                if (_loadingMore)
                                  Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ),
                                  )
                                else if (_sessionHasMore)
                                  Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                      child: Text('下滑加载更多',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    ),
                                  ),
                              ],
                            ),
                ),
              ],
            ),
          ),
          // Divider
          Container(
            width: 1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                              (_streamingContent.isNotEmpty ? 1 : 0) +
                              (_messageHasMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            // Loading more indicator at top
                            if (_messageHasMore && i == 0) {
                              return _loadingMoreMessages
                                  ? Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Center(
                                        child: SizedBox(
                                          width: 16, height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    )
                                  : Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Center(
                                        child: Text('向上滚动加载更多历史消息',
                                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                      ),
                                    );
                            }
                            final msgIndex = _messageHasMore ? i - 1 : i;
                            if (msgIndex < _messages.length) {
                              final m = _messages[msgIndex];
                              return ChatMessageWidget(
                                content: m.text,
                                isUser: m.isUser,
                                timestamp: m.timestamp,
                                toolCalls: m.toolCalls,
                              );
                            }
                            // Streaming content at bottom
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
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Skill suggestions overlay
                      if (_skillSuggestionsVisible) _buildSkillSuggestions(),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _skillNode,
                              enabled: !_sending && !_loadingMessages,
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              decoration: InputDecoration(
                                hintText: _sending
                                    ? 'AI 回复中...'
                                    : (_loadingMessages
                                        ? '加载会话中...'
                                        : '输入消息... /加载技能\nEnter 发送 · Shift+Enter 换行'),
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
                              onPressed:
                                  (_sending || _loadingMessages)
                                      ? null
                                      : _sendMessage,
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
      final isPin = entry.key == 'pin';
      final label = isPin ? '📌 置顶' : (sourceLabels[entry.key] ?? entry.key);
      final sessions = entry.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, isPin ? 4 : 8, 16, 4),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                Spacer(),
                Text(
                  '${sessions.length}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ...sessions.map((s) => _SessionItem(
                session: s,
                selected: _activeSession?.id == s.id,
                pinned: _pinnedSessionIds.contains(s.id),
                onTap: () => _selectSession(s),
                onDelete: () => _deleteSession(s.id),
                onTogglePin: () => _togglePin(s.id),
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

  List<Map<String, String>> get _filteredSkills {
    if (_skillFilter.isEmpty) return _skills;
    return _skills
        .where((s) =>
            (s['name'] ?? '').toLowerCase().contains(_skillFilter) ||
            (s['description'] ?? '').toLowerCase().contains(_skillFilter))
        .toList();
  }

  Widget _buildSkillSuggestions() {
    final filtered = _filteredSkills.take(10).toList();
    if (filtered.isEmpty) {
      return SizedBox.shrink();
    }
    return Container(
      constraints: BoxConstraints(maxHeight: 200),
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: filtered.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        itemBuilder: (context, i) {
          final skill = filtered[i];
          return InkWell(
            onTap: () => _insertSkill(skill['name'] ?? ''),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: AppTheme.secondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          skill['name'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if ((skill['description'] ?? '').isNotEmpty)
                          Text(
                            skill['description'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '选择',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_outlined,
              size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          SizedBox(height: 16),
          Text(
            '选择一个会话或开始新对话',
            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: 8),
          Text(
            '与 Hermes AI 聊天，管理你的对话',
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
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
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _SessionItem({
    required this.session,
    required this.selected,
    this.pinned = false,
    required this.onTap,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: selected
            ? AppTheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          onLongPress: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('操作'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin,
                          color: AppTheme.primary),
                      title: Text(pinned ? '取消置顶' : '置顶会话'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onTogglePin();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('删除「${session.title}」',
                          style: const TextStyle(color: Colors.red)),
                      onTap: () {
                        Navigator.pop(ctx);
                        onDelete();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: AppTheme.primary,
                        width: 3,
                      ),
                    ),
                  )
                : null,
            child: Padding(
              padding: EdgeInsets.only(left: selected ? 9 : 12, right: 8, top: 10, bottom: 10),
              child: Row(
                children: [
                  // Pin icon
                  if (pinned)
                    Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin,
                          size: 12, color: AppTheme.warning),
                    ),
                  // Status dot
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
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
                            color: selected
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        if (session.preview != null) ...[
                          SizedBox(height: 2),
                          Text(
                            session.preview!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                    color: selected
                                        ? Theme.of(context).colorScheme.onSurfaceVariant
                                        : Theme.of(context).colorScheme.onSurfaceVariant),
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
      ),
    );
  }
}
