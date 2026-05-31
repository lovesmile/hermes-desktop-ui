import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'config_service.dart';
import 'embedded_bridge.dart';
import 'gateway_service.dart';
import 'hermes_bridge.dart';
import 'local_db.dart';
import 'remote_bridge.dart';
import 'remote_ssh_executor.dart';
import 'ssh_config.dart';
import 'wsl_bridge.dart';

export 'ssh_config.dart';

enum ConnectionMode { local, remote, embedded }

enum ConnStatus { disconnected, connecting, connected, error }

enum SetupState {
  none,
  waitingForHermes,
  detectedLocal,
  downloading,
  installing,
  ready,
  failed
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
  }) =>
      ConnectionInfo(
        status: status ?? this.status,
        mode: mode ?? this.mode,
        message: message ?? this.message,
        port: port ?? this.port,
      );
}

class ConnectionManager {
  ConnectionManager._();
  static final ConnectionManager _instance = ConnectionManager._();
  factory ConnectionManager() => _instance;

  final ValueNotifier<ConnectionInfo> stateNotifier =
      ValueNotifier(const ConnectionInfo());
  ConnectionInfo get state => stateNotifier.value;

  final RemoteSshExecutor _remoteExecutor = RemoteSshExecutor();
  final ValueNotifier<SetupState> setupNotifier = ValueNotifier(SetupState.none);

  String _wslDistro = 'Ubuntu';
  String get wslDistro => _wslDistro;

  Timer? _healthTimer;

  // 最后一条远程 Gateway 启动命令的输出（用于错误展示）
  String _lastRemoteGatewayOutput = '';

  /// SSH 隧道本地端口（与远程 gateway 端口不同，避免冲突）
  int _tunnelPort = 0;

  late final WslBridge _wslBridge = WslBridge(distro: _wslDistro);
  late final RemoteBridge _remoteBridge = RemoteBridge(_remoteExecutor);
  late final EmbeddedBridge _embeddedBridge =
      EmbeddedBridge(bundlePath: hermesBundlePath);

  static const String defaultHermesDownloadUrl =
      'https://github.com/lovesmile/hermes-desktop-ui/releases/latest/download/hermes-bundle-windows.zip';

  String get hermesBundlePath {
    final userHome =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    return '$userHome\\.hermes-desktop\\hermes';
  }

  Future<void> init() async {
    await ConfigService.ensureInitialized();
    final config = await ConfigService().readDesktopConfig();

    _wslDistro = config['wsl_distro'] ?? 'Ubuntu';
    _wslBridge.setDistro(_wslDistro);

    final modeStr = config['connection_mode'] as String? ?? 'local';
    final mode = modeStr == 'remote'
        ? ConnectionMode.remote
        : (modeStr == 'embedded' ? ConnectionMode.embedded : ConnectionMode.local);
    final port = config['local_port'] ?? 8642;
    final ssh = config.containsKey('ssh_config')
        ? SshConfig.fromJson(config['ssh_config'])
        : const SshConfig();

    stateNotifier.value =
        ConnectionInfo(status: ConnStatus.connecting, mode: mode, port: port);

    // 确保首次启动检查所需的字段存在
    if (!config.containsKey('gateway_url')) {
      config['gateway_url'] = ConnectionManager().gatewayUrl;
    }
    if (!config.containsKey('api_key')) {
      config['api_key'] = 'hermes-desktop-dev-key';
    }
    await ConfigService().writeDesktopConfig(config);

    _startHealthCheck();
    if (mode == ConnectionMode.remote) {
      if (ssh.isValid) {
        await connectRemote(ssh);
      } else {
        stateNotifier.value = ConnectionInfo(
          status: ConnStatus.disconnected,
          mode: ConnectionMode.remote,
          message: 'SSH 未配置，请在设置中完成',
        );
      }
    } else if (mode == ConnectionMode.embedded) {
      await switchToEmbedded();
    } else {
      await switchToLocal();
    }
  }

