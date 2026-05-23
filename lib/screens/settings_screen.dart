import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/config_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gateway = GatewayService();
  final _configService = ConfigService();
  String _configContent = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    final content = await _configService.readConfig();
    setState(() {
      _configContent = content;
      _loading = false;
    });
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
        title: const Text('Gateway 地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置 Hermes Gateway 地址。\n本地: http://localhost:8642\n远程: http://服务器IP:8642',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
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
            const Text('编辑 config.yaml'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '~/.hermes/config.yaml',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontFamily: 'monospace'),
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
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: Colors.white,
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
                // Model section
                _buildSection('模型配置', [
                  _buildSettingRow('当前模型', 'deepseek-v4-flash'),
                  _buildSettingRow('Provider', 'deepseek'),
                  _buildSettingRow('API 地址', 'https://api.deepseek.com'),
                ]),
                const SizedBox(height: 16),
                // Display section
                _buildSection('显示设置', [
                  _buildThemeToggle(),
                  _buildSettingRow('UI 语言', '简体中文'),
                ]),
                const SizedBox(height: 16),
                // Gateway section
                _buildSection('Gateway 设置', [
                  FutureBuilder<String>(
                    future: _configService.getGatewayUrl(),
                    builder: (context, snapshot) {
                      final url = snapshot.data ?? 'http://localhost:8642';
                      return ListTile(
                        title: const Text('Gateway 地址',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text(url,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white38,
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
                const SizedBox(height: 16),
                // Profile section
                _buildSection('Profile', [
                  _buildSettingRow('当前 Profile', 'default'),
                  ListTile(
                    title: const Text('管理 Profiles',
                        style: TextStyle(fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {},
                    contentPadding: EdgeInsets.zero,
                  ),
                ]),
                const SizedBox(height: 16),
                // Config file
                _buildSection('配置文件', [
                  ListTile(
                    title: const Text('编辑 config.yaml',
                        style: TextStyle(fontSize: 14)),
                    subtitle: const Text('~/.hermes/config.yaml',
                        style: TextStyle(fontSize: 12, color: Colors.white38)),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: _showConfigEditor,
                    contentPadding: EdgeInsets.zero,
                  ),
                  ListTile(
                    title: const Text('查看 .env',
                        style: TextStyle(fontSize: 14)),
                    subtitle: const Text('~/.hermes/.env',
                        style: TextStyle(fontSize: 12, color: Colors.white38)),
                    trailing: const Icon(Icons.visibility_outlined, size: 20),
                    onTap: () async {
                      final env = await _configService.getEnvVars();
                      final keys = env.keys.join('\n');
                      if (mounted) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('环境变量'),
                            content: Text(
                              keys.isEmpty ? '无环境变量' : keys,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('关闭')),
                            ],
                          ),
                        );
                      }
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ]),
                const SizedBox(height: 16),
                // About
                _buildSection('关于', [
                  _buildSettingRow('Hermes Desktop', 'v1.0.0'),
                  _buildSettingRow('Hermes Agent', 'v2.x'),
                  _buildSettingRow('项目地址',
                      'github.com/NousResearch/hermes-agent'),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

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
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 140,
            child: Text(
              '主题',
              style: TextStyle(fontSize: 14, color: Colors.white70),
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
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}
