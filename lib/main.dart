import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/platforms_screen.dart';
import 'screens/cron_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';

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

  void _onThemeChanged() => setState(() {});

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

  static const _navItems = [
    (Icons.dashboard_outlined, Icons.dashboard, '仪表盘'),
    (Icons.chat_outlined, Icons.chat, '聊天'),
    (Icons.devices_outlined, Icons.devices, '平台'),
    (Icons.schedule_outlined, Icons.schedule, '定时'),
    (Icons.article_outlined, Icons.article, '日志'),
    (Icons.memory_outlined, Icons.memory, '模型'),
    (Icons.settings_outlined, Icons.settings, '设置'),
  ];

  void navigateTo(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // M3 NavigationRail
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => navigateTo(i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.5,
              backgroundColor: scheme.surface,
              indicatorColor: scheme.secondaryContainer,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6750A4), Color(0xFFD0BCFF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('H',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20)),
                      ),
                    ),
                  ],
                ),
              ),
              destinations: _navItems.map((item) {
                return NavigationRailDestination(
                  icon: Icon(item.$1),
                  selectedIcon: Icon(item.$2, color: scheme.primary),
                  label: Text(item.$3),
                );
              }).toList(),
            ),
            // Separator
            VerticalDivider(width: 1, color: scheme.outlineVariant),
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
      ),
    );
  }
}