  Future<({String stdout, int exitCode})> runShell(
    String cmd, {
    bool allowFailure = false,
  }) async {
    final normalizedCmd = _normalizeCronCommand(cmd);
    try {
      final out = await _bridgeForMode(state.mode).exec(normalizedCmd);
      return (stdout: out.stdout, exitCode: out.exitCode);
    } catch (e) {
      if (allowFailure) return (stdout: e.toString(), exitCode: 1);
      rethrow;
    }
  }

  Future<String> resolveHermesHome() async {
    switch (state.mode) {
      case ConnectionMode.embedded:
        final userHome = Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            '';
        return '$userHome\\.hermes';
      case ConnectionMode.remote:
        final rr = await runShell('pwd', allowFailure: true);
        final rh = rr.stdout.trim().isNotEmpty ? rr.stdout.trim() : '/home/unknown';
        return '$rh/.hermes';
      case ConnectionMode.local:
        final lr = await runShell('echo \$HOME', allowFailure: true);
        final lh = lr.stdout.trim().isNotEmpty ? lr.stdout.trim() : r'$HOME';
        return '$lh/.hermes';
    }
  }

  Future<({String stdout, int exitCode})> readTextFile(
    String path, {
    bool allowFailure = false,
  }) {
    switch (state.mode) {
      case ConnectionMode.embedded:
        return runShell('type "${path.replaceAll('"', '""')}" 2>nul',
            allowFailure: allowFailure);
      case ConnectionMode.local:
      case ConnectionMode.remote:
        return runShell("cat '${path.replaceAll("'", "'\\''")}' 2>/dev/null",
            allowFailure: allowFailure);
    }
  }

  String _cronScript(String joined) =>
      'export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"; '
      'HERMES_BIN="\$(command -v hermes 2>/dev/null || true)"; '
      'if [ -z "\$HERMES_BIN" ] && [ -x "\$HOME/.local/bin/hermes" ]; then HERMES_BIN="\$HOME/.local/bin/hermes"; fi; '
      'if [ -z "\$HERMES_BIN" ] && [ -f "\$HOME/.local/bin/hermes" ]; then HERMES_BIN="\$HOME/.local/bin/hermes"; fi; '
      'if [ -z "\$HERMES_BIN" ]; then echo "hermes command not found"; exit 127; fi; '
      '"\$HERMES_BIN" --accept-hooks cron $joined 2>&1';

