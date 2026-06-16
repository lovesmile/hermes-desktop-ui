import 'ssh_config.dart';

abstract class HermesBridge {
  Future<void> init();
  Future<bool> connect({SshConfig? config, int? localPort});
  Future<void> disconnect();
  Future<BridgeExecResult> exec(String command);
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
