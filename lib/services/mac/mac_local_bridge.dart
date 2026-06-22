import 'dart:io';

import '../hermes_bridge.dart';
import '../ssh_config.dart';

class MacLocalBridge implements HermesBridge {
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> init() async {}

  @override
  Future<bool> connect({SshConfig? config, int? localPort}) async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<BridgeExecResult> exec(String command) async {
    final result = await Process.run('/bin/bash', ['-c', command]);
    return BridgeExecResult(
      stdout: result.stdout.toString().trim(),
      stderr: result.stderr.toString().trim(),
      exitCode: result.exitCode,
    );
  }
}
