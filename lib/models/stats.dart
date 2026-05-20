class DailyStat {
  final DateTime date;
  final int sessions;
  final int tokens;

  DailyStat({
    required this.date,
    this.sessions = 0,
    this.tokens = 0,
  });

  factory DailyStat.fromJson(Map<String, dynamic> json) {
    return DailyStat(
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      sessions: json['sessions'] ?? 0,
      tokens: json['tokens'] ?? 0,
    );
  }
}

class Stats {
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int totalSessions;
  final double dailyAvgSessions;
  final Map<String, int> modelUsage;
  final List<DailyStat> dailyStats;

  Stats({
    this.totalTokens = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalSessions = 0,
    this.dailyAvgSessions = 0,
    this.modelUsage = const {},
    this.dailyStats = const [],
  });

  factory Stats.fromJson(Map<String, dynamic> json) {
    return Stats(
      totalTokens: json['total_tokens'] ?? json['totalTokens'] ?? 0,
      inputTokens: json['input_tokens'] ?? json['inputTokens'] ?? 0,
      outputTokens: json['output_tokens'] ?? json['outputTokens'] ?? 0,
      totalSessions: json['total_sessions'] ?? json['totalSessions'] ?? 0,
      dailyAvgSessions:
          (json['daily_avg_sessions'] ?? json['dailyAvgSessions'] ?? 0).toDouble(),
      modelUsage: Map<String, int>.from(
          json['model_usage'] ?? json['modelUsage'] ?? {}),
      dailyStats: (json['daily_stats'] ?? json['dailyStats'] ?? [])
          .map<DailyStat>((d) => DailyStat.fromJson(d))
          .toList(),
    );
  }
}
