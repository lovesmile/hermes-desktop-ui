import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'config_service.dart';
import 'local_db.dart';
/// 连接模式
enum ConnectionMode {
  local,
  remote,
}

String connectionModeToDbSuffix(String mode) {
  if (mode == 'local') return '';
  // IP 作为 namespace
  final safe = mode.replaceAll('.', '_').replaceAll(':', '_');
  return '_$safe';
}

enum ConnStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Setup state for the first-run Hermes bundle installation wizard.
enum SetupState {
  none,
  waitingForHermes,
  downloading,
  installing,
  ready,
  failed,
}

class ConnectionInfo {
  final ConnStatus status;
  final ConnectionMode mode;
  final String message;
  final int port;

  const ConnectionInfo({
    this.status = ConnStatus.disconnected,
    this.mode = ConnectionMode.local,
    this.message = '',
    this.port = 8642,
  });

  ConnectionInfo copyWith({
    ConnStatus? status,
    ConnectionMode? mode,
    String? message,
    int? port,
  }) {
    return ConnectionInfo(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      message: message ?? this.message,
      port: port ?? this.port,
    );
  }
}

/// SSH 连接配置
class SshConfig {
  final String host;
  final int port;
  final String user;
  final String? keyPath;
  final String? password;

  const SshConfig({
    this.host = '',
    this.port = 22,
    this.user = '',
    this.keyPath,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'user': user,
        'keyPath': keyPath ?? '',
        'password': password ?? '',
      };

  factory SshConfig.fromJson(Map<String, dynamic> json) => SshConfig(
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 22,
        user: json['user'] as String? ?? '',
        keyPath: json['keyPath'] as String?,
        password: json['password'] as String?,
      );

  bool get isValid => host.isNotEmpty && user.isNotEmpty;
}

/// 连接管理器
/// 保证 localhost:<port> 有东西在响应
/// 本地模式：管理 Hermes 进程生命周期
/// 远程模式：SSH 隧道 (ssh -L)
class ConnectionManager {
  ConnectionManager._();
  static final ConnectionManager _instance = ConnectionManager._();
  factory ConnectionManager() => _instance;

  final _configService = ConfigService();

  // 可观察状态
  final ValueNotifier<ConnectionInfo> stateNotifier =
      ValueNotifier(const ConnectionInfo());
  ConnectionInfo get state => stateNotifier.value;

  // SSH 子进程
  Process? _sshProcess;

  // Hermes Gateway 本地进程
  Process? _hermesProcess;

  // 当前 SSH 配置（用于 execRemote）
  SshConfig? _currentSshConfig;

  // 定时健康检查
  Timer? _healthTimer;

  /// Default URL for downloading the Hermes bundle.
  /// Override by passing a custom URL to [downloadHermesBundle].
  static const String defaultHermesDownloadUrl =
      'https://github.com/lovesmile/hermes-desktop-ui/releases/latest/download/hermes-bundle-windows.zip';

  /// Notifier for the first-run Hermes bundle setup wizard.
  final ValueNotifier<SetupState> setupNotifier =
      ValueNotifier(SetupState.none);

  /// Path where the Hermes bundle is (or will be) installed.
  String get hermesBundlePath {
    final dir = _appDataDir();
    return '${dir.path}/hermes';
  }

  /// 从配置初始化
  Future<void> init() async {
    final config = await _configService.readDesktopConfig();
    final modeStr = config['connection_mode'] as String? ?? 'local';
    final mode = modeStr == 'local' ? ConnectionMode.local : ConnectionMode.remote;
    final port = config['local_port'] as int? ?? 8642;

    SshConfig sshConfig;
    if (config.containsKey('ssh_config')) {
      sshConfig = SshConfig.fromJson(
          config['ssh_config'] as Map<String, dynamic>? ?? {});
    } else {
      sshConfig = const SshConfig();
    }

    stateNotifier.value = ConnectionInfo(
      status: ConnStatus.disconnected,
      mode: mode,
      port: port,
    );

    // 启动健康检查
    _startHealthCheck();

    // 如果已配置远程，自动连
    if (mode == ConnectionMode.remote && sshConfig.isValid) {
      await connectRemote(sshConfig);
    } else {
      final ok = await checkLocal();
      if (!ok) {
        await checkAndSetup();
      }
    }
  }

