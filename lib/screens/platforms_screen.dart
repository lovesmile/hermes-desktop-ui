import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/config_service.dart';
import '../models/platform_config.dart';

class PlatformsScreen extends StatefulWidget {
  const PlatformsScreen({super.key});

  @override
  State<PlatformsScreen> createState() => _PlatformsScreenState();
}

class _PlatformsScreenState extends State<PlatformsScreen> {
  final _gateway = GatewayService();
  final _configService = ConfigService();
  List<PlatformConfig> _platforms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlatforms();
  }

  Future<void> _loadPlatforms() async {
    setState(() => _loading = true);
    try {
      final platforms = await _configService.getPlatformConfigs();
      setState(() {
        _platforms = platforms;
        _loading = false;
      });
    } catch (e) {
      // Fallback to defaults
      setState(() {
        _platforms = PlatformConfig.defaults;
        _loading = false;
      });
    }
  }

  void _showPlatformDetail(PlatformConfig platform) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PlatformDetailSheet(
        platform: platform,
        onSaved: () {
          _loadPlatforms();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _restartGateway() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重启 Gateway'),
        content: const Text('确定要重启 Hermes Gateway 吗？这会导致短暂的连接中断。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定重启')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('平台管理'),
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
          : GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
              ),
              itemCount: _platforms.length,
              itemBuilder: (context, i) => _buildPlatformCard(_platforms[i]),
            ),
    );
  }

  Widget _buildPlatformCard(PlatformConfig platform) {
    return Card(
      child: InkWell(
        onTap: () => _showPlatformDetail(platform),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                platform.icon,
                style: const TextStyle(fontSize: 36),
              ),
              const SizedBox(height: 12),
              Text(
                platform.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (platform.configured
                          ? AppTheme.success
                          : Colors.white38)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  platform.configured ? '已配置' : '未配置',
                  style: TextStyle(
                    fontSize: 12,
                    color: platform.configured
                        ? AppTheme.success
                        : Colors.white38,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (platform.configured) ...[
                const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: platform.status == 'connected'
                        ? AppTheme.success
                        : AppTheme.warning,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformDetailSheet extends StatefulWidget {
  final PlatformConfig platform;
  final VoidCallback onSaved;

  const _PlatformDetailSheet({
    required this.platform,
    required this.onSaved,
  });

  @override
  State<_PlatformDetailSheet> createState() => _PlatformDetailSheetState();
}

class _PlatformDetailSheetState extends State<_PlatformDetailSheet> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _getFields().forEach((key, value) {
      _controllers[key] = TextEditingController();
    });
  }

  Map<String, String> _getFields() {
    switch (widget.platform.name.toLowerCase()) {
      case 'telegram':
        return {'Bot Token': ''};
      case 'discord':
        return {'Bot Token': '', 'Client ID': ''};
      case 'slack':
        return {'Bot Token': '', 'Signing Secret': ''};
      case 'whatsapp':
        return {'Phone Number ID': '', 'Access Token': ''};
      case '飞书':
        return {'App ID': '', 'App Secret': ''};
      case '企业微信':
        return {'Corp ID': '', 'Agent ID': '', 'Secret': ''};
      case 'matrix':
        return {'Homeserver': '', 'Access Token': ''};
      case '微信':
        return {'App ID': '', 'App Secret': ''};
      default:
        return {'API Key': ''};
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _helpForPlatform(String name) {
    switch (name.toLowerCase()) {
      case 'telegram':
        return '从 @BotFather 创建 Bot 获取 Token。需先向 @BotFather 发送 /newbot。';
      case 'discord':
        return '在 Discord Developer Portal 创建应用，启用 Bot 功能后获取 Token。需开启 Message Content Intent。';
      case 'slack':
        return '在 Slack API 页面创建应用，添加 Bot Token Scopes。需订阅 message.channels 事件。';
      case 'whatsapp':
        return '通过 WhatsApp Business Platform API。需要 Meta Developer 账号和 Phone Number ID。';
      case '飞书':
        return '在飞书开放平台创建自建应用，获取 App ID 和 App Secret。需配置事件订阅。';
      case '企业微信':
        return '在企业微信管理后台创建自建应用，获取 Corp ID、Agent ID 和 Secret。';
      case 'matrix':
        return '输入 Matrix 服务器的 Homeserver URL 以及用户的 Access Token。可从 Element 设置中获取。';
      case '微信':
        return '在微信公众平台创建服务号，获取 App ID 和 App Secret。需配置 IP 白名单。';
      default:
        return '输入该平台所需的 API 凭证。';
    }
  }

  String _hintForField(String field, String platform) {
    final hints = {
      'Bot Token': '1234567890:ABCdefGHIjklMNOpqrsTUVwxyz',
      'Client ID': '123456789012345678',
      'Signing Secret': 'abcd1234efgh5678ijkl9012mnop3456',
      'Phone Number ID': '123456789012345',
      'Access Token': 'EAAx...ZBx',
      'App ID': 'cli_xxxxxxxxxxxxxx',
      'App Secret': 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
      'Corp ID': 'wwxxxxxxxxxxxxx',
      'Agent ID': '1000001',
      'Secret': 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
      'Homeserver': 'https://matrix.example.com',
      'API Key': 'sk-...',
    };
    return '例如: ${hints[field] ?? field}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24, right: 24, top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.platform.icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.platform.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (widget.platform.configured
                          ? AppTheme.success
                          : Colors.white38)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  widget.platform.configured ? '已连接' : '未连接',
                  style: TextStyle(
                    color: widget.platform.configured
                        ? AppTheme.success
                        : Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 配置说明
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.info.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppTheme.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _helpForPlatform(widget.platform.name),
                      style: TextStyle(fontSize: 12, color: AppTheme.info),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ..._controllers.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: e.value,
                  decoration: InputDecoration(
                    labelText: e.key,
                    hintText: _hintForField(e.key, widget.platform.name),
                  ),
                  obscureText: e.key.contains('Token') ||
                      e.key.contains('Secret') ||
                      e.key.contains('Key'),
                ),
              )),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('配置已保存，请重启 Gateway 生效')),
                );
                widget.onSaved();
              },
              child: const Text('保存配置'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
