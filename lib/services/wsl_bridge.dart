import 'dart:convert';
import 'dart:io';

import 'hermes_bridge.dart';
import 'ssh_config.dart';

class WslBridge implements HermesBridge {
  WslBridge({required String distro}) : _distro = distro;

  String _distro;
  bool _connected = false;
  int? _lastPid; // 跟踪最近一次启动的进程 PID

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
    final process = await Process.start(
      'wsl.exe',
      ['-d', _distro, 'bash', '-s'],
    );
    _lastPid = process.pid;
    // Pipe command via stdin — bash -c has a WSL+Dart variable assignment bug
    process.stdin.write(command);
    await process.stdin.close();
    final outBytes = <int>[];
    final errBytes = <int>[];
    await Future.wait([
      process.stdout.forEach((chunk) => outBytes.addAll(chunk)),
      process.stderr.forEach((chunk) => errBytes.addAll(chunk)),
    ]);
    final exitCode = await process.exitCode;
    return BridgeExecResult(
      stdout: utf8.decode(outBytes, allowMalformed: true).trim(),
      stderr: utf8.decode(errBytes, allowMalformed: true).trim(),
      exitCode: exitCode,
    );
  }

  @override
  Future<bool> killProcess(int pid) async {
    try {
      // WSL 中用 kill 命令杀进程
      final result = await Process.run('wsl.exe', ['-d', _distro, 'kill', '-9', pid.toString()]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
