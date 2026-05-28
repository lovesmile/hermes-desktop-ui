class SshConfig {
  final String host;
  final int port;
  final String user;
  final String? keyPath;
  final String? password;

  const SshConfig({
    this.host = '',
    this.port = 22,
    this.user = '',
    this.keyPath,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'user': user,
        'keyPath': keyPath ?? '',
        'password': password ?? '',
      };

  factory SshConfig.fromJson(Map<String, dynamic> json) => SshConfig(
        host: json['host'] ?? '',
        port: json['port'] ?? 22,
        user: json['user'] ?? '',
        keyPath: json['keyPath'],
        password: json['password'],
      );

  bool get isValid => host.isNotEmpty && user.isNotEmpty;
}
