import 'ssh_config.dart';

abstract class HermesBridge {
  Future<void> init();
  Future<bool> connect({SshConfig? config, int? localPort});
  Future<void> disconnect();
  Future<BridgeExecResult> exec(String command);
  /// 杀掉指定 PID 的进程（用于取消长时任务如 git clone）
  Future<bool> killProcess(int pid);
  bool get isConnected;
}

class BridgeExecResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  const BridgeExecResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}
