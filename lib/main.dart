import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'services/config_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/platforms_screen.dart';
import 'screens/cron_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/models_screen.dart' as ms; // Provider数据

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
  bool _firstCheckDone = false;

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
  void initState() {
    super.initState();
    // 延迟检查，等 build 完成后再弹出向导
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstSetup();
    });
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
      _showSetupWizard();
    }
  }

  void _showSetupWizard() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SetupWizardDialog(
        onComplete: () {
          // 保存后重新加载
        },
      ),
    );
  }

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

/// 首次启动配置向导
class _SetupWizardDialog extends StatefulWidget {
  final VoidCallback onComplete;
  const _SetupWizardDialog({required this.onComplete});

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

  @override
  void dispose() {
    _gatewayUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _providerApiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final configService = ConfigService();

      // 1. 保存 Gateway 配置到 desktop_config.json
      await configService.writeDesktopConfig({
        'gateway_url': _gatewayUrlCtrl.text.trim(),
        'api_key': _apiKeyCtrl.text.trim(),
      });

      // 2. 写 config.yaml（model.default + model.provider）
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

      // 3. 写 .env（Provider 的 API Key 和 Base URL）
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已保存，可开始使用')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
              // 说明文字
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: AppTheme.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '配置 Hermes Desktop 的连接参数。Gateway 地址默认为本地 8642 端口。'
                        '如果 Hermes 运行在远程服务器，请填写服务器 IP 和端口。',
                        style: TextStyle(fontSize: 12, color: AppTheme.info),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Gateway 连接 ──
              Text('Gateway 连接',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _gatewayUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Gateway 地址',
                  hintText: 'http://localhost:8642',
                  prefixIcon: Icon(Icons.link, size: 18),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _apiKeyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '与 .env 中 API_SERVER_KEY 一致',
                  prefixIcon: Icon(Icons.key, size: 18),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // ── LLM Provider ──
              Text('LLM 模型',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedProvider,
                decoration: const InputDecoration(
                  labelText: 'Provider',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: ms.allProviders
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedProvider = v;
                    final newModels = ms.providerModels[v] ?? [];
                    if (newModels.isNotEmpty) {
                      _selectedModel = newModels.first;
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              if (models.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: models.contains(_selectedModel) ? _selectedModel : models.first,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedModel = v);
                  },
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _providerApiKeyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Provider API Key',
                  hintText: 'LLM 服务商的 API Key',
                  prefixIcon: Icon(Icons.vpn_key_outlined, size: 18),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // ── 提示 ──
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
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '配置会写入 ~/.hermes/config.yaml 和 .env。'
                        '如果 Hermes 已经配好，只需填 Gateway 地址即可。',
                        style: TextStyle(fontSize: 11, color: AppTheme.warning),
                      ),
                    ),
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
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('保存'),
        ),
      ],
    );
  }
}
