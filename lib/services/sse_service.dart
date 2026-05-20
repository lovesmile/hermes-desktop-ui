import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SseService {
  HttpClient? _client;
  StreamSubscription? _subscription;
  bool _isCancelled = false;

  /// 建立 SSE 连接，返回流式数据
  Stream<String> connect(String url, {Map<String, String>? headers}) {
    _isCancelled = false;
    _client = HttpClient();

    final controller = StreamController<String>.broadcast(
      onCancel: () {
        _isCancelled = true;
        _subscription?.cancel();
        _client?.close(force: true);
      },
    );

    _connect(url, headers, controller);

    return controller.stream;
  }

  Future<void> _connect(
    String url,
    Map<String, String>? headers,
    StreamController<String> controller,
  ) async {
    try {
      final uri = Uri.parse(url);
      final request = await _client!.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');
      headers?.forEach((k, v) => request.headers.set(k, v));

      // Send empty body for chat initiation
      request.write(jsonEncode({'message': ''}));

      final response = await request.close();
      if (response.statusCode != 200) {
        controller.addError('连接失败: HTTP ${response.statusCode}');
        controller.close();
        return;
      }

      await response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (_isCancelled) return;
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') {
              controller.close();
              return;
            }
            controller.add(data);
          }
        },
        onError: (e) {
          if (!_isCancelled) {
            controller.addError(e);
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!_isCancelled) {
        controller.addError('SSE 连接错误: $e');
      }
      if (!controller.isClosed) {
        controller.close();
      }
    }
  }

  void disconnect() {
    _isCancelled = true;
    _subscription?.cancel();
    _client?.close(force: true);
  }
}
