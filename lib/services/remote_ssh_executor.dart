import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'connection_manager.dart';
import 'ssh_executor.dart';

class RemoteSshExecutor extends SshExecutor {
  Process? _sshProcess;
  SshConfig? _currentConfig;
  int _localPort = 8642;

  @override
  SshConfig? get config => _currentConfig;
  @override
  bool get isConnected => _sshProcess != null;

  void setLocalPort(int port) => _localPort = port;

  @override
  Future<bool> connect(SshConfig config) async {
    await disconnect();
    _currentConfig = config;

    try {
      final tunnelArgs = <String>[
        '-L', '$_localPort:localhost:8642',
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ServerAliveInterval=30',
        '-N',
      ];

      if (config.password != null && config.password!.isNotEmpty &&
          (config.keyPath == null || config.keyPath!.isEmpty)) {
        // 密码认证：尝试通过本地系统的 sshpass (通常在 WSL 中可用)
        final distro = ConnectionManager().wslDistro;
        final sshArgs = _buildSshArgs(config);
        final allArgs = ['-p', config.password!, 'ssh', ...tunnelArgs, ...sshArgs];
        _sshProcess = await Process.start('wsl.exe', ['-d', distro, 'sshpass', ...allArgs]);
      } else {
        // 密钥或无密码：Windows 原生 ssh
        final allArgs = [...tunnelArgs, ..._buildSshArgs(config)];
        _sshProcess = await Process.start('ssh', allArgs);
      }

      await Future.delayed(const Duration(seconds: 4));
      return await _checkGateway();
    } catch (e) {
      await disconnect();
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _sshProcess?.kill();
    _sshProcess = null;
    _currentConfig = null;
  }

  @override
  Future<String> exec(String command) async {
    if (_currentConfig == null) throw StateError('Not connected');
    final config = _currentConfig!;

    if (config.password != null && config.password!.isNotEmpty) {
      const q = "'";
      final escapedPw = config.password!.replaceAll(q, "'\\''");
      final escapedCmd = command.replaceAll(q, "'\\''");
      final buf = StringBuffer("sshpass -p $q$escapedPw$q ssh");
      buf.write(' -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30');
      if (config.port != 22) buf.write(' -p ${config.port}');
      buf.write(' ${config.user}@${config.host} $q$escapedCmd$q');

      final distro = ConnectionManager().wslDistro;
      final result = await Process.run('wsl.exe', ['-d', distro, 'bash', '-c', buf.toString()], stdoutEncoding: null, stderrEncoding: null);
      if (result.exitCode != 0) throw Exception('SSH failed: ${utf8.decode(result.stderr as List<int>, allowMalformed: true)}');
      return utf8.decode(result.stdout as List<int>, allowMalformed: true).trim();
    }

    final args = _buildSshArgs(config);
    args.add("'$command'");
    final result = await Process.run('ssh', args);
    return (result.stdout as String).trim();
  }

  List<String> _buildSshArgs(SshConfig config) {
    final args = <String>['-o', 'StrictHostKeyChecking=accept-new', '-o', 'ServerAliveInterval=30'];
    if (config.keyPath != null && config.keyPath!.isNotEmpty) args.addAll(['-i', config.keyPath!]);
    if (config.port != 22) args.addAll(['-p', config.port.toString()]);
    args.add('${config.user}@${config.host}');
    return args;
  }

  Future<bool> _checkGateway() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(Uri.parse('http://localhost:$_localPort/health'));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) { return false; }
  }
}
