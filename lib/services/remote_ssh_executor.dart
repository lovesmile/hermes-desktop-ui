import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'connection_manager.dart';
import 'ssh_executor.dart';

class RemoteSshExecutor extends SshExecutor {
  Process? _sshProcess;
  SshConfig? _currentConfig;
  int _tunnelPort = 0;   // 本地 SSH 隧道监听端口
  int _remotePort = 8642; // 远程 gateway 实际端口
  String? _lastError;
  bool _tunnelEstablished = false;

  @override
  SshConfig? get config => _currentConfig;
  @override
  bool get isConnected => _sshProcess != null;
  String? get lastError => _lastError;
  bool get tunnelEstablished => _tunnelEstablished;

  /// 设置 SSH 隧道本地监听端口和远程目标端口
  void setTunnelPorts({int? tunnel, int? remote}) {
    if (tunnel != null) _tunnelPort = tunnel;
    if (remote != null) _remotePort = remote;
  }

  /// 兼容旧接口
  void setLocalPort(int port) => _tunnelPort = port;

  @override
  Future<bool> connect(SshConfig config) async {
    await disconnect();
    _currentConfig = config;
    _lastError = null;
    _tunnelEstablished = false;

    try {
      final tunnelArgs = <String>[
        '-L', '$_tunnelPort:localhost:$_remotePort',
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ServerAliveInterval=30',
        '-N',
      ];

      if (config.password != null && config.password!.isNotEmpty &&
          (config.keyPath == null || config.keyPath!.isEmpty)) {
        // 密码认证：通过 WSL sshpass
        // 密码中可能包含 $ ` \ 等 shell 特殊字符，需要用单引号包裹防止 bash 展开
        final distro = ConnectionManager().wslDistro;
        final sshArgs = _buildSshArgs(config);
        final escapedPw = _shEscape(config.password!);
        final allArgs = ['-p', escapedPw, 'ssh', ...tunnelArgs, ...sshArgs];
        _sshProcess = await Process.start('wsl.exe', ['-d', distro, 'sshpass', ...allArgs]);
      } else {
        // 密钥或无密码：Windows 原生 ssh
        final allArgs = [
          ...tunnelArgs,
          ..._buildSshArgs(config),
        ];
        _sshProcess = await Process.start('ssh', allArgs);
      }

      // 收集 stderr（sshpass/ssh 错误信息会输出到这里）
      final stderrBuf = StringBuffer();
      _sshProcess!.stderr.transform(utf8.decoder).listen(stderrBuf.write);

      // 等待 4 秒：隧道建立成功则进程保持运行，失败则提前退出
      final exitCode = await Future.any([
        _sshProcess!.exitCode.then<int?>((code) => code),
        Future.delayed(const Duration(seconds: 4), () => null),
      ]);

      if (exitCode != null) {
        // 进程提前退出 = 连接失败
        final errMsg = stderrBuf.toString().trim();
        _lastError = errMsg.isNotEmpty ? errMsg : 'SSH 进程异常退出 (code: $exitCode)';
        await disconnect();
        return false;
      }

      // 隧道已建立
      _tunnelEstablished = true;

      // 进程仍在运行，检查 gateway 是否可访问
      final gatewayOk = await _checkGateway();
      if (!gatewayOk) {
        _lastError = 'SSH 隧道已建立但 Gateway 无响应';
      }
      return gatewayOk;
    } catch (e) {
      _lastError = '连接异常: $e';
      await disconnect();
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _sshProcess?.kill();
    _sshProcess = null;
    _currentConfig = null;
    _tunnelEstablished = false;
  }

  @override
  Future<String> exec(String command) async {
    if (_currentConfig == null) throw StateError('Not connected');
    final config = _currentConfig!;

    if (config.password != null && config.password!.isNotEmpty) {
      final distro = ConnectionManager().wslDistro;
      // Use separate argument arrays (same pattern as connect()), avoid bash -c escaping issues
      final sshArgs = _buildSshArgs(config);
      final escapedPw = _shEscape(config.password!);
      // wsl.exe joins args and passes to `bash -c`, which expands $ variables.
      // Escape $ → \$ to prevent WSL bash from expanding them — the remote
      // shell should do the expansion instead.
      final escapedCmd = command.replaceAll('\$', '\\\$');
      final result = await Process.run('wsl.exe', [
        '-d', distro,
        'sshpass', '-p', escapedPw, 'ssh',
        ...sshArgs, escapedCmd,
      ], stdoutEncoding: null, stderrEncoding: null)
          .timeout(const Duration(seconds: 30));
      if (result.exitCode != 0) {
        throw Exception('SSH failed: ${utf8.decode(result.stderr as List<int>, allowMalformed: true)}');
      }
      return utf8.decode(result.stdout as List<int>, allowMalformed: true).trim();
    }

    // 密钥认证 — stdoutEncoding:null 避免 Windows 系统代码页（如 CP936）截断 UTF-8
    final args = [
      ..._buildSshArgs(config),
      'LC_ALL=C.UTF-8 $command',
    ];
    final result = await Process.run('ssh', args,
        stdoutEncoding: null, stderrEncoding: null)
        .timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      final err = utf8.decode(result.stderr as List<int>, allowMalformed: true).trim();
      throw Exception(err.isNotEmpty ? err : 'SSH failed (exit ${result.exitCode})');
    }
    return utf8.decode(result.stdout as List<int>, allowMalformed: true).trim();
  }

  List<String> _buildSshArgs(SshConfig config) {
    final args = <String>[
      '-o', 'StrictHostKeyChecking=accept-new',
      '-o', 'ServerAliveInterval=30',
      '-o', 'BatchMode=yes',
      '-o', 'ConnectTimeout=10',
    ];
    if (config.keyPath != null && config.keyPath!.isNotEmpty) {
      args.addAll(['-o', 'IdentitiesOnly=yes', '-i', config.keyPath!]);
    }
    if (config.port != 22) args.addAll(['-p', config.port.toString()]);
    args.add('${config.user}@${config.host}');
    return args;
  }

  /// Escape string for use in bash (wsl.exe joins args and passes to `bash -c`).
  /// Single quotes prevent $ ` \ " and other special chars from being expanded.
  static String _shEscape(String s) {
    return "'" + s.replaceAll("'", "'\\''") + "'";
  }

  Future<bool> _checkGateway() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(Uri.parse('http://localhost:$_tunnelPort/health'));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) { return false; }
  }
}
