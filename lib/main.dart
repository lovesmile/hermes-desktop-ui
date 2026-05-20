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
  runApp(const HermesDesktopApp());
}

class HermesDesktopApp extends StatelessWidget {
  const HermesDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Desktop',
      theme: AppTheme.darkTheme,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: KeyedSubtree(
                key: ValueKey(_currentIndex),
                child: _buildScreen(_currentIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return DashboardScreen(onNavigate: navigateTo);
      case 1:
        return const ChatScreen();
      case 2:
        return const PlatformsScreen();
      case 3:
        return const CronScreen();
      case 4:
        return const LogsScreen();
      case 5:
        return const ModelsScreen();
      case 6:
        return const SettingsScreen();
      default:
        return const DashboardScreen();
    }
  }
}
