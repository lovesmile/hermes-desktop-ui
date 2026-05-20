class CronJob {
  final String id;
  final String name;
  final String schedule; // cron expression
  final String prompt;
  final String status; // active, paused
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime createdAt;
  final String? deliverTarget;
  final List<String>? skillNames;

  CronJob({
    required this.id,
    required this.name,
    required this.schedule,
    required this.prompt,
    this.status = 'active',
    this.lastRunAt,
    this.nextRunAt,
    required this.createdAt,
    this.deliverTarget,
    this.skillNames,
  });

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';

  factory CronJob.fromJson(Map<String, dynamic> json) {
    return CronJob(
      id: json['id'] ?? '',
      name: json['name'] ?? '未命名任务',
      schedule: json['schedule'] ?? '0 9 * * *',
      prompt: json['prompt'] ?? '',
      status: json['status'] ?? 'active',
      lastRunAt: json['last_run_at'] != null
          ? DateTime.tryParse(json['last_run_at'])
          : null,
      nextRunAt: json['next_run_at'] != null
          ? DateTime.tryParse(json['next_run_at'])
          : null,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      deliverTarget: json['deliver_target'],
      skillNames: json['skill_names'] != null
          ? List<String>.from(json['skill_names'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'schedule': schedule,
        'prompt': prompt,
        'status': status,
        'deliver_target': deliverTarget,
        'skill_names': skillNames,
      };
}
