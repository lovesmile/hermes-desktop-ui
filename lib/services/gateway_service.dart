import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import 'config_service.dart';
import 'connection_manager.dart';

/// Hermes Gateway API Server 客户端
class GatewayService {
  static final GatewayService _instance = GatewayService._();
  factory GatewayService() => _instance;
  GatewayService._();

  final _configService = ConfigService();
  String _baseUrl = ConfigService.defaultGatewayUrl;
  /// 当前使用的 Gateway URL
  String get baseUrl => _baseUrl;
  bool _offline = false;
  bool get isOffline => _offline;
  HttpClient _client = HttpClient();

  /// 数据刷新通知器 — 连接切换/服务器变更时触发，各页面监听到后重新加载数据
  final ValueNotifier<int> refreshNotifier = ValueNotifier<int>(0);

  /// 当前连接的服务器标识（"local" 或远程 IP），用于隔离不同服务器的缓存数据
  String _serverId = 'local';
  String get serverId => _serverId;

  /// 设置服务器标识并刷新数据
  void setServerId(String id) {
    _serverId = id;
    // 清除所有缓存
    _apiKey = null;
    _offline = false;
    _lastSessionId = null;
    _client.close(force: true);
    _client = HttpClient();
    _client.connectionTimeout = const Duration(seconds: 5);
    // 通知所有监听页面刷新数据
    refreshNotifier.value++;
  }

  /// 从响应头中读取的最后一个 session ID
  String? _lastSessionId;
  /// 最后创建的会话的 session ID（发第一条消息后设置）
  String? get lastSessionId => _lastSessionId;

  /// 当前正在用的 API Key（从桌面配置读取）
  String? _apiKey;
  Future<String> get apiKey async {
    if (_apiKey != null) return _apiKey!;
    final config = await _configService.readDesktopConfig();
    _apiKey = config['api_key'] as String?;
    return _apiKey ?? '';
  }

  /// 从 ConnectionManager 刷新 Gateway URL
  Future<void> refreshBaseUrl() async {
    _baseUrl = ConnectionManager().gatewayUrl;
  }

  void _resetClient() {
    _client.close(force: true);
    _client = HttpClient();
    _client.connectionTimeout = const Duration(seconds: 5);
  }

  /// 在请求上添加认证头（如果配置了 API Key）
  Future<void> _applyAuth(HttpClientRequest request) async {
    final key = await apiKey;
    if (key != null && key.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $key');
    }
  }

  // ═══════════════════════════════════════════
  //  Gateway 状态 (GET /api/status)
  // ═══════════════════════════════════════════

  Future<Map<String, dynamic>> getStatus() async {
    try {
      _resetClient();
      final request = await _client
          .getUrl(Uri.parse('$_baseUrl/api/status'))
          .timeout(const Duration(seconds: 5));
      await _applyAuth(request);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      _offline = false;
      return json is Map<String, dynamic> ? json : {};
    } catch (_) {
      _offline = true;
      return {};
    }
  }

  // ═══════════════════════════════════════════
  //  流式聊天 (POST /v1/chat/completions, SSE)
  // ═══════════════════════════════════════════

  Stream<String> chatStream(String message,
      {String? sessionId, List<Map<String, String>>? attachments}) {
    final controller = StreamController<String>.broadcast();
    _doChat(message, sessionId, controller, attachments: attachments);
    return controller.stream;
  }

  Future<void> _doChat(String message, String? sessionId,
      StreamController<String> controller,
      {List<Map<String, String>>? attachments}) async {
    try {
      final uri = Uri.parse('$_baseUrl/v1/chat/completions');
      final request = await _client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'text/event-stream');
      await _applyAuth(request);
      if (sessionId != null && sessionId.isNotEmpty) {
        request.headers.set('X-Hermes-Session-Id', sessionId);
      }

      // Build the user message content — text-only or multimodal
      Map<String, dynamic> userMessage;
      if (attachments != null && attachments.isNotEmpty) {
        final contentParts = <Map<String, dynamic>>[
          {'type': 'text', 'text': message},
        ];
        for (final att in attachments) {
          final path = att['path'] ?? '';
          final mime = att['mime'] ?? 'image/png';
          if (path.isNotEmpty) {
            final file = File(path);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              final b64 = base64Encode(bytes);
              contentParts.add({
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mime;base64,$b64',
                },
              });
            }
          }
        }
        userMessage = {'role': 'user', 'content': contentParts};
      } else {
        userMessage = {'role': 'user', 'content': message};
      }

      final body = jsonEncode({
        'model': 'hermes-agent',
        'messages': [userMessage],
        'stream': true,
      });
      request.add(utf8.encode(body));

      final response = await request.close();

      // 读取响应头中的 session ID（无论新会话还是续传都会返回）
      _lastSessionId = response.headers.value('x-hermes-session-id');

      if (response.statusCode != 200) {
        final errBody = await response.transform(utf8.decoder).join();
        controller.addError('HTTP ${response.statusCode}: $errBody');
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
  //  日志
  // ═══════════════════════════════════════════

  Future<List<LogEntry>> getLogs(
      {String? source, String? level, String? keyword}) async {
    final logs = <LogEntry>[];
    try {
      final logSource = source ?? 'agent';
      String? content;

      switch (ConnectionManager().state.mode) {
        case ConnectionMode.embedded:
          try {
            final home = ConfigService.resolveHermesHome();
            final f = File('$home/logs/$logSource.log');
            if (await f.exists()) content = await f.readAsString();
          } catch (_) {}
        case ConnectionMode.local:
        case ConnectionMode.remote:
          final hermesPath = await ConnectionManager().resolveHermesHome();
          final result = await ConnectionManager().runShell(
              'cat "$hermesPath/logs/$logSource.log" 2>/dev/null || true',
              allowFailure: true);
          if (result.stdout.isNotEmpty) content = result.stdout;
      }

      if (content != null && content.isNotEmpty) {
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

  /// 清除指定源的所有日志文件内容
  Future<bool> clearLogs(String source) async {
    try {
      switch (ConnectionManager().state.mode) {
        case ConnectionMode.embedded: {
          final home = ConfigService.resolveHermesHome();
          final logPath = '$home/logs/$source.log';
          final file = File(logPath);
          if (await file.exists()) {
            await file.writeAsString('');
          } else {
            await file.create(recursive: true);
          }
          refreshNotifier.value++;
          return true;
        }
        case ConnectionMode.local:
        case ConnectionMode.remote: {
          final hermesPath = await ConnectionManager().resolveHermesHome();
          final result = await ConnectionManager().runShell(
              ': > "$hermesPath/logs/$source.log" 2>/dev/null',
              allowFailure: true);
          final ok = result.exitCode == 0;
          if (ok) refreshNotifier.value++;
          return ok;
        }
      }
    } catch (_) {
      return false;
    }
  }

  /// 清除缓存的 API Key（当设置页修改后调用）
  void invalidateApiKey() {
    _apiKey = null;
  }

  /// 重启 Gateway 服务
  Future<bool> restartGateway() async {
    try {
      _resetClient();
      final request = await _client
          .postUrl(Uri.parse('$_baseUrl/gateway/restart'))
          .timeout(const Duration(seconds: 5));
      _applyAuth(request);
      final response = await request.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
