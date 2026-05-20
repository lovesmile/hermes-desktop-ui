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
      ];

  String get icon {
    switch (name.toLowerCase()) {
      case 'telegram':
        return '📱';
      case 'discord':
        return '💬';
      case 'slack':
        return '🔷';
      case 'whatsapp':
        return '🟢';
      case '飞书':
        return '📃';
      case '企业微信':
        return '🏢';
      case 'matrix':
        return '🧩';
      case '微信':
        return '💚';
      default:
        return '🔌';
    }
  }
}
