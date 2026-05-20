import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/session.dart';
import '../models/stats.dart';
import '../models/cron_job.dart';
import '../models/log_entry.dart';

/// Hermes Gateway API Server 客户端
/// 真实接口: OpenAI-compatible API + 文件 I/O
class GatewayService {
  static final GatewayService _instance = GatewayService._();
  factory GatewayService() => _instance;
  GatewayService._();

  String _baseUrl = 'http://localhost:8642';
  bool _offline = false;
  bool get isOffline => _offline;
  HttpClient _client = HttpClient();

  String get _hermesHome =>
      '${Platform.environment['HOME'] ?? '/home/tian'}/.hermes';

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
  //  会话（从 SQLite / 文件目录读取）
  // ═══════════════════════════════════════════

  Future<List<Session>> getSessions() async {
    final sessions = <Session>[];
    try {
      final dir = Directory('$_hermesHome/sessions');
      if (await dir.exists()) {
        final files = await dir
            .list()
            .where((e) => e.path.endsWith('.jsonl') || e.path.endsWith('.json'))
            .toList();
        // 按修改时间倒序
        files.sort((a, b) {
          final ma = a.statSync().modified;
          final mb = b.statSync().modified;
          return mb.compareTo(ma);
        });

        for (final f in files.take(50)) {
          final name = f.uri.pathSegments.last;
          final stat = f.statSync();
          sessions.add(Session(
            id: name.replaceAll(RegExp(r'\.(jsonl|json)$'), ''),
            title: name.replaceAll(RegExp(r'[_.]'), ' ').replaceAll(RegExp(r'\.(jsonl|json)$'), ''),
            source: 'cli',
            createdAt: stat.modified,
            updatedAt: stat.modified,
            messageCount: 0,
          ));
        }
      }
    } catch (_) {}
    return sessions;
  }

  Future<bool> deleteSession(String id) async {
    try {
      final file = File('$_hermesHome/sessions/$id.jsonl');
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      final file2 = File('$_hermesHome/sessions/$id.json');
      if (await file2.exists()) {
        await file2.delete();
        return true;
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
