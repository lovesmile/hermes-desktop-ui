class DisplaySession {
  final String id; // 本地 uuid，永不随后端 session 变化
  String title;
  String? remark;
  String currentBackendId; // 当前绑定的后端 session_id
  List<String> backendIdHistory; // 历史后端 session_id 列表
  String? preview; // 最近一条消息的预览
  String? model;
  String? provider;
  DateTime createdAt;
  DateTime updatedAt;

  String get displayTitle => remark ?? title;

  DisplaySession({
    required this.id,
    required this.title,
    this.remark,
    required this.currentBackendId,
    List<String>? backendIdHistory,
    this.preview,
    this.model,
    this.provider,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : backendIdHistory = backendIdHistory ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  DisplaySession copyWith({
    String? title,
    String? remark,
    String? currentBackendId,
    List<String>? backendIdHistory,
    String? preview,
    String? model,
    String? provider,
    DateTime? updatedAt,
  }) {
    return DisplaySession(
      id: id,
      title: title ?? this.title,
      remark: remark ?? this.remark,
      currentBackendId: currentBackendId ?? this.currentBackendId,
      backendIdHistory: backendIdHistory ?? this.backendIdHistory,
      preview: preview ?? this.preview,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  factory DisplaySession.fromJson(Map<String, dynamic> json) {
    return DisplaySession(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      remark: json['remark'] as String?,
      currentBackendId: json['current_backend_id'] ?? '',
      backendIdHistory: (json['backend_id_history'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      preview: json['preview'] as String?,
      model: json['model'] as String?,
      provider: json['provider'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (remark != null) 'remark': remark,
        'current_backend_id': currentBackendId,
        'backend_id_history': backendIdHistory,
        if (preview != null) 'preview': preview,
        if (model != null) 'model': model,
        if (provider != null) 'provider': provider,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
    if (d is int) return DateTime.fromMillisecondsSinceEpoch(d);
    return DateTime.now();
  }
}
