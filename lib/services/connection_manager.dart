import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  Process? _embeddedGatewayProcess;
  bool _embeddedGatewayExited = false;
  bool _restartingEmbedded = false; // 防止健康检查定时器并发重启
  // 内嵌 Gateway 启动时的 stderr（用于诊断启动失败原因）
  String _lastEmbeddedStderr = '';

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

    final modeStr = config['connection_mode'] as String? ?? 'local';
    final mode = modeStr == 'remote'
        ? ConnectionMode.remote
        : (modeStr == 'embedded' ? ConnectionMode.embedded : ConnectionMode.local);

    // 从 mode 命名空间读取配置，避免跨模式污染
    int port;
    SshConfig ssh;
    switch (mode) {
      case ConnectionMode.local: {
        final localCfg = (config['local'] as Map?) ?? {};
        _wslDistro = (localCfg['wsl_distro'] as String?) ?? 'Ubuntu';
        port = (localCfg['gateway_port'] as int?) ?? 8642;
        ssh = const SshConfig();
        break;
      }
      case ConnectionMode.remote: {
        final remoteCfg = (config['remote'] as Map?) ?? {};
        port = (remoteCfg['gateway_port'] as int?) ?? 8642;
        ssh = SshConfig(
          host: remoteCfg['ssh_host'] as String? ?? '',
          port: remoteCfg['ssh_port'] as int? ?? 22,
          user: remoteCfg['ssh_user'] as String? ?? '',
          keyPath: remoteCfg['ssh_key_path'] as String?,
          password: remoteCfg['ssh_password'] as String?,
        );
        break;
      }
      case ConnectionMode.embedded:
        port = 8642;
        ssh = const SshConfig();
    }
    _wslBridge.setDistro(_wslDistro);

    // 确保首次启动检查所需的字段存在
    if (!config.containsKey('gateway_url')) {
      config['gateway_url'] = ConnectionManager().gatewayUrl;
    }
    await ConfigService().writeDesktopConfig(config);

    stateNotifier.value =
        ConnectionInfo(status: ConnStatus.connecting, mode: mode, port: port);

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
        final lh = lr.stdout.trim().isNotEmpty ? lr.stdout.trim() : r'\$HOME';
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

  /// Shell 前缀：修正 PATH 并查找 hermes 二进制路径，结果存入 \$HERMES_BIN
  static String get hermesBinShell =>
      'export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"; '
      'HERMES_BIN="\$(command -v hermes 2>/dev/null || true)"; '
      r'if [ -z "$HERMES_BIN" ] && [ -x "$HOME/.local/bin/hermes" ]; then '
      r'  HERMES_BIN="$HOME/.local/bin/hermes"; '
      r'fi; '
      r'if [ -z "$HERMES_BIN" ] && [ -f "$HOME/.local/bin/hermes" ]; then '
      r'  HERMES_BIN="$HOME/.local/bin/hermes"; '
      r'fi; ';

  /// Shell 命令：重启 Gateway 服务（优先 systemctl，回退 pkill + nohup）
  /// 需先调用 [hermesBinShell] 设置 \$HERMES_BIN
  static String get restartGatewayShell =>
      r'if systemctl --user status hermes-gateway >/dev/null 2>&1; then '
      r'  systemctl --user restart hermes-gateway; '
      r'else '
      r'  pkill -f "hermes gateway" 2>/dev/null || true; sleep 2; '
      r'  if [ -n "$HERMES_BIN" ]; then '
      r'    API_SERVER_ENABLED=true nohup "$HERMES_BIN" gateway run --replace '
      r'      > ~/.hermes/logs/gateway.log 2>&1 & '
      r'  fi; '
      r'fi';

  String _cronScript(String joined) =>
      '${hermesBinShell}'
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
    // 远程模式使用 SSH 隧道端口，其他模式用 state.port
    final port = state.mode == ConnectionMode.remote && _tunnelPort > 0
        ? _tunnelPort
        : state.port;

    // 1. 尝试配置的端口
    if (await _checkHealth(port)) {
      stateNotifier.value =
          state.copyWith(status: ConnStatus.connected, message: '在线');
      return true;
    }

    // 2. 本地模式：自动检测 WSL 中 Gateway 的实际端口
    if (state.mode == ConnectionMode.local && _wslBridge.isConnected) {
      final detectedPort = await _detectGatewayPort();
      if (detectedPort != null && detectedPort != port) {
        final cfg = await ConfigService().readDesktopConfig();
        cfg['local'] ??= <String, dynamic>{};
        (cfg['local'] as Map<String, dynamic>)['gateway_port'] = detectedPort;
        await ConfigService().writeDesktopConfig(cfg);
        stateNotifier.value = state.copyWith(
          port: detectedPort,
          message: '自动修正端口 $detectedPort...',
        );
        if (await _checkHealth(detectedPort)) {
          stateNotifier.value = state.copyWith(
            status: ConnStatus.connected,
            message: '在线',
          );
          return true;
        }
      }
    }

    // 3. 全部失败 → 显示可操作的错误提示
    final hint = state.mode == ConnectionMode.local
        ? '连接失败 (端口 $port)，请确认 WSL 中已运行: hermes gateway run'
        : '连接失败 (端口 $port)，请在设置中检查端口配置';
    stateNotifier.value = state.copyWith(
      status: ConnStatus.error,
      message: hint,
    );
    return false;
  }

  /// 检测指定端口上的 /health 是否可达
  Future<bool> _checkHealth(int port) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('http://localhost:$port/health'));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 通过 WSL 检测 Gateway 实际监听端口
  Future<int?> _detectGatewayPort() async {
    try {
      // 优先读 .env 中的端口配置
      final result = await _wslBridge.exec(
        'grep -oP "^API_SERVER_PORT=\\\K\d+" ~/.hermes/.env 2>/dev/null || true',
      );
      final trimmed = result.stdout.trim();
      if (trimmed.isNotEmpty) {
        final p = int.tryParse(trimmed);
        if (p != null && p > 0) return p;
      }
      // fallback：扫描常见端口
      for (final p in [8642, 8643, 8644, 8645]) {
        if (await _checkHealth(p)) return p;
      }
    } catch (_) {}
    return null;
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
      final pw = ((await ConfigService().readDesktopConfig())['remote']
              as Map?)?['ssh_password'] as String?;
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

      // 保存配置
      final dc = await ConfigService().readDesktopConfig();
      dc['remote'] = {
        ...?dc['remote'] as Map?,
        'ssh_key_path': keyPath,
        'ssh_password': config.password,
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
    final remoteCfg = (desktopConfig['remote'] as Map?) ?? {};
    final remoteGatewayPort = remoteCfg['gateway_port'] as int? ?? 8642;

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
      // 同步 API_SERVER_KEY：读取远程 .env 中的 key 保存到本地配置
      // 若 .env 无 key，用本地生成的 key 写入 .env
      final keyResult = await runShell(
        r"grep '^API_SERVER_KEY=' ~/.hermes/.env | head -1 | cut -d= -f2-",
        allowFailure: true,
      );
      final remoteKey = keyResult.stdout.trim();

      if (remoteKey.isNotEmpty) {
        final dc2 = await ConfigService().readDesktopConfig();
        dc2['api_key'] = remoteKey;
        await ConfigService().writeDesktopConfig(dc2);
        GatewayService().invalidateApiKey();
      } else {
        final localKey = await _ensureApiKey();
        await runShell(
          r"sed -i '/^API_SERVER_KEY=/d' ~/.hermes/.env 2>/dev/null; "
          'echo "API_SERVER_KEY=$localKey" >> ~/.hermes/.env; '
          '${hermesBinShell}'
          '${restartGatewayShell}',
          allowFailure: true,
        );
        // 等待 gateway 重启完成
        for (var i = 0; i < 8; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (await checkLocal()) break;
        }
        if (!await checkLocal()) {
          stateNotifier.value = state.copyWith(
            status: ConnStatus.error,
            message: '远程 Gateway 重启失败，请手动运行: systemctl --user restart hermes-gateway',
          );
          return false;
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
    final remotePort = state.port;
    final apiKey = await _ensureApiKey();

    final setupCmd = r'''
# 1. 配置 .env
mkdir -p ~/.hermes
touch ~/.hermes/.env
sed -i '/^API_SERVER_ENABLED=/d' ~/.hermes/.env
echo "API_SERVER_KEY=__API_KEY__" >> ~/.hermes/.env
echo "API_SERVER_ENABLED=true" >> ~/.hermes/.env
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
  API_SERVER_ENABLED=true \
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
  API_SERVER_ENABLED=true \
    nohup "$HERMES_BIN" gateway run --replace \
    > ~/.hermes/logs/gateway.log 2>&1 &
  disown
  wait_port && { echo "BINARY_OK"; exit 0; }
fi

echo "NO_METHOD"
'''.replaceAll('__REMOTE_PORT__', remotePort.toString())
      .replaceAll('__API_KEY__', apiKey);

    final setupResult = await runShell(setupCmd.trim(), allowFailure: true);
    _lastRemoteGatewayOutput = setupResult.stdout.trim().replaceAll('\r\n', '\n');

    if (_lastRemoteGatewayOutput.contains('NO_METHOD')) return false;

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
    final desktopConfig = await ConfigService().readDesktopConfig();
    final localCfg = (desktopConfig['local'] as Map?) ?? {};
    final localPort = localCfg['gateway_port'] as int? ?? 8642;
    await disconnect();
    stateNotifier.value = state.copyWith(
      mode: ConnectionMode.local,
      status: ConnStatus.connecting,
      message: '切换到本地模式...',
      port: localPort,
    );
    await _wslBridge.connect();

    final localApiKey = await _ensureApiKey();
    // 如果 gateway 已在运行且 API_SERVER_KEY 一致，跳过重启
    bool restartOk = true;
    final alreadyHealthy = await checkLocal();
    if (!alreadyHealthy) {
      restartOk = await _restartLocalGatewayShell(localApiKey);
      await Future.delayed(const Duration(seconds: 3));
    } else {
      final currentKey = await _wslBridge.exec(
        r"grep '^API_SERVER_KEY=' ~/.hermes/.env 2>/dev/null | cut -d= -f2",
      ).then((r) => r.stdout.trim());
      if (currentKey != localApiKey) {
        restartOk = await _restartLocalGatewayShell(localApiKey);
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    await _applyConnectionContext(namespace: 'local', serverId: 'local');
    final healthy = await checkLocal();
    if (!healthy || !restartOk) {
      stateNotifier.value = state.copyWith(
        status: ConnStatus.error,
        message: restartOk ? '本地 Gateway 启动后无响应' : '本地 Gateway 重启失败：未找到 hermes 命令，请检查 WSL 中 hermes 是否安装',
      );
    }
  }

  Future<bool> _restartLocalGatewayShell(String apiKey) async {
    return _wslBridge.exec(
      '${hermesBinShell}'
      r"sed -i '/^API_SERVER_KEY=/d' ~/.hermes/.env 2>/dev/null; "
      'echo "API_SERVER_KEY=$apiKey" >> ~/.hermes/.env; '
      r'if systemctl --user status hermes-gateway >/dev/null 2>&1; then '
      r'  systemctl --user restart hermes-gateway; '
      r'  echo "OK"; '
      r'else '
      r'  pkill -f "hermes gateway" 2>/dev/null || true;'
      r'  sleep 2; '
      r'  if [ -n "$HERMES_BIN" ]; then '
      r'    API_SERVER_ENABLED=true nohup "$HERMES_BIN" gateway run --replace '
      r'      > ~/.hermes/logs/gateway.log 2>&1 & '
      r'    echo "OK"; '
      r'  else '
      r'    echo "NO_HERMES_BINARY"; '
      r'  fi; '
      r'fi',
    ).then((r) => r.stdout.trim().contains('OK')).catchError((_) => false);
  }

  Future<void> switchToEmbedded() async {
    await disconnect();
    // 动态找可用端口，避免与 WSL gateway（默认 8642）冲突
    final freePort = await _findFreePort();
    stateNotifier.value = state.copyWith(
      mode: ConnectionMode.embedded,
      status: ConnStatus.connecting,
      message: '切换到内嵌模式...',
      port: freePort,
    );
    await _embeddedBridge.connect();
    await _applyConnectionContext(namespace: 'embedded', serverId: 'embedded');

    // 确保 hermes.exe 存在，否则自动下载
    final exePath = '$hermesBundlePath\\hermes.exe';
    if (!await File(exePath).exists()) {
      // 先检查安装包自带的 hermes.exe（{app}\hermes\hermes.exe）
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final bundledExe = '$appDir\\hermes\\hermes.exe';
      if (await File(bundledExe).exists()) {
        await Directory(hermesBundlePath).create(recursive: true);
        await File(bundledExe).copy(exePath);
      } else {
        stateNotifier.value = state.copyWith(
          status: ConnStatus.connecting,
          message: '正在下载内嵌 Hermes...',
        );
        try {
          final zipPath = await downloadHermesBundle(defaultHermesDownloadUrl);
          stateNotifier.value = state.copyWith(
            status: ConnStatus.connecting,
            message: '正在安装...',
          );
          await extractBundle(zipPath);
          try { await File(zipPath).delete(); } catch (_) {}
          if (!await File(exePath).exists()) {
            stateNotifier.value = state.copyWith(
              status: ConnStatus.error,
              message: '安装失败：解压后未找到 hermes.exe',
            );
            return;
          }
        } catch (e) {
          stateNotifier.value = state.copyWith(
            status: ConnStatus.error,
            message: '下载或安装失败: $e',
          );
          return;
        }
      }
    }

    // 启动 Gateway
    final started = await _ensureEmbeddedGatewayRunning();
    if (started) {
      stateNotifier.value = state.copyWith(status: ConnStatus.connected, message: '内嵌模式');
    } else {
      final stderrHint = _lastEmbeddedStderr.isNotEmpty ? ': ${_lastEmbeddedStderr.trim()}' : '';
      stateNotifier.value = state.copyWith(
        status: ConnStatus.error,
        message: '内嵌 Gateway 启动失败$stderrHint',
      );
    }
  }

  Future<bool> _ensureEmbeddedGatewayRunning() async {
    if (_restartingEmbedded) return false;
    _restartingEmbedded = true;
    final exePath = '$hermesBundlePath\\hermes.exe';
    if (!await File(exePath).exists()) { _restartingEmbedded = false; return false; }

    final userHome = Platform.environment['USERPROFILE'] ?? '';
    final hermesDir = Directory('$userHome\\.hermes');
    if (!hermesDir.existsSync()) hermesDir.createSync(recursive: true);

    // 确保 .env 中有 API_SERVER_KEY（API Server 必需）、API_SERVER_PORT、API_SERVER_ENABLED
    final envFile = File('$userHome\\.hermes\\.env');
    final oldLines = envFile.existsSync()
        ? await envFile.readAsString().then((s) => s.split('\n')
            .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('# .env not found'))
            .toList())
        : <String>[];
    final cleanLines = oldLines
        .where((l) => !l.startsWith('API_SERVER_KEY=') &&
                      !l.startsWith('API_SERVER_PORT=') &&
                      !l.startsWith('API_SERVER_ENABLED='))
        .toList();
    final apiKey = await _ensureApiKey();
    cleanLines.addAll([
      'API_SERVER_KEY=$apiKey',
      'API_SERVER_PORT=${state.port}',
      'API_SERVER_ENABLED=true',
    ]);
    await envFile.writeAsString('${cleanLines.join('\n')}\n');
    // 清理残留进程和锁文件：先杀进程，等锁确实释放了再启动
    await Process.run('taskkill', ['/F', '/IM', 'hermes.exe']);
    final lockFiles = ['gateway.lock', 'runtime.lock', 'hermes.pid'];
    for (final lock in lockFiles) {
      final f = File('$userHome\\.hermes\\$lock');
      for (int i = 0; i < 10; i++) {
        if (!await f.exists()) break;
        try {
          await f.delete();
          break;
        } catch (_) {
          // 进程还在占锁，等 300ms 再试
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    // 启动 Gateway 守护进程（不等待退出）
    // runInShell: false → Process.kill() 直接杀 hermes.exe（不经过 cmd.exe），避免锁残留
    _embeddedGatewayProcess = await Process.start(
      exePath,
      ['gateway', 'run'],
      runInShell: false,
      workingDirectory: '$userHome\\.hermes',
    );
    // 捕获 stderr 用于诊断启动失败原因
    _lastEmbeddedStderr = '';
    _embeddedGatewayProcess!.stderr.listen((chunk) {
      _lastEmbeddedStderr += utf8.decode(chunk, allowMalformed: true);
    });
    // 后台监听退出，以便后续重启
    final proc = _embeddedGatewayProcess!;
    proc.exitCode.then((code) {
      _embeddedGatewayExited = true;
      if (_embeddedGatewayProcess != proc) return;
      if (code != 0 && _lastEmbeddedStderr.isEmpty) {
        _lastEmbeddedStderr = 'process exited with code $code';
      }
      if (state.mode == ConnectionMode.embedded &&
          state.status == ConnStatus.connected) {
        _ensureEmbeddedGatewayRunning();
      }
    });

    // 等待就绪（最长 15s），同时检查进程是否还在运行
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (_embeddedGatewayExited) {
        break;
      }
      if (await _checkHealth(state.port)) { _restartingEmbedded = false; return true; }
    }
    _restartingEmbedded = false;
    return false;
  }

  Future<bool> restartEmbeddedGateway() async {
    if (state.mode != ConnectionMode.embedded) return false;
    _embeddedGatewayExited = false;
    final oldProcess = _embeddedGatewayProcess;
    _embeddedGatewayProcess = null;
    oldProcess?.kill();
    await Future.delayed(const Duration(milliseconds: 500));
    return _ensureEmbeddedGatewayRunning();
  }

  Future<void> switchToRemote(SshConfig config) async {
    await connectRemote(config);
  }

  Future<void> disconnect() async {
    _embeddedGatewayExited = false;
    // 先置 null 再杀进程，防止 exitCode.then 触发自动重启
    final oldProcess = _embeddedGatewayProcess;
    _embeddedGatewayProcess = null;
    oldProcess?.kill();
    await Future.wait([
      _remoteBridge.disconnect(),
      _wslBridge.disconnect(),
      _embeddedBridge.disconnect(),
    ]);
    // 清理内嵌模式锁文件，先杀残留进程再删锁
    final userHome = Platform.environment['USERPROFILE'] ?? '';
    await Process.run('taskkill', ['/F', '/IM', 'hermes.exe']);
    for (final lock in ['gateway.lock', 'runtime.lock', 'hermes.pid', 'auth.lock']) {
      final f = File('$userHome\\.hermes\\$lock');
      if (await f.exists()) try { await f.delete(); } catch (_) {}
    }
    _tunnelPort = 0;
    stateNotifier.value = state.copyWith(status: ConnStatus.disconnected);
  }

  void _startHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (state.status == ConnStatus.connected || state.status == ConnStatus.error) {
        final ok = await checkLocal();
        if (!ok) {
          if (state.mode == ConnectionMode.remote) {
            final c = _remoteExecutor.config;
            if (c != null) {
              await _reconnectRemote(c);
            }
          } else if (state.mode == ConnectionMode.embedded) {
            final restarted = await _ensureEmbeddedGatewayRunning();
            if (restarted && state.status != ConnStatus.connected) {
              stateNotifier.value = state.copyWith(
                status: ConnStatus.connected,
                message: '内嵌模式',
              );
            }
          }
        }
      }
    });
  }

  static String remoteNamespaceOf(SshConfig c) =>
      '${c.user}_${c.host}'.replaceAll('.', '_');
  String get gatewayUrl =>
      'http://localhost:${_tunnelPort > 0 ? _tunnelPort : state.port}';

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
      return state.port + 1000;
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
    if (!config.containsKey('local')) config['local'] = <String, dynamic>{};
    (config['local'] as Map<String, dynamic>)['wsl_distro'] = d;
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
      final cpuR = await runShell("head -1 /proc/stat", allowFailure: true);
      double cpu = 0.0;
      final cpuLine = cpuR.stdout.trim();
      if (cpuLine.startsWith('cpu ')) {
        final parts = cpuLine.split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          final user = int.tryParse(parts[1]) ?? 0;
          final nice = int.tryParse(parts[2]) ?? 0;
          final system = int.tryParse(parts[3]) ?? 0;
          final idle = int.tryParse(parts[4]) ?? 0;
          final total = user + nice + system + idle;
          if (total > 0) cpu = (user + nice + system) * 100.0 / total;
        }
      }

      final memR = await runShell(
        "free -m | awk '/^Mem:/ {printf \"MEM:%s|%s\\n\", \$3, \$2}'",
        allowFailure: true);
      int memUsed = 0, memTotal = 0;
      final memLine = memR.stdout.trim();
      if (memLine.startsWith('MEM:')) {
        final parts = memLine.substring(4).split('|');
        memUsed = int.tryParse(parts.first) ?? 0;
        memTotal = int.tryParse(parts.last) ?? 0;
      }

      final diskR = await runShell(
        "df -h / | awk 'NR==2 {printf \"DISK:%s|%s\\n\", \$3, \$2}'",
        allowFailure: true);
      String diskUsed = '', diskTotal = '';
      final diskLine = diskR.stdout.trim();
      if (diskLine.startsWith('DISK:')) {
        final parts = diskLine.substring(5).split('|');
        diskUsed = parts.isNotEmpty ? parts.first : '';
        diskTotal = parts.length > 1 ? parts.last : '';
      }

      final upR = await runShell(
        "uptime -p | awk '{printf \"UPTIME:%s\\n\", \$0}'",
        allowFailure: true);
      final uptime = upR.stdout.trim().startsWith('UPTIME:')
          ? upR.stdout.trim().substring(7)
          : '';
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
        'disk': {'used': '0B', 'total': '0B'},
        'uptime': 'unknown'
      };
    }
      }
    }
  }

  Future<Map<String, int>> getTokenUsage() async => {'daily': 0, 'monthly': 0};
  Future<bool> checkAndSetup() async {
    if (state.mode == ConnectionMode.embedded) {
      if (!await checkLocal()) {
        return _ensureEmbeddedGatewayRunning();
      }
      return true;
    }
    return checkLocal();
  }
  Future<bool> startLocalGateway() async {
    if (state.mode == ConnectionMode.embedded) {
      stateNotifier.value = state.copyWith(
        status: ConnStatus.connecting,
        message: '启动内嵌 Gateway...',
      );
      final ok = await _ensureEmbeddedGatewayRunning();
      stateNotifier.value = state.copyWith(
        status: ok ? ConnStatus.connected : ConnStatus.error,
        message: ok ? '内嵌模式' : '内嵌 Gateway 启动失败',
      );
      return ok;
    }
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

  Future<String> _ensureApiKey() async {
    final config = await ConfigService().readDesktopConfig();
    var key = config['api_key'] as String?;
    if (key == null || key.isEmpty) {
      key = _generateRandomKey();
      config['api_key'] = key;
      await ConfigService().writeDesktopConfig(config);
    }
    GatewayService().invalidateApiKey();
    return key;
  }

  String _generateRandomKey() {
    final random = Random();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
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
}

