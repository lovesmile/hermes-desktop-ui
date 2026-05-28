import 'dart:io';
import 'ssh_executor.dart';
import 'ssh_config.dart';

/// 内嵌模式执行器：直接通过本地 Process 执行
class EmbeddedExecutor extends SshExecutor {
  final String bundlePath;
  bool _connected = false;

  EmbeddedExecutor({required this.bundlePath});

  @override
  SshConfig? get config => null;
  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect(SshConfig config) async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<String> exec(String command) async {
    final result = await Process.run('cmd.exe', ['/c', command]);
    return result.stdout.toString().trim();
  }
}
