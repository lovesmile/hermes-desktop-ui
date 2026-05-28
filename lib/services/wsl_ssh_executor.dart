import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'ssh_executor.dart';
import 'ssh_config.dart';

/// WSL 专用执行器
class WslSshExecutor extends SshExecutor {
  String _distro = 'Ubuntu';
  SshConfig? _config;
  bool _connected = false;

  void setDistro(String d) => _distro = d;

  @override
  SshConfig? get config => _config;
  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect(SshConfig config) async {
    _config = config;
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _config = null;
  }

  @override
  Future<String> exec(String command) async {
    final result = await Process.run('wsl.exe', ['-d', _distro, 'bash', '-c', command], stdoutEncoding: null, stderrEncoding: null);
    return utf8.decode(result.stdout as List<int>, allowMalformed: true).trim();
  }
}
