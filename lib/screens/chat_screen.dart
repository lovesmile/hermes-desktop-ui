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
import '../models/display_session.dart';
import '../widgets/chat_message.dart';
import '../widgets/chat_drop_zone.dart';
import '../widgets/model_switcher.dart';

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

  List<DisplaySession> _displaySessions = [];
  List<DisplaySession> _displayedDisplaySessions = [];
  DisplaySession? _activeDisplaySession;
  List<_Message> _messages = [];
  List<_Message> _allLoadedMessages = []; // 完整消息列表
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingMoreMessages = false;
  bool _sending = false;
  bool _loadingMessages = false;
  String _streamingContent = '';
  Timer? _streamThrottleTimer;
  int _segmentsCommitted = 0; // 已提交为独立消息的字符数，超 2000 自动分段
  static const int _segmentMaxLen = 2000;
  bool _interrupted = false; // 被新消息中断的标志
  final List<Map<String, String>> _attachedFiles = [];
  String? _currentSessionModel; // 当前会话使用的模型
  String? _currentSessionProvider; // 当前会话使用的 provider

  // 是否正在思考（已发出请求但尚未收到任何 token）
  bool get _isThinking => _sending && _streamingContent.isEmpty;

  // 取消当前活跃的流式回复
  void _cancelCurrentChat() {
    _streamThrottleTimer?.cancel();
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
        _interrupted = true;
        _segmentsCommitted = 0;
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
    _migrateAndLoad();
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
    _migrateAndLoad();
  }

  @override
  void dispose() {
    _gateway.disconnectChat();
    _streamThrottleTimer?.cancel();
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

  Future<void> _migrateAndLoad() async {
    await _localDb.migrateOldSessionsIfNeeded();
    await _loadDisplaySessions();
  }

  Future<void> _loadDisplaySessions() async {
    setState(() => _loading = true);
    try {
      final sessions = await _localDb.getDisplaySessions();
      setState(() {
        _displaySessions = sessions;
        _sessionPage = 0;
        _sessionHasMore = sessions.length > _sessionPageSize;
        _displayedDisplaySessions = sessions.take(_sessionPageSize).toList();
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
    final more = _displaySessions.length > start
        ? _displaySessions.sublist(start, end > _displaySessions.length ? _displaySessions.length : end)
        : <DisplaySession>[];
    setState(() {
      _displayedDisplaySessions.addAll(more);
      _sessionHasMore = _displaySessions.length > _displayedDisplaySessions.length;
      _loadingMore = false;
    });
  }

  Future<void> _loadSkills() async {
    try {
      final skills = await _configService.getSkills();
      if (mounted) setState(() => _skills = skills);
    } catch (_) {}
  }

  Future<void> _loadSessionMessages() async {
    if (_activeDisplaySession == null) return;

    // 读取会话的模型设置
    _currentSessionModel = _activeDisplaySession!.model;
    _currentSessionProvider = _activeDisplaySession!.provider;

    // 检查缓存（用 displayId）
    final cached = _messageCache[_activeDisplaySession!.id];
    if (cached != null) {
      _applyMessagePagination(cached);
      return;
    }

    _showLoading('加载会话中...');
    try {
      // 从本地数据库读取（用当前后端 session_id）
      final backendId = _activeDisplaySession!.currentBackendId;
      if (backendId.isEmpty) {
        _hideLoading();
        _applyMessagePagination([]);
        return;
      }
      final rawMessages = await _localDb.getMessages(backendId);
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
        // Read attachments from JSON
        final attJson = m['attachments'] as List?;
        final atts = attJson?.map((a) {
          final am = a as Map<String, dynamic>;
          return <String, String>{
            'name': (am['name'] as String?) ?? '',
            'mime': (am['mime'] as String?) ?? 'application/octet-stream',
          };
        }).toList();
        final hasAtts = atts != null && atts.isNotEmpty;
        final tsStr = m['timestamp'] as String?;
        final ts = tsStr != null ? DateTime.tryParse(tsStr) ?? DateTime.now() : DateTime.now();
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
        if (text.trim().isEmpty && !hasAtts) continue;
        if (role != 'user' && text.length > _segmentMaxLen) {
          // ★ AI 长回复分段显示，每段不超过 2000 字
          for (int i = 0; i < text.length; i += _segmentMaxLen) {
            final end = (i + _segmentMaxLen < text.length) ? i + _segmentMaxLen : text.length;
            messages.add(_Message(text: text.substring(i, end), isUser: false, timestamp: ts));
          }
        } else {
          messages.add(_Message(
            text: text,
            isUser: role == 'user',
            timestamp: ts,
            attachments: role == 'user' ? atts : null,
          ));
        }
      }
      // 写入缓存（用 displayId）
      _messageCache[_activeDisplaySession!.id] = messages;
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

  void _selectSession(DisplaySession ds) {
    // 如果已选中相同会话，不做任何事
    if (_activeDisplaySession?.id == ds.id) return;

    // ★ 保存当前会话的输入框草稿
    if (_activeDisplaySession != null) {
      final currentText = _inputController.text.trim();
      if (currentText.isNotEmpty) {
        _draftMessages[_activeDisplaySession!.id] = currentText;
      } else {
        _draftMessages.remove(_activeDisplaySession!.id);
      }
    }

    // 先移除 listener 再切换输入框，避免嵌套 setState
    _inputController.removeListener(_onInputChanged);

    setState(() {
      _activeDisplaySession = ds;
      _currentSessionModel = ds.model;
      _currentSessionProvider = ds.provider;
      _messages = [];
      // ★ 如果此会话正在流式回复中，显示其 buffer
      if (_streamingBuffers.containsKey(ds.id)) {
        _streamingContent = _streamingBuffers[ds.id]!;
        _sending = true;
      } else {
        _streamingContent = '';
        _sending = false;
      }
    });
    // ★ 恢复目标会话的输入框草稿
    final draft = _draftMessages[ds.id];
    _inputController.text = draft ?? '';
    if (draft != null && draft.isNotEmpty) {
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: draft.length),
      );
    }
    _inputController.addListener(_onInputChanged);
    // 检查缓存，有就直接显示（用 displayId）
    final cached = _messageCache[ds.id];
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
    if (_activeDisplaySession != null) {
      final currentText = _inputController.text.trim();
      if (currentText.isNotEmpty) {
        _draftMessages[_activeDisplaySession!.id] = currentText;
      }
    }
    setState(() {
      _activeDisplaySession = null;
      _messages = [];
      _streamingContent = '';
      _interrupted = false;
      _currentSessionModel = null;
      _currentSessionProvider = null;
    });
    _inputController.text = '';
  }

  /// 构建发送给 API 的模型名（带 provider 前缀）。
  /// Gateway API 期望格式为 provider/model_name（如 deepseek/deepseek-v4-flash）。
  /// 如果 model 已含 `/`（如 anthropic/claude-sonnet-4）则不重复加前缀。
  String? _buildModelName() {
    final m = _currentSessionModel;
    if (m == null || m.isEmpty) return null;
    final p = _currentSessionProvider;
    if (p == null || p.isEmpty) return m; // 无 provider 信息，原样返回
    if (m.contains('/')) return m; // 已含前缀（如 anthropic/claude-sonnet-4）
    return '$p/$m';
  }

  void _onModelSelected(ModelSelectionResult result) async {
    if (result.asGlobal) {
      // 对话框已保存配置并重启 Gateway，这里只刷新 UI
      setState(() {
        _currentSessionModel = result.model;
        _currentSessionProvider = result.provider;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('全局默认模型已切换为 ${result.model}，Gateway 重启中...'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // 应用到当前会话
      final displayId = _activeDisplaySession?.id;
      if (displayId == null) {
        // 没有活跃会话（新对话），直接切换无副作用
        setState(() {
          _currentSessionModel = result.model;
          _currentSessionProvider = result.provider;
        });
        return;
      }

      // 有活跃会话：需要确认用户知道上下文会丢失
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('切换会话模型'),
          content: const Text(
            '切换模型后，AI 将不记得之前的对话内容（上下文丢失），'
            '但历史消息仍可查看。\n\n'
            '下一消息起生效。确定要继续吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定切换'),
            ),
          ],
        ),
      );

      if (proceed != true) return;

      // 保存模型
      await _localDb.updateSessionModel(displayId, result.model, provider: result.provider);
      // 更新展示会话
      final ds = await _localDb.getDisplaySession(displayId);
      if (ds != null) {
        await _localDb.updateDisplaySession(ds.copyWith(
          model: result.model,
          provider: result.provider,
          updatedAt: DateTime.now(),
        ));
      }
      setState(() {
        _currentSessionModel = result.model;
        _currentSessionProvider = result.provider;
        if (_activeDisplaySession != null) {
          _activeDisplaySession = _activeDisplaySession!.copyWith(
            model: result.model,
            provider: result.provider,
          );
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('会话模型已切换为 ${result.model}，下一消息起生效'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
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

  Future<void> _pasteImageFromClipboard() async {
    Directory? tempDir;
    try {
      // Windows: 用 PowerShell 将剪贴板图片保存到临时文件后读取
      tempDir = await Directory.systemTemp.createTemp('hermes_clip_');
      final tempPng = '${tempDir.path}\\clipboard_paste.png';
      final psResult = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; '
        r'$img = [System.Windows.Forms.Clipboard]::GetImage(); '
        r'if ($img -ne $null) { '
        r'  $img.Save("'"$tempPng"'", [System.Drawing.Imaging.ImageFormat]::Png); '
        r'  $img.Dispose(); '
        r'  Write-Output "OK"; '
        r'} else { '
        r'  Write-Output "NO_IMAGE"; '
        r'}',
      ]);
      if (psResult.stdout.toString().trim() != 'OK') return;
      final file = File(tempPng);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      final b64 = base64Encode(bytes);
      if (mounted) {
        setState(() {
          _attachedFiles.add(_makeAttachment('clipboard.png', '', b64));
        });
      }
    } catch (e) {
      debugPrint('ChatScreen: 粘贴剪贴板图片失败: $e');
    } finally {
      await tempDir?.delete(recursive: true);
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
    if (_activeDisplaySession?.id != null) {
      _sessionDrafts.remove(_activeDisplaySession!.id);
    }

    // ★ 如果正在回复中，先中断当前回复
    bool wasReplying = _sending;
    if (_sending) {
      _cancelCurrentChat();
    }
    // 清除之前的中断标记（新消息开始）
    _interrupted = false;

    // ★ 用 displayId 作为本地会话标识
    final String? displayId = _activeDisplaySession?.id;
    final bool isNewSession = displayId == null;
    // ★ 取当前后端 session_id 发往 Gateway
    final gatewayIdForApi = _activeDisplaySession?.currentBackendId;
    // ★ 记下 displayId 供 onDone 使用
    final String? displayIdAtSend = displayId;

    if (isNewSession) {
      // ★ 无激活会话：生成本地 displayId + 暂存用户消息
      final localDisplayId = '${DateTime.now().microsecondsSinceEpoch}';
      final title = '${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} ${text.length > 25 ? '${text.substring(0, 25)}...' : text}';
      // 用一个暂存 backendId 存放用户消息（onDone 后替换为真实后端 session_id）
      final tempBackendId = 'pending_$localDisplayId';
      await _localDb.createSession(
        id: tempBackendId, title: title, userMessage: text,
        model: _currentSessionModel, provider: _currentSessionProvider,
        userAttachments: _attachedFiles.isNotEmpty
            ? _attachedFiles.map((m) => Map<String, String>.from(m)).toList()
            : null,
      );
      // 创建 DisplaySession
      final newDs = DisplaySession(
        id: localDisplayId,
        title: title,
        currentBackendId: tempBackendId,
        model: _currentSessionModel,
        provider: _currentSessionProvider,
      );
      await _localDb.createDisplaySession(newDs);
      _displaySessions.insert(0, newDs);
      _displayedDisplaySessions.insert(0, newDs);
      _messageCache[localDisplayId] = [
        _Message(text: text, isUser: true, timestamp: DateTime.now(),
            attachments: _attachedFiles.isNotEmpty
                ? _attachedFiles.map((m) => Map<String, String>.from(m)).toList()
                : null),
      ];
      setState(() => _activeDisplaySession = newDs);
    } else if (displayId != null && _activeDisplaySession != null) {
      // 已有会话：用户消息存入当前后端
      final currentBackendId = _activeDisplaySession!.currentBackendId;
      if (currentBackendId.isNotEmpty) {
        await _localDb.addMessage(currentBackendId, 'user', text,
          attachments: _attachedFiles.isNotEmpty
              ? _attachedFiles.map((m) => Map<String, String>.from(m)).toList()
              : null,
        );
      }
      // 更新展示会话的 updatedAt
      await _localDb.updateDisplaySession(
        _activeDisplaySession!.copyWith(updatedAt: DateTime.now()),
      );
    }

    // 本地显示用户消息（纯附件无文字时显示附件名）
    final displayText = text.isNotEmpty
        ? text
        : _attachedFiles.map((a) => '[${a['name'] ?? '附件'}]').join(' ');
    final userMsg = _Message(
      text: displayText, isUser: true, timestamp: DateTime.now(),
      attachments: _attachedFiles.isNotEmpty
          ? _attachedFiles.map((m) => Map<String, String>.from(m)).toList()
          : null,
    );
    if (displayIdAtSend != null) {
      final cached = _messageCache[displayIdAtSend];
      if (cached != null && !isNewSession) cached.add(userMsg);
    }
    setState(() {
      if (displayIdAtSend != null) _messages.add(userMsg);
      _sending = true;
    });
    _segmentsCommitted = 0;
    _scrollToBottom();

    try {
      // 传副本，防止 finally 中 clear() 影响异步 _doChat 读取
      // Gateway API 只支持图片附件，非图片文件通过文本告知 AI 路径
      final filesForApi = _attachedFiles.isNotEmpty
          ? _attachedFiles
              .where((a) => (a['mime'] ?? '').startsWith('image/'))
              .map((m) => Map<String, String>.from(m))
              .toList()
          : null;
      // 非图片文件：在文本中附加路径，让 AI 用 read_file 工具读取
      final nonImagePaths = _attachedFiles
          .where((a) => !(a['mime'] ?? '').startsWith('image/'))
          .map((a) => a['path'] ?? '')
          .where((p) => p.isNotEmpty)
          .toList();
      String apiText = text;
      if (nonImagePaths.isNotEmpty) {
        final instruction = '\n\n[附件文件路径]:\n${nonImagePaths.map((p) => '- $p').join('\n')}\n请使用 read_file 工具读取这些文件并分析。';
        apiText = text.isNotEmpty ? '$text$instruction' : '请读取以下文件:\n${nonImagePaths.map((p) => '- $p').join('\n')}';
      }
      // 同样保存附件信息供 onDone 回调使用（那时 _attachedFiles 已被 finally 清除）
      final pendingAttachments = _attachedFiles.isNotEmpty
          ? _attachedFiles.map((m) => Map<String, String>.from(m)).toList()
          : null;
      final stream = _gateway.chatStream(apiText, sessionId: gatewayIdForApi,
          attachments: filesForApi,
          model: _buildModelName());

      // ★ 如果此会话已有活跃流，先取消旧的（防止重复）
      final oldSid = displayIdAtSend ?? '__pending_new__';
      if (_streamSubscriptions.containsKey(oldSid)) {
        await _streamSubscriptions[oldSid]!.cancel();
        _streamSubscriptions.remove(oldSid);
        _streamingBuffers.remove(oldSid);
        _streamingSessions.remove(oldSid);
      }

      // ★ 用 listen 替代 await for，实现并行流
      final sub = stream.listen(
        (chunk) {
          // 累积到 buffer
          final sid = displayIdAtSend ?? '__pending__';
          _streamingBuffers[sid] = (_streamingBuffers[sid] ?? '') + chunk;
          // 仅当此会话是当前激活会话时更新 UI（节流到 ~300ms 防卡死）
          if (_activeDisplaySession?.id == sid && mounted) {
            if (_streamThrottleTimer == null || !_streamThrottleTimer!.isActive) {
              _streamThrottleTimer?.cancel();
              _streamThrottleTimer = Timer(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                // 确保节流触发时还是同一个会话
                if (_activeDisplaySession?.id != sid) return;
                final full = _streamingBuffers[sid] ?? '';
                setState(() {
                  // ★ 超过 2000 字自动分段，每段作为独立消息
                  while (full.length - _segmentsCommitted >= _segmentMaxLen) {
                    final seg = full.substring(_segmentsCommitted, _segmentsCommitted + _segmentMaxLen);
                    _messages.add(_Message(text: seg, isUser: false, timestamp: DateTime.now()));
                    _segmentsCommitted += _segmentMaxLen;
                  }
                  _streamingContent = full.substring(_segmentsCommitted);
                });
                _scrollToBottom();
                _scrollToBottom();
              });
            }
          }
        },
        onDone: () async {
          if (!mounted) return;
          _streamThrottleTimer?.cancel();
          final newSessionId = _gateway.lastSessionId;
          // 读 buffer（用 displayId）
          final bufferKey = displayIdAtSend ?? '__pending__';
          final response = _streamingBuffers[bufferKey] ?? '';

          if (displayIdAtSend == null && newSessionId != null && newSessionId.isNotEmpty) {
            // ── 全新会话 ──
            // isNewSession 分支已创建 DisplaySession + tempBackendId
            // 这里把 tempBackendId 替换为真实后端 session_id
            _streamSubscriptions.remove('__pending__');
            _streamingBuffers.remove('__pending__');
            _streamingSessions.remove('__pending__');

            // 读取旧 displayId（刚创建的那个）
            final newDsList = await _localDb.getDisplaySessions();
            final latestDs = newDsList.isNotEmpty ? newDsList.first : null;
            final tempBackendId = latestDs?.currentBackendId ?? '';

            if (latestDs != null && newSessionId.isNotEmpty) {
              // 从 tempBackendId 迁移消息到真实后端 session_id
              final rawMessages = await _localDb.getMessages(tempBackendId);
              await _localDb.createSession(
                id: newSessionId, title: latestDs.title,
                model: _currentSessionModel,
                provider: _currentSessionProvider,
              );
              // 逐条迁移消息
              for (final msg in rawMessages) {
                await _localDb.addMessage(
                  newSessionId, msg['role'] as String? ?? 'user',
                  msg['content'] as String? ?? '',
                );
              }
              // 加上 AI 回复
              if (response.isNotEmpty) {
                await _localDb.addMessage(newSessionId, 'assistant', response);
              }
              // 删除临时 backend
              await _localDb.deleteSession(tempBackendId);
              // 更新 DisplaySession
              await _localDb.switchBackendId(latestDs.id, newSessionId);
              final updatedDs = latestDs.copyWith(
                currentBackendId: newSessionId,
                backendIdHistory: latestDs.backendIdHistory,
                updatedAt: DateTime.now(),
              );
              final preview = response.length > 100 ? '${response.substring(0, 100)}...' : response;
              _messageCache[latestDs.id] = [
                _Message(text: text, isUser: true, timestamp: DateTime.now(),
                    attachments: pendingAttachments),
                _Message(text: response, isUser: false, timestamp: DateTime.now()),
              ];
              if (mounted) {
                setState(() {
                  _activeDisplaySession = updatedDs;
                  final idx = _displaySessions.indexWhere((s) => s.id == latestDs.id);
                  if (idx >= 0) _displaySessions[idx] = updatedDs;
                  final didx = _displayedDisplaySessions.indexWhere((s) => s.id == latestDs.id);
                  if (didx >= 0) _displayedDisplaySessions[didx] = updatedDs;
                  _messages = List.from(_messageCache[latestDs.id]!);
                  _streamingContent = '';
                  _sending = false;
                });
              }
            }
          } else if (displayIdAtSend != null && response.isNotEmpty) {
            // ── 已有会话：存 AI 回复 ──
            _streamSubscriptions.remove(displayIdAtSend);
            _streamingBuffers.remove(displayIdAtSend);
            _streamingSessions.remove(displayIdAtSend);

            // 获取当前 DisplaySession
            final ds = await _localDb.getDisplaySession(displayIdAtSend);
            if (ds != null) {
              final currentBackendId = ds.currentBackendId;
              if (currentBackendId.isNotEmpty) {
                await _localDb.addMessage(currentBackendId, 'assistant', response);
              }
              // Gateway 返回了新 session_id → 切换 backend
              if (newSessionId != null && newSessionId.isNotEmpty && newSessionId != currentBackendId) {
                // 创建新后端会话
                await _localDb.createSession(
                  id: newSessionId, title: ds.title,
                  model: ds.model, provider: ds.provider,
                );
                // 迁移旧消息到新后端
                if (currentBackendId.isNotEmpty) {
                  final oldMessages = await _localDb.getMessages(currentBackendId);
                  for (final msg in oldMessages) {
                    await _localDb.addMessage(
                      newSessionId, msg['role'] as String? ?? 'user',
                      msg['content'] as String? ?? '',
                    );
                    if (msg['attachments'] != null) {
                      // 简化处理：跳过附件迁移
                    }
                  }
                }
                // 切换 DisplaySession
                await _localDb.switchBackendId(displayIdAtSend, newSessionId);
                final updatedDs = ds.copyWith(
                  currentBackendId: newSessionId,
                  updatedAt: DateTime.now(),
                );
                final cached = _messageCache[displayIdAtSend];
                if (cached != null) {
                  cached.add(_Message(text: response, isUser: false, timestamp: DateTime.now()));
                }
                if (mounted) {
                  setState(() {
                    final idx = _displaySessions.indexWhere((s) => s.id == displayIdAtSend);
                    if (idx >= 0) _displaySessions[idx] = updatedDs;
                    final didx = _displayedDisplaySessions.indexWhere((s) => s.id == displayIdAtSend);
                    if (didx >= 0) _displayedDisplaySessions[didx] = updatedDs;
                    if (_activeDisplaySession?.id == displayIdAtSend) {
                      _activeDisplaySession = updatedDs;
                      if (_segmentsCommitted < response.length) {
                        _messages.add(_Message(text: response.substring(_segmentsCommitted), isUser: false, timestamp: DateTime.now()));
                      }
                    }
                    _streamingContent = '';
                    _sending = false;
                    _segmentsCommitted = 0;
                  });
                }
              } else {
                // 同一个后端：只添加消息
                final cached = _messageCache[displayIdAtSend];
                if (cached != null) {
                  cached.add(_Message(text: response, isUser: false, timestamp: DateTime.now()));
                }
                if (mounted) {
                  setState(() {
                    if (_activeDisplaySession?.id == displayIdAtSend) {
                      if (_segmentsCommitted < response.length) {
                        _messages.add(_Message(text: response.substring(_segmentsCommitted), isUser: false, timestamp: DateTime.now()));
                      }
                    }
                    _streamingContent = '';
                    _sending = false;
                    _segmentsCommitted = 0;
                  });
                }
              }
            }
          } else if (displayIdAtSend != null) {
            // ── 已有会话但无响应内容 ──
            _streamSubscriptions.remove(displayIdAtSend);
            _streamingBuffers.remove(displayIdAtSend);
            _streamingSessions.remove(displayIdAtSend);
            if (mounted) {
              setState(() {
                _streamingContent = '';
                _sending = false;
                _segmentsCommitted = 0;
              });
            }
          }
        },
        onError: (e) {
          _streamThrottleTimer?.cancel();
          // 清理
          final sid = displayIdAtSend ?? '__pending__';
          _streamSubscriptions.remove(sid);
          _streamingBuffers.remove(sid);
          _streamingSessions.remove(sid);
          if (mounted) {
            setState(() {
              _messages.add(_Message(text: '⚠️ 发送失败: $e', isUser: false, timestamp: DateTime.now(), isError: true));
              _sending = false;
              _streamingContent = '';
              _segmentsCommitted = 0;
            });
          }
        },
        cancelOnError: false,
      );

      // ★ 记录订阅
      final sid = displayIdAtSend ?? '__pending_new__';
      _streamSubscriptions[sid] = sub;
      _streamingBuffers[sid] = '';
      _streamingSessions.add(sid);

      // 如果没有 sessionId（新会话），用 pending key 占位
      if (displayIdAtSend == null) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        title: Text(_activeDisplaySession?.displayTitle ?? '新对话'),
        actions: [
          ModelSwitcher(
            currentModel: _currentSessionModel,
            currentProvider: _currentSessionProvider,
            onModelSelected: _onModelSelected,
          ),
          if (_activeDisplaySession != null)
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
                      : _displaySessions.isEmpty
                          ? Center(
                              child: Text('暂无会话',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                          : ListView(
                              controller: _sessionScrollController,
                              children: [
                                ..._buildSessionList(),
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
                              (_sending || _interrupted ? 1 : 0) +
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
                                attachments: m.attachments,
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
                ChatDropZone(
                  onFileDropped: (files) =>
                      setState(() => _attachedFiles.addAll(files)),
                  child: Container(
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
                            child: Focus(
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent &&
                                    event.logicalKey == LogicalKeyboardKey.keyV &&
                                    HardwareKeyboard.instance.isControlPressed) {
                                  _pasteImageFromClipboard();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                key: ValueKey('input_${_activeDisplaySession?.id ?? 'new'}'),
                                controller: _inputController,
                                focusNode: _skillNode,
                                enabled: !_sending && !_loadingMessages,
                                maxLines: 4,
                                minLines: 1,
                                textInputAction: TextInputAction.send,
                                decoration: InputDecoration(
                                  hintText: '输入消息... / 加载技能\nEnter 发送 · Shift+Enter 换行',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
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
              ),
            ],
          ),
        ),
      ],
    ),
  );
  }

  /// 扁平会话列表 — 只显示 Desktop 本机会话（source == cli），无分组
  List<Widget> _buildSessionList() {
    final cs = Theme.of(context).colorScheme;
    final q = _searchController.text.trim().toLowerCase();

    List<DisplaySession> sessions;
    if (q.isEmpty) {
      sessions = List.from(_displayedDisplaySessions);
    } else {
      // 搜索时忽略分页，全量搜索
      sessions = _displaySessions
          .where((s) => s.displayTitle.toLowerCase().contains(q))
          .toList();
    }

    // 已置顶的排前面
    sessions.sort((a, b) {
      final aPinned = _pinnedSessionIds.contains(a.id);
      final bPinned = _pinnedSessionIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0;
    });
    return sessions.isEmpty
        ? [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('暂无会话', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            ),
          ]
        : sessions.map((s) => _SessionItem(
              ds: s,
              selected: _activeDisplaySession?.id == s.id,
              pinned: _pinnedSessionIds.contains(s.id),
              onTap: () => _selectSession(s),
              onDelete: () => _deleteDisplaySession(s.id),
              onTogglePin: () => _togglePin(s.id),
              onSetRemark: () => _setDisplaySessionRemark(s.id),
            )).toList();
  }

  Future<void> _setDisplaySessionRemark(String id) async {
    final ds = _displaySessions.firstWhere((s) => s.id == id);
    final controller = TextEditingController(text: ds.remark ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置备注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入备注名称',
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('清除')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    final remark = result.isNotEmpty ? result : null;
    final updated = ds.copyWith(remark: remark);
    await _localDb.updateDisplaySession(updated);
    setState(() {
      final idx = _displaySessions.indexWhere((s) => s.id == id);
      if (idx >= 0) _displaySessions[idx] = updated;
      final didx = _displayedDisplaySessions.indexWhere((s) => s.id == id);
      if (didx >= 0) _displayedDisplaySessions[didx] = updated;
      if (_activeDisplaySession?.id == id) {
        _activeDisplaySession = updated;
      }
    });
  }

  Future<void> _deleteDisplaySession(String id) async {
    _showLoading('删除中...');
    try {
      final ds = _displaySessions.firstWhere((s) => s.id == id);
      if (ds.currentBackendId.isNotEmpty) {
        await _localDb.deleteSession(ds.currentBackendId);
      }
      for (final oldId in ds.backendIdHistory) {
        await _localDb.deleteSession(oldId);
      }
      await _localDb.deleteDisplaySession(id);
      _hideLoading();
      setState(() {
        _displaySessions.removeWhere((s) => s.id == id);
        _displayedDisplaySessions.removeWhere((s) => s.id == id);
        if (_activeDisplaySession?.id == id) _newChat();
      });
    } catch (e) {
      _hideLoading();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
      _loadDisplaySessions();
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
  final List<Map<String, String>>? attachments;

  _Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.toolCalls,
    this.attachments,
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
  final DisplaySession ds;
  final bool selected;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onSetRemark;

  const _SessionItem({
    required this.ds,
    required this.selected,
    this.pinned = false,
    required this.onTap,
    required this.onDelete,
    required this.onTogglePin,
    required this.onSetRemark,
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
                          ds.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight:
                                selected ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          ds.preview?.isNotEmpty == true
                              ? ds.preview!
                              : '暂无消息',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? Theme.of(context).colorScheme.onSurfaceVariant
                                  : Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
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
        PopupMenuItem<String>(
          value: 'remark',
          child: SizedBox(
            width: 180,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                const SizedBox(width: 12),
                Text(ds.remark != null ? '编辑备注' : '设置备注'),
              ],
            ),
          ),
          onTap: () => onSetRemark(),
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
