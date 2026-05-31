import 'dart:io';

import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/config_service.dart';
import '../services/connection_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gateway = GatewayService();
  final _configService = ConfigService();
  final _cm = ConnectionManager();
  String _configContent = '';
  bool _loading = true;
  ConnStatus? _prevConnStatus; // 上次连接状态，用于检测状态转换

  // Connection mode
  ConnectionMode _selectedMode = ConnectionMode.local;

  // SSH form controllers
  final _hostController = TextEditingController();
  final _sshPortController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();

  // Port override
  final _portController = TextEditingController(text: '8642');

  // Connection testing
  bool _testingConnection = false;
  String? _connectionMessage;
  bool? _connectionSuccess;

  // Model config
  Map<String, String> _modelConfig = {'model': '-', 'provider': '-', 'base_url': '-'};
  String _hermesVersion = '-';

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadConnectionState();
    _cm.stateNotifier.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    _cm.stateNotifier.removeListener(_onConnectionChanged);
    _hostController.dispose();
    _sshPortController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    final state = _cm.state;
    final justConnected = _prevConnStatus != ConnStatus.connected &&
        state.status == ConnStatus.connected;
    _prevConnStatus = state.status;

    setState(() {
      _connectionMessage = state.message;
      _connectionSuccess = state.status == ConnStatus.connected;
    });

    if (justConnected) {
      // 无论哪种模式，连接成功后都重新加载配置
      _loadConfig();
    }
  }

  Future<void> _loadConnectionState() async {
    final state = _cm.state;
    setState(() {
      _selectedMode = state.mode;
      _portController.text = state.port.toString();
      _connectionMessage = state.message;
      _connectionSuccess = state.status == ConnStatus.connected;
    });

    // Load saved SSH config
    final config = await _configService.readDesktopConfig();
    final ssh = config['ssh_config'] as Map<String, dynamic>?;
    if (ssh != null) {
      setState(() {
        _hostController.text = ssh['host'] ?? '';
        _sshPortController.text = (ssh['port'] ?? 22).toString();
        _userController.text = ssh['user'] ?? '';
        _passwordController.text = ssh['password'] ?? '';
      });
    }
  }

  /// Shell-escape a string for single-quote usage on Linux
  String _shellQuote(String s) {
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_sshPortController.text.trim()) ?? 22;
    final user = _userController.text.trim();
    final password = _passwordController.text.trim();

    if (host.isEmpty || user.isEmpty) {
      setState(() { _connectionMessage = '请填写主机地址和用户名'; _connectionSuccess = false; });
      return;
    }
    if (password.isEmpty) {
      setState(() { _connectionMessage = '请填写 SSH 密码'; _connectionSuccess = false; });
      return;
    }

    setState(() { _testingConnection = true; _connectionMessage = null; _connectionSuccess = null; });

    try {
      final buf = StringBuffer('sshpass -p ${_shellQuote(password)} ssh');
      buf.write(' -o ConnectTimeout=5');
      buf.write(' -o StrictHostKeyChecking=accept-new');
      if (port != 22) buf.write(' -p $port');
      buf.write(' ${_shellQuote('$user@$host')}');
      buf.write(' exit');

      final result = await Process.run('wsl.exe', ['-d', 'Ubuntu', 'bash', '-c', buf.toString()]);
      if (result.exitCode == 0) {
        setState(() { _connectionMessage = 'SSH 连接成功 ✓'; _connectionSuccess = true; });
      } else {
        final err = (result.stderr as String).trim();
        setState(() { _connectionMessage = err.isNotEmpty ? err : '连接失败'; _connectionSuccess = false; });
      }
    } catch (e) {
      setState(() { _connectionMessage = '连接异常: $e'; _connectionSuccess = false; });
    } finally {
      setState(() => _testingConnection = false);
    }
  }

  Future<void> _saveConnectionConfig() async {
    final config = await _configService.readDesktopConfig();
    config['connection_mode'] = _selectedMode == ConnectionMode.remote
        ? 'remote'
        : (_selectedMode == ConnectionMode.embedded ? 'embedded' : 'local');
    config['local_port'] = int.tryParse(_portController.text.trim()) ?? 8642;
    config['ssh_config'] = {
      'host': _hostController.text.trim(),
      'port': int.tryParse(_sshPortController.text.trim()) ?? 22,
      'user': _userController.text.trim(),
      'password': _passwordController.text.trim(),
    };
    await _configService.writeDesktopConfig(config);

    if (_selectedMode == ConnectionMode.local) {
      await _cm.switchToLocal();
    } else if (_selectedMode == ConnectionMode.embedded) {
      final ok = await _ensureEmbeddedInstalled();
      if (ok) await _cm.switchToEmbedded();
    } else {
      final host = _hostController.text.trim();
      final sshConfig = SshConfig(
        host: host,
        port: int.tryParse(_sshPortController.text.trim()) ?? 22,
        user: _userController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await _cm.switchToRemote(sshConfig);
      if (mounted) _loadConnectionState();
    }

    if (mounted) {
      final st = _cm.state;
      if (st.status == ConnStatus.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_selectedMode == ConnectionMode.remote ? "远程" : _selectedMode == ConnectionMode.embedded ? "内嵌" : "本地"}连接成功')),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('连接失败'),
            content: Text(st.message.isNotEmpty ? st.message : '请检查配置后重试'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
            ],
          ),
        );
      }
    }
  }

  /// Ensure embedded Hermes is installed, auto-download if missing
  Future<bool> _ensureEmbeddedInstalled() async {
    final exePath = '${_cm.hermesBundlePath}\\hermes.exe';
    if (await File(exePath).exists()) return true;

    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EmbeddedInstallDialog(
        downloadUrl: ConnectionManager.defaultHermesDownloadUrl,
      ),
    );
    return ok ?? false;
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    final content = await _configService.readConfig();
    final modelCfg = await _configService.readModelConfig();
    final version = await _detectHermesVersion();
    setState(() {
      _configContent = content;
      _modelConfig = modelCfg;
      _hermesVersion = version;
      _loading = false;
    });
  }

  /// 通过 CLI「hermes --version」获取真实版本号，适配三种模式
  Future<String> _detectHermesVersion() async {
    // 优先从 Gateway 状态获取（如果 gateway 返回了 version 字段）
    try {
      final status = await _gateway.getStatus();
      final v = status['version'] as String?;
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}

    final mode = _cm.state.mode;
    if (mode == ConnectionMode.embedded) {
      try {
        final exePath = '${_cm.hermesBundlePath}\\hermes.exe';
        if (await File(exePath).exists()) {
          final r = await Process.run(exePath, ['--version']);
          if (r.exitCode == 0) return (r.stdout as String).trim();
        }
        final r = await Process.run('hermes', ['--version']);
        if (r.exitCode == 0) return (r.stdout as String).trim();
      } catch (_) {}
    } else if (_cm.state.status == ConnStatus.connected) {
      final r = await _cm.runShell('hermes --version 2>/dev/null', allowFailure: true);
      if (r.exitCode == 0) {
        final v = r.stdout.trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '-';
  }

  Future<void> _saveConfig(String content) async {
    final success = await _configService.writeConfig(content);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '配置已保存' : '保存失败'),
          backgroundColor: success ? AppTheme.success : AppTheme.error,
        ),
      );
      if (success) _loadConfig();
    }
  }

  void _showGatewayUrlEditor(String currentUrl) {
    final controller = TextEditingController(text: currentUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gateway 地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('设置 Hermes Gateway 地址。\n本地: http://localhost:8642\n远程: http://服务器IP:8642',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'http://localhost:8642',
                prefixIcon: Icon(Icons.link),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await _configService.setGatewayUrl(url);
                await _gateway.refreshBaseUrl();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gateway 地址已更新，重启应用后生效')),
                  );
                }
              }
              Navigator.pop(ctx);
              _loadConfig();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showEnvEditor() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EnvEditorDialog(),
    );
  }

  Future<void> _restartGateway() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重启 Gateway'),
        content: const Text('确定要重启 Hermes Gateway 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重启')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _gateway.restartGateway();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gateway 正在重启...')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重启失败: $e')),
          );
        }
      }
    }
  }

  void _showConfigEditor() {
    final controller = TextEditingController(text: _configContent);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text('编辑 config.yaml'),
            Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '~/.hermes/config.yaml',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 450,
          child: Column(
            children: [
              // 提示栏
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.info.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppTheme.info),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '编辑后点击"保存并重启"将自动写入 ~/.hermes/config.yaml 并重启 Gateway 生效。',
                        style: TextStyle(fontSize: 11, color: AppTheme.info),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                    hintText: '# YAML 配置内容...',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          OutlinedButton(
            onPressed: () {
              _saveConfig(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('仅保存'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              _saveConfig(controller.text);
              Navigator.pop(ctx);
              _restartGateway();
            },
            child: const Text('保存并重启 Gateway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton.icon(
            onPressed: _restartGateway,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('重启 Gateway'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.warning),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Connection Mode Section ──
                _buildSection('连接模式', [
                  _buildConnectionModeSelector(colorScheme),
                ]),
                const SizedBox(height: 16),

                // ── SSH Config Section (remote only) ──
                if (_selectedMode == ConnectionMode.remote) ...[
                  _buildSection('SSH 远程配置', [
                    _buildSshConfigForm(colorScheme),
                    const SizedBox(height: 12),
                    _buildTestConnectionRow(colorScheme),
                    if (_connectionMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _buildStatusBanner(colorScheme),
                      ),
                  ]),
                  const SizedBox(height: 16),
                ],

                // ── Port Override Section (not needed in remote mode — port auto-handled) ──
                if (_selectedMode != ConnectionMode.remote)
                  _buildSection('端口设置', [
                    _buildPortOverrideField(colorScheme),
                  ]),
                if (_selectedMode != ConnectionMode.remote) const SizedBox(height: 16),

                // ── Apply Button ──
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _cm.state.status == ConnStatus.connecting ? null : _saveConnectionConfig,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('应用连接配置'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Gateway 管理 ──
                _buildGatewayManagementSection(colorScheme),
                const SizedBox(height: 24),

                // ── Model section ──
                _buildSection('模型配置', [
                  _buildSettingRow('当前模型', _modelConfig['model'] ?? '-'),
                  _buildSettingRow('Provider', _modelConfig['provider'] ?? '-'),
                  _buildSettingRow('API 地址', _modelConfig['base_url'] ?? '-'),
                ]),
                SizedBox(height: 16),

                // ── Display section ──
                _buildSection('显示设置', [
                  _buildThemeToggle(),
                  _buildThemeColorPicker(),
                  _buildSettingRow('UI 语言', '简体中文'),
                ]),
                SizedBox(height: 16),

                // ── Gateway section (hidden in remote — tunnel URL auto-set) ──
                if (_selectedMode != ConnectionMode.remote) ...[
                  _buildSection('Gateway 设置', [
                    FutureBuilder<String>(
                      future: _configService.getGatewayUrl(),
                      builder: (context, snapshot) {
                        final url = snapshot.data ?? 'http://localhost:8642';
                        return ListTile(
                          title: Row(
                            children: [
                              Text('Gateway 地址',
                                  style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('什么是 Gateway?'),
                                      content: const Text(
                                        'Hermes Gateway 是 Hermes Desktop 与 Hermes Agent 之间的桥梁。\n\n'
                                        '• 本地模式: Gateway 运行在本机 localhost:8642\n'
                                        '• 远程模式: Gateway 运行在远程服务器上，通过 SSH 连接\n\n'
                                        'Gateway 负责转发会话请求、管理令牌、提供机器状态和令牌用量统计等功能。'
                                        '请确保 Gateway 地址与服务器实际监听地址一致。',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('知道了'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: Icon(Icons.help_outline, size: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          subtitle: Text(url,
                              style: TextStyle(
                                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontFamily: 'monospace')),
                          trailing: const Icon(Icons.edit_outlined, size: 20),
                          onTap: () => _showGatewayUrlEditor(url),
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
                    _buildSettingRow('超时时间', '30 分钟'),
                    _buildSettingRow('日志级别', 'INFO'),
                  ]),
                  SizedBox(height: 16),
                ],

                // ── Config file ──
                _buildSection('配置文件', [
                  ListTile(
                    title: Text('编辑 config.yaml',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text('~/.hermes/config.yaml',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    trailing: Icon(Icons.edit_outlined, size: 20),
                    onTap: _showConfigEditor,
                    contentPadding: EdgeInsets.zero,
                  ),
                  ListTile(
                    title: Text('编辑 .env',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text('~/.hermes/.env',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: _showEnvEditor,
                    contentPadding: EdgeInsets.zero,
                  ),
                ]),
                const SizedBox(height: 16),

                // ── About ──
                _buildSection('关于', [
                  _buildSettingRow('Hermes Desktop', 'v1.0.0'),
                  _buildSettingRow('Hermes Agent', _hermesVersion.split('\n').first),
                  _buildSettingRow('项目地址',
                      'github.com/lovesmile/hermes-desktop-ui'),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════
  //  Connection mode widget
  // ═══════════════════════════════════════════

  Widget _buildConnectionModeSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择 Gateway 运行模式',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildModeRadio(
                value: ConnectionMode.local,
                title: '本地',
                subtitle: '本地运行 Gateway',
                icon: Icons.computer,
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModeRadio(
                value: ConnectionMode.embedded,
                title: '内嵌',
                subtitle: 'Windows 内嵌运行',
                icon: Icons.memory,
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModeRadio(
                value: ConnectionMode.remote,
                title: '远程',
                subtitle: '通过 SSH 连接远程服务器',
                icon: Icons.cloud,
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),

        // Connection status indicator
        const SizedBox(height: 12),
        _buildConnectionStatusRow(colorScheme),
      ],
    );
  }

  Widget _buildModeRadio({
    required ConnectionMode value,
    required String title,
    required String subtitle,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final selected = _selectedMode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_selectedMode == value) return;
        setState(() {
          _selectedMode = value;
          _connectionSuccess = null;
          _connectionMessage = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Radio<ConnectionMode>(
              value: value,
              groupValue: _selectedMode,
              onChanged: (v) {
                if (_selectedMode == v) return;
                setState(() {
                  _selectedMode = v!;
                  _connectionSuccess = null;
                  _connectionMessage = null;
                });
              },
              activeColor: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              icon,
              size: 22,
              color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusRow(ColorScheme colorScheme) {
    final state = _cm.state;
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (state.status) {
      case ConnStatus.connected:
        statusColor = AppTheme.success;
        statusText = '已连接';
        statusIcon = Icons.check_circle;
        break;
      case ConnStatus.connecting:
        statusColor = AppTheme.warning;
        statusText = '连接中...';
        statusIcon = Icons.sync;
        break;
      case ConnStatus.error:
        statusColor = AppTheme.error;
        statusText = '连接错误';
        statusIcon = Icons.error;
        break;
      case ConnStatus.disconnected:
        statusColor = colorScheme.onSurfaceVariant;
        statusText = '未连接';
        statusIcon = Icons.circle_outlined;
        break;
    }

    final modeText = switch (state.mode) {
      ConnectionMode.local => '本地',
      ConnectionMode.embedded => '内嵌',
      ConnectionMode.remote => '远程',
    };
    final portText = state.port.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 16),
          Text(
            '$modeText 模式',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Text(
            '端口: $portText',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
          ),
          const Spacer(),
          if (state.message.isNotEmpty)
            Flexible(
              child: Text(
                state.message,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  SSH config form
  // ═══════════════════════════════════════════

  Widget _buildSshConfigForm(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 主机地址 ──
        TextField(
          controller: _hostController,
          decoration: const InputDecoration(
            labelText: '主机地址',
            hintText: '192.168.1.100 或 example.com',
            prefixIcon: Icon(Icons.dns_outlined, size: 20),
            helperText: '服务器 IP 地址，如 192.168.1.100',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),

        // ── 用户名 + SSH 端口 ──
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  hintText: 'root',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                  helperText: '登录远程服务器的用户名',
                  helperMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _sshPortController,
                decoration: const InputDecoration(
                  labelText: 'SSH 端口',
                  hintText: '22',
                  prefixIcon: Icon(Icons.settings_ethernet, size: 20),
                  helperText: '默认 22',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── SSH 密码 ──
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码',
            hintText: 'SSH 登录密码',
            prefixIcon: Icon(Icons.lock_outline, size: 20),
            helperText: '远程服务器的 SSH 登录密码，首次连接后自动切换为密钥认证',
            helperMaxLines: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildTestConnectionRow(ColorScheme colorScheme) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _testingConnection ? null : _testConnection,
          icon: _testingConnection
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : Icon(Icons.wifi_find, size: 18),
          label: Text(_testingConnection ? '测试中...' : '测试连接'),
        ),
        const SizedBox(width: 12),
        if (_connectionSuccess == true)
          Icon(Icons.check_circle, size: 20, color: AppTheme.success)
        else if (_connectionSuccess == false)
          Icon(Icons.cancel, size: 20, color: AppTheme.error),
      ],
    );
  }

  Widget _buildStatusBanner(ColorScheme colorScheme) {
    final isSuccess = _connectionSuccess == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isSuccess
            ? AppTheme.success.withValues(alpha: 0.1)
            : AppTheme.error.withValues(alpha: 0.1),
        border: Border.all(
          color: isSuccess
              ? AppTheme.success.withValues(alpha: 0.3)
              : AppTheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: isSuccess ? AppTheme.success : AppTheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _connectionMessage ?? '',
              style: TextStyle(
                fontSize: 12,
                color: isSuccess ? AppTheme.success : AppTheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Port override
  // ═══════════════════════════════════════════

  Widget _buildPortOverrideField(ColorScheme colorScheme) {
    return TextField(
      controller: _portController,
      decoration: InputDecoration(
        labelText: _selectedMode == ConnectionMode.remote ? '远程 Gateway 端口' : 'Gateway 端口',
        hintText: '8642',
        prefixIcon: Icon(Icons.router_outlined, size: 20),
        helperText: _selectedMode == ConnectionMode.remote
            ? '远程服务器上 Hermes Gateway 的监听端口，默认 8642'
            : '默认 8642，修改后需要保存配置并重启 Gateway',
        helperMaxLines: 2,
      ),
      keyboardType: TextInputType.number,
    );
  }

  // ═══════════════════════════════════════════
  //  Gateway management section
  // ═══════════════════════════════════════════

  Widget _buildGatewayManagementSection(ColorScheme colorScheme) {
    return _buildSection('Gateway 管理', [
      // Running status
      ValueListenableBuilder<ConnectionInfo>(
        valueListenable: _cm.stateNotifier,
        builder: (context, conn, _) {
          final isRunning = conn.status == ConnStatus.connected;
          return ListTile(
            title: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isRunning ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isRunning ? '运行中' : '已停止',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            subtitle: Text(
              conn.status == ConnStatus.connected
                  ? '本地 Gateway 正常运行'
                  : conn.status == ConnStatus.connecting
                      ? '正在启动...'
                      : conn.message.isNotEmpty
                          ? conn.message
                          : 'Gateway 未运行',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            contentPadding: EdgeInsets.zero,
          );
        },
      ),
      const Divider(height: 16),
      // Version info
      _buildSettingRow('版本信息', _hermesVersion),
      const Divider(height: 16),
      // Control buttons
      ValueListenableBuilder<ConnectionInfo>(
        valueListenable: _cm.stateNotifier,
        builder: (context, conn, _) {
          final isRunning = conn.status == ConnStatus.connected;
          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (isRunning || conn.status == ConnStatus.connecting)
                      ? null
                      : () => _cm.startLocalGateway(),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('启动'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRunning ? () => _cm.disconnect() : null,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRunning ? _restartGateway : null,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('重启'),
                ),
              ),
            ],
          );
        },
      ),
    ]);
  }

  // ═══════════════════════════════════════════
  //  Shared helpers
  // ═══════════════════════════════════════════

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '主题',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          Text(
            themeModeNotifier.value ? '深色主题' : '浅色主题',
            style: const TextStyle(fontSize: 14),
          ),
          const Spacer(),
          Switch(
            value: themeModeNotifier.value,
            onChanged: (_) => themeModeNotifier.toggle(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeColorPicker() {
    final cs = Theme.of(context).colorScheme;
    final currentIdx = themeColorNotifier.value;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题色',
              style: TextStyle(fontSize: 14, color: cs.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(AppTheme.seedColors.length, (i) {
              final selected = i == currentIdx;
              return Tooltip(
                message: AppTheme.themeNames[i],
                preferBelow: false,
                child: GestureDetector(
                onTap: () async {
                  themeColorNotifier.value = i;
                  final cfg = await _configService.readDesktopConfig();
                  cfg['theme_color'] = i;
                  await _configService.writeDesktopConfig(cfg);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.seedColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : cs.outlineVariant,
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 6)]
                        : null,
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// .env 文件编辑器弹窗
class _EnvEditorDialog extends StatefulWidget {
  @override
  State<_EnvEditorDialog> createState() => _EnvEditorDialogState();
}

class _EnvEditorDialogState extends State<_EnvEditorDialog> {
  final _configService = ConfigService();
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final content = await _configService.readEnvFile();
    if (mounted) {
      setState(() {
        _controller.text = content;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final success = await _configService.writeEnvFile(_controller.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '.env 已保存' : '保存失败'),
          backgroundColor: success ? AppTheme.success : AppTheme.error,
        ),
      );
      if (success) Navigator.pop(context);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('编辑 .env'),
          const Spacer(),
          Text('~/.hermes/.env',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 450,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                  hintText: '# .env 配置内容...',
                ),
              ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('保存'),
        ),
      ],
    );
  }
}

/// 内嵌 Hermes 下载安装对话框
class _EmbeddedInstallDialog extends StatefulWidget {
  final String downloadUrl;

  const _EmbeddedInstallDialog({required this.downloadUrl});

  @override
  State<_EmbeddedInstallDialog> createState() => _EmbeddedInstallDialogState();
}

class _EmbeddedInstallDialogState extends State<_EmbeddedInstallDialog> {
  String _status = '正在下载...';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _startInstall();
  }

  Future<void> _startInstall() async {
    final cm = ConnectionManager();
    try {
      setState(() => _status = '正在下载内嵌 Hermes...');
      final zipPath = await cm.downloadHermesBundle(
        widget.downloadUrl,
        onProgress: (received, total) {
          if (!mounted) return;
          final pct = total > 0 ? (received * 100 ~/ total) : 0;
          setState(() => _status = '正在下载内嵌 Hermes... $pct%');
        },
      );
      if (!mounted) return;

      setState(() => _status = '正在安装...');
      await cm.extractBundle(zipPath);
      if (!mounted) return;

      final exePath = '${cm.hermesBundlePath}\hermes.exe';
      if (!await File(exePath).exists()) {
        setState(() {
          _status = '安装失败：解压后未找到 hermes.exe';
          _failed = true;
        });
        return;
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '下载或安装失败: $e';
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('安装内嵌 Hermes'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_failed)
              Icon(Icons.error_outline, size: 48, color: AppTheme.error)
            else
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            const SizedBox(height: 20),
            Text(_status, style: TextStyle(color: cs.onSurface)),
            if (_failed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _failed = false;
                          _status = '正在下载...';
                        });
                        _startInstall();
                      },
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
