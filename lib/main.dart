import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    // Window is configured but not shown yet — wait for first frame to avoid white flash
  });

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await ConnectionManager().init();
  runApp(HermesDesktopApp());

  // Show window after first frame is rendered, avoiding white screen
  SchedulerBinding.instance.addPostFrameCallback((_) {
    windowManager.show();
    windowManager.focus();
  });
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
  }

  Future<void> _checkMaximized() async {
    try {
      final maxed = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maxed);
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _checkFirstSetup() async {
    if (_firstCheckDone) return;
    _firstCheckDone = true;

    final desktopConfig = await ConfigService().readDesktopConfig();
    final hasMode = desktopConfig.containsKey('connection_mode') &&
        (desktopConfig['connection_mode'] as String?)?.isNotEmpty == true;

    if (!hasMode) {
      // 首次启动或未完成配置 — 显示全屏引导
      _showSetupWizard();
      return;
    }

    // 已配置过，健康检查由定时器处理，不弹向导打扰用户
    await ConnectionManager().checkAndSetup();
  }

  void _showSetupWizard() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SetupScreen(
        onComplete: () {
          Navigator.pop(ctx);
        },
      ),
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
                  SvgPicture.asset('assets/logo.svg', width: 18, height: 18),
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
                  indicatorColor: scheme.secondaryContainer,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SvgPicture.asset('assets/logo.svg', width: 40, height: 40),
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
                              } else if (conn.mode == ConnectionMode.embedded) {
                                label = '内嵌模式';
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


