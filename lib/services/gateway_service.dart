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
    _offline = false;
    _lastSessionId = null;
    _cachedApiKey = null;
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

  /// 从 ConnectionManager 刷新 Gateway URL
  Future<void> refreshBaseUrl() async {
    _baseUrl = ConnectionManager().gatewayUrl;
  }

  void _resetClient() {
    _client.close(force: true);
    _client = HttpClient();
    _client.connectionTimeout = const Duration(seconds: 5);
  }

  /// 从桌面配置读取 API_SERVER_KEY（兼容旧版 gateway）
  String? _cachedApiKey;
  Future<String?> get _apiKey async {
    if (_cachedApiKey != null) return _cachedApiKey;
    final config = await _configService.readDesktopConfig();
    _cachedApiKey = config['api_key'] as String?;
    return _cachedApiKey;
  }

  void invalidateApiKey() => _cachedApiKey = null;

  Future<void> _applyAuth(HttpClientRequest request) async {
    final key = await _apiKey;
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
      {String? sessionId, List<Map<String, String>>? attachments, String? model}) {
    final controller = StreamController<String>.broadcast();
    _doChat(message, sessionId, controller, attachments: attachments, model: model);
    return controller.stream;
  }

  Future<void> _doChat(String message, String? sessionId,
      StreamController<String> controller,
      {List<Map<String, String>>? attachments, String? model}) async {
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
        final contentParts = <Map<String, dynamic>>[];
        if (message.isNotEmpty) {
          contentParts.add({'type': 'text', 'text': message});
        }
        for (final att in attachments) {
          final path = att['path'] ?? '';
          final mime = att['mime'] ?? 'image/png';
          // Gateway API 仅支持图片附件，跳过非图片文件
          if (!mime.startsWith('image/')) {
            debugPrint('[GatewayService] skipping non-image attachment: ${att['name']} ($mime)');
            continue;
          }
          String b64;
          if (path.isNotEmpty) {
            final file = File(path);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              b64 = base64Encode(bytes);
            } else {
              continue; // 文件不存在，跳过
            }
          } else {
            // 无路径（如剪贴板粘贴），从 b64 字段读取
            b64 = att['b64'] ?? '';
            if (b64.isEmpty) continue;
          }
          contentParts.add({
            'type': 'image_url',
            'image_url': {
              'url': 'data:$mime;base64,$b64',
            },
          });
        }
        userMessage = contentParts.isNotEmpty
            ? {'role': 'user', 'content': contentParts}
            : {'role': 'user', 'content': message.isNotEmpty ? message : '(attachment)'};
      } else {
        userMessage = {'role': 'user', 'content': message};
      }

      final body = jsonEncode({
        'model': model ?? 'hermes-agent',
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

  /// 重启 Gateway 服务（统一入口，自动处理三种模式的状态管理）
  Future<bool> restartGateway() async {
    return ConnectionManager().restartGateway();
  }

  // ═══════════════════════════════════════════
  //  模型管理
  // ═══════════════════════════════════════════

  /// 获取当前模型信息（优先从 /api/status，回退到本地配置文件解析）
  Future<Map<String, String>> getCurrentModelInfo() async {
    try {
      final status = await getStatus();
      final model = status['model']?.toString();
      final provider = status['provider']?.toString();
      if (model != null && model.isNotEmpty && model != '-') {
        return {
          'model': model,
          'provider': provider ?? '-',
        };
      }
    } catch (_) {}
    // fallback: 从配置文件解析
    return _configService.readModelConfig();
  }

  /// 切换模型：更新配置文件中的 model.default 并重启 gateway
  Future<bool> setModel(String modelName) async {
    try {
      final configService = _configService;
      final config = await configService.readConfig();

      final lines = config.split('\n');
      bool inModelSection = false;
      bool found = false;

      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed == 'model:') {
          inModelSection = true;
          continue;
        }
        if (inModelSection) {
          // 离开 model 节（遇到新的顶层键）
          if (lines[i].isNotEmpty &&
              trimmed.endsWith(':') &&
              lines[i].length - lines[i].trimLeft().length == 0 &&
              !trimmed.startsWith('-')) {
            break;
          }
          if (trimmed.startsWith('default:')) {
            lines[i] = '  default: $modelName';
            found = true;
            break;
          }
        }
      }

      final newConfig = found
          ? lines.join('\n')
          : '${config.trimRight()}\n\nmodel:\n  default: $modelName\n';

      final ok = await configService.writeConfig(newConfig);
      if (!ok) return false;

      await restartGateway();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hermes Agent 支持的 provider → 默认 Base URL
  static const Map<String, String> providerBaseUrls = {
    'deepseek': 'https://api.deepseek.com/v1',
    'openrouter': 'https://openrouter.ai/api/v1',
    'anthropic': 'https://api.anthropic.com/v1',
    'openai': 'https://api.openai.com/v1',
    'gemini': 'https://generativelanguage.googleapis.com/v1beta/openai',
    'kimi': 'https://api.moonshot.cn/v1',
    'ollama': 'http://localhost:11434/v1',
    'glm': 'https://api.z.ai/api/paas/v4',
    'minimax': 'https://api.minimax.io/v1',
    'arcee': 'https://api.arcee.ai/v1',
    'opencode-zen': 'https://opencode.ai/zen/v1',
    'opencode-go': 'https://opencode.ai/zen/go/v1',
    'huggingface': 'https://api-inference.huggingface.co/v1',
    'qwen': 'https://portal.qwen.ai/v1',
    'xiaomi': 'https://api.xiaomimimo.com/v1',
  };

  static const List<String> allProviders = [
    'deepseek', 'openrouter', 'anthropic', 'openai', 'gemini', 'kimi',
    'ollama', 'glm', 'minimax', 'arcee',
    'opencode-zen', 'opencode-go', 'huggingface', 'qwen', 'xiaomi',
  ];
  static const Map<String, List<String>> providerModels = {
    'deepseek': [
      'deepseek-v4-flash', 'deepseek-v3', 'deepseek-r1',
      'deepseek-r1-distill-qwen-32b',
    ],
    'openrouter': [
      'anthropic/claude-sonnet-4', 'anthropic/claude-opus-4', 'anthropic/claude-haiku-4',
      'openai/gpt-4o', 'openai/gpt-4o-mini', 'openai/gpt-4.1', 'openai/o3', 'openai/o4-mini',
      'google/gemini-2.5-pro', 'google/gemini-2.5-flash',
      'deepseek/deepseek-v4-flash', 'deepseek/deepseek-v3', 'deepseek/deepseek-r1',
      'meta-llama/llama-4', 'meta-llama/llama-3.3-70b',
      'cohere/command-r7', 'cohere/command-r-plus',
      'mistralai/mistral-large', 'mistralai/mistral-saba',
      'qwen/qwen-max', 'qwen/qwen-plus',
    ],
    'anthropic': [
      'claude-sonnet-4', 'claude-opus-4', 'claude-haiku-4',
      'claude-sonnet-4-20250514', 'claude-opus-4-20250514',
    ],
    'openai': [
      'gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'gpt-4.1-nano',
      'o3', 'o3-mini', 'o4-mini',
      'gpt-4.1-2025-04-14', 'gpt-4o-2024-08-06',
    ],
    'gemini': [
      'gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.5-flash-lite',
      'gemini-2.0-flash', 'gemini-1.5-pro', 'gemini-1.5-flash',
    ],
    'kimi': [
      'kimi-k2.5', 'kimi-k2', 'kimi-v1.5',
    ],
    'ollama': [
      'llama-3.3-70b', 'llama-3.1-8b', 'qwen-2.5-72b', 'qwen-2.5-32b',
      'mistral-large', 'mixtral-8x22b', 'deepseek-r1-70b',
      'gemma-3-27b', 'phi-4', 'nomic-embed-text',
    ],
    'glm': [
      'glm-4-plus', 'glm-4-air', 'glm-4-long', 'glm-4-flash',
      'glm-5', 'glm-5-flash',
    ],
    'minimax': [
      'minimax-m2.5', 'minimax-m1', 'minimax-text-01',
    ],
    'arcee': [
      'trinity-mini', 'trinity-large', 'trinity-medium',
      'arcee-neo', 'arcee-7b',
    ],
    'opencode-zen': [
      'gpt-4o', 'claude-sonnet-4', 'gemini-2.5-pro',
      'deepseek-v4-flash', 'qwen-max',
    ],
    'opencode-go': [
      'glm-5', 'kimi-k2.5', 'minimax-m2.5',
      'qwen-plus', 'deepseek-v3',
    ],
    'huggingface': [
      'meta-llama/Llama-4', 'meta-llama/Llama-3.3-70B-Instruct',
      'mistralai/Mistral-Large', 'mistralai/Mistral-Saba',
      'Qwen/Qwen2.5-72B-Instruct', 'deepseek-ai/DeepSeek-R1',
      'google/gemma-3-27b-it',
    ],
    'qwen': [
      'qwen-max', 'qwen-plus', 'qwen-turbo', 'qwen-long',
      'qwen-max-2026-01-25',
    ],
    'xiaomi': [
      'mimo-v2-pro', 'mimo-v2-flash', 'mimo-v2-omni',
      'mimo-v2-vision',
    ],
    'custom': [''],
  };

  /// 将 providerModels 摊平为列表（供 UI 下拉逐项渲染）
  static List<Map<String, String>> get knownModels {
    final list = <Map<String, String>>[];
    for (final entry in providerModels.entries) {
      for (final model in entry.value) {
        list.add({'provider': entry.key, 'model': model});
      }
    }
    return list;
  }
}
