import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'config/theme.dart';
import 'services/config_service.dart';
import 'services/local_db.dart';
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

/// 单实例锁 — 绑定到本地端口，第二个实例绑定失败则退出
RawServerSocket? _instanceLock;

Future<bool> _tryLockInstance() async {
  try {
    final server = await RawServerSocket.bind('127.0.0.1', 49876, shared: false);
    _instanceLock = server;
    return true;
  } catch (_) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for desktop
  sqfliteFfiInit();

  // 防止多开 — 独占端口锁，如果绑定失败说明已有实例在运行
  if (!await _tryLockInstance()) {
    exit(0);
  }

  // ★ 启动时立即设置 DB 模式，避免 UI 先加载了默认 local 数据
  await ConfigService.ensureInitialized();
  final config = await ConfigService().readDesktopConfig();
  final modeStr = config['connection_mode'] as String? ?? 'local';
  final dbMode = modeStr == 'remote' ? 'remote'
      : (modeStr == 'embedded' ? 'embedded' : 'local');
  await LocalDatabase().setMode(dbMode);

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1440, 960),
    minimumSize: Size(1215, 800),
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

  // Show window immediately — init runs in background so user sees UI faster
  runApp(HermesDesktopApp());

  windowManager.show();
  windowManager.focus();

  // Cleanup embedded hermes.exe / SSH tunnel on app exit
  windowManager.addListener(_AppWindowListener());

  // init() reads config, starts health checks, and for remote mode
  // establishes SSH tunnel. Doing it after show() means the window
  // appears instantly while connection setup completes in parallel.
  await ConnectionManager().init();
}

class _AppWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await ConnectionManager().disconnect();
  }

  @override
  void onWindowFocus() {}
  @override
  void onWindowBlur() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowMaximize() {}
  @override
  void onWindowUnmaximize() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowMove() {}
  @override
  void onWindowEnterFullScreen() {}
  @override
  void onWindowLeaveFullScreen() {}
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
    themeColorNotifier.addListener(_onThemeChanged);
    _loadThemeColor();
  }

  Future<void> _loadThemeColor() async {
    final config = await ConfigService().readDesktopConfig();
    final saved = config['theme_color'] as int? ?? 0;
    themeColorNotifier.value = saved.clamp(0, AppTheme.themeNames.length - 1);
  }

  @override
  void dispose() {
    themeModeNotifier.removeListener(_onThemeChanged);
    themeColorNotifier.removeListener(_onThemeChanged);
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
  int _currentIndex = 7;
  bool _firstCheckDone = false;
  bool _isMaximized = false;

  final ValueNotifier<int> tabNotifier = ValueNotifier<int>(7);

  static final _navItems = [
    ('📊', '仪表盘'),
    ('⏱️', '定时任务'),
    ('🧠', '模型与技能'),
    ('📁', '文件'),
    ('🖥️', '平台'),
    ('📝', '日志'),
    ('⚙️', '设置'),
    ('🤖', '聊天'),
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
                  const Text('⚡', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
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
                // ── 自定义侧边栏（仿 HTML 设计） ──
                Container(
                  width: 220,
                  color: scheme.surfaceContainerHighest,
                  child: Column(
                    children: [
                      // Logo 区域
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
                              ),
                              child: Center(
                                child: Text('⚡', style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold, fontSize: 20)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Hermes Desktop',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14,
                                    color: scheme.onSurface,
                                  )),
                            ),
                          ],
                        ),
                      ),
                      // 导航项
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: _navItems.asMap().entries.expand((entry) {
                              final i = entry.key;
                              final item = entry.value;
                              final selected = i == _currentIndex;
                              final list = <Widget>[];
                              if (i == 7) {
                                list.add(Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
                                ));
                              }
                              list.add(Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? scheme.primary.withValues(alpha: 0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: selected
                                      ? Border(
                                          left: BorderSide(color: scheme.primary, width: 2.5),
                                        )
                                      : null,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => navigateTo(i),
                                  hoverColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    child: Row(
                                      children: [
                                        Text(item.$1, style: TextStyle(fontSize: 20)),
                                        const SizedBox(width: 14),
                                        Text(item.$2, style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                          color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                        )),
                                      ],
                                    ),
                                  ),
                                ),
                              ));
                              return list;
                            }).toList(),
                          ),
                        ),
                      ),
                      // 底部状态
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showHelpDialog(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.help_outline, size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text('使用帮助',
                                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
                              dotColor = AppTheme.success;
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
                              dotColor = AppTheme.warning;
                              label = '连接中...';
                              break;
                            case ConnStatus.disconnected:
                              dotColor = s.error;
                              label = '未连接';
                              break;
                            case ConnStatus.error:
                              dotColor = s.error;
                              label = conn.message.isNotEmpty ? conn.message : '未连接';
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
                                Flexible(
                                  child: Text(label, style: TextStyle(fontSize: 12, color: s.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _currentIndex,
                          children: [
                            DashboardScreen(onNavigate: navigateTo, tabNotifier: tabNotifier),  // 0 仪表盘
                            const CronScreen(),       // 1 定时
                            ModelsScreen(onNavigate: navigateTo),  // 2 模型与技能
                            const FileBrowserScreen(), // 3 文件
                            const PlatformsScreen(),    // 4 平台
                            const LogsScreen(),         // 5 日志
                            const SettingsScreen(),     // 6 设置
                            const ChatScreen(),         // 7 聊天
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
