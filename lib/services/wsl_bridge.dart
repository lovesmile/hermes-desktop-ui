import 'dart:convert';
import 'dart:io';

import 'hermes_bridge.dart';
import 'ssh_config.dart';

class WslBridge implements HermesBridge {
  WslBridge({required String distro}) : _distro = distro;

  String _distro;
  bool _connected = false;

  void setDistro(String distro) => _distro = distro;

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
    final result = await Process.run(
      'wsl.exe',
      ['-d', _distro, 'bash', '-c', command],
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    return BridgeExecResult(
      stdout: utf8.decode(result.stdout as List<int>, allowMalformed: true).trim(),
      stderr: utf8.decode(result.stderr as List<int>, allowMalformed: true).trim(),
      exitCode: result.exitCode,
    );
  }
}
