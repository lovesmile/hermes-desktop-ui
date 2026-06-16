import 'dart:convert';
import 'dart:io';
import '../models/session.dart';
import '../models/display_session.dart';
import 'config_service.dart';
import 'connection_manager.dart';

/// Desktop 客户端本地数据库
/// 用 JSON 文件存储会话和消息，类似 IM 客户端本地存储
/// 每次操作后立即持久化，重启不丢数据
/// 支持 local/远程IP 两种模式，用不同 DB 文件隔离
class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._();
  factory LocalDatabase() => _instance;
  LocalDatabase._();

  String _mode = 'local';

  /// 切换连接模式，同时切换 DB 文件实现隔离
  Future<void> setMode(String mode) async {
    if (_mode == mode) return;
    _mode = mode;
    _cache = null;
  }

  String get _dbPath {
    final base = '${ConfigService.resolveHermesHome()}/desktop_db';
    final suffix = connectionModeToDbSuffix(_mode);
    return suffix.isEmpty ? '${base}.json' : '${base}$suffix.json';
  }

  String connectionModeToDbSuffix(String mode) {
    if (mode == 'local') return '';
    if (mode == 'embedded') return '_embedded';
    return '_${mode.replaceAll(RegExp(r'[^a-zA-Z0-9_\\-]'), '_')}';
  }

  Map<String, dynamic>? _cache;

  Future<Map<String, dynamic>> _read() async {
    if (_cache != null) return _cache!;
    try {
      final file = File(_dbPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        _cache = jsonDecode(content) as Map<String, dynamic>? ?? {};
        return _cache!;
      }
    } catch (_) {}
    _cache = {'version': 1, 'sessions': <String, dynamic>{}, 'display_sessions': <String, dynamic>{}};
    return _cache!;
  }

  Future<void> _write(Map<String, dynamic> data) async {
    _cache = data;
    try {
      await File(_dbPath).writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  /// 获取所有会话（按 updatedAt 倒序）
  Future<List<Session>> getSessions() async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final list = <Session>[];
    for (final entry in sessionsMap.entries) {
      final s = entry.value as Map<String, dynamic>? ?? {};
      list.add(Session(
        id: s['id'] as String? ?? entry.key,
        title: s['title'] as String? ?? '',
        remark: s['remark'] as String?,
        gatewaySessionId: s['gateway_session_id'] as String?,
        source: s['source'] as String? ?? 'cli',
        createdAt: _parseDate(s['created_at']),
        updatedAt: _parseDate(s['updated_at']),
        messageCount: (s['messages'] as List?)?.length ?? 0,
        preview: _getPreview(s['messages'] as List?),
        model: s['model'] as String?,
        provider: s['provider'] as String?,
      ));
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// 获取指定会话的消息列表
  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final session = sessionsMap[sessionId] as Map<String, dynamic>?;
    if (session == null) return [];
    final messages = session['messages'] as List? ?? [];
    return messages.cast<Map<String, dynamic>>();
  }

  /// 获取单个会话
  Future<Session?> getSession(String sessionId) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final s = sessionsMap[sessionId] as Map<String, dynamic>?;
    if (s == null) return null;
    return Session(
      id: s['id'] as String? ?? sessionId,
      title: s['title'] as String? ?? '',
      remark: s['remark'] as String?,
      gatewaySessionId: s['gateway_session_id'] as String?,
      source: s['source'] as String? ?? 'cli',
      createdAt: _parseDate(s['created_at']),
      updatedAt: _parseDate(s['updated_at']),
      messageCount: (s['messages'] as List?)?.length ?? 0,
      preview: _getPreview(s['messages'] as List?),
      model: s['model'] as String?,
      provider: s['provider'] as String?,
    );
  }

  /// 创建新会话（含标题和第一条消息）
  Future<void> createSession({
    required String id,
    required String title,
    String userMessage = '',
    String assistantMessage = '',
    String? model,
    String? provider,
    List<Map<String, String>>? userAttachments,
  }) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final now = DateTime.now().toIso8601String();
    final messages = <Map<String, dynamic>>[];
    if (userMessage.isNotEmpty ||
        (userAttachments != null && userAttachments.isNotEmpty)) {
      final msg = <String, dynamic>{
        'role': 'user',
        'content': userMessage,
        'timestamp': now,
      };
      if (userAttachments != null && userAttachments.isNotEmpty) {
        msg['attachments'] = userAttachments.map((a) => <String, String>{
          'name': a['name'] ?? '',
          'mime': a['mime'] ?? 'application/octet-stream',
        }).toList();
      }
      messages.add(msg);
    }
    if (assistantMessage.isNotEmpty) {
      messages.add({
        'role': 'assistant',
        'content': assistantMessage,
        'timestamp': now,
      });
    }
    sessionsMap[id] = {
      'id': id,
      'title': title,
      'source': 'cli',
      'created_at': now,
      'updated_at': now,
      'messages': messages,
      if (model != null) 'model': model,
      if (provider != null) 'provider': provider,
    };
    await _write(db);
  }

  /// 添加消息到指定会话
  Future<void> addMessage(String sessionId, String role, String content,
      {List<Map<String, String>>? attachments}) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final session = sessionsMap[sessionId] as Map<String, dynamic>?;
    if (session == null) return;
    final messages = session['messages'] as List? ?? [];
    final msg = <String, dynamic>{
      'role': role,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (attachments != null && attachments.isNotEmpty) {
      msg['attachments'] = attachments.map((a) => <String, String>{
        'name': a['name'] ?? '',
        'mime': a['mime'] ?? 'application/octet-stream',
      }).toList();
    }
    messages.add(msg);
    session['messages'] = messages;
    session['updated_at'] = DateTime.now().toIso8601String();
    // 更新标题预览：取第一条用户消息
    if (session['title'] == null || (session['title'] as String).isEmpty) {
      for (final m in messages) {
        if (m['role'] == 'user') {
          final c = (m['content'] as String?) ?? '';
          session['title'] = c.length > 25 ? '${c.substring(0, 25)}...' : c;
          break;
        }
      }
    }
    await _write(db);
  }

  /// 设置会话备注
  Future<void> updateSessionRemark(String sessionId, String? remark) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final session = sessionsMap[sessionId] as Map<String, dynamic>?;
    if (session == null) return;
    if (remark != null && remark.isNotEmpty) {
      session['remark'] = remark;
    } else {
      session.remove('remark');
    }
    await _write(db);
  }

  /// 更新会话的 Gateway session ID（续聊用）
  /// 传 null 或空字符串会从 DB 中移除该 key，而非存空值
  Future<void> updateGatewaySessionId(String localSessionId, String? gatewaySessionId) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final session = sessionsMap[localSessionId] as Map<String, dynamic>?;
    if (session == null) return;
    if (gatewaySessionId != null && gatewaySessionId.isNotEmpty) {
      session['gateway_session_id'] = gatewaySessionId;
    } else {
      session.remove('gateway_session_id');
    }
    await _write(db);
  }

  /// 更新会话的模型和 provider
  @Deprecated('Per-session model switching has been removed. Use global config only.')
  Future<void> updateSessionModel(String sessionId, String? model, {String? provider}) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final session = sessionsMap[sessionId] as Map<String, dynamic>?;
    if (session == null) return;
    if (model != null && model.isNotEmpty) {
      session['model'] = model;
    } else {
      session.remove('model');
    }
    if (provider != null && provider.isNotEmpty) {
      session['provider'] = provider;
    } else {
      session.remove('provider');
    }
    await _write(db);
  }

  /// 删除会话
  Future<void> deleteSession(String sessionId) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    sessionsMap.remove(sessionId);
    await _write(db);
  }

  /// 清除缓存（强制下次重新读取磁盘）
  void invalidate() {
    _cache = null;
  }

  /// 迁移旧版 sessions 到 DisplaySession（无数据时自动执行一次）
  Future<void> migrateOldSessionsIfNeeded() async {
    final db = await _read();
    final dsMap = db['display_sessions'] as Map<String, dynamic>? ?? {};
    if (dsMap.isNotEmpty) return; // 已有展示会话，无需迁移
    final oldMap = db['sessions'] as Map<String, dynamic>? ?? {};
    if (oldMap.isEmpty) return; // 没有旧会话

    final migrated = <String, dynamic>{};
    for (final entry in oldMap.entries) {
      final s = entry.value as Map<String, dynamic>? ?? {};
      final id = s['id'] as String? ?? entry.key;
      final messages = s['messages'] as List? ?? [];
      final preview = _getPreview(messages);
      migrated[id] = {
        'id': id,
        'title': s['title'] ?? '未命名会话',
        if (s['remark'] != null) 'remark': s['remark'],
        'current_backend_id': id,
        'backend_id_history': [id],
        if (preview.isNotEmpty) 'preview': preview,
        if (s['model'] != null) 'model': s['model'],
        if (s['provider'] != null) 'provider': s['provider'],
        'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
        'updated_at': s['updated_at'] ?? DateTime.now().toIso8601String(),
      };
    }
    db['display_sessions'] = migrated;
    await _write(db);
  }

  // ═══════════════════════════════════════════
  //  DisplaySession — 展示层会话（用户看到的条目）
  //  每个 DisplaySession 对应一个用户聊天条目，
  //  绑定一个或多个后端 backend session_id。
  //  切换模型 → 后端生成新 session_id → 更新 currentBackendId
  //  → 展示层条目不变，title/remark 不丢失。
  // ═══════════════════════════════════════════

  /// 获取所有展示会话（按 updatedAt 倒序）
  Future<List<DisplaySession>> getDisplaySessions() async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    final list = map.values
        .map((v) => DisplaySession.fromJson(v as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// 获取单个展示会话
  Future<DisplaySession?> getDisplaySession(String id) async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    final data = map[id] as Map<String, dynamic>?;
    if (data == null) return null;
    return DisplaySession.fromJson(data);
  }

  /// 创建展示会话
  Future<void> createDisplaySession(DisplaySession ds) async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    map[ds.id] = ds.toJson();
    db['display_sessions'] = map;
    await _write(db);
  }

  /// 更新展示会话字段
  Future<void> updateDisplaySession(DisplaySession ds) async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    map[ds.id] = ds.toJson();
    db['display_sessions'] = map;
    await _write(db);
  }

  /// 切换后端 session_id：更新 currentBackendId + 追加到 history
  Future<void> switchBackendId(String displayId, String newBackendId) async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    final data = map[displayId] as Map<String, dynamic>?;
    if (data == null) return;
    final ds = DisplaySession.fromJson(data);
    final updated = ds.copyWith(
      currentBackendId: newBackendId,
      backendIdHistory: [...ds.backendIdHistory, ds.currentBackendId],
      updatedAt: DateTime.now(),
    );
    map[displayId] = updated.toJson();
    db['display_sessions'] = map;
    await _write(db);
  }

  /// 删除展示会话
  Future<void> deleteDisplaySession(String id) async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    map.remove(id);
    db['display_sessions'] = map;
    await _write(db);
  }

  /// 获取展示会话的所有消息（按后端 session 查询）
  Future<List<Map<String, dynamic>>> getDisplayMessages(String displayId) async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    final data = map[displayId] as Map<String, dynamic>?;
    if (data == null) return [];
    final ds = DisplaySession.fromJson(data);
    final backendId = ds.currentBackendId;
    if (backendId.isEmpty) return [];
    return getMessages(backendId);
  }

  /// 向展示会话的当前后端添加消息
  Future<void> addDisplayMessage(String displayId, String role, String content,
      {List<Map<String, String>>? attachments}) async {
    final db = await _read();
    final map = db['display_sessions'] as Map<String, dynamic>? ?? {};
    final data = map[displayId] as Map<String, dynamic>?;
    if (data == null) return;
    final ds = DisplaySession.fromJson(data);
    if (ds.currentBackendId.isEmpty) return;
    await addMessage(ds.currentBackendId, role, content, attachments: attachments);
    // 更新展示会话的 updatedAt
    final updated = ds.copyWith(updatedAt: DateTime.now());
    map[displayId] = updated.toJson();
    db['display_sessions'] = map;
    await _write(db);
  }

  // ── helpers ──

  DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
    return DateTime.now();
  }

  String _getPreview(List? messages) {
    if (messages == null || messages.isEmpty) return '';
    // 倒序找第一个有非空内容的消息，兼容 content 为 String/Map 等多种格式
    for (int i = messages.length - 1; i >= 0; i--) {
      final m = messages[i] as Map<String, dynamic>? ?? {};
      final raw = m['content'];
      String text;
      if (raw is String) {
        text = raw;
      } else if (raw is Map) {
        text = raw.toString();
      } else {
        text = raw?.toString() ?? '';
      }
      text = text.trim();
      if (text.isNotEmpty) return text.length > 100 ? '${text.substring(0, 100)}...' : text;
    }
    return '';
  }
}
