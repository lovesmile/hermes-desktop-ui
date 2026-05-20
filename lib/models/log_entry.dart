class LogEntry {
  final DateTime timestamp;
  final String level; // INFO, WARN, ERROR, DEBUG
  final String source; // agent, gateway, error
  final String message;
  final Map<String, dynamic>? metadata;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.metadata,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      level: json['level'] ?? 'INFO',
      source: json['source'] ?? 'agent',
      message: json['message'] ?? '',
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }
}
