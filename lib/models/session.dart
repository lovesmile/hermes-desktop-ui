class Session {
  final String id;
  final String title;
  final String? remark;
  final String? gatewaySessionId;
  final String source; // cli, telegram, discord, slack, etc.
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final String? preview;

  String get displayTitle => remark ?? title;

  Session({
    required this.id,
    required this.title,
    this.remark,
    this.gatewaySessionId,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.preview,
  });

  Session copyWith({String? remark, String? gatewaySessionId}) {
    return Session(
      id: id,
      title: title,
      remark: remark ?? this.remark,
      gatewaySessionId: gatewaySessionId ?? this.gatewaySessionId,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt,
      messageCount: messageCount,
      preview: preview,
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] ?? '',
      title: json['title'] ?? json['name'] ?? '未命名会话',
      remark: json['remark'] as String?,
      gatewaySessionId: json['gateway_session_id'] as String?,
      source: json['source'] ?? 'cli',
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDate(json['updated_at'] ?? json['updatedAt']),
      messageCount: json['message_count'] ?? json['messageCount'] ?? 0,
      preview: json['preview'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (remark != null) 'remark': remark,
        if (gatewaySessionId != null) 'gateway_session_id': gatewaySessionId,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'message_count': messageCount,
      };

  static DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
    if (d is int) return DateTime.fromMillisecondsSinceEpoch(d * 1000);
    return DateTime.now();
  }
}
