import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/platforms_screen.dart';
import 'screens/cron_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/models_screen.dart';
import 'widgets/sidebar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
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

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Desktop',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeModeNotifier.value ? ThemeMode.dark : ThemeMode.light,
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
  bool _sidebarCollapsed = false;

  static const _titles = [
    '仪表盘',
    '聊天',
    '平台管理',
    '定时任务',
    '日志查看',
    '模型与技能',
    '设置',
  ];

  void navigateTo(int index) {
    setState(() => _currentIndex = index);
  }

  void _onItemSelected(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(
            currentIndex: _currentIndex,
            collapsed: _sidebarCollapsed,
            onItemSelected: _onItemSelected,
            onToggleCollapse: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                DashboardScreen(onNavigate: navigateTo),
                const ChatScreen(),
                const PlatformsScreen(),
                const CronScreen(),
                const LogsScreen(),
                const ModelsScreen(),
                const SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreen(int index) {
    return const SizedBox.shrink();
  }
}
