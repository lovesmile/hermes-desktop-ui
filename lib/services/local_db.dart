import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/session.dart';
import '../models/display_session.dart';
import 'config_service.dart';

/// Desktop 客户端本地数据库
/// 使用 SQLite（sqflite_common_ffi）存储会话和消息
/// 首次启动自动从旧 JSON 文件迁移数据
class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._();
  factory LocalDatabase() => _instance;
  LocalDatabase._();

  Database? _db;
  String _mode = 'local';

  /// 切换连接模式，同时切换 DB 文件实现隔离
  Future<void> setMode(String mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _close();
  }

  String get _dbPath {
    final base = '${ConfigService.resolveHermesHome()}/desktop_db';
    final suffix = connectionModeToDbSuffix(_mode);
    return suffix.isEmpty ? '$base.db' : '${base}_$suffix.db';
  }

  String connectionModeToDbSuffix(String mode) {
    if (mode == 'local') return '';
    if (mode == 'embedded') return '_embedded';
    return '_${mode.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}';
  }

  // ── DB lifecycle ──

  Future<Database> _getDb() async {
    if (_db != null) return _db!;

    final path = _dbPath;
    final dir = File(path).parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 首次启动时从 JSON 迁移
    final sqliteExists = await File(path).exists();
    if (!sqliteExists) {
      await _migrateFromJsonIfNeeded();
    }

    _db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _onCreate,
      ),
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        remark TEXT,
        gateway_session_id TEXT,
        source TEXT DEFAULT 'cli',
        model TEXT,
        provider TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        attachments TEXT,
        tool_calls TEXT,
        timestamp TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS display_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        remark TEXT,
        current_backend_id TEXT NOT NULL DEFAULT '',
        backend_id_history TEXT NOT NULL DEFAULT '[]',
        preview TEXT,
        model TEXT,
        provider TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id)');
  }

  Future<void> _close() async {
    await _db?.close();
    _db = null;
  }

  // ── 从 JSON 迁移 ──

  Future<void> _migrateFromJsonIfNeeded() async {
    final base = '${ConfigService.resolveHermesHome()}/desktop_db';
    final suffix = connectionModeToDbSuffix(_mode);
    final jsonPath = suffix.isEmpty ? '$base.json' : '${base}_$suffix.json';
    final jsonFile = File(jsonPath);
    if (!await jsonFile.exists()) return;

    try {
      final content = await jsonFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final dbPath = _dbPath;
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _onCreate,
        ),
      );

      try {
        // 迁移 sessions + messages
        final sessionsMap = data['sessions'] as Map<String, dynamic>? ?? {};
        for (final entry in sessionsMap.entries) {
          final s = entry.value as Map<String, dynamic>;
          final id = s['id'] as String? ?? entry.key;
          await db.insert('sessions', {
            'id': id,
            'title': s['title'] ?? '',
            'remark': s['remark'],
            'gateway_session_id': s['gateway_session_id'],
            'source': s['source'] ?? 'cli',
            'model': s['model'],
            'provider': s['provider'],
            'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
            'updated_at': s['updated_at'] ?? DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          final msgs = s['messages'] as List? ?? [];
          for (final msg in msgs) {
            final m = msg as Map<String, dynamic>;
            await db.insert('messages', {
              'session_id': id,
              'role': m['role'] ?? 'user',
              'content': m['content'] ?? '',
              'attachments': m['attachments'] != null ? jsonEncode(m['attachments']) : null,
              'tool_calls': m['tool_calls'] != null ? jsonEncode(m['tool_calls']) : null,
              'timestamp': m['timestamp'] ?? DateTime.now().toIso8601String(),
            });
          }
        }

        // 迁移 display_sessions
        final dsMap = data['display_sessions'] as Map<String, dynamic>? ?? {};
        for (final entry in dsMap.entries) {
          final s = entry.value as Map<String, dynamic>;
          await db.insert('display_sessions', {
            'id': s['id'] ?? entry.key,
            'title': s['title'] ?? '',
            'remark': s['remark'],
            'current_backend_id': s['current_backend_id'] ?? '',
            'backend_id_history':
                s['backend_id_history'] != null ? jsonEncode(s['backend_id_history']) : '[]',
            'preview': s['preview'],
            'model': s['model'],
            'provider': s['provider'],
            'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
            'updated_at': s['updated_at'] ?? DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } finally {
        await db.close();
      }

      // 迁移成功后重命名 JSON 作为备份
      await jsonFile.rename('$jsonPath.migrated');
    } catch (_) {
      // 迁移失败则从头开始
    }
  }

  // ── Session 方法 ──

  Future<List<Session>> getSessions() async {
    final db = await _getDb();
    final rows = await db.query('sessions', orderBy: 'updated_at DESC');
    final list = <Session>[];
    for (final row in rows) {
      list.add(Session(
        id: row['id'] as String,
        title: row['title'] as String? ?? '',
        remark: row['remark'] as String?,
        gatewaySessionId: row['gateway_session_id'] as String?,
        source: row['source'] as String? ?? 'cli',
        createdAt: _parseDate(row['created_at']),
        updatedAt: _parseDate(row['updated_at']),
        messageCount: await _countMessages(row['id'] as String),
        preview: await _getPreview(row['id'] as String),
        model: row['model'] as String?,
        provider: row['provider'] as String?,
      ));
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final db = await _getDb();
    final rows = await db.query('messages',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'id ASC');
    return rows.map((row) {
      final map = <String, dynamic>{
        'role': row['role'],
        'content': row['content'],
        'timestamp': row['timestamp'],
      };
      if (row['attachments'] != null) {
        try {
          map['attachments'] = jsonDecode(row['attachments'] as String);
        } catch (_) {}
      }
      if (row['tool_calls'] != null) {
        try {
          map['tool_calls'] = jsonDecode(row['tool_calls'] as String);
        } catch (_) {}
      }
      return map;
    }).toList();
  }

  Future<Session?> getSession(String sessionId) async {
    final db = await _getDb();
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [sessionId]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Session(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      remark: row['remark'] as String?,
      gatewaySessionId: row['gateway_session_id'] as String?,
      source: row['source'] as String? ?? 'cli',
      createdAt: _parseDate(row['created_at']),
      updatedAt: _parseDate(row['updated_at']),
      messageCount: await _countMessages(row['id'] as String),
      preview: await _getPreview(row['id'] as String),
      model: row['model'] as String?,
      provider: row['provider'] as String?,
    );
  }

  Future<void> createSession({
    required String id,
    required String title,
    String userMessage = '',
    String assistantMessage = '',
    String? model,
    String? provider,
    List<Map<String, String>>? userAttachments,
  }) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    await db.insert('sessions', {
      'id': id,
      'title': title,
      'source': 'cli',
      'model': model,
      'provider': provider,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (userMessage.isNotEmpty ||
        (userAttachments != null && userAttachments.isNotEmpty)) {
      await db.insert('messages', {
        'session_id': id,
        'role': 'user',
        'content': userMessage,
        'attachments': userAttachments != null ? jsonEncode(userAttachments) : null,
        'timestamp': now,
      });
    }
    if (assistantMessage.isNotEmpty) {
      await db.insert('messages', {
        'session_id': id,
        'role': 'assistant',
        'content': assistantMessage,
        'timestamp': now,
      });
    }
  }

  Future<void> addMessage(String sessionId, String role, String content,
      {List<Map<String, String>>? attachments,
      void Function(String preview)? onPreviewUpdated}) async {
    if (sessionId.isEmpty) return;
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    await db.insert('messages', {
      'session_id': sessionId,
      'role': role,
      'content': content,
      'attachments': attachments != null ? jsonEncode(attachments) : null,
      'timestamp': now,
    });
    await db.update('sessions',
        {'updated_at': now},
        where: 'id = ?', whereArgs: [sessionId]);
    // 同步更新 display_sessions 的预览
    if (role != 'tool') {
      final trimmed = content.trim();
      if (trimmed.isNotEmpty) {
        final preview = trimmed.length > 100 ? '${trimmed.substring(0, 100)}...' : trimmed;
        await db.update(
          'display_sessions',
          {'preview': preview, 'updated_at': now},
          where: 'current_backend_id = ?',
          whereArgs: [sessionId],
        );
        onPreviewUpdated?.call(preview);
      }
    }
  }

  Future<void> updateSessionRemark(String sessionId, String? remark) async {
    final db = await _getDb();
    await db.update('sessions',
        {'remark': (remark != null && remark.isNotEmpty) ? remark : null},
        where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<void> updateGatewaySessionId(
      String localSessionId, String? gatewaySessionId) async {
    final db = await _getDb();
    await db.update('sessions',
        {'gateway_session_id': gatewaySessionId},
        where: 'id = ?', whereArgs: [localSessionId]);
  }

  @Deprecated('Per-session model switching has been removed.')
  Future<void> updateSessionModel(String sessionId, String? model,
      {String? provider}) async {
    final db = await _getDb();
    await db.update('sessions',
        {'model': model, 'provider': provider},
        where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await _getDb();
    await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  void invalidate() {
    // SQLite 连接持续存在，无需清除缓存
  }

  // ── DisplaySession 方法 ──

  Future<List<DisplaySession>> getDisplaySessions() async {
    final db = await _getDb();
    final rows = await db.query('display_sessions', orderBy: 'updated_at DESC');
    return rows.map((row) => DisplaySession(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      remark: row['remark'] as String?,
      currentBackendId: row['current_backend_id'] as String? ?? '',
      backendIdHistory: _parseStrList(row['backend_id_history'] as String?),
      preview: row['preview'] as String?,
      model: row['model'] as String?,
      provider: row['provider'] as String?,
      createdAt: _parseDate(row['created_at']),
      updatedAt: _parseDate(row['updated_at']),
    )).toList();
  }

  Future<DisplaySession?> getDisplaySession(String id) async {
    final db = await _getDb();
    final rows = await db.query('display_sessions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return DisplaySession(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      remark: row['remark'] as String?,
      currentBackendId: row['current_backend_id'] as String? ?? '',
      backendIdHistory: _parseStrList(row['backend_id_history'] as String?),
      preview: row['preview'] as String?,
      model: row['model'] as String?,
      provider: row['provider'] as String?,
      createdAt: _parseDate(row['created_at']),
      updatedAt: _parseDate(row['updated_at']),
    );
  }

  Future<void> createDisplaySession(DisplaySession ds) async {
    final db = await _getDb();
    await db.insert('display_sessions', {
      'id': ds.id,
      'title': ds.title,
      'remark': ds.remark,
      'current_backend_id': ds.currentBackendId,
      'backend_id_history': jsonEncode(ds.backendIdHistory),
      'preview': ds.preview,
      'model': ds.model,
      'provider': ds.provider,
      'created_at': ds.createdAt.toIso8601String(),
      'updated_at': ds.updatedAt.toIso8601String(),
    });
  }

  Future<void> updateDisplaySession(DisplaySession ds) async {
    final db = await _getDb();
    await db.update('display_sessions', {
      'title': ds.title,
      'remark': ds.remark,
      'current_backend_id': ds.currentBackendId,
      'backend_id_history': jsonEncode(ds.backendIdHistory),
      'preview': ds.preview,
      'model': ds.model,
      'provider': ds.provider,
      'updated_at': ds.updatedAt.toIso8601String(),
    }, where: 'id = ?', whereArgs: [ds.id]);
  }

  Future<void> switchBackendId(String displayId, String newBackendId) async {
    final ds = await getDisplaySession(displayId);
    if (ds == null) return;
    // 切换时从新后端读取最新一条消息更新 preview
    final rows = await (await _getDb()).rawQuery(
      "SELECT content FROM messages WHERE session_id = ? AND role != 'tool' ORDER BY id DESC LIMIT 1",
      [newBackendId],
    );
    String? preview;
    if (rows.isNotEmpty) {
      final raw = (rows.first['content'] as String? ?? '').trim();
      if (raw.isNotEmpty) {
        preview = raw.length > 100 ? '${raw.substring(0, 100)}...' : raw;
      }
    }
    final updated = ds.copyWith(
      currentBackendId: newBackendId,
      backendIdHistory: [...ds.backendIdHistory, ds.currentBackendId],
      preview: preview ?? ds.preview,
      updatedAt: DateTime.now(),
    );
    await updateDisplaySession(updated);
  }

  Future<void> deleteDisplaySession(String id) async {
    final db = await _getDb();
    await db.delete('display_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getDisplayMessages(String displayId) async {
    final ds = await getDisplaySession(displayId);
    if (ds == null || ds.currentBackendId.isEmpty) return [];
    return getMessages(ds.currentBackendId);
  }

  Future<void> addDisplayMessage(String displayId, String role, String content,
      {List<Map<String, String>>? attachments}) async {
    final ds = await getDisplaySession(displayId);
    if (ds == null || ds.currentBackendId.isEmpty) return;
    await addMessage(ds.currentBackendId, role, content,
        attachments: attachments);
    // 更新展示会话的时间戳
    final updated = ds.copyWith(updatedAt: DateTime.now());
    await updateDisplaySession(updated);
  }

  // ── 兼容旧接口 ──

  Future<void> migrateOldSessionsIfNeeded() async {
    // JSON→SQLite 迁移在 _getDb() 中自动处理
  }

  // ── Helpers ──

  Future<void> _syncPreview(String sessionId) async {
    final db = await _getDb();
    // 取最后一条非 tool 消息作为预览
    final rows = await db.rawQuery(
      "SELECT content FROM messages WHERE session_id = ? AND role != 'tool' ORDER BY id DESC LIMIT 1",
      [sessionId],
    );
    String? preview;
    if (rows.isNotEmpty) {
      final raw = (rows.first['content'] as String? ?? '').trim();
      if (raw.isNotEmpty) {
        preview = raw.length > 100 ? '${raw.substring(0, 100)}...' : raw;
      }
    }
    // 更新所有引用该后端 session 的 display_sessions
    await db.update(
      'display_sessions',
      {'preview': preview, 'updated_at': DateTime.now().toIso8601String()},
      where: 'current_backend_id = ?',
      whereArgs: [sessionId],
    );
  }

  List<String> _parseStrList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
    return DateTime.now();
  }

  Future<int> _countMessages(String sessionId) async {
    final db = await _getDb();
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM messages WHERE session_id = ?', [sessionId]);
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<String?> _getPreview(String sessionId) async {
    final db = await _getDb();
    final rows = await db.rawQuery(
      "SELECT content FROM messages WHERE session_id = ? AND role != 'tool' ORDER BY id DESC LIMIT 1",
      [sessionId],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['content'] as String? ?? '';
    final text = raw.trim();
    if (text.isEmpty) return null;
    return text.length > 100 ? '${text.substring(0, 100)}...' : text;
  }
}
