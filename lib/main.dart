import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config/theme.dart';
import 'services/config_service.dart';
import 'services/connection_manager.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/platforms_screen.dart';
import 'screens/cron_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/file_browser_screen.dart';
import 'screens/models_screen.dart' as ms;
import 'services/snack_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1080, 720),
    center: true,
    title: 'Hermes Desktop',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await ConnectionManager().init();
  runApp(HermesDesktopApp());
}

class HermesDesktopApp extends StatefulWidget {
  @override
  State<HermesDesktopApp> createState() => _HermesDesktopAppState();
}

class _HermesDesktopAppState extends State<HermesDesktopApp> {
  @override
  void initState() {
    super.initState();
    themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Desktop',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeModeNotifier.value ? ThemeMode.dark : ThemeMode.light,
      scaffoldMessengerKey: rootScaffoldKey,
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _firstCheckDone = false;
  bool _isMaximized = false;

  final ValueNotifier<int> tabNotifier = ValueNotifier<int>(0);

  static final _navItems = [
    (Icons.dashboard_outlined, Icons.dashboard, '仪表盘'),
    (Icons.chat_outlined, Icons.chat, '聊天'),
    (Icons.devices_outlined, Icons.devices, '平台'),
    (Icons.schedule_outlined, Icons.schedule, '定时'),
    (Icons.article_outlined, Icons.article, '日志'),
    (Icons.memory_outlined, Icons.memory, '模型与技能'),
    (Icons.folder_outlined, Icons.folder, '文件'),
    (Icons.settings_outlined, Icons.settings, '设置'),
  ];

  void navigateTo(int index) {
    tabNotifier.value = index;
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    _checkMaximized();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstSetup();
    });
    ConnectionManager().setupNotifier.addListener(_onSetupStateChanged);
  }

  Future<void> _checkMaximized() async {
    try {
      final maxed = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maxed);
    } catch (_) {}
  }

  @override
  void dispose() {
    ConnectionManager().setupNotifier.removeListener(_onSetupStateChanged);
    super.dispose();
  }

  Future<void> _checkFirstSetup() async {
    if (_firstCheckDone) return;
    _firstCheckDone = true;

    final configService = ConfigService();
    final desktopConfig = await configService.readDesktopConfig();
    final hasGatewayUrl = desktopConfig.containsKey('gateway_url') &&
        (desktopConfig['gateway_url'] as String?)?.isNotEmpty == true;
    final hasApiKey = desktopConfig.containsKey('api_key') &&
        (desktopConfig['api_key'] as String?)?.isNotEmpty == true;

    if (!hasGatewayUrl || !hasApiKey) {
      // 先检测本地 WSL/hermes 环境
      final hasLocalHermes = await _detectLocalHermes();
      _showSetupWizard(detected: hasLocalHermes);
      return;
    }

    final ok = await ConnectionManager().checkAndSetup();
    if (!ok && mounted) {
      _showSetupDialog();
    }
  }

  /// 检测本地是否有 WSL 和 Hermes
  Future<bool> _detectLocalHermes() async {
    try {
      // 检查 WSL 是否可用
      final wslResult = await Process.run('wsl.exe', ['--list', '--quiet']);
      if (wslResult.exitCode != 0) return false;
      final distros = (wslResult.stdout as String)
          .split('\n')
          .map((s) => s.trim().replaceAll('\x00', ''))
          .where((s) => s.isNotEmpty)
          .toList();
      if (distros.isEmpty) return false;

      // 在第一个 WSL 发行版中检查 hermes 命令
      final checkResult = await Process.run('wsl.exe', [
        '-d', distros.first, 'bash', '-c',
        'command -v hermes 2>/dev/null && echo "EXISTS" || echo ""',
      ]);
      final out = (checkResult.stdout as String).trim();
      return out.contains('EXISTS');
    } catch (_) {
      return false;
    }
  }

  void _showSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SetupScreen(
        onComplete: () {
          Navigator.pop(ctx);
          if (mounted) ConnectionManager().checkAndSetup();
        },
      ),
    );
  }

  void _showSetupWizard({bool detected = false}) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SetupWizardDialog(
        localHermesDetected: detected,
        onComplete: () {},
      ),
    );
  }

  void _onSetupStateChanged() {
    if (!mounted) return;
    final state = ConnectionManager().setupNotifier.value;
    if (state == SetupState.waitingForHermes) {
      _showHermesSetupDialog();
    }
  }

  void _showHermesSetupDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HermesDownloadDialog(),
    );
  }

  Future<void> _showHelpDialog(BuildContext context) async {
    final doc = await rootBundle.loadString('assets/support_docs.md');
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 10),
            const Text('使用帮助'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Markdown(
            data: doc,
            selectable: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final uri = Uri.parse(
                  'https://github.com/lovesmile/hermes-desktop-ui/issues');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('问题反馈'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          // ── 自定义标题栏 ──
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
              ),
            ),
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Image.asset('assets/icon.png', width: 18, height: 18),
                  const SizedBox(width: 8),
                  Text('Hermes Desktop',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface)),
                  const Spacer(),
                  SizedBox(
                    width: 32, height: 32,
                    child: IconButton(
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 14),
                      onPressed: () => themeModeNotifier.toggle(),
                      visualDensity: VisualDensity.compact,
                      tooltip: isDark ? '浅色模式' : '深色模式',
                      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 46, height: 32,
                    child: IconButton(
                      icon: const Icon(Icons.minimize, size: 14),
                      iconSize: 14,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => windowManager.minimize(),
                      tooltip: '最小化',
                      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 46, height: 32,
                    child: IconButton(
                      icon: Icon(_isMaximized ? Icons.filter_none : Icons.crop_square, size: 14),
                      iconSize: 14,
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                      tooltip: '最大化',
                      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 46, height: 32,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      iconSize: 14,
                      visualDensity: VisualDensity.compact,
                      hoverColor: Colors.red,
                      onPressed: () => windowManager.close(),
                      tooltip: '关闭',
                      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 主内容 ──
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) => navigateTo(i),
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -0.5,
                  backgroundColor: scheme.surface,
                  indicatorColor: scheme.secondaryContainer,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Image.asset('assets/icon.png', width: 40, height: 40),
                  ),
                  destinations: _navItems.map((item) {
                    return NavigationRailDestination(
                      icon: Icon(item.$1),
                      selectedIcon: Icon(item.$2, color: scheme.primary),
                      label: Text(item.$3),
                    );
                  }).toList(),
                  trailing: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        IconButton(
                          icon: const Icon(Icons.help_outline),
                          onPressed: () => _showHelpDialog(context),
                          tooltip: '帮助',
                          style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: scheme.outlineVariant),
                Expanded(
                  child: Column(
                    children: [
                      // ── 连接状态指示条 ──
                      ValueListenableBuilder<ConnectionInfo>(
                        valueListenable: ConnectionManager().stateNotifier,
                        builder: (context, conn, _) {
                          final s = Theme.of(context).colorScheme;
                          Color dotColor;
                          String label;
                          switch (conn.status) {
                            case ConnStatus.connected:
                              dotColor = Colors.green;
                              if (conn.mode == ConnectionMode.remote) {
                                final parts = conn.message.split('已连接 ');
                                final remotePart = parts.length > 1 ? parts.last : conn.message;
                                label = '远程: $remotePart';
                              } else {
                                label = '本地模式';
                              }
                              break;
                            case ConnStatus.connecting:
                              dotColor = Colors.orange;
                              label = '连接中...';
                              break;
                            case ConnStatus.disconnected:
                            case ConnStatus.error:
                              dotColor = Colors.red;
                              label = '未连接';
                              break;
                          }
                          return Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: s.surfaceContainerLow,
                              border: Border(bottom: BorderSide(color: s.outlineVariant, width: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Text(label, style: TextStyle(fontSize: 12, color: s.onSurfaceVariant)),
                              ],
                            ),
                          );
                        },
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _currentIndex,
                          children: [
                            DashboardScreen(onNavigate: navigateTo, tabNotifier: tabNotifier),
                            const ChatScreen(),
                            const PlatformsScreen(),
                            const CronScreen(),
                            const LogsScreen(),
                            ModelsScreen(onNavigate: navigateTo),
                            const FileBrowserScreen(),
                            const SettingsScreen(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 首次启动配置向导
class _SetupWizardDialog extends StatefulWidget {
  final VoidCallback onComplete;
  final bool localHermesDetected;

  const _SetupWizardDialog({required this.onComplete, this.localHermesDetected = false});

  @override
  State<_SetupWizardDialog> createState() => _SetupWizardDialogState();
}

class _SetupWizardDialogState extends State<_SetupWizardDialog> {
  final _gatewayUrlCtrl = TextEditingController(text: 'http://localhost:8642');
  final _apiKeyCtrl = TextEditingController(text: 'hermes-desktop-dev-key');
  String _selectedProvider = 'deepseek';
  String _selectedModel = 'deepseek-v4-flash';
  final _providerApiKeyCtrl = TextEditingController(text: '');
  bool _saving = false;

  // 连接模式选择（未检测到本地时启用）
  ConnectionMode _selectedMode = ConnectionMode.local;

  @override
  void initState() {
    super.initState();
    if (widget.localHermesDetected) {
      _selectedMode = ConnectionMode.local;
    }
  }

  @override
  void dispose() {
    _gatewayUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _providerApiKeyCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    setState(() => _saving = true);
    try {
      // 保存连接配置（含连接模式）
      final configService = ConfigService();
      final existingConfig = await configService.readDesktopConfig();
      existingConfig['connection_mode'] = _selectedMode == ConnectionMode.remote
          ? 'remote'
          : (_selectedMode == ConnectionMode.embedded ? 'embedded' : 'local');
      existingConfig['gateway_url'] = _gatewayUrlCtrl.text.trim();
      existingConfig['api_key'] = _apiKeyCtrl.text.trim();
      await configService.writeDesktopConfig(existingConfig);

      final hermesHome = ConfigService.resolveHermesHome();
      final configFile = File('$hermesHome/config.yaml');
      if (await configFile.exists()) {
        var content = await configFile.readAsString();
        content = content.replaceAll(
            RegExp(r'^(\s+)default:.*$', multiLine: true),
            '  default: $_selectedModel');
        content = content.replaceAll(
            RegExp(r'^(\s+)provider:.*$', multiLine: true),
            '  provider: $_selectedProvider');
        await configFile.writeAsString(content);
      }

      if (_providerApiKeyCtrl.text.trim().isNotEmpty) {
        final envFile = File('$hermesHome/.env');
        if (await envFile.exists()) {
          var envContent = await envFile.readAsString();
          final providerUpper = _selectedProvider.toUpperCase();
          final keyVar = '${providerUpper}_API_KEY';
          if (envContent.contains('$keyVar=')) {
            envContent = envContent.replaceAll(
              RegExp('^$keyVar=.*' r'$', multiLine: true),
              '$keyVar=${_providerApiKeyCtrl.text.trim()}',
            );
          } else {
            envContent += '\n$keyVar=${_providerApiKeyCtrl.text.trim()}\n';
          }
          final baseUrl = ms.providerBaseUrls[_selectedProvider] ?? '';
          if (baseUrl.isNotEmpty) {
            final urlVar = '${providerUpper}_BASE_URL';
            if (envContent.contains('$urlVar=')) {
              envContent = envContent.replaceAll(
                  RegExp('^$urlVar=.*' r'$', multiLine: true),
                  '$urlVar=$baseUrl');
            } else {
              envContent += '\n$urlVar=$baseUrl\n';
            }
          }
          await envFile.writeAsString(envContent);
        }
      }

      if (mounted) {
        // 根据选择模式尝试连接
        try {
          final cm = ConnectionManager();
          if (_selectedMode == ConnectionMode.remote) {
            // 远程模式需要 SSH 配置，这里只是记录，用户后续在设置页配置 SSH
          } else if (_selectedMode == ConnectionMode.embedded) {
            await cm.switchToEmbedded();
          } else {
            await cm.switchToLocal();
          }
        } catch (_) {
          // 连接失败不阻止配置保存
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('配置已保存，可开始使用')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = ms.providerModels[_selectedProvider] ?? [];
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Text('首次使用设置'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 环境检测结果
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (widget.localHermesDetected ? AppTheme.success : AppTheme.warning)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      widget.localHermesDetected
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 16,
                      color: widget.localHermesDetected ? AppTheme.success : AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.localHermesDetected
                            ? '检测到本地已安装 Hermes Agent，可直接连接。'
                            : '未检测到本地 Hermes 环境，请选择连接方式。',
                        style: TextStyle(fontSize: 12, color: widget.localHermesDetected ? AppTheme.success : AppTheme.warning),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 连接模式选择（仅未检测到本地时显示）
              if (!widget.localHermesDetected) ...[
                Text('连接方式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildModeOption(
                        value: ConnectionMode.embedded,
                        title: '内嵌模式',
                        subtitle: 'Windows 内嵌运行 Hermes',
                        icon: Icons.memory,
                        color: AppTheme.info,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildModeOption(
                        value: ConnectionMode.remote,
                        title: '远程连接',
                        subtitle: '通过 SSH 连接远程服务器',
                        icon: Icons.cloud,
                        color: AppTheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              Text('Gateway 连接', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(controller: _gatewayUrlCtrl, decoration: const InputDecoration(
                labelText: 'Gateway 地址', hintText: 'http://localhost:8642',
                prefixIcon: Icon(Icons.link, size: 18), isDense: true,
              )),
              const SizedBox(height: 8),
              TextField(controller: _apiKeyCtrl, obscureText: true, decoration: const InputDecoration(
                labelText: 'API Key', hintText: '与 .env 中 API_SERVER_KEY 一致',
                prefixIcon: Icon(Icons.key, size: 18), isDense: true,
              )),
              const SizedBox(height: 16),
              Text('LLM 模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedProvider,
                decoration: const InputDecoration(labelText: 'Provider', isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: ms.allProviders.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedProvider = v;
                    final newModels = ms.providerModels[v] ?? [];
                    if (newModels.isNotEmpty) _selectedModel = newModels.first;
                  });
                },
              ),
              const SizedBox(height: 8),
              if (models.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: models.contains(_selectedModel) ? _selectedModel : models.first,
                  decoration: const InputDecoration(labelText: '模型', isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  items: models.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _selectedModel = v); },
                ),
              const SizedBox(height: 8),
              TextField(controller: _providerApiKeyCtrl, obscureText: true, decoration: const InputDecoration(
                labelText: 'Provider API Key', hintText: 'LLM 服务商的 API Key',
                prefixIcon: Icon(Icons.vpn_key_outlined, size: 18), isDense: true,
              )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppTheme.warning),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      '配置会写入 ~/.hermes/config.yaml 和 .env。如果 Hermes 已经配好，只需填 Gateway 地址即可。',
                      style: TextStyle(fontSize: 11, color: AppTheme.warning),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('跳过'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildModeOption({
    required ConnectionMode value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final selected = _selectedMode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedMode = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected ? color.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: selected ? color : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: selected ? color : Theme.of(context).colorScheme.onSurface,
            )),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hermes 下载/安装进度对话框
class _HermesDownloadDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('正在安装 Hermes Agent'),
      content: SizedBox(
        width: 360,
        child: ValueListenableBuilder<SetupState>(
          valueListenable: ConnectionManager().setupNotifier,
          builder: (context, state, _) {
            String text;
            switch (state) {
              case SetupState.downloading: text = '正在下载...'; break;
              case SetupState.installing: text = '正在安装...'; break;
              case SetupState.ready: text = '安装完成'; break;
              case SetupState.failed: text = '安装失败'; break;
              default: text = '准备中...';
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state == SetupState.failed)
                  Icon(Icons.error_outline, size: 48, color: AppTheme.error)
                else
                  const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(height: 20),
                Text(text, style: TextStyle(color: cs.onSurface)),
                if (state == SetupState.ready) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('完成')),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