  /// 检查本地 Gateway
  Future<bool> checkLocal() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final request = await client
          .getUrl(Uri.parse('http://localhost:${state.port}/health'));
      final response = await request.close();
      client.close();
      if (response.statusCode == 200) {
        stateNotifier.value = state.copyWith(
          status: ConnStatus.connected,
          message: '本地 Gateway 运行中',
        );
        return true;
      }
    } catch (_) {}
    stateNotifier.value = state.copyWith(
      status: ConnStatus.disconnected,
      message: '本地 Gateway 未响应',
    );
    return false;
  }

  /// 构建 SSH 命令参数列表（不含认证方式）
  List<String> _buildSshArgs(SshConfig config, String command) {
    final args = <String>[
      '-o', 'StrictHostKeyChecking=accept-new',
      '-o', 'ServerAliveInterval=30',
    ];
    if (config.keyPath != null && config.keyPath!.isNotEmpty) {
      args.addAll(['-i', config.keyPath!]);
    }
    if (config.port != 22) {
      args.addAll(['-p', config.port.toString()]);
    }
    args.add('${config.user}@${config.host}');
    if (command.isNotEmpty) {
      args.add(command);
    }
    return args;
  }

  /// 连接远程服务器（SSH 隧道）
  /// 密码认证走 WSL + sshpass，密钥认证直走 Windows ssh
  Future<bool> connectRemote(SshConfig config) async {
    // 先断开已有隧道
    await disconnect();

    stateNotifier.value = state.copyWith(
      status: ConnStatus.connecting,
      mode: ConnectionMode.remote,
      message: '正在建立 SSH 隧道...',
    );

    try {
      final tunnelArgs = <String>[
        '-L', '${state.port}:localhost:8642',
        '-o', 'ExitOnForwardFailure=yes',
        '-N',
      ];

      if (config.password != null && config.password!.isNotEmpty &&
          (config.keyPath == null || config.keyPath!.isEmpty)) {
        // ── 密码认证：通过 WSL + sshpass ──
        final sshArgs = _buildSshArgs(config, '');
        // 隧道参数插在 ssh 和 user@host 之间
        // sshpass -p 'pw' ssh -L ... -N -o ... user@host -p 22
        final allArgs = [
          '-p', config.password!,
          'ssh',
          ...tunnelArgs,
          ...sshArgs,
        ];
        _sshProcess = await Process.start('wsl.exe', ['-d', 'Ubuntu', 'sshpass', ...allArgs]);
      } else {
        // ── 密钥认证或无密码：Windows 原生 ssh ──
        final allArgs = [
          ...tunnelArgs,
          ..._buildSshArgs(config, ''),
        ];
        _sshProcess = await Process.start('ssh', allArgs);
      }

      // 保存配置
      await _saveConfig(ConnectionMode.remote, config);

      // 等待隧道建立
      await Future.delayed(const Duration(seconds: 3));

      // 验证连接
      final ok = await checkLocal();
      if (ok) {
        _currentSshConfig = config;
        await LocalDatabase().setMode(config.host);
        ConfigService().setMode(config.host);
        stateNotifier.value = state.copyWith(
          status: ConnStatus.connected,
          message: '已连接 ${config.user}@${config.host}',
        );
      } else {
        stateNotifier.value = state.copyWith(
          status: ConnStatus.error,
          message: '隧道已建立但 Gateway 无响应',
        );
      }
      return ok;
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: ConnStatus.error,
        message: 'SSH 连接失败: $e',
      );
      return false;
    }
  }

  /// 断开当前连接
  Future<void> disconnect() async {
    _sshProcess?.kill();
    _sshProcess = null;
    _currentSshConfig = null;
    stateNotifier.value = state.copyWith(
      status: ConnStatus.disconnected,
      message: '已断开',
    );
  }

  /// 切换到本地模式
  Future<void> switchToLocal() async {
    await disconnect();
    stateNotifier.value = state.copyWith(
      mode: ConnectionMode.local,
      status: ConnStatus.disconnected,
      message: '切换到本地模式',
    );
    await _saveConfig(ConnectionMode.local);
    await LocalDatabase().setMode('local');
    ConfigService().setMode('local');
    await checkLocal();
  }

  /// 切换到远程模式
  Future<void> switchToRemote(SshConfig config) async {
    await connectRemote(config);
  }

  /// 保存连接配置
  Future<void> _saveConfig(ConnectionMode mode, [SshConfig? ssh]) async {
    final config = await _configService.readDesktopConfig();
    if (mode == ConnectionMode.local) {
      config['connection_mode'] = 'local';
    } else if (ssh != null) {
      config['connection_mode'] = ssh.host;
      config['ssh_config'] = ssh.toJson();
    }
    config['local_port'] = state.port;
    if (ssh != null) {
      config['ssh_config'] = ssh.toJson();
    }
    await _configService.writeDesktopConfig(config);
  }

  /// 启动定时健康检查（每10秒）
  void _startHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (state.status == ConnStatus.connected ||
          state.status == ConnStatus.error) {
        checkLocal().then((ok) {
          if (!ok && state.mode == ConnectionMode.remote) {
            // 远程隧道断了，尝试重连 TODO
          }
        });
      }
    });
  }

  /// 释放资源
  void dispose() {
    _healthTimer?.cancel();
    disconnect();
  }

  /// 获取当前 Gateway URL
  String get gatewayUrl => 'http://localhost:${state.port}';

  /// 获取输出目录路径
  String get outputsDir => '${ConfigService.resolveHermesHome()}/outputs';

  /// 在远程服务器上执行命令（SSH）
  /// 支持密钥认证 (-i keyPath) 和密码认证 (sshpass)
  Future<String> execRemote(String command) async {
    if (_currentSshConfig == null || !_currentSshConfig!.isValid) {
      throw StateError('No remote connection configured');
    }
    final config = _currentSshConfig!;

    final args = <String>[];

    // 密钥认证
    if (config.keyPath != null && config.keyPath!.isNotEmpty) {
      args.add('-i');
      args.add(config.keyPath!);
    }

    args.add('-o');
    args.add('StrictHostKeyChecking=accept-new');
    args.add('-o');
    args.add('ServerAliveInterval=30');
    args.add('-o');
    args.add('BatchMode=yes');

    // 非默认端口
    if (config.port != 22) {
      args.add('-p');
      args.add(config.port.toString());
    }

    final target = '${config.user}@${config.host}';

    // 密码认证（无密钥时通过 WSL + sshpass）
    if (config.password != null &&
        config.password!.isNotEmpty &&
        (config.keyPath == null || config.keyPath!.isEmpty)) {
      // sshpass -p 'pw' ssh -o ... user@host -p 22 command
      const quote = "'";
      final escapedPw = config.password!.replaceAll(quote, "'\\''");
      final buf = StringBuffer("sshpass -p $quote${escapedPw}$quote ssh");
      buf.write(' -o StrictHostKeyChecking=accept-new');
      buf.write(' -o ServerAliveInterval=30');
      if (config.port != 22) {
        buf.write(' -p ${config.port}');
      }
      buf.write(' ${config.user}@${config.host}');
      // 将 command 用单引号包裹（避免 shell 展开）
      final escapedCmd = command.replaceAll(quote, "'\\''");
      buf.write(' $quote${escapedCmd}$quote');

      final result = await Process.run('wsl.exe', ['-d', 'Ubuntu', 'bash', '-c', buf.toString()],
          stdoutEncoding: null, stderrEncoding: null);
      final outStr = utf8.decode(result.stdout as List<int>, allowMalformed: true);
      final errStr = utf8.decode(result.stderr as List<int>, allowMalformed: true);
      if (result.exitCode != 0) {
        throw Exception('SSH exec via sshpass failed (exit ${result.exitCode}): $errStr');
      }
      return outStr.trim();
    } else {
      // 密钥认证或无需密码
      args.add(target);
      args.add(command);

      final result = await Process.run('ssh', args);
      if (result.exitCode != 0) {
        throw Exception(
            'SSH exec failed (exit ${result.exitCode}): ${result.stderr}');
      }
      return (result.stdout as String).trim();
    }
  }

  /// Whether this process is running on Windows
  bool get _isWindows => Platform.isWindows;

  /// 运行 bash 命令，自动处理 WSL 前缀垃圾输出
  Future<ProcessResult> _runBash(String command) async {
    if (_isWindows) {
      final r = await Process.run('wsl.exe', ['-d', 'Ubuntu', 'bash', '-c', command],
          stdoutEncoding: null, stderrEncoding: null);
      final outStr = _decodeWslOutput(r.stdout as List<int>);
      final errStr = _decodeWslOutput(r.stderr as List<int>);
      return ProcessResult(r.pid, r.exitCode, outStr, errStr);
    } else {
      return Process.run('bash', ['-c', command]);
    }
  }

  /// Execute a bash command via Process.run (public version of _runBash).
  /// On Windows, uses wsl.exe -d Ubuntu. Multi-line output preserved.
  Future<ProcessResult> execBash(String command) async {
    if (Platform.isWindows) {
      final r = await Process.run('wsl.exe', ['-d', 'Ubuntu', 'bash', '-c', command],
          stdoutEncoding: null, stderrEncoding: null);
      final outStr = _decodeWslOutput(r.stdout as List<int>);
      final errStr = _decodeWslOutput(r.stderr as List<int>);
      return ProcessResult(r.pid, r.exitCode, outStr, errStr);
    } else {
      final r = await Process.run('bash', ['-c', command],
          stdoutEncoding: null, stderrEncoding: null);
      return ProcessResult(r.pid, r.exitCode,
          utf8.decode(r.stdout as List<int>, allowMalformed: true),
          utf8.decode(r.stderr as List<int>, allowMalformed: true));
    }
  }

  /// Decode WSL output: skip leading garbage bytes, then decode the rest as UTF-8.
  String _decodeWslOutput(List<int> raw) {
    // Find where valid UTF-8 starts (skip WSL notification garbage)
    int start = 0;
    while (start < raw.length) {
      final b = raw[start];
      // Skip non-printable control chars and null bytes in the preamble
      if (b == 0 || (b < 32 && b != 10 && b != 13)) {
        start++;
      } else {
        break;
      }
    }
    // Also find the newline after the garbage (typically the first \n)
    final sub = raw.sublist(start);
    final decoded = utf8.decode(sub, allowMalformed: true);
    return _cleanWslOutput(decoded);
  }

  /// Unified shell execution: local mode → execBash (WSL), remote mode → execRemote (SSH).
  /// Returns (stdout, exitCode). Throws on non-zero exit unless [allowFailure] is true.
  Future<({String stdout, int exitCode})> runShell(String command, {bool allowFailure = false}) async {
    if (state.mode == ConnectionMode.remote && _currentSshConfig != null) {
      try {
        final out = await execRemote(command);
        return (stdout: out, exitCode: 0);
      } catch (e) {
        if (allowFailure) return (stdout: e.toString(), exitCode: 1);
        rethrow;
      }
    }
    final result = await execBash(command);
    final out = (result.stdout as String).trim();
    if (!allowFailure && result.exitCode != 0) {
      throw Exception(out.isNotEmpty ? out : 'runShell failed (exit ${result.exitCode})');
    }
    return (stdout: out, exitCode: result.exitCode);
  }

  /// 从 WSL stdout 中去掉 UTF-16 垃圾，保留有效内容
  String _cleanWslOutput(String raw) {
    final lines = raw.split('\n')
        .map((l) => l.trim())
        .where((l) {
          if (l.isEmpty) return false;
          // 跳过含 null byte 的行（WSL 连接通知 w\u0000s\u0000l\u0000:\u0000）
          if (l.codeUnits.any((c) => c == 0)) return false;
          // 跳过已知 WSL 通知行
          if (l.startsWith('wsl:') || l.contains('Failed')) return false;
          // 第一个字符为控制字符则跳过（UTF-16 BOM 等）
          if (l.codeUnitAt(0) < 32) return false;
          return true;
        })
        .toList();
    return lines.isNotEmpty ? lines.join('\n') : '';
  }
  /// 获取机器状态（CPU、内存、磁盘、运行时间）
  /// 本地模式通过 Process.run 执行系统命令
  /// 远程模式通过 SSH execRemote 执行
  Future<Map<String, dynamic>> getMachineStatus() async {
    try {
      if (state.mode == ConnectionMode.local) {
        // CPU: top -bn1 取样一次，提取 %Cpu(s) 第2列 (us)
        final cpuResult = await _runBash(
          r"""top -bn1 | grep '%Cpu' | awk '{print $2}'""",
        );
        debugPrint('CPU raw output: ${cpuResult.stdout}');
        final cpuRaw = (cpuResult.stdout as String).trim();
        final cpu = cpuRaw.isNotEmpty ? (double.tryParse(cpuRaw) ?? 0.0) : 0.0;

        // 内存: free -m, 格式 "used|total"
        final memResult = await _runBash(
          r"""free -m | grep Mem | awk '{printf "%d|%d", $3, $2}'""",
        );
        debugPrint('MEM raw output: ${memResult.stdout}');
        final memParts =
            (memResult.stdout as String).trim().split('|');
        final memUsed = int.tryParse(memParts.isNotEmpty ? memParts[0] : '0') ?? 0;
        final memTotal =
            int.tryParse(memParts.length > 1 ? memParts[1] : '0') ?? 0;

        // 磁盘: df -h /, 格式 "used|total"
        final diskResult = await _runBash(
          r"""df -h / | tail -1 | awk '{printf "%s|%s", $3, $2}'""",
        );
        debugPrint('DISK raw output: ${diskResult.stdout}');
        final diskParts =
            (diskResult.stdout as String).trim().split('|');
        final diskUsed = diskParts.isNotEmpty ? diskParts[0] : '0';
        final diskTotal = diskParts.length > 1 ? diskParts[1] : '0';

        // 运行时间
        final uptimeResult = await _runBash('uptime -p');
        debugPrint('UPTIME raw output: ${uptimeResult.stdout}');
        final uptime = (uptimeResult.stdout as String).trim();

        return {
          'cpu': cpu,
          'memory': {'used': memUsed, 'total': memTotal},
          'disk': {'used': diskUsed, 'total': diskTotal},
          'uptime': uptime,
        };
      } else {
        // 远程模式: 通过 SSH 执行相同的命令
        final cpuStr =
            await execRemote(r"""top -bn1 | grep '%Cpu' | awk '{print $2}'""");
        debugPrint('CPU (remote) raw output: $cpuStr');
        final cpu = double.tryParse(cpuStr.trim()) ?? 0.0;

        final memStr = await execRemote(
            r"""free -m | grep Mem | awk '{printf "%d|%d", $3, $2}'""");
        debugPrint('MEM (remote) raw output: $memStr');
        final memParts = memStr.trim().split('|');
        final memUsed = int.tryParse(memParts.isNotEmpty ? memParts[0] : '0') ?? 0;
        final memTotal =
            int.tryParse(memParts.length > 1 ? memParts[1] : '0') ?? 0;

        final diskStr = await execRemote(
            r"""df -h / | tail -1 | awk '{printf "%s|%s", $3, $2}'""");
        debugPrint('DISK (remote) raw output: $diskStr');
        final diskParts = diskStr.trim().split('|');
        final diskUsed = diskParts.isNotEmpty ? diskParts[0] : '0';
        final diskTotal = diskParts.length > 1 ? diskParts[1] : '0';

        final uptimeStr = await execRemote('uptime -p');
        debugPrint('UPTIME (remote) raw output: $uptimeStr');
        final uptime = uptimeStr.trim();

        return {
          'cpu': cpu,
          'memory': {'used': memUsed, 'total': memTotal},
          'disk': {'used': diskUsed, 'total': diskTotal},
          'uptime': uptime,
        };
      }
    } catch (e) {
      debugPrint('getMachineStatus error: $e');
      return {
        'cpu': 0.0,
        'memory': {'used': 0, 'total': 0},
        'disk': {'used': '0', 'total': '0'},
        'uptime': 'unknown',
      };
    }
  }

  /// 获取 Token 用量（从 desktop_db.json 本地数据库统计消息数）
  /// 统计当天和当月的所有消息（user + assistant）
  /// 返回 daily（当日）和 monthly（当月）的消息计数
  Future<Map<String, int>> getTokenUsage() async {
    try {
      final dbPath = '${ConfigService.resolveHermesHome()}/desktop_db.json';
      final today = DateTime.now();
      final todayPrefix =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final monthPrefix = '${today.year}-${today.month.toString().padLeft(2, '0')}';

      String jsonContent;
      if (state.mode == ConnectionMode.local) {
        if (Platform.isWindows) {
          // Windows: read via wsl.exe to avoid UNC path issues
          final result = await Process.run(
            'wsl.exe',
            ['bash', '-c', 'cat ~/.hermes/desktop_db.json 2>/dev/null || echo "{}"'],
          );
          if (result.exitCode != 0) {
            debugPrint('getTokenUsage: wsl cat failed (exit ${result.exitCode})');
            return {'daily': 0, 'monthly': 0};
          }
          jsonContent = (result.stdout as String).trim();
        } else {
          // Linux/macOS: read directly
          final file = File(dbPath);
          if (!await file.exists()) {
            debugPrint('getTokenUsage: desktop_db.json not found at $dbPath');
            return {'daily': 0, 'monthly': 0};
          }
          jsonContent = await file.readAsString();
        }
      } else {
        // 远程模式: 通过 SSH 读取 desktop_db.json
        jsonContent = await execRemote('cat $dbPath 2>/dev/null || echo "{}"');
      }

      if (jsonContent.isEmpty || jsonContent == '{}') {
        return {'daily': 0, 'monthly': 0};
      }

      final db = jsonDecode(jsonContent) as Map<String, dynamic>? ?? {};
      final sessionsMap = db['sessions'] as Map<String, dynamic>? ?? {};

      int daily = 0;
      int monthly = 0;

      for (final entry in sessionsMap.entries) {
        final session = entry.value as Map<String, dynamic>? ?? {};
        final messages = session['messages'] as List? ?? [];
        for (final msg in messages) {
          final msgMap = msg as Map<String, dynamic>? ?? {};
          final timestamp = msgMap['timestamp'] as String? ?? '';
          if (timestamp.startsWith(monthPrefix)) {
            monthly++;
            if (timestamp.startsWith(todayPrefix)) {
              daily++;
            }
          }
        }
      }

      debugPrint('getTokenUsage: daily=$daily monthly=$monthly');
      return {'daily': daily, 'monthly': monthly};
    } catch (e) {
      debugPrint('getTokenUsage error: $e');
      return {'daily': 0, 'monthly': 0};
    }
  }

  /// 启动本地 Hermes Gateway 进程
  /// 1. 尝试同目录下的 hermes.exe（安装包模式）
  /// 2. 尝试 PATH 中的 hermes
  /// 3. 尝试 pip install
  /// 4. 尝试 wsl.exe（Windows）
  Future<bool> startLocalGateway() async {
    _hermesProcess?.kill();
    _hermesProcess = null;

    stateNotifier.value = state.copyWith(
      status: ConnStatus.connecting,
      message: '正在启动本地 Gateway...',
    );

    // 尝试的命令列表（按优先级）
    final attempts = <List<String>>[];

    // 1. 检查同目录下的 Hermes（安装包模式）
    final appDir = Platform.script.resolve('.').toFilePath();
    final bundledHermes = '$appDir/hermes/hermes.exe';
    if (await File(bundledHermes).exists()) {
      attempts.add([bundledHermes, 'gateway', 'run', '--port', state.port.toString()]);
    }

    // 2. 检查 PATH 中的 hermes
    final hasHermes = await _commandExists('hermes');
    if (hasHermes) {
      attempts.addAll([
        ['hermes', 'gateway', 'run', '--port', state.port.toString()],
        ['hermes', 'serve', '--port', state.port.toString()],
        ['hermes', 'gateway', 'run'],
        ['hermes', 'serve'],
      ]);
    }

    // Windows 下尝试 WSL
    if (_isWindows) {
      if (hasHermes) {
        attempts.add(['wsl.exe', 'hermes', 'gateway', 'run', '--port', state.port.toString()]);
      } else {
        attempts.add(['wsl.exe', 'hermes', 'gateway', 'run', '--port', state.port.toString()]);
      }
    }

    // 最后尝试 pip install
    if (!hasHermes) {
      attempts.add(['pip', 'install', 'hermes-agent']);
    }

    for (final cmd in attempts) {
      try {
        // 如果是 pip install，先装再启动
        if (cmd[0] == 'pip' && cmd[1] == 'install') {
          stateNotifier.value = state.copyWith(
            status: ConnStatus.connecting,
            message: '正在安装 Hermes Agent...',
          );
          final installResult = await Process.run('pip', ['install', 'hermes-agent']);
          if (installResult.exitCode != 0) continue;
          // 安装成功后直接启动
          final startCmd = ['hermes', 'gateway', 'run', '--port', state.port.toString()];
          _hermesProcess = await Process.start(startCmd[0], startCmd.sublist(1));
        } else {
          _hermesProcess = await Process.start(cmd[0], cmd.sublist(1));
        }

        final pid = _hermesProcess?.pid;
        debugPrint('Started: ${cmd.join(' ')} (pid: $pid)');

        // 监听进程退出 → 自动重启
        _hermesProcess?.exitCode.then((code) {
          debugPrint('Hermes process exited (pid: $pid, code: $code)');
          if (state.mode == ConnectionMode.local &&
              state.status == ConnStatus.connected) {
            debugPrint('Auto-restarting Hermes...');
            startLocalGateway();
          }
        });

        await Future.delayed(const Duration(seconds: 3));

        final ok = await checkLocal();
        if (ok) {
          stateNotifier.value = state.copyWith(
            status: ConnStatus.connected,
            message: '本地 Gateway 已启动',
          );
          return true;
        }

        _hermesProcess?.kill();
        _hermesProcess = null;
      } catch (e) {
        debugPrint('startLocalGateway attempt failed ($cmd): $e');
        _hermesProcess?.kill();
        _hermesProcess = null;
      }
    }

    stateNotifier.value = state.copyWith(
      status: ConnStatus.error,
      message: '无法启动本地 Gateway，请手动安装 Hermes\npip install hermes-agent',
    );
    return false;
  }

  /// 检查命令是否存在 PATH 中
  Future<bool> _commandExists(String cmd) async {
    try {
      if (_isWindows) {
        final r = await Process.run('where', [cmd]);
        return r.exitCode == 0;
      } else {
        final r = await Process.run('which', [cmd]);
        return r.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Hermes Bundle Download & Install
  // ---------------------------------------------------------------------------

  /// Returns the platform-appropriate application data directory.
  Directory _appDataDir() {
    // On Windows use %APPDATA%, on Linux/macOS use ~/.local/share or similar.
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return Directory('$appData\\hermes-desktop');
    } else if (Platform.isMacOS) {
      return Directory(
          '${Platform.environment['HOME'] ?? '/tmp'}/Library/Application Support/hermes-desktop');
    } else {
      // Linux / WSL
      final xdg = Platform.environment['XDG_DATA_HOME'] ??
          '${Platform.environment['HOME'] ?? '/tmp'}/.local/share';
      return Directory('$xdg/hermes-desktop');
    }
  }

  /// Download the Hermes bundle from [url] and save it to a temporary file.
  ///
  /// Reports download progress via [onProgress] callback with (received, total)
  /// bytes. Returns the path to the downloaded file on success. Throws on any
  /// network or I/O failure.
  Future<String> downloadHermesBundle(
    String url, {
    Function(int received, int total)? onProgress,
  }) async {
    setupNotifier.value = SetupState.downloading;

    final tempDir = Directory('${_appDataDir().path}/downloads');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : 'hermes-bundle.zip';
    final destPath = '${tempDir.path}/$fileName';

    // Remove any partial download from a previous attempt.
    final destFile = File(destPath);
    if (await destFile.exists()) {
      await destFile.delete();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      // Follow redirects.
      request.followRedirects = true;
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}: $url',
          uri: uri,
        );
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final sink = destFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(receivedBytes, totalBytes);
        } else {
          // Total size unknown — just report what we have.
          onProgress?.call(receivedBytes, receivedBytes);
        }
      }

      await sink.flush();
      await sink.close();

      debugPrint('Downloaded Hermes bundle ($receivedBytes bytes) to $destPath');
      return destPath;
    } catch (e) {
      setupNotifier.value = SetupState.failed;
      // Clean up partial download on failure.
      if (await destFile.exists()) {
        await destFile.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Extract a downloaded Hermes bundle archive (zip or tar.gz) to the bundle
  /// installation directory ([hermesBundlePath]).
  ///
  /// Uses system commands (`unzip` for .zip, `tar` for .tar.gz). Throws on
  /// extraction failure.
  Future<void> extractBundle(String zipPath) async {
    setupNotifier.value = SetupState.installing;

    final installDir = Directory(hermesBundlePath);

    // Remove any previous installation.
    if (await installDir.exists()) {
      await installDir.delete(recursive: true);
    }
    await installDir.create(recursive: true);

    final file = File(zipPath);
    if (!await file.exists()) {
      throw FileSystemException('Bundle file not found', zipPath);
    }

    final lower = zipPath.toLowerCase();

    try {
      if (lower.endsWith('.zip')) {
        if (Platform.isWindows) {
          // Use PowerShell's Expand-Archive on Windows.
          final result = await Process.run(
            'powershell',
            [
              '-NoProfile',
              '-Command',
              'Expand-Archive',
              '-Path',
              zipPath,
              '-DestinationPath',
              installDir.path,
              '-Force',
            ],
          );
          if (result.exitCode != 0) {
            throw Exception(
                'Expand-Archive failed (exit ${result.exitCode}): ${result.stderr}');
          }
        } else {
          final result = await Process.run(
            'unzip',
            ['-o', zipPath, '-d', installDir.path],
          );
          if (result.exitCode != 0) {
            throw Exception(
                'unzip failed (exit ${result.exitCode}): ${result.stderr}');
          }
        }
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        final result = await Process.run(
          'tar',
          ['-xzf', zipPath, '-C', installDir.path],
        );
        if (result.exitCode != 0) {
          throw Exception(
              'tar extraction failed (exit ${result.exitCode}): ${result.stderr}');
        }
      } else {
        throw ArgumentError(
            'Unsupported archive format: $zipPath (expected .zip, .tar.gz, or .tgz)');
      }

      // List what was extracted for debugging.
      final contents = await installDir.list().toList();
      debugPrint(
          'Extracted ${contents.length} items to ${installDir.path}');

      setupNotifier.value = SetupState.ready;
    } catch (e) {
      setupNotifier.value = SetupState.failed;
      rethrow;
    }
  }

  /// Check whether Hermes is available and set up, and if not, orchestrate the
  /// first-run wizard flow.
  ///
  /// Returns `true` if Hermes is already available or was successfully started.
  /// Returns `false` if setup is needed (the caller should observe
  /// [setupNotifier] and guide the user through the wizard).
  Future<bool> checkAndSetup() async {
    // 1. Already running? Great.
    final localOk = await checkLocal();
    if (localOk) {
      setupNotifier.value = SetupState.ready;
      return true;
    }

    // 2. Try to start the local gateway from an existing installation.
    final started = await startLocalGateway();
    if (started) {
      setupNotifier.value = SetupState.ready;
      return true;
    }

    // 3. Neither is available — signal that the user needs the setup wizard.
    setupNotifier.value = SetupState.waitingForHermes;
    return false;
  }
}
