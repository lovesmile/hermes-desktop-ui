import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/config_service.dart';
import '../services/connection_manager.dart';
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: platform.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        platform.iconData,
                        color: platform.color,
                        size: 28,
                      ),
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
                              : Theme.of(context).colorScheme.onSurfaceVariant)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      platform.configured ? '已配置' : '未配置',
                      style: TextStyle(
                        fontSize: 12,
                        color: platform.configured
                            ? AppTheme.success
                            : Theme.of(context).colorScheme.onSurfaceVariant,
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
            Icon(platform.iconData, color: platform.color, size: 24),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
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
                    Expanded(child: Text(line.substring(2), style: TextStyle(fontSize: 13, height: 1.5, color: Theme.of(context).colorScheme.onSurface))),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: TextStyle(fontSize: 13, height: 1.5, color: Theme.of(context).colorScheme.onSurface)),
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
          '1. 确保 Hermes 运行在可联网的环境中\n'
          '2. 在下方点击"扫码绑定微信"按钮\n\n'
          '# 扫码绑定\n'
          '- 按钮拉起 iLink Bot 二维码\n'
          '- 使用微信扫描二维码确认登录\n'
          '- 系统会自动轮询状态，确认后保存凭证并重启 Gateway\n\n'
          '# 发送消息\n'
          '- 绑定成功后即可在微信中向 Hermes 发消息\n'
          '- Hermes 会自动回复\n\n'
          '# 注意事项\n'
          '- 基于 iLink Bot 协议，非微信公众号接口\n'
          '- 微信个人号扫码，无需服务号/订阅号\n'
          '- 登录凭证会持久化保存，下次启动无需重新扫码',
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
  Map<String, TextEditingController> _controllers = {};
  final _formKey = GlobalKey<FormState>();
  String _dialogError = '';

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _getFields().forEach((key, value) {
      _controllers[key] = TextEditingController();
    });
  }

  // ═══════════════════════════════════════════
  //  WeChat QR login — full lifecycle
  // ═══════════════════════════════════════════

  Process? _wechatProcess;
  StreamSubscription<String>? _wechatSubscription;
  bool _wechatLoading = false;
  String? _wechatQrUrl;
  String? _wechatError;
  String? _wechatScanStatus;
  int _wechatRemaining = 480;
  String _wechatStatusText = '';

  @override
  void dispose() {
    _cancelWechatFlow();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Cleanly cancel the ongoing WeChat QR login process
  void _cancelWechatFlow() {
    _wechatSubscription?.cancel();
    _wechatSubscription = null;
    if (_wechatProcess != null) {
      _wechatProcess!.kill();
      _wechatProcess = null;
    }
  }

  /// Start the full QR login flow: fetch QR → poll → save credentials
  Future<void> _startWechatQrFlow() async {
    // Cancel any previous flow
    _cancelWechatFlow();
    setState(() {
      _wechatLoading = true;
      _wechatQrUrl = null;
      _wechatError = null;
      _wechatScanStatus = null;
      _wechatRemaining = 480;
      _wechatStatusText = '正在获取二维码...';
    });

    try {
      // 查找脚本：优先 ~/.hermes/scripts/，其次项目默认位置
      final findScript = await ConnectionManager().runShell(
        'ls "\$HOME/.hermes/scripts/wechat_qr_login_full.py" 2>/dev/null || '
        'ls scripts/wechat_qr_login_full.py 2>/dev/null || echo ""',
        allowFailure: true,
      );
      var scriptPath = findScript.stdout.trim();
      if (scriptPath.isEmpty) {
        // 最后的 fallback：让用户配置
        throw Exception('找不到 wechat_qr_login_full.py 脚本，'
            '请将其复制到 ~/.hermes/scripts/ 目录');
      }
      // 确保是绝对路径（通过 ~ 扩展）
      if (!scriptPath.startsWith('/')) {
        scriptPath = r'$HOME/.hermes/scripts/wechat_qr_login_full.py';
      }
      _wechatProcess =
          await ConnectionManager().startShellProcess('python3 $scriptPath');

      _wechatSubscription = _wechatProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return;
          try {
            final data = jsonDecode(trimmed) as Map<String, dynamic>;
            _handleWechatEvent(data);
          } catch (_) {
            // skip non-JSON lines
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _wechatLoading = false;
            _wechatError = '读取输出失败: $e';
          });
        },
        onDone: () {
          // Process ended naturally (not cancelled)
          if (!mounted) return;
          // If no confirmed/error state was set, check if process had an error
          if (_wechatLoading && _wechatError == null && _wechatScanStatus != 'confirmed') {
            // Check stderr for clues
            _wechatProcess?.stderr
                .transform(utf8.decoder)
                .join()
                .then((stderr) {
              if (mounted) {
                setState(() {
                  _wechatLoading = false;
                  _wechatError = stderr.isNotEmpty
                      ? stderr
                      : '进程意外结束，请重试';
                });
              }
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      setState(() {
        _wechatLoading = false;
        _wechatError = e.toString();
      });
    }
  }

  void _handleWechatEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final status = data['status'] as String? ?? '';

    switch (status) {
      case 'qr_ready':
        setState(() {
          _wechatLoading = false;
          _wechatQrUrl = data['qrcode_url'] as String?;
          _wechatError = null;
          _wechatScanStatus = 'qr_ready';
          _wechatStatusText = '请用微信扫描二维码';
        });

      case 'waiting_scan':
        final remaining = data['remaining'] as int? ?? 0;
        final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
        final seconds = (remaining % 60).toString().padLeft(2, '0');
        setState(() {
          _wechatRemaining = remaining;
          _wechatScanStatus = 'waiting';
          _wechatStatusText = '等待扫码  $minutes:$seconds';
        });

      case 'scanned':
        setState(() {
          _wechatScanStatus = 'scanned';
          _wechatStatusText = '已扫码，请在手机上确认';
        });

      case 'confirmed':
        final botId = data['ilink_bot_id'] as String? ?? '';
        final botToken = data['bot_token'] as String? ?? '';
        final baseUrl = data['baseurl'] as String? ?? 'https://ilinkai.weixin.qq.com';
        setState(() {
          _wechatLoading = false;
          _wechatScanStatus = 'confirmed';
          _wechatStatusText = '✓ 绑定成功，正在保存配置...';
        });
        _saveWechatConfig(botId, botToken, baseUrl);

      case 'expired':
        final attempt = data['attempt'] as int? ?? 0;
        final maxAttempts = data['max_attempts'] as int? ?? 3;
        if (attempt < maxAttempts) {
          setState(() {
            _wechatScanStatus = 'expired';
            _wechatStatusText = '二维码已过期，正在重试 ($attempt/$maxAttempts)...';
            _wechatQrUrl = null;
          });
          // The script will automatically retry with a new QR code
          // But if the script has already exited (onDone), we need to restart
          // The onDone handler will handle this
        } else {
          setState(() {
            _wechatLoading = false;
            _wechatError = '重试次数已达上限，请重新绑定';
          });
        }

      case 'timeout':
        setState(() {
          _wechatLoading = false;
          _wechatError = '等待超时（8分钟），请重新绑定';
        });

      case 'failed':
        setState(() {
          _wechatLoading = false;
          _wechatError = data['error'] as String? ?? '绑定失败';
        });

      case 'error':
        setState(() {
          _wechatLoading = false;
          _wechatError = data['error'] as String? ?? '发生错误';
        });

      default:
        // unknown — ignore
        break;
    }
  }

  /// Save WeChat credentials to .env via runShell and restart gateway
  Future<void> _saveWechatConfig(String botId, String token, String baseUrl) async {
    try {
      final homeRes = await ConnectionManager().runShell('echo \$HOME', allowFailure: true);
      final home = homeRes.stdout.trim().isNotEmpty ? homeRes.stdout.trim() : r'$HOME';
      final envPath = '$home/.hermes/.env';

      // Read current .env
      final readResult = await ConnectionManager().runShell(
        'cat "$envPath" 2>/dev/null || echo ""',
        allowFailure: true,
      );
      String envContent = readResult.stdout;

      // Update or add WEIXIN_ACCOUNT_ID
      if (envContent.contains('WEIXIN_ACCOUNT_ID=')) {
        envContent = envContent.replaceAll(
          RegExp(r'WEIXIN_ACCOUNT_ID=.*'),
          'WEIXIN_ACCOUNT_ID=$botId',
        );
      } else {
        envContent += '\nWEIXIN_ACCOUNT_ID=$botId';
      }

      // Update or add WEIXIN_TOKEN
      if (envContent.contains('WEIXIN_TOKEN=')) {
        envContent = envContent.replaceAll(
          RegExp(r'WEIXIN_TOKEN=.*'),
          'WEIXIN_TOKEN=$token',
        );
      } else {
        envContent += '\nWEIXIN_TOKEN=$token';
      }

      // Update or add WEIXIN_BASE_URL
      if (envContent.contains('WEIXIN_BASE_URL=')) {
        envContent = envContent.replaceAll(
          RegExp(r'WEIXIN_BASE_URL=.*'),
          'WEIXIN_BASE_URL=$baseUrl',
        );
      } else {
        envContent += '\nWEIXIN_BASE_URL=$baseUrl';
      }

      // Write .env via base64 (avoid shell escaping issues)
      final b64 = base64Encode(utf8.encode(envContent));
      await ConnectionManager().runShell(
        'echo "$b64" | base64 -d > "$envPath"',
      );

      if (!mounted) return;
      setState(() {
        _wechatStatusText = '✓ 配置已保存，正在重启 Gateway...';
      });

      // Restart gateway
      try {
        await ConnectionManager().runShell(
          'hermes --accept-hooks gateway restart',
          allowFailure: true,
        );
      } catch (_) {
        // Gateway restart might fail if not running, that's OK
      }

      if (!mounted) return;
      setState(() {
        _wechatLoading = false;
        _wechatStatusText = '✓ 绑定完成';
      });

      // Notify parent to refresh platform list
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wechatLoading = false;
        _wechatError = '保存配置失败: $e';
      });
    }
  }

  // ═══════════════════════════════════════════
  //  Field management
  // ═══════════════════════════════════════════

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
        return {'引导': '扫码绑定'};
      default:
        return {'API Key': ''};
    }
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
        return '使用 iLink Bot 协议扫码登录。点击下方按钮获取二维码后用微信扫码确认。';
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

  // ═══════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════

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
              Icon(widget.platform.iconData, color: widget.platform.color, size: 28),
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
                          : Theme.of(context).colorScheme.onSurfaceVariant)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  widget.platform.configured ? '已连接' : '未连接',
                  style: TextStyle(
                    color: widget.platform.configured
                        ? AppTheme.success
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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
            if (widget.platform.name == '微信') ...[
            // ── 微信扫码绑定（完整流程） ──
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_wechatLoading || _wechatScanStatus == 'confirmed')
                    ? null
                    : _startWechatQrFlow,
                icon: _wechatLoading && _wechatQrUrl == null
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        _wechatScanStatus == 'confirmed'
                            ? Icons.check_circle_outline
                            : Icons.qr_code_scanner,
                        size: 20,
                      ),
                label: Text(
                  _wechatScanStatus == 'confirmed'
                      ? '已绑定'
                      : _wechatLoading && _wechatQrUrl == null
                          ? '正在获取二维码...'
                          : '扫码绑定微信',
                ),
              ),
            ),
            // Show cancel button during flow
            if (_wechatLoading || _wechatQrUrl != null || _wechatScanStatus == 'waiting' || _wechatScanStatus == 'scanned')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      _cancelWechatFlow();
                      setState(() {
                        _wechatLoading = false;
                        _wechatQrUrl = null;
                        _wechatError = null;
                        _wechatScanStatus = null;
                      });
                    },
                    child: const Text('取消绑定'),
                  ),
                ),
              ),
            // QR code and status area
            if (_wechatQrUrl != null ||
                _wechatError != null ||
                _wechatScanStatus != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildWechatStatus(),
              ),
            ],
          ] else ...[
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
          ],
          if (widget.platform.name != '微信') ...[
            if (_dialogError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dialogError,
                        style: TextStyle(fontSize: 12, color: AppTheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  // Validate required fields are not empty
                  final emptyFields = _controllers.entries
                      .where((e) => e.key != '引导' && e.value.text.trim().isEmpty)
                      .map((e) => e.key)
                      .toList();
                  if (emptyFields.isNotEmpty) {
                    setState(() {
                      _dialogError = '请填写: ${emptyFields.join(", ")}';
                    });
                    return;
                  }
                  setState(() => _dialogError = '');
                  widget.onSaved();
                },
                child: const Text('保存配置'),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Build the WeChat QR/status display area
  Widget _buildWechatStatus() {
    final cs = Theme.of(context).colorScheme;

    // Error state
    if (_wechatError != null) {
      return Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 8),
          Text(
            _wechatError!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _startWechatQrFlow,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重新绑定'),
          ),
        ],
      );
    }

    // Confirmed state
    if (_wechatScanStatus == 'confirmed') {
      return Column(
        children: [
          Icon(Icons.check_circle, size: 48, color: AppTheme.success),
          const SizedBox(height: 8),
          Text(
            _wechatStatusText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.success),
          ),
        ],
      );
    }

    // QR code state
    if (_wechatQrUrl != null) {
      return Column(
        children: [
          // QR code image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              'https://api.qrserver.com/v1/create-qr-code/'
              '?size=200x200&data=${Uri.encodeComponent(_wechatQrUrl!)}',
              width: 200, height: 200,
              errorBuilder: (_, __, ___) => Icon(
                Icons.qr_code, size: 120, color: AppTheme.primary,
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const SizedBox(
                  width: 200, height: 200,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Scan status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_wechatScanStatus == 'waiting' || _wechatScanStatus == 'qr_ready')
                Icon(Icons.qr_code_scanner, size: 16,
                    color: cs.onSurfaceVariant),
              if (_wechatScanStatus == 'scanned')
                Icon(Icons.smartphone, size: 16, color: AppTheme.warning),
              const SizedBox(width: 6),
              Text(
                _wechatStatusText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _wechatScanStatus == 'scanned'
                      ? AppTheme.warning
                      : cs.onSurface,
                ),
              ),
            ],
          ),
          if (_wechatScanStatus == 'waiting' || _wechatScanStatus == 'qr_ready') ...[
            const SizedBox(height: 8),
            // Progress bar showing remaining time
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _wechatRemaining / 480.0,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '二维码剩余 ${_wechatRemaining ~/ 60} 分钟',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          // Show the raw link for manual use
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _wechatQrUrl!,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    // Copy to clipboard
                    // Use platform channel or just select text
                  },
                  child: Icon(Icons.copy, size: 14, color: cs.primary),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Loading state (no QR yet)
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
