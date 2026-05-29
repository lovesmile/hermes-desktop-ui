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
        ConnectionInfo(status: ConnStatus.disconnected, mode: mode, port: port);

    _startHealthCheck();
    if (mode == ConnectionMode.remote && ssh.isValid) {
      await connectRemote(ssh);
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
    if (state.mode == ConnectionMode.embedded) {
      final userHome = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      return '$userHome\\.hermes';
    }
    final r = await runShell('echo \$HOME', allowFailure: true);
    final home = r.stdout.trim().isNotEmpty ? r.stdout.trim() : r'$HOME';
    return '$home/.hermes';
  }

  Future<({String stdout, int exitCode})> readTextFile(
    String path, {
    bool allowFailure = false,
  }) {
    if (state.mode == ConnectionMode.embedded) {
      return runShell('type "${path.replaceAll('"', '""')}" 2>nul',
          allowFailure: allowFailure);
    }
    return runShell("cat '${path.replaceAll("'", "'\\''")}' 2>/dev/null",
        allowFailure: allowFailure);
  }

  Future<({String stdout, int exitCode})> runHermesCron(
    List<String> args, {
    bool allowFailure = false,
  }) {
    if (state.mode == ConnectionMode.embedded) {
      final hermesExe = '$hermesBundlePath\\hermes.exe';
      final joined = args.map((a) => '"${a.replaceAll('"', '""')}"').join(' ');
      final cmd =
          'if exist "${hermesExe.replaceAll('"', '""')}" ( "${hermesExe.replaceAll('"', '""')}" --accept-hooks cron $joined ) else ( hermes --accept-hooks cron $joined ) 2>&1';
      return runShell(cmd, allowFailure: allowFailure);
    }

    final joined = args.map((a) => "'${a.replaceAll("'", "'\\''")}'").join(' ');
    final cmd = 'export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"; '
        'HERMES_BIN="\$(command -v hermes 2>/dev/null || true)"; '
        'if [ -z "\$HERMES_BIN" ] && [ -x "\$HOME/.local/bin/hermes" ]; then HERMES_BIN="\$HOME/.local/bin/hermes"; fi; '
        'if [ -z "\$HERMES_BIN" ] && [ -f "\$HOME/.local/bin/hermes" ]; then HERMES_BIN="\$HOME/.local/bin/hermes"; fi; '
        'if [ -z "\$HERMES_BIN" ]; then echo "hermes command not found"; exit 127; fi; '
        '"\$HERMES_BIN" --accept-hooks cron $joined 2>&1';
    return runShell(cmd, allowFailure: allowFailure);
  }

  String _normalizeCronCommand(String cmd) {
    final trim = cmd.trim();
    if (!trim.startsWith('hermes --accept-hooks cron ')) return cmd;

    final suffix = trim.substring('hermes --accept-hooks cron '.length);

    if (state.mode == ConnectionMode.embedded) {
      final hermesExe = '$hermesBundlePath\\hermes.exe'.replaceAll('"', '""');
      return 'if exist "$hermesExe" ( "$hermesExe" --accept-hooks cron $suffix ) else ( hermes --accept-hooks cron $suffix )';
    }

    return 'export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"; '
        'HERMES_BIN="\$(command -v hermes 2>/dev/null || true)"; '
        'if [ -z "\$HERMES_BIN" ] && [ -x "\$HOME/.local/bin/hermes" ]; then HERMES_BIN="\$HOME/.local/bin/hermes"; fi; '
        'if [ -z "\$HERMES_BIN" ] && [ -f "\$HOME/.local/bin/hermes" ]; then HERMES_BIN="\$HOME/.local/bin/hermes"; fi; '
        'if [ -z "\$HERMES_BIN" ]; then echo "hermes command not found"; exit 127; fi; '
        '"\$HERMES_BIN" --accept-hooks cron $suffix';
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

  Future<String> execRemote(String command) async {
    final out = await _remoteBridge.exec(command);
    if (out.exitCode != 0) {
      throw Exception(out.stderr.isEmpty ? 'Remote command failed' : out.stderr);
    }
    return out.stdout;
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

  Future<bool> connectRemote(SshConfig config) async {
    await disconnect();
    stateNotifier.value = state.copyWith(
      status: ConnStatus.connecting,
      mode: ConnectionMode.remote,
      message: '正在连接远程...',
    );

    if (await _remoteBridge.connect(
      config: SshConfigWrapper(config),
      localPort: state.port,
    )) {
      final ns = remoteNamespaceOf(config);
      await _applyConnectionContext(namespace: ns, serverId: config.host);
      stateNotifier.value =
          state.copyWith(status: ConnStatus.connected, message: '远程已连接');
      return true;
    }

    stateNotifier.value = state.copyWith(
      status: ConnStatus.error,
      message: '连接失败',
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
            await connectRemote(c);
          }
        }
      }
    });
  }

  static String remoteNamespaceOf(SshConfig c) =>
      '${c.user}_${c.host}'.replaceAll('.', '_');
  String get gatewayUrl => 'http://localhost:${state.port}';

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
    try {
      final cpu = await runShell(
        "grep 'cpu ' /proc/stat | awk '{usage=(\$2+\$4)*100/(\$2+\$4+\$5)} END {printf \"%.1f\", usage}'",
        allowFailure: true,
      );
      final mem = await runShell(
        "free -m | awk '/^Mem:/ {print \$3 \"|\" \$2}'",
        allowFailure: true,
      );
      final disk = await runShell(
        "df -h / | awk 'NR==2 {print \$3 \"|\" \$2}'",
        allowFailure: true,
      );
      final uptime = await runShell('uptime -p', allowFailure: true);
      final mParts = mem.stdout.trim().split('|');
      final dParts = disk.stdout.trim().split('|');
      return {
        'cpu': double.tryParse(cpu.stdout) ?? 0.0,
        'memory': {
          'used': int.tryParse(mParts.first) ?? 0,
          'total': int.tryParse(mParts.last) ?? 0,
        },
        'disk': {'used': dParts.first, 'total': dParts.last},
        'uptime': uptime.stdout.trim(),
      };
    } catch (_) {
      return {
        'cpu': 0.0,
        'memory': {'used': 0, 'total': 0},
        'uptime': 'unknown'
      };
    }
  }

  Future<Map<String, int>> getTokenUsage() async => {'daily': 0, 'monthly': 0};
  Future<bool> checkAndSetup() async => checkLocal();
  Future<bool> startLocalGateway() async => checkLocal();

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
    ConfigService().setMode(namespace);
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
