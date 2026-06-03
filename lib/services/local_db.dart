import 'dart:convert';
import 'dart:io';
import '../models/session.dart';
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
    _cache = {'version': 1, 'sessions': <String, dynamic>{}};
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
    );
  }

  /// 创建新会话（含标题和第一条消息）
  Future<void> createSession({
    required String id,
    required String title,
    String userMessage = '',
    String assistantMessage = '',
  }) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final now = DateTime.now().toIso8601String();
    final messages = <Map<String, dynamic>>[];
    if (userMessage.isNotEmpty) {
      messages.add({
        'role': 'user',
        'content': userMessage,
        'timestamp': now,
      });
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
    };
    await _write(db);
  }

  /// 添加消息到指定会话
  Future<void> addMessage(String sessionId, String role, String content) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final session = sessionsMap[sessionId] as Map<String, dynamic>?;
    if (session == null) return;
    final messages = session['messages'] as List? ?? [];
    messages.add({
      'role': role,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
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
  Future<void> updateGatewaySessionId(String localSessionId, String gatewaySessionId) async {
    final db = await _read();
    final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};
    final session = sessionsMap[localSessionId] as Map<String, dynamic>?;
    if (session == null) return;
    session['gateway_session_id'] = gatewaySessionId;
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

  // ── helpers ──

  DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
    return DateTime.now();
  }

  String? _getPreview(List? messages) {
    if (messages == null || messages.isEmpty) return null;
    // 取最后一条消息（无论 user 还是 assistant）
    final last = messages.last as Map<String, dynamic>? ?? {};
    final c = last['content'] as String? ?? '';
    if (c.isNotEmpty) return c.length > 100 ? '${c.substring(0, 100)}...' : c;
    return null;
  }
}
