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
      child: Stack(
        children: [
          InkWell(
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
          // Docs button
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showPlatformDocs(platform),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.help_outline,
                      size: 16, color: AppTheme.info),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlatformDocs(PlatformConfig platform) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(platform.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(child: Text('${platform.name} 接入文档')),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: _buildDocContent(platform.name),
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

  Widget _buildDocContent(String name) {
    final docs = _platformDocs();
    final content = docs[name] ?? '暂无接入文档';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content
          .split('\n')
          .map((line) {
            if (line.startsWith('#')) {
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  line.replaceAll('#', '').trim(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              );
            }
            if (line.trim().isEmpty) return const SizedBox(height: 8);
            if (line.startsWith('- ')) {
              return Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('  •  ', style: TextStyle(color: AppTheme.primary)),
                    Expanded(child: Text(line.substring(2), style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white70))),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white70)),
            );
          })
          .toList(),
    );
  }

  Map<String, String> _platformDocs() {
    return {
      'Telegram': '# 接入步骤\n'
          '1. 打开 Telegram，搜索 @BotFather\n'
          '2. 发送 /newbot 创建一个新 Bot\n'
          '3. 按提示设置 Bot 名称和用户名（以 bot 结尾）\n'
          '4. BotFather 会返回一个 HTTP API Token\n'
          '- 格式: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz\n\n'
          '# 配置 Hermes\n'
          '- 将 Token 填入 "Bot Token" 字段\n'
          '- 保存后重启 Gateway\n\n'
          '# 验证\n'
          '- 在 Telegram 中找到你的 Bot，发送 /start\n'
          '- Hermes 会自动回复\n\n'
          '# 可选设置\n'
          '- 设置 Bot 头像: /setuserpic\n'
          '- 设置 Bot 描述: /setdescription\n'
          '- 设置命令列表: /setcommands',

      'Discord': '# 接入步骤\n'
          '1. 打开 Discord Developer Portal (https://discord.com/developers/applications)\n'
          '2. 点击 "New Application"，输入名称\n'
          '3. 左侧菜单选择 "Bot"，点击 "Add Bot"\n'
          '4. 在 Bot 页面找到 Token，点击 "Copy"\n\n'
          '# 重要权限设置\n'
          '- 开启 "Message Content Intent" （必须）\n'
          '- 开启 "Server Members Intent" （推荐）\n\n'
          '# 邀请 Bot 到服务器\n'
          '- 在 OAuth2 > URL Generator 选择:\n'
          '  • Scopes: bot, applications.commands\n'
          '  • Bot Permissions: Send Messages, Read Messages, Read Message History\n'
          '- 生成 URL，在浏览器打开，选择服务器\n\n'
          '# 配置 Hermes\n'
          '- 填入 Bot Token\n'
          '- 保存后重启 Gateway',

      'Slack': '# 接入步骤\n'
          '1. 打开 Slack API (https://api.slack.com/apps)\n'
          '2. 点击 "Create New App" > "From Scratch"\n'
          '3. 设置 App 名称，选择 Workspace\n\n'
          '# 配置 Bot Token\n'
          '- 左侧 "OAuth & Permissions" > "Bot Token Scopes" 添加:\n'
          '  • chat:write — 发送消息\n'
          '  • channels:history — 读取频道历史\n'
          '  • channels:read — 读取频道信息\n'
          '  • app_mentions:read — 接收 @提及\n'
          '- 点击 "Install to Workspace"，复制 Bot User OAuth Token\n\n'
          '# 事件订阅\n'
          '- "Event Subscriptions" > 开启\n'
          '- Subscribe to bot events: 添加 app_mention\n\n'
          '# 配置 Hermes\n'
          '- 填入 Bot Token\n'
          '- 保存后重启 Gateway',

      'WhatsApp': '# 接入步骤\n'
          '1. 访问 Meta Developer (https://developers.facebook.com)\n'
          '2. 创建应用 > "Business" 类型\n'
          '3. 添加 "WhatsApp" 产品\n\n'
          '# 获取凭证\n'
          '- Business Account ID: 在 WhatsApp > 设置中查看\n'
          '- Phone Number ID: WhatsApp > API 设置中查看\n'
          '- Access Token: 点击 "Generate Token"\n\n'
          '# 配置 Webhook\n'
          '- Callback URL: 你的 Hermes Gateway 地址 + /webhook/whatsapp\n'
          '- Verify Token: 自定义验证字符串\n\n'
          '# 配置 Hermes\n'
          '- 填入 Phone Number ID 和 Access Token\n'
          '- 保存后重启 Gateway',

      '飞书': '# 接入步骤\n'
          '1. 打开飞书开放平台 (https://open.feishu.cn)\n'
          '2. 创建企业自建应用\n'
          '3. 获取 App ID 和 App Secret\n\n'
          '# 权限配置\n'
          '- 权限管理 > 添加权限:\n'
          '  • im:message — 发送消息\n'
          '  • im:message:read — 读取消息\n'
          '  • im:resource — 下载文件\n\n'
          '# 事件订阅\n'
          '- 事件配置 > 添加事件:\n'
          '  • im.message.receive_v1 — 接收消息\n'
          '- 回调地址: 你的 Hermes Gateway 地址 + /webhook/feishu\n\n'
          '# 发布应用\n'
          '- 版本管理与发布 > 创建版本 > 提交审核\n'
          '- 审核通过后启用\n\n'
          '# 配置 Hermes\n'
          '- 填入 App ID 和 App Secret\n'
          '- 保存后重启 Gateway',

      '企业微信': '# 接入步骤\n'
          '1. 登录企业微信管理后台 (https://work.weixin.qq.com/wework_admin)\n'
          '2. 应用管理 > 自建 > 创建应用\n\n'
          '# 获取凭证\n'
          '- Corp ID: 我的企业 > 企业信息 > 企业ID\n'
          '- Agent ID: 应用详情页 > AgentId\n'
          '- Secret: 应用详情页 > Secret > 查看\n\n'
          '# 配置接收消息\n'
          '- 应用详情 > 接收消息 > 设置 API 接收\n'
          '- URL: 你的 Hermes Gateway 地址 + /webhook/wecom\n'
          '- Token: 自定义，与 Hermes 配置一致\n'
          '- EncodingAESKey: 随机生成\n\n'
          '# 配置 Hermes\n'
          '- 填入 Corp ID、Agent ID、Secret\n'
          '- 保存后重启 Gateway',

      'Matrix': '# 接入步骤\n'
          '1. 需要一个 Matrix 服务器地址（如 matrix.org 或自建）\n'
          '2. 注册一个 Matrix 账号\n\n'
          '# 获取 Access Token\n'
          '- 登录 Element Web 或客户端\n'
          '- 设置 > 帮助及关于 > 高级 > 访问令牌\n'
          '- 或者 API: POST /_matrix/client/v3/login\n\n'
          '# 配置 Hermes\n'
          '- Homeserver: https://matrix.example.com\n'
          '- Access Token: 从 Element 复制\n'
          '- 保存后重启 Gateway\n\n'
          '# 注意\n'
          '- 机器人会自动加入有邀请的 Room\n'
          '- 支持 E2EE 的房间无法读取消息',

      '微信': '# 接入步骤\n'
          '1. 注册微信公众号 (https://mp.weixin.qq.com)\n'
          '2. 选择"服务号"类型（个人只能申请订阅号）\n\n'
          '# 获取凭证\n'
          '- App ID: 开发 > 基本配置 > AppID\n'
          '- App Secret: 生成并复制 AppSecret\n\n'
          '# 配置服务器\n'
          '- 开发 > 基本配置 > 服务器配置\n'
          '- URL: 你的 Hermes Gateway 地址 + /webhook/wechat\n'
          '- Token: 自定义字符串，与 Hermes 配置一致\n'
          '- EncodingAESKey: 随机生成\n\n'
          '# IP 白名单\n'
          '- 在基本配置中添加服务器 IP 到白名单\n\n'
          '# 配置 Hermes\n'
          '- 填入 App ID 和 App Secret\n'
          '- 保存后重启 Gateway',
    };
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
