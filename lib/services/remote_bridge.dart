import 'hermes_bridge.dart';
import 'remote_ssh_executor.dart';
import 'ssh_config.dart';

class RemoteBridge implements HermesBridge {
  RemoteBridge(this._executor);

  final RemoteSshExecutor _executor;

  @override
  bool get isConnected => _executor.isConnected;

  @override
  Future<void> init() async {}

  @override
  Future<bool> connect({SshConfig? config, int? localPort}) async {
    if (config == null) return false;
    if (localPort != null) _executor.setLocalPort(localPort);
    return _executor.connect(config);
  }

  @override
  Future<void> disconnect() => _executor.disconnect();

  @override
  Future<BridgeExecResult> exec(String command) async {
    try {
      final out = await _executor.exec(command);
      return BridgeExecResult(stdout: out, stderr: '', exitCode: 0);
    } catch (e) {
      return BridgeExecResult(stdout: '', stderr: e.toString(), exitCode: 1);
    }
  }

  @override
  Future<bool> killProcess(int pid) async {
    // 远程 SSH 无法直接杀本地进程，通过 pkill 发送信号
    try {
      await _executor.exec('kill -9 $pid 2>/dev/null || true');
      return true;
    } catch (_) {
      return false;
    }
  }
}
