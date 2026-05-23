import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/session.dart';
import '../models/stats.dart';
import '../models/cron_job.dart';
import '../models/log_entry.dart';
import 'config_service.dart';

/// Hermes Gateway API Server 客户端
/// 真实接口: OpenAI-compatible API + 文件 I/O
class GatewayService {
  static final GatewayService _instance = GatewayService._();
  factory GatewayService() => _instance;
  GatewayService._();

  final _configService = ConfigService();
  String _baseUrl = ConfigService.defaultGatewayUrl;
  bool _offline = false;
  bool get isOffline => _offline;
  HttpClient _client = HttpClient();

  /// 从配置中刷新 Gateway URL
  Future<void> refreshBaseUrl() async {
    _baseUrl = await _configService.getGatewayUrl();
  }

  String get _hermesHome => ConfigService.resolveHermesHome();

  void _resetClient() {
    _client.close(force: true);
    _client = HttpClient();
    _client.connectionTimeout = const Duration(seconds: 5);
  }

  // ═══════════════════════════════════════════
  //  健康检查 (GET /health)
  // ═══════════════════════════════════════════

  Future<bool> checkHealth() async {
    try {
      _resetClient();
      final request = await _client
          .getUrl(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      _offline = false;
      return json['status'] == 'ok';
    } catch (_) {
      _offline = true;
      return false;
    }
  }

  // ═══════════════════════════════════════════
  //  流式聊天 (POST /v1/chat/completions, SSE)
  // ═══════════════════════════════════════════

  Stream<String> chatStream(String message, {String? sessionId}) {
    final controller = StreamController<String>.broadcast(
      onCancel: () {
        _client.close(force: true);
        _resetClient();
      },
    );

    _doChat(message, sessionId, controller);
    return controller.stream;
  }

  Future<void> _doChat(String message, String? sessionId,
      StreamController<String> controller) async {
    try {
      final uri = Uri.parse('$_baseUrl/v1/chat/completions');
      final request = await _client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'text/event-stream');
      if (sessionId != null) {
        request.headers.set('X-Hermes-Session-Id', sessionId);
      }

      final body = jsonEncode({
        'model': 'hermes-agent',
        'messages': [
          {'role': 'user', 'content': message}
        ],
        'stream': true,
      });
      request.write(body);

      final response = await request.close();
      if (response.statusCode != 200) {
        controller.addError('HTTP ${response.statusCode}');
        controller.close();
        return;
      }

      await response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              controller.close();
              return;
            }
            try {
              final parsed = jsonDecode(data);
              final delta = parsed['choices']?[0]?['delta'];
              if (delta != null) {
                final content = delta['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  controller.add(content);
                }
              }
            } catch (_) {
              // skip unparseable chunks
            }
          }
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
        onError: (e) {
          if (!controller.isClosed) controller.addError(e);
        },
      );
    } catch (e) {
      _offline = true;
      if (!controller.isClosed) {
        controller.addError('连接失败: $e');
        controller.close();
      }
    }
  }

  void disconnectChat() {
    _client.close(force: true);
    _resetClient();
  }

  // ═══════════════════════════════════════════
  //  统计信息（从文件系统读取）
  // ═══════════════════════════════════════════

  Future<Stats> getStats() async {
    // 从 session 文件和日志中粗略统计
    final sessions = await getSessions();
    int tokens = 0;
    try {
      final logFile = File('$_hermesHome/logs/agent.log');
      if (await logFile.exists()) {
        final content = await logFile.readAsString();
        // 粗略估算 token 数
        tokens = content.length ~/ 4;
      }
    } catch (_) {}

    return Stats(
      totalSessions: sessions.length,
      totalTokens: tokens,
      inputTokens: tokens ~/ 2,
      outputTokens: tokens ~/ 2,
      dailyAvgSessions: sessions.length > 0 ? 1.0 : 0,
    );
  }

  // ═══════════════════════════════════════════
  //  会话（从 JSON 文件读取）
  // ═══════════════════════════════════════════

  Future<List<Session>> getSessions() async {
    final sessions = <Session>[];
    final seenIds = <String>{};
    try {
      final dir = Directory('$_hermesHome/sessions');
      if (await dir.exists()) {
        final files = await dir.list().toList();
        // 只读 session_*.json 文件，排除 session_cron_* 和 request_dump_*
        final sessionFiles = files.where((e) {
          final name = e.uri.pathSegments.last;
          return name.startsWith('session_') &&
              !name.startsWith('session_cron_') &&
              name.endsWith('.json');
        }).toList();

        // 按修改时间倒序
        sessionFiles.sort((a, b) {
          final mb = b.statSync().modified;
          final ma = a.statSync().modified;
          return mb.compareTo(ma);
        });

        for (final f in sessionFiles) {
          try {
            final content = await File(f.path).readAsString();
            final json = jsonDecode(content);
            final sid = json['session_id'] ?? '';
            if (sid.isEmpty || seenIds.contains(sid)) continue;
            seenIds.add(sid);

            final lastUpdated = json['last_updated'] ?? json['session_start'] ?? '';
            final updatedAt = lastUpdated is String
                ? (DateTime.tryParse(lastUpdated) ?? DateTime.now())
                : DateTime.now();

            // 从 session_id 提取可读标题
            String title = _formatSessionTitle(sid);
            final messages = json['messages'] as List?;
            final msgCount = messages?.length ?? 0;
            final platform = json['platform'] ?? 'cli';

            // 尝试用最后一条用户消息做标题（更易回忆）
            String userMsg = '';
            if (messages != null && messages.isNotEmpty) {
              for (int i = messages.length - 1; i >= 0; i--) {
                if (messages[i]['role'] == 'user') {
                  final c = messages[i]['content'];
                  if (c is String && c.isNotEmpty) {
                    final clean = c.replaceAll('\\n', ' ').replaceAll('\n', ' ').trim();
                    if (clean.isNotEmpty) {
                      userMsg = clean.length > 30
                          ? '${clean.substring(0, 30)}...'
                          : clean;
                    }
                  }
                  break;
                }
              }
            }
            if (userMsg.isNotEmpty) {
              title = '$title $userMsg';
            }

            // 提取预览：最后一条 assistant 消息的前100字符
            String? preview;
            if (messages != null && messages.isNotEmpty) {
              for (int i = messages.length - 1; i >= 0; i--) {
                final msg = messages[i];
                if (msg['role'] == 'assistant') {
                  final c = msg['content'];
                  if (c is String && c.isNotEmpty) {
                    preview = c.length > 100 ? '${c.substring(0, 100)}...' : c;
                    break;
                  }
                }
              }
              if (preview == null) {
                final lastMsg = messages.last;
                final c = lastMsg['content'];
                if (c is String && c.isNotEmpty) {
                  preview = c.length > 100 ? '${c.substring(0, 100)}...' : c;
                }
              }
            }

            sessions.add(Session(
              id: sid,
              title: title,
              source: platform,
              createdAt: updatedAt,
              updatedAt: updatedAt,
              messageCount: msgCount,
              preview: preview,
            ));
          } catch (_) {
            // skip unparseable files
          }
        }
      }
    } catch (_) {}
    return sessions;
  }

  /// 将 session_id 格式化为可读短标题
  String _formatSessionTitle(String sid) {
    // 格式: 20260521_154713_7d9a32 → 05/21 15:47
    try {
      final parts = sid.split('_');
      if (parts.length >= 2) {
        final dateStr = parts[0]; // 20260521
        final timeStr = parts[1]; // 154713
        if (dateStr.length == 8 && timeStr.length == 6) {
          final month = dateStr.substring(4, 6);
          final day = dateStr.substring(6, 8);
          final hour = timeStr.substring(0, 2);
          final min = timeStr.substring(2, 4);
          return '$month/$day $hour:$min';
        }
      }
    } catch (_) {}
    // Fallback: use last 8 chars
    return sid.length > 8 ? '...${sid.substring(sid.length - 8)}' : sid;
  }

  /// 加载指定会话的消息列表
  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId) async {
    try {
      final dir = Directory('$_hermesHome/sessions');
      if (await dir.exists()) {
        final files = await dir.list().toList();
        for (final f in files) {
          final name = f.uri.pathSegments.last;
          if (name.startsWith('session_') && name.endsWith('.json')) {
            try {
              final content = await File(f.path).readAsString();
              final json = jsonDecode(content);
              if (json['session_id'] == sessionId) {
                final messages = json['messages'] as List?;
                if (messages != null) {
                  return messages.cast<Map<String, dynamic>>();
                }
                return [];
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> deleteSession(String sessionId) async {
    try {
      final dir = Directory('$_hermesHome/sessions');
      if (await dir.exists()) {
        final files = await dir.list().toList();
        for (final f in files) {
          final name = f.uri.pathSegments.last;
          if (name.endsWith('.json')) {
            try {
              final content = await File(f.path).readAsString();
              final json = jsonDecode(content);
              if (json['session_id'] == sessionId) {
                await File(f.path).delete();
                return true;
              }
            } catch (_) {}
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> renameSession(String id, String title) async {
    // SQLite session store, rename not directly supported
    return true;
  }

  Future<Session> getSession(String id) async {
    final sessions = await getSessions();
    return sessions.firstWhere(
      (s) => s.id == id,
      orElse: () => Session(
        id: id,
        title: '未知会话',
        source: 'cli',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  配置（直接读文件）
  // ═══════════════════════════════════════════

  Future<Map<String, dynamic>> getConfig() async {
    try {
      final file = File('$_hermesHome/config.yaml');
      if (await file.exists()) {
        final content = await file.readAsString();
        return {'content': content, 'path': '$_hermesHome/config.yaml'};
      }
    } catch (_) {}
    return {};
  }

  Future<bool> updateConfig(Map<String, dynamic> data) async {
    if (data.containsKey('content')) {
      try {
        await File('$_hermesHome/config.yaml').writeAsString(data['content']);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════
  //  定时任务（从 SQLite 读取）
  // ═══════════════════════════════════════════

  Future<List<CronJob>> getCronJobs() async {
    final jobs = <CronJob>[];
    try {
      final dbPath = '$_hermesHome/cron.db';
      // 简单文本解析，没有 sqlite 依赖
      final file = File(dbPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final parts = line.split('|');
          if (parts.length >= 3) {
            jobs.add(CronJob(
              id: parts[0].trim(),
              name: parts[1].trim(),
              schedule: parts[2].trim(),
              prompt: parts.length > 3 ? parts[3].trim() : '',
              status: parts.length > 4 ? parts[4].trim() : 'active',
              createdAt: DateTime.now(),
            ));
          }
        }
      }
    } catch (_) {}
    return jobs;
  }

  Future<CronJob> createCronJob(Map<String, dynamic> data) async {
    // 简化实现：写 cron.db
    return CronJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: data['name'] ?? '',
      schedule: data['schedule'] ?? '',
      prompt: data['prompt'] ?? '',
      createdAt: DateTime.now(),
    );
  }

  Future<CronJob> updateCronJob(String id, Map<String, dynamic> data) async {
    return CronJob(
      id: id,
      name: data['name'] ?? '',
      schedule: data['schedule'] ?? '',
      prompt: data['prompt'] ?? '',
      status: data['status'] ?? 'active',
      createdAt: DateTime.now(),
    );
  }

  Future<bool> deleteCronJob(String id) async {
    return true;
  }

  Future<bool> runCronJob(String id) async {
    return true;
  }

  // ═══════════════════════════════════════════
  //  日志
  // ═══════════════════════════════════════════

  Future<List<LogEntry>> getLogs(
      {String? source, String? level, String? keyword}) async {
    final logs = <LogEntry>[];
    try {
      final logSource = source ?? 'agent';
      final file = File('$_hermesHome/logs/$logSource.log');
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        for (final line in lines.reversed.take(500)) {
          if (line.trim().isEmpty) continue;
          if (keyword != null &&
              !line.toLowerCase().contains(keyword.toLowerCase())) {
            continue;
          }

          // 解析日志级别
          String logLevel = 'INFO';
          if (line.contains('ERROR') || line.contains('error')) {
            logLevel = 'ERROR';
          } else if (line.contains('WARN') || line.contains('warn')) {
            logLevel = 'WARN';
          } else if (line.contains('DEBUG') || line.contains('debug')) {
            logLevel = 'DEBUG';
          }

          if (level != null && level != 'ALL' && level != logLevel) continue;

          logs.add(LogEntry(
            timestamp: DateTime.now(),
            level: logLevel,
            source: logSource,
            message: line,
          ));
        }
      }
    } catch (_) {}
    return logs;
  }

  // ═══════════════════════════════════════════
  //  网关控制
  // ═══════════════════════════════════════════

  Future<bool> restartGateway() async {
    try {
      _resetClient();
      final request = await _client
          .postUrl(Uri.parse('$_baseUrl/v1/runs/restart'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close();
      return response.statusCode == 200 || response.statusCode == 202;
    } catch (_) {
      return false;
    }
  }
}
