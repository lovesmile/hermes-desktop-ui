import 'package:flutter/material.dart';
import '../config/theme.dart';

class PlatformConfig {
  final String name;
  final bool configured;
  final Map<String, String> configFields;
  final String status; // connected, disconnected, error

  PlatformConfig({
    required this.name,
    this.configured = false,
    this.configFields = const {},
    this.status = 'disconnected',
  });

  factory PlatformConfig.fromJson(Map<String, dynamic> json) {
    return PlatformConfig(
      name: json['name'] ?? '',
      configured: json['configured'] ?? false,
      configFields: json['config_fields'] != null
          ? Map<String, String>.from(json['config_fields'])
          : {},
      status: json['status'] ?? 'disconnected',
    );
  }

  static List<PlatformConfig> get defaults => [
        PlatformConfig(name: 'Telegram', configured: false),
        PlatformConfig(name: 'Discord', configured: false),
        PlatformConfig(name: 'Slack', configured: false),
        PlatformConfig(name: 'WhatsApp', configured: false),
        PlatformConfig(name: '飞书', configured: false),
        PlatformConfig(name: '企业微信', configured: false),
        PlatformConfig(name: 'Matrix', configured: false),
        PlatformConfig(name: '微信', configured: false),
        PlatformConfig(name: 'Signal', configured: false),
        PlatformConfig(name: '邮件', configured: false),
        PlatformConfig(name: '钉钉', configured: false),
        PlatformConfig(name: 'QQ 机器人', configured: false),
        PlatformConfig(name: 'Home Assistant', configured: false),
        PlatformConfig(name: 'Webhook', configured: false),
        PlatformConfig(name: 'SMS', configured: false),
        PlatformConfig(name: 'Mattermost', configured: false),
        PlatformConfig(name: '元宝', configured: false),
      ];

  /// 平台主题色
  Color get color {
    switch (name.toLowerCase()) {
      case 'telegram':
        return const Color(0xFF0088CC);
      case 'discord':
        return const Color(0xFF5865F2);
      case 'slack':
        return const Color(0xFF4A154B);
      case 'whatsapp':
        return const Color(0xFF25D366);
      case '信号':
      case 'signal':
        return const Color(0xFF3A76F0);
      case '飞书':
      case 'feishu':
        return const Color(0xFF3370FF);
      case '企业微信':
      case 'wecom':
        return const Color(0xFF07C160);
      case 'matrix':
        return const Color(0xFF0DBD8B);
      case '微信':
      case 'wechat':
        return const Color(0xFF07C160);
      case '钉钉':
      case 'dingtalk':
        return const Color(0xFF0089FF);
      case '邮件':
      case 'email':
        return const Color(0xFFCF4646);
      case 'qq 机器人':
      case 'qqbot':
        return const Color(0xFF1EBAFC);
      case 'home assistant':
        return const Color(0xFF41BDF5);
      case 'webhook':
        return const Color(0xFF9B59B6);
      case 'sms':
        return const Color(0xFF2ECC71);
      case 'mattermost':
        return const Color(0xFF0058CC);
      case '元宝':
      case 'yuanbao':
        return const Color(0xFF3C6FE4);
      default:
        return AppTheme.primary;
    }
  }

  /// 平台图标（Material Icons + 品牌感）
  IconData get iconData {
    switch (name.toLowerCase()) {
      case 'telegram':
        return Icons.send_outlined;
      case 'discord':
        return Icons.headset_mic_outlined;
      case 'slack':
        return Icons.tag;
      case 'whatsapp':
        return Icons.chat_bubble_outline;
      case '信号':
      case 'signal':
        return Icons.lock_outline;
      case '飞书':
      case 'feishu':
        return Icons.description_outlined;
      case '企业微信':
      case 'wecom':
        return Icons.business_outlined;
      case 'matrix':
        return Icons.grid_view_outlined;
      case '微信':
      case 'wechat':
        return Icons.wechat_outlined;
      case '钉钉':
      case 'dingtalk':
        return Icons.notifications_outlined;
      case '邮件':
      case 'email':
        return Icons.mail_outline;
      case 'qq 机器人':
      case 'qqbot':
        return Icons.smart_toy_outlined;
      case 'home assistant':
        return Icons.home_outlined;
      case 'webhook':
        return Icons.webhook_outlined;
      case 'sms':
        return Icons.sms_outlined;
      case 'mattermost':
        return Icons.forum_outlined;
      case '元宝':
      case 'yuanbao':
        return Icons.auto_awesome_outlined;
      default:
        return Icons.power_outlined;
    }
  }
}
