import 'ssh_config.dart';

/// SSH 执行器抽象层：屏蔽底层连接差异
abstract class SshExecutor {
  Future<bool> connect(SshConfig config);
  Future<void> disconnect();
  Future<String> exec(String command);
  bool get isConnected;
  SshConfig? get config;
}
