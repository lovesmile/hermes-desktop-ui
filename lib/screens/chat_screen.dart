import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/local_db.dart';
import '../services/config_service.dart';
import '../models/session.dart';
import '../widgets/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  /// 外部调用：从技能列表右键选中后，创建一个新会话并插入技能命令
  static final ValueNotifier<String?> skillInvocationNotifier = ValueNotifier(null);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _gateway = GatewayService();
  final _configService = ConfigService();
  final _localDb = LocalDatabase();
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
  bool _interrupted = false; // 被新消息中断的标志
  final List<Map<String, String>> _attachedFiles = [];

  // 是否正在思考（已发出请求但尚未收到任何 token）
  bool get _isThinking => _sending && _streamingContent.isEmpty;

  // 取消当前活跃的流式回复
  void _cancelCurrentChat() {
    // 取消所有活跃订阅
    for (final entry in _streamSubscriptions.entries) {
      entry.value.cancel();
    }
    _streamSubscriptions.clear();
    _streamingBuffers.clear();
    _streamingSessions.clear();
    if (mounted) {
      setState(() {
        _streamingContent = '';
        _sending = false;
        _interrupted = true; // 标记为被中断
      });
    }
  }

  // ★ 并行流式支持：每个会话独立 buffer 和 subscription
  final Map<String, String> _streamingBuffers = {};
  final Map<String, StreamSubscription> _streamSubscriptions = {};
  final Set<String> _streamingSessions = {};

  // ★ 每个会话独立的输入框草稿
  final Map<String, String> _draftMessages = {};
  bool _searching = false;

  // 每个会话独立的输入框草稿
  final Map<String, String> _sessionDrafts = {};

  // 消息分页
  static const int _messagePageSize = 30;
  int _messageStartIndex = 0;
  bool _messageHasMore = false;

  // Loading 弹窗
  bool _loadingDialogShowing = false;

  void _showLoading(String message) {
    if (_loadingDialogShowing) return;
    _loadingDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }

  void _hideLoading() {
    if (!_loadingDialogShowing) return;
    _loadingDialogShowing = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

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

    // 监听技能调用命令
    ChatScreen.skillInvocationNotifier.addListener(_onSkillInvocation);

    // 监听连接切换（GatewayService.setServerId 触发时重新加载会话和数据）
    GatewayService().refreshNotifier.addListener(_onModeChanged);
  }

  void _onSkillInvocation() {
    final cmd = ChatScreen.skillInvocationNotifier.value;
    if (cmd == null) return;
    ChatScreen.skillInvocationNotifier.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _newChat();
      _insertSkill(cmd);
      _skillNode.requestFocus();
    });
  }

  /// 连接模式切换时：清空缓存、重新加载会话
  void _onModeChanged() {
    _messageCache.clear();
    _draftMessages.clear();
    _sessionDrafts.clear();
    _streamingBuffers.clear();
    for (final sub in _streamSubscriptions.values) {
      sub.cancel();
    }
    _streamSubscriptions.clear();
    _streamingSessions.clear();
    _newChat();
    _loadSessions();
  }

  @override
  void dispose() {
    _gateway.disconnectChat();
    // ★ 取消所有并行流的订阅
    for (final sub in _streamSubscriptions.values) {
      sub.cancel();
    }
    _streamSubscriptions.clear();
    _streamingBuffers.clear();
    _streamingSessions.clear();
    _scrollController.dispose();
    _sessionScrollController.dispose();
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _searchController.dispose();
    _skillNode.dispose();
    ChatScreen.skillInvocationNotifier.removeListener(_onSkillInvocation);
    GatewayService().refreshNotifier.removeListener(_onModeChanged);
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
      final sessions = await _localDb.getSessions();
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

    _showLoading('加载会话中...');
    try {
      // 从本地数据库读取
      final rawMessages = await _localDb.getMessages(_activeSession!.id);
      if (rawMessages.isEmpty) {
        _hideLoading();
        _applyMessagePagination([]);
        return;
      }
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
      _hideLoading();
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
      _hideLoading();
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

    // ★ 保存当前会话的输入框草稿
    if (_activeSession != null) {
      final currentText = _inputController.text.trim();
      if (currentText.isNotEmpty) {
        _draftMessages[_activeSession!.id] = currentText;
      } else {
        _draftMessages.remove(_activeSession!.id);
      }
    }

    // 先移除 listener 再切换输入框，避免嵌套 setState
    _inputController.removeListener(_onInputChanged);

    setState(() {
      _activeSession = session;
      _messages = [];
      // ★ 如果此会话正在流式回复中，显示其 buffer
      if (_streamingBuffers.containsKey(session.id)) {
        _streamingContent = _streamingBuffers[session.id]!;
        _sending = true;
      } else {
        _streamingContent = '';
        _sending = false;
      }
    });
    // ★ 恢复目标会话的输入框草稿
    final draft = _draftMessages[session.id];
    _inputController.text = draft ?? '';
    if (draft != null && draft.isNotEmpty) {
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: draft.length),
      );
    }
    _inputController.addListener(_onInputChanged);
    // 检查缓存，有就直接显示
    final cached = _messageCache[session.id];
    if (cached != null) {
      _applyMessagePagination(cached);
    } else {
      _loadSessionMessages();
    }
    // ★ 确保加载完后滚动到底部（ListView lazy 渲染需要延迟）
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    });
  }

  void _newChat() {
    // ★ 保存当前会话的输入草稿
    if (_activeSession != null) {
      final currentText = _inputController.text.trim();
      if (currentText.isNotEmpty) {
        _draftMessages[_activeSession!.id] = currentText;
      }
    }
    setState(() {
      _activeSession = null;
      _messages = [];
      _streamingContent = '';
      _interrupted = false;
    });
    _inputController.text = '';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result != null) {
      for (final file in result.files) {
        if (file.path == null) continue;
        try {
          final bytes = await File(file.path!).readAsBytes();
          final b64 = base64Encode(bytes);
          if (mounted) {
            setState(() {
              _attachedFiles.add(_makeAttachment(file.name, file.path!, b64));
            });
          }
        } catch (_) {}
      }
    }
  }

  Map<String, String> _makeAttachment(String name, String path, String b64) {
    final ext = name.split('.').last.toLowerCase();
    final mime = {
      'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'svg': 'image/svg+xml', 'pdf': 'application/pdf',
      'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain', 'csv': 'text/csv', 'json': 'application/json',
      'md': 'text/markdown', 'py': 'text/x-python', 'js': 'text/javascript',
      'html': 'text/html', 'css': 'text/css',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
      'zip': 'application/zip', 'gz': 'application/gzip',
    }[ext] ?? 'application/octet-stream';
    return {'name': name, 'path': path, 'mime': mime, 'b64': b64};
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if ((text.isEmpty && _attachedFiles.isEmpty) || (_sending && !text.startsWith('/'))) return;

    _inputController.clear();
    // 发送后清除该会话的输入草稿
    if (_activeSession?.id != null) {
      _sessionDrafts.remove(_activeSession!.id);
    }

    // ★ 如果正在回复中，先中断当前回复
    bool wasReplying = _sending;
    if (_sending) {
      _cancelCurrentChat();
    }
    // 清除之前的中断标记（新消息开始）
    _interrupted = false;

    // ★ 记录发消息时的会话 ID
    final sessionIdAtSend = _activeSession?.id;

    if (sessionIdAtSend != null) {
      // 已有会话：用户消息立即持久化
      await _localDb.addMessage(sessionIdAtSend, 'user', text);
      // 立即更新内存中的会话预览（显示用户刚发的消息）
      final userPreview = text.length > 100 ? '${text.substring(0, 100)}...' : text;
      final updatedSession = Session(
        id: sessionIdAtSend,
        title: _activeSession?.title ?? '',
        source: _activeSession?.source ?? 'cli',
        createdAt: _activeSession?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        messageCount: (_messageCache[sessionIdAtSend]?.length ?? 0) + 1,
        preview: userPreview,
      );
      final idx = _sessions.indexWhere((s) => s.id == sessionIdAtSend);
      final displayIdx = _displayedSessions.indexWhere((s) => s.id == sessionIdAtSend);
      if (idx >= 0) _sessions.removeAt(idx);
      if (displayIdx >= 0) _displayedSessions.removeAt(displayIdx);
      _sessions.insert(0, updatedSession);
      _displayedSessions.insert(0, updatedSession);
    }

    // 本地显示用户消息
    final userMsg = _Message(text: text, isUser: true, timestamp: DateTime.now());
    if (sessionIdAtSend != null) {
      final cached = _messageCache[sessionIdAtSend];
      if (cached != null) cached.add(userMsg);
    }
    setState(() {
      if (sessionIdAtSend != null) _messages.add(userMsg);
      _sending = true;
    });
    _scrollToBottom();

    try {
      final stream = _gateway.chatStream(text, sessionId: sessionIdAtSend,
          attachments: _attachedFiles.isNotEmpty ? _attachedFiles : null);

      // ★ 如果此会话已有活跃流，先取消旧的（防止重复）
      if (sessionIdAtSend != null && _streamSubscriptions.containsKey(sessionIdAtSend)) {
        await _streamSubscriptions[sessionIdAtSend]!.cancel();
        _streamSubscriptions.remove(sessionIdAtSend);
        _streamingBuffers.remove(sessionIdAtSend);
        _streamingSessions.remove(sessionIdAtSend);
      }

      // ★ 用 listen 替代 await for，实现并行流
      final sub = stream.listen(
        (chunk) {
          // 累积到 buffer — 新会话用 __pending__ 占位，已有会话用 sessionId
          final sid = sessionIdAtSend ?? '__pending__';
          _streamingBuffers[sid] = (_streamingBuffers[sid] ?? '') + chunk;
          // 仅当此会话是当前激活会话时更新 UI
          if (_activeSession?.id == sid && mounted) {
            setState(() => _streamingContent = _streamingBuffers[sid]!);
            _scrollToBottom();
          }
        },
        onDone: () async {
          if (!mounted) return;
          final newSessionId = _gateway.lastSessionId;
          // 读 buffer（新会话从 __pending__ 取，已有会话从 sessionId 取）
          final bufferKey = sessionIdAtSend ?? '__pending__';
          final response = _streamingBuffers[bufferKey] ?? '';

          if (sessionIdAtSend == null && newSessionId != null && newSessionId.isNotEmpty) {
            // ── 全新会话 ──
            // 清理 pending buffer，迁移到真实 sessionId
            _streamSubscriptions.remove('__pending__');
            _streamingBuffers.remove('__pending__');
            _streamingSessions.remove('__pending__');
            final title = '${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} ${text.length > 25 ? '${text.substring(0, 25)}...' : text}';
            await _localDb.createSession(
              id: newSessionId, title: title,
              userMessage: text, assistantMessage: response,
            );
            final preview = response.length > 100 ? '${response.substring(0, 100)}...' : response;
            final newSession = Session(
              id: newSessionId, title: title, source: 'cli',
              createdAt: DateTime.now(), updatedAt: DateTime.now(),
              messageCount: 2, preview: preview,
            );
            // 缓存
            _messageCache[newSessionId] = [
              _Message(text: text, isUser: true, timestamp: DateTime.now()),
              _Message(text: response, isUser: false, timestamp: DateTime.now()),
            ];
            if (mounted) {
              setState(() {
                _activeSession = newSession;
                _sessions.insert(0, newSession);
                _displayedSessions.insert(0, newSession);
                _messages = List.from(_messageCache[newSessionId]!);
                _streamingContent = '';
                _sending = false;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _skillNode.requestFocus();
              });
            }
          } else if (sessionIdAtSend != null && response.isNotEmpty) {
            // ── 已有会话：存 AI 回复 ──
            // 清理流状态
            _streamSubscriptions.remove(sessionIdAtSend);
            _streamingBuffers.remove(sessionIdAtSend);
            _streamingSessions.remove(sessionIdAtSend);
            await _localDb.addMessage(sessionIdAtSend, 'assistant', response);
            final cached = _messageCache[sessionIdAtSend];
            if (cached != null) {
              cached.add(_Message(text: response, isUser: false, timestamp: DateTime.now()));
            }
            // 更新列表预览
            final updated = Session(
              id: sessionIdAtSend, title: _activeSession?.title ?? '',
              source: 'cli',
              createdAt: _activeSession?.createdAt ?? DateTime.now(),
              updatedAt: DateTime.now(),
              messageCount: (_messageCache[sessionIdAtSend]?.length ?? 0),
              preview: response.length > 100 ? '${response.substring(0, 100)}...' : response,
            );
            if (mounted) {
              setState(() {
                final idx = _sessions.indexWhere((s) => s.id == sessionIdAtSend);
                final displayIdx = _displayedSessions.indexWhere((s) => s.id == sessionIdAtSend);
                if (idx >= 0) _sessions[idx] = updated;
                if (displayIdx >= 0) _displayedSessions[displayIdx] = updated;
                // 如果当前正好在看这个会话，显示回复
                if (_activeSession?.id == sessionIdAtSend) {
                  _messages.add(_Message(text: response, isUser: false, timestamp: DateTime.now()));
                  _streamingContent = '';
                  _sending = false;
                }
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _skillNode.requestFocus();
              });
            }
          }
        },
        onError: (e) {
          // 清理
          final sid = sessionIdAtSend ?? '__pending__';
          _streamSubscriptions.remove(sid);
          _streamingBuffers.remove(sid);
          _streamingSessions.remove(sid);
          if (mounted) {
            setState(() {
              _messages.add(_Message(text: '⚠️ 发送失败: $e', isUser: false, timestamp: DateTime.now(), isError: true));
              if (sessionIdAtSend == null) _sending = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _skillNode.requestFocus();
            });
          }
        },
        cancelOnError: false,
      );

      // ★ 记录订阅
      final sid = sessionIdAtSend ?? '__pending_new__';
      _streamSubscriptions[sid] = sub;
      _streamingBuffers[sid] = '';
      _streamingSessions.add(sid);

      // 如果没有 sessionId（新会话），用 pending key 占位
      if (sessionIdAtSend == null) {
        // 稍后 onDone 中会拿到 Gateway 返回的 sessionId
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_Message(text: '⚠️ 连接失败: $e', isUser: false, timestamp: DateTime.now(), isError: true));
          _sending = false;
        });
      }
    } finally {
      // 不在这里设置 _sending = false，由 onDone 处理
      if (mounted) {
        setState(() => _attachedFiles.clear());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _skillNode.requestFocus();
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      // 用跳转而非动画，确保立即到位
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
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
                            if (_interrupted) {
                              // 被中断的回复：显示一条提示消息
                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.cancel_outlined,
                                        size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    SizedBox(width: 6),
                                    Text('已中断',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              );
                            }
                            if (_isThinking) {
                              // AI 正在思考中：显示动画指示器
                              return _buildThinkingIndicator();
                            }
                            if (_streamingContent.isNotEmpty) {
                              // AI 正在流式输出
                              return ChatMessageWidget(
                                content: _streamingContent,
                                isUser: false,
                                timestamp: DateTime.now(),
                              );
                            }
                            return SizedBox.shrink();
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
                      // Attachment chips
                      if (_attachedFiles.isNotEmpty)
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _attachedFiles.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (_, i) {
                              final f = _attachedFiles[i];
                              return InputChip(
                                label: Text(f['name'] ?? '', style: const TextStyle(fontSize: 12)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () => setState(() => _attachedFiles.removeAt(i)),
                                avatar: Icon(
                                  (f['mime'] ?? '').startsWith('image/') ? Icons.image : Icons.attach_file,
                                  size: 16,
                                ),
                              );
                            },
                          ),
                        ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.attach_file),
                            onPressed: _sending ? null : _pickFile,
                            tooltip: '添加文件',
                          ),
                          Expanded(
                            child: TextField(
                              key: ValueKey('input_${_activeSession?.id ?? 'new'}'),
                              controller: _inputController,
                              focusNode: _skillNode,
                              enabled: !_sending && !_loadingMessages,
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              decoration: InputDecoration(
                                hintText: _sending
                                    ? 'AI 回复中...'
                                    : '输入消息... / 加载技能\nEnter 发送 · Shift+Enter 换行',
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
                            child: _sending
                                ? IconButton(
                                    onPressed: _cancelCurrentChat,
                                    icon: const Icon(Icons.stop_rounded),
                                    tooltip: '停止回复',
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppTheme.error,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    onPressed:
                                        (_loadingMessages)
                                            ? null
                                            : _sendMessage,
                                    icon: const Icon(Icons.send_rounded),
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
    _showLoading('删除中...');
    try {
      await _localDb.deleteSession(id);
      _hideLoading();
      setState(() {
        _sessions.removeWhere((s) => s.id == id);
        _displayedSessions.removeWhere((s) => s.id == id);
        if (_activeSession?.id == id) _newChat();
      });
    } catch (e) {
      _hideLoading();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
      _loadSessions();
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
    final filtered = _filteredSkills.toList();
    if (filtered.isEmpty) {
      return SizedBox.shrink();
    }
    return Container(
      constraints: BoxConstraints(maxHeight: 300, minHeight: 120),
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

  // 「正在思考」状态指示器 — 伪装成接收到的 AI 消息
  Widget _buildThinkingIndicator() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 头像（与 ChatMessageWidget 一致）
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
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
          // 消息气泡（与 ChatMessageWidget 一致）
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在思考',
                      style: TextStyle(
                          fontSize: 14, color: scheme.onSurface)),
                  const SizedBox(width: 8),
                  _AnimatedDots(),
                ],
              ),
            ),
          ),
        ],
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

/// 脉冲点动画 — 表示 AI 正在思考
class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2; // 每个点错开 0.2s
            // 用正弦波计算透明度: 在 0.3~1.0 之间脉冲
            final t = (_controller.value + delay) % 1.0;
            final opacity = 0.3 + 0.7 * (1.0 - (t * 2 - 1).abs());
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
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
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.65)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onSecondaryTap: () => _showContextMenu(context),
          borderRadius: BorderRadius.circular(8),
          onLongPress: () => _showContextMenu(context),
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 5,
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

  void _showContextMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + size.width,
        offset.dy,
        offset.dx + size.width + 1,
        offset.dy + 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      items: [
        PopupMenuItem<String>(
          value: 'pin',
          child: SizedBox(
            width: 180,
            child: Row(
              children: [
                Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 12),
                Text(pinned ? '取消置顶' : '置顶会话'),
              ],
            ),
          ),
          onTap: () => onTogglePin(),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: SizedBox(
            width: 180,
            child: Row(
              children: [
                const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                const SizedBox(width: 12),
                Text('删除',
                    style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          onTap: () => onDelete(),
        ),
      ],
    );
  }
}