  Future<({String stdout, int exitCode})> runHermesCron(
    List<String> args, {
    bool allowFailure = false,
  }) {
    switch (state.mode) {
      case ConnectionMode.embedded: {
        final hermesExe = '$hermesBundlePath\\hermes.exe';
        final joined =
            args.map((a) => '"${a.replaceAll('"', '""')}"').join(' ');
        final cmd =
            'if exist "${hermesExe.replaceAll('"', '""')}" ( "${hermesExe.replaceAll('"', '""')}" --accept-hooks cron $joined ) else ( hermes --accept-hooks cron $joined ) 2>&1';
        return runShell(cmd, allowFailure: allowFailure);
      }
      case ConnectionMode.local: {
        final joined =
            args.map((a) => "'${a.replaceAll("'", "'\\''")}'").join(' ');
        return runShell(_cronScript(joined), allowFailure: allowFailure);
      }
      case ConnectionMode.remote: {
        final joined =
            args.map((a) => "'${a.replaceAll("'", "'\\''")}'").join(' ');
        return runShell(_cronScript(joined),
            allowFailure: allowFailure);
      }
    }
  }

  String _normalizeCronCommand(String cmd) {
    final trim = cmd.trim();
    if (!trim.startsWith('hermes --accept-hooks cron ')) return cmd;

    final suffix = trim.substring('hermes --accept-hooks cron '.length);

    switch (state.mode) {
      case ConnectionMode.embedded: {
        final hermesExe = '$hermesBundlePath\\hermes.exe'.replaceAll('"', '""');
        return 'if exist "$hermesExe" ( "$hermesExe" --accept-hooks cron $suffix ) else ( hermes --accept-hooks cron $suffix )';
      }
      case ConnectionMode.local:
        return _cronScript(suffix);
      case ConnectionMode.remote:
        return _cronScript(suffix);
    }
  }

  Future<ProcessResult> execBash(String command) async {
    final res = await runShell(command, allowFailure: true);
    return ProcessResult(0, res.exitCode, res.stdout, '');
  }

  Future<Process> startShellProcess(String command) {
    switch (state.mode) {
      case ConnectionMode.local:
        return Process.start('wsl.exe', ['-d', _wslDistro, 'bash', '-c', command]);
      case ConnectionMode.embedded:
        return Process.start('cmd.exe', ['/c', command]);
      case ConnectionMode.remote:
        throw UnsupportedError('Streaming shell process is not supported in remote mode');
    }
  }

  /// 启动微信扫码登录进程（python3 脚本）
  Future<Process> startWechatProcess(String scriptPath) {
    return startShellProcess('python3 $scriptPath');
  }

  Future<bool> checkLocal() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('$gatewayUrl/health'));
      final res = await req.close();
      if (res.statusCode == 200) {
        stateNotifier.value =
            state.copyWith(status: ConnStatus.connected, message: '在线');
        return true;
      }
    } catch (_) {}
    stateNotifier.value =
        state.copyWith(status: ConnStatus.disconnected, message: '未响应');
    return false;
  }

  /// Shell 单引号转义（防止 bash 展开特殊字符）
  static String _shQuote(String s) =>
      "'${s.replaceAll("'", "'\\''")}'";

  /// 首次密码连接时自动生成密钥并上传，后续改用密钥认证
  Future<SshConfig> _ensureRemoteKey(SshConfig config) async {
    // ── recovery: keyPath 设了但文件被删 → 用保存的密码重新生成 ──
    if ((config.password == null || config.password!.isEmpty) &&
        config.keyPath != null && config.keyPath!.isNotEmpty) {
      if (await File(config.keyPath!).exists()) return config;
      final pw = ((await ConfigService().readDesktopConfig())['ssh_config']
              as Map?)?['password'] as String?;
      if (pw != null && pw.isNotEmpty) config = config.copyWith(password: pw);
      else return config;
    }

    if (config.password == null || config.password!.isEmpty) return config;
    if (config.keyPath != null && config.keyPath!.isNotEmpty) return config;

    final home = Platform.environment['USERPROFILE'] ?? '';
    final sshDir = '$home\\.hermes\\ssh';
    final keyPath = '$sshDir\\id_ed25519_${config.host}';

    if (await File(keyPath).exists()) {
      return config.copyWith(keyPath: keyPath, password: null);
    }

    try {
      await Directory(sshDir).create(recursive: true);
      final gen = await Process.run('ssh-keygen', [
        '-t', 'ed25519',
        '-f', keyPath,
        '-N', '',
        '-q',
      ]);
      if (gen.exitCode != 0) return config;

      final pubKey = await File('$keyPath.pub').readAsString();
      final escapedPw = _shQuote(config.password!);
      final sshArgs = [
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=10',
      ];
      if (config.port != 22) {
        sshArgs.addAll(['-p', config.port.toString()]);
      }
      sshArgs.add('${config.user}@${config.host}');

      final uploadProc = await Process.start('wsl.exe', [
        '-d', _wslDistro,
        'sshpass', '-p', escapedPw, 'ssh',
        ...sshArgs,
        'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
            'cat >> ~/.ssh/authorized_keys && '
            'chmod 600 ~/.ssh/authorized_keys',
      ]);
      uploadProc.stdin.writeln(pubKey);
      uploadProc.stdin.close();
      final uploadCode = await uploadProc.exitCode;

      if (uploadCode != 0) return config;

      // 保存配置，保留密码用于密钥文件丢失后的恢复
      final dc = await ConfigService().readDesktopConfig();
      dc['ssh_config'] = {
        'host': config.host,
        'port': config.port,
        'user': config.user,
        'keyPath': keyPath,
        'password': config.password,
      };
      await ConfigService().writeDesktopConfig(dc);

      return config.copyWith(keyPath: keyPath, password: null);
    } catch (_) {
      return config;
    }
  }

  Future<bool> connectRemote(SshConfig config) async {
    await disconnect();

    // 从配置文件读取最新 gateway 端口，避免 state.port 过期
    final desktopConfig = await ConfigService().readDesktopConfig();
    final remoteGatewayPort = desktopConfig['local_port'] as int? ?? 8642;

    stateNotifier.value = state.copyWith(
      status: ConnStatus.connecting,
      mode: ConnectionMode.remote,
      message: '正在连接远程...',
    );

    _tunnelPort = await _findFreePort();
    _remoteExecutor.setTunnelPorts(
      tunnel: _tunnelPort,
      remote: remoteGatewayPort,
    );

    // 密码认证 → 自动升级为密钥认证（后续不再依赖 WSL/sshpass）
    config = await _ensureRemoteKey(config);

    bool connected;
    try {
      connected = await _remoteBridge.connect(
        config: SshConfigWrapper(config),
        localPort: _tunnelPort,
      );
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: ConnStatus.error,
        message: '连接失败: $e',
      );
      return false;
    }

    if (connected) {
      // Gateway 已在运行 — 将远程 API_SERVER_KEY 同步到本地
      final keyResult = await runShell(
        "grep '^API_SERVER_KEY=' ~/.hermes/.env | head -1 | cut -d= -f2-",
        allowFailure: true,
      );
      final remoteKey = keyResult.stdout.trim();
      if (remoteKey.isNotEmpty) {
        final dc2 = await ConfigService().readDesktopConfig();
        if (dc2['api_key'] != remoteKey) {
          dc2['api_key'] = remoteKey;
          await ConfigService().writeDesktopConfig(dc2);
          GatewayService().invalidateApiKey();
        }
      }

      final ns = remoteNamespaceOf(config);
      await _applyConnectionContext(namespace: ns, serverId: config.host);
      stateNotifier.value =
          state.copyWith(status: ConnStatus.connected, message: '远程已连接');
      return true;
    }

    // 隧道已建立但 Gateway 无响应 — 尝试远程启动 Gateway
    if (_remoteExecutor.tunnelEstablished) {
      stateNotifier.value = state.copyWith(
        status: ConnStatus.connecting,
        message: '远程 Gateway 未运行，正在自动启动...',
      );
      await _startRemoteGateway();
      // 等待 8 秒让 Gateway 完成启动
      for (var i = 0; i < 8; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (await checkLocal()) break;
      }
      if (await checkLocal()) {
        final ns = remoteNamespaceOf(config);
        await _applyConnectionContext(namespace: ns, serverId: config.host);
        return true;
      }
      // 从 stdout 提取具体失败原因展示给用户
      stateNotifier.value = state.copyWith(
        status: ConnStatus.error,
        message: _lastRemoteGatewayOutput.isNotEmpty ? '远程 Gateway 启动失败: $_lastRemoteGatewayOutput' : '远程 Gateway 启动失败，请手动登录服务器运行: hermes gateway run',
      );
      return false;
    }

    final errMsg = _remoteExecutor.lastError;
    stateNotifier.value = state.copyWith(
      status: ConnStatus.error,
      message: errMsg != null ? '连接失败: $errMsg' : '连接失败',
    );
    return false;
  }

  Future<bool> _startRemoteGateway() async {
    // 生成唯一 API key
    final hostnameResult = await runShell('hostname', allowFailure: true);
    final hostname = hostnameResult.stdout.trim();
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final generatedKey = 'hermes-desktop-${hostname.isNotEmpty ? hostname : "remote"}-$timestamp';

    // 读取远程 gateway 端口（与 SSH 隧道目标端口一致）
    final remotePort = state.port;

    // 单次 SSH 连接：配置 .env + 尝试所有启动方式 + 等待端口就绪
    final setupCmd = r'''
# 1. 配置 .env
mkdir -p ~/.hermes
touch ~/.hermes/.env
sed -i '/^API_SERVER_ENABLED=/d' ~/.hermes/.env
sed -i '/^API_SERVER_KEY=/d' ~/.hermes/.env
echo "API_SERVER_ENABLED=true" >> ~/.hermes/.env
echo "API_SERVER_KEY=__API_KEY__" >> ~/.hermes/.env
echo "ENV_OK"

PORT=__REMOTE_PORT__

wait_port() {
  local i=0
  while [ $i -lt 10 ]; do
    if ss -tln 2>/dev/null | grep -q ":$PORT "; then
      echo "PORT_READY"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "PORT_TIMEOUT"
  return 1
}

# 2. 尝试 systemd
if systemctl --user status hermes-gateway >/dev/null 2>&1; then
  ERR=$(systemctl --user restart hermes-gateway 2>&1 || systemctl --user start hermes-gateway 2>&1)
  if [ -n "$ERR" ]; then
    echo "SYSTEMD_STDERR: $ERR"
  fi
  wait_port && { echo "SYSTEMD_OK"; exit 0; }
  echo "SYSTEMD_FAIL"
fi

# 3. fallback: python venv
if [ -d ~/.hermes/hermes-agent/venv ]; then
  . ~/.hermes/hermes-agent/venv/bin/activate
  cd ~/.hermes/hermes-agent
  pkill -f "hermes_cli\.main gateway" 2>/dev/null || true
  sleep 1
  API_SERVER_ENABLED=true API_SERVER_KEY=__API_KEY__ \
    nohup python -m hermes_cli.main gateway run --replace \
    > ~/.hermes/logs/gateway.log 2>&1 &
  disown
  wait_port && { echo "VENV_OK"; exit 0; }
fi

# 4. fallback: hermes binary
HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
if [ -z "$HERMES_BIN" ] && [ -x "$HOME/.local/bin/hermes" ]; then
  HERMES_BIN="$HOME/.local/bin/hermes"
fi
if [ -n "$HERMES_BIN" ]; then
  pkill -f "hermes gateway" 2>/dev/null || true
  sleep 1
  API_SERVER_ENABLED=true API_SERVER_KEY=__API_KEY__ \
    nohup "$HERMES_BIN" gateway run --replace \
    > ~/.hermes/logs/gateway.log 2>&1 &
  disown
  wait_port && { echo "BINARY_OK"; exit 0; }
fi

echo "NO_METHOD"
'''.replaceAll('__API_KEY__', generatedKey)
       .replaceAll('__REMOTE_PORT__', remotePort.toString());

    final setupResult = await runShell(setupCmd.trim(), allowFailure: true);
    _lastRemoteGatewayOutput = setupResult.stdout.trim().replaceAll('\r\n', '\n');

    if (_lastRemoteGatewayOutput.contains('NO_METHOD')) return false;

    // 将生成的 API key 同步到本地配置
    final dc = await ConfigService().readDesktopConfig();
    dc['api_key'] = generatedKey;
    await ConfigService().writeDesktopConfig(dc);
    GatewayService().invalidateApiKey();

    // 等待端口就绪（最多再等 10 秒）
    _lastRemoteGatewayOutput += '\nwaiting for port...';
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await checkLocal()) {
        _lastRemoteGatewayOutput += '\nport: READY';
        return true;
      }
    }
    _lastRemoteGatewayOutput += '\nport: TIMEOUT';
    return false;
  }

  /// 轻量重连 — 只重建 SSH 隧道，不触发 context/refresh 切换
  Future<bool> _reconnectRemote(SshConfig config) async {
    _remoteBridge.disconnect();
    stateNotifier.value =
        state.copyWith(status: ConnStatus.connecting, message: '正在重连...');

    if (_tunnelPort <= 0) _tunnelPort = await _findFreePort();
    _remoteExecutor.setTunnelPorts(
      tunnel: _tunnelPort,
      remote: state.port,
    );

    bool ok;
    try {
      ok = await _remoteBridge.connect(
        config: SshConfigWrapper(config),
        localPort: _tunnelPort,
      );
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: ConnStatus.error,
        message: '重连失败: $e',
      );
      return false;
    }

    if (ok) {
      stateNotifier.value =
          state.copyWith(status: ConnStatus.connected, message: '远程已连接');
      return true;
    }

    // 隧道已建立但 Gateway 无响应 — 尝试启动
    if (_remoteExecutor.tunnelEstablished) {
      stateNotifier.value = state.copyWith(
        status: ConnStatus.connecting,
        message: '正在启动远程 Gateway...',
      );
      await _startRemoteGateway();
      for (var i = 0; i < 8; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (await checkLocal()) break;
      }
      if (await checkLocal()) {
        stateNotifier.value =
            state.copyWith(status: ConnStatus.connected, message: '远程已连接');
        return true;
      }
      stateNotifier.value = state.copyWith(
        status: ConnStatus.error,
        message: _lastRemoteGatewayOutput.isNotEmpty ? '远程 Gateway 启动失败: $_lastRemoteGatewayOutput' : '重连失败: Gateway 无响应',
      );
      return false;
    }

    final errMsg = _remoteExecutor.lastError;
    stateNotifier.value = state.copyWith(
      status: ConnStatus.error,
      message: errMsg != null ? '重连失败: $errMsg' : '重连失败',
    );
    return false;
  }

  Future<void> switchToLocal() async {
    await disconnect();
    stateNotifier.value = state.copyWith(
      mode: ConnectionMode.local,
      status: ConnStatus.connecting,
      message: '切换到本地模式...',
    );
    await _wslBridge.connect();
    await _applyConnectionContext(namespace: 'local', serverId: 'local');
    await checkLocal();
  }

  Future<void> switchToEmbedded() async {
    await disconnect();
    stateNotifier.value = state.copyWith(
      mode: ConnectionMode.embedded,
      status: ConnStatus.connecting,
      message: '切换到内嵌模式...',
    );
    await _embeddedBridge.connect();
    await _applyConnectionContext(namespace: 'embedded', serverId: 'embedded');
    await checkLocal();
  }

  Future<void> switchToRemote(SshConfig config) async {
    await connectRemote(config);
  }

  Future<void> disconnect() async {
    await Future.wait([
      _remoteBridge.disconnect(),
      _wslBridge.disconnect(),
      _embeddedBridge.disconnect(),
    ]);
    _tunnelPort = 0;
    stateNotifier.value = state.copyWith(status: ConnStatus.disconnected);
  }

  void _startHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (state.status == ConnStatus.connected || state.status == ConnStatus.error) {
        final ok = await checkLocal();
        if (!ok && state.mode == ConnectionMode.remote) {
          final c = _remoteExecutor.config;
          if (c != null) {
            await _reconnectRemote(c);
          }
        }
      }
    });
  }

  static String remoteNamespaceOf(SshConfig c) =>
      '${c.user}_${c.host}'.replaceAll('.', '_');
  String get gatewayUrl =>
      'http://localhost:${_tunnelPort > 0 ? _tunnelPort : state.port}';

  /// 找一个空闲的本地端口给 SSH 隧道使用
  Future<int> _findFreePort() async {
    try {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = server.port;
      await server.close();
      return port;
    } catch (_) {
      return state.port + 1000; // fallback
    }
  }

  Future<List<String>> getWslDistros() async {
    try {
      final r = await Process.run('wsl.exe', ['--list', '--quiet']);
      return utf8
          .decode(r.stdout as List<int>, allowMalformed: true)
          .split('\n')
          .map((s) => s.trim().replaceAll('\x00', ''))
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return ['Ubuntu'];
    }
  }

  Future<void> setWslDistro(String d) async {
    _wslDistro = d;
    _wslBridge.setDistro(d);
    final config = await ConfigService().readDesktopConfig();
    config['wsl_distro'] = d;
    await ConfigService().writeDesktopConfig(config);
  }

  Future<Map<String, dynamic>> getMachineStatus() async {
    switch (state.mode) {
      case ConnectionMode.embedded:
        return {
          'cpu': 0.0,
          'memory': {'used': 0, 'total': 0},
          'disk': {'used': '0B', 'total': '0B'},
          'uptime': 'embedded',
        };
      case ConnectionMode.local:
      case ConnectionMode.remote: {
        try {
      final result = await runShell(r'''
grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "CPU:%.1f\n"}'
free -m | awk '/^Mem:/ {printf "MEM:%s|%s\n", $3, $2}'
df -h / | awk 'NR==2 {printf "DISK:%s|%s\n", $3, $2}'
uptime -p | awk '{printf "UPTIME:%s\n", $0}'
''', allowFailure: true);
      final out = result.stdout.trim().replaceAll('\r\n', '\n');
      double cpu = 0.0;
      int memUsed = 0, memTotal = 0;
      String diskUsed = '', diskTotal = '';
      String uptime = '';
      for (final line in out.split('\n')) {
        if (line.startsWith('CPU:')) {
          cpu = double.tryParse(line.substring(4)) ?? 0.0;
        } else if (line.startsWith('MEM:')) {
          final parts = line.substring(4).split('|');
          memUsed = int.tryParse(parts.first) ?? 0;
          memTotal = int.tryParse(parts.last) ?? 0;
        } else if (line.startsWith('DISK:')) {
          final parts = line.substring(5).split('|');
          diskUsed = parts.isNotEmpty ? parts.first : '';
          diskTotal = parts.length > 1 ? parts.last : '';
        } else if (line.startsWith('UPTIME:')) {
          uptime = line.substring(7);
        }
      }
      return {
        'cpu': cpu,
        'memory': {'used': memUsed, 'total': memTotal},
        'disk': {'used': diskUsed, 'total': diskTotal},
        'uptime': uptime,
      };
    } catch (_) {
      return {
        'cpu': 0.0,
        'memory': {'used': 0, 'total': 0},
        'uptime': 'unknown'
      };
    }
      }
    }
  }

  Future<Map<String, int>> getTokenUsage() async => {'daily': 0, 'monthly': 0};
  Future<bool> checkAndSetup() async => checkLocal();
  Future<bool> startLocalGateway() async {
    if (state.mode == ConnectionMode.remote && _remoteExecutor.tunnelEstablished) {
      await _startRemoteGateway();
      await Future.delayed(const Duration(seconds: 5));
    }
    return checkLocal();
  }

  Future<String> downloadHermesBundle(
    String url, {
    Function(int, int)? onProgress,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final dest = '${tempDir.path}/hermes.zip';
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final sink = File(dest).openWrite();
    int received = 0;
    await for (final chunk in res) {
      received += chunk.length;
      sink.add(chunk);
      if (onProgress != null) onProgress(received, res.contentLength);
    }
    await sink.flush();
    await sink.close();
    return dest;
  }

  Future<void> extractBundle(String zipPath) async {
    final installDir = Directory(hermesBundlePath);
    if (!installDir.existsSync()) installDir.createSync(recursive: true);
    if (Platform.isWindows) {
      await Process.run('powershell', [
        '-Command',
        'Expand-Archive',
        '-Path',
        zipPath,
        '-DestinationPath',
        installDir.path,
        '-Force'
      ]);
    }
  }
  Future<void> _applyConnectionContext({
    required String namespace,
    required String serverId,
  }) async {
    await LocalDatabase().setMode(namespace);
    await GatewayService().refreshBaseUrl();
    GatewayService().setServerId(serverId);
  }

  HermesBridge _bridgeForMode(ConnectionMode mode) {
    switch (mode) {
      case ConnectionMode.remote:
        return _remoteBridge;
      case ConnectionMode.embedded:
        return _embeddedBridge;
      case ConnectionMode.local:
        return _wslBridge;
    }
  }
}

class SshConfigWrapper extends SshConfig {
  SshConfigWrapper(SshConfig c)
      : super(
          host: c.host,
          port: c.port,
          user: c.user,
          keyPath: c.keyPath,
          password: c.password,
        );

  bool get useKeyAuth => false;
}
