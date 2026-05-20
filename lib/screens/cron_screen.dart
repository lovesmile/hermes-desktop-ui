import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/config_service.dart';
import '../models/cron_job.dart';

class CronScreen extends StatefulWidget {
  const CronScreen({super.key});

  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> {
  final _gateway = GatewayService();
  List<CronJob> _jobs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() => _loading = true);
    try {
      final jobs = await _gateway.getCronJobs();
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleJob(CronJob job) async {
    try {
      await _gateway.updateCronJob(job.id, {
        'status': job.isActive ? 'paused' : 'active',
      });
      _loadJobs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _runJob(CronJob job) async {
    try {
      await _gateway.runCronJob(job.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务已触发')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('触发失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteJob(CronJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${job.name}」？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _gateway.deleteCronJob(job.id);
        _loadJobs();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _CronJobDialog(
        onSaved: () {
          _loadJobs();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showEditDialog(CronJob job) {
    showDialog(
      context: context,
      builder: (ctx) => _CronJobDialog(
        existingJob: job,
        onSaved: () {
          _loadJobs();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '从未';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('定时任务')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _jobs.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadJobs,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _jobs.length,
                    itemBuilder: (context, i) => _buildJobCard(_jobs[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_outlined,
              size: 64, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Text('暂无定时任务',
              style: TextStyle(fontSize: 18, color: Colors.white38)),
          const SizedBox(height: 8),
          const Text('点击右下角 + 创建新任务',
              style: TextStyle(fontSize: 14, color: Colors.white24)),
        ],
      ),
    );
  }

  Widget _buildJobCard(CronJob job) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: job.isActive ? AppTheme.success : AppTheme.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    job.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E3A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    job.schedule,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppTheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (job.prompt.isNotEmpty) ...[
              Text(
                job.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                _buildInfoChip(Icons.history, '上次: ${_relativeTime(job.lastRunAt)}'),
                if (job.nextRunAt != null) ...[
                  const SizedBox(width: 16),
                  _buildInfoChip(
                      Icons.schedule, '下次: ${_relativeTime(job.nextRunAt)}'),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: 0.06)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionChip(
                  Icons.play_arrow,
                  '执行',
                  AppTheme.success,
                  () => _runJob(job),
                ),
                const SizedBox(width: 8),
                _buildActionChip(
                  job.isActive ? Icons.pause : Icons.play_arrow,
                  job.isActive ? '暂停' : '恢复',
                  AppTheme.warning,
                  () => _toggleJob(job),
                ),
                const SizedBox(width: 8),
                _buildActionChip(
                  Icons.edit_outlined,
                  '编辑',
                  AppTheme.info,
                  () => _showEditDialog(job),
                ),
                const SizedBox(width: 8),
                _buildActionChip(
                  Icons.delete_outline,
                  '删除',
                  AppTheme.error,
                  () => _deleteJob(job),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _buildActionChip(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CronJobDialog extends StatefulWidget {
  final CronJob? existingJob;
  final VoidCallback onSaved;

  const _CronJobDialog({this.existingJob, required this.onSaved});

  @override
  State<_CronJobDialog> createState() => _CronJobDialogState();
}

class _CronJobDialogState extends State<_CronJobDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _promptController;
  final _gateway = GatewayService();
  final _configService = ConfigService();
  List<Map<String, String>> _availableSkills = [];
  List<String> _selectedSkills = [];
  bool _skillsLoading = true;
  String _selectedPreset = '';

  static const _presets = [
    ('每30分钟', '*/30 * * * *'),
    ('每小时', '0 * * * *'),
    ('每6小时', '0 */6 * * *'),
    ('每天9点', '0 9 * * *'),
    ('每天21点', '0 21 * * *'),
    ('每周一9点', '0 9 * * 1'),
    ('每月1日9点', '0 9 1 * *'),
  ];

  @override
  void initState() {
    super.initState();
    final job = widget.existingJob;
    _nameController = TextEditingController(text: job?.name ?? '');
    _scheduleController = TextEditingController(text: job?.schedule ?? '0 9 * * *');
    _promptController = TextEditingController(text: job?.prompt ?? '');
    if (job?.skillNames != null) {
      _selectedSkills = List.from(job!.skillNames!);
    }
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    try {
      final skills = await _configService.getSkills();
      setState(() {
        _availableSkills = skills;
        _skillsLoading = false;
      });
    } catch (_) {
      setState(() => _skillsLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final Map<String, dynamic> data = {
        'name': _nameController.text.trim(),
        'schedule': _scheduleController.text.trim(),
        'prompt': _promptController.text.trim(),
        'status': 'active',
      };
      if (_selectedSkills.isNotEmpty) {
        data['skill_names'] = _selectedSkills;
      }
      if (widget.existingJob != null) {
        await _gateway.updateCronJob(widget.existingJob!.id, data);
      } else {
        await _gateway.createCronJob(data);
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingJob != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑任务' : '新建任务'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '任务名称'),
                  validator: (v) =>
                      v?.trim().isEmpty == true ? '请输入任务名称' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedPreset.isEmpty ? null : _selectedPreset,
                        decoration: const InputDecoration(
                          labelText: '常用定时',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: _presets.map((p) => DropdownMenuItem(
                              value: p.$1,
                              child: Text(p.$1, style: const TextStyle(fontSize: 14)),
                            )).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            final preset = _presets.firstWhere((p) => p.$1 == v);
                            setState(() {
                              _selectedPreset = v;
                              _scheduleController.text = preset.$2;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _scheduleController,
                        decoration: const InputDecoration(labelText: 'Cron 表达式'),
                        validator: (v) =>
                            v?.trim().isEmpty == true ? '请输入表达式' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    labelText: '执行提示词',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 6,
                  validator: (v) =>
                      v?.trim().isEmpty == true ? '请输入提示词' : null,
                ),
                const SizedBox(height: 16),
                // 技能多选
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '关联技能（可选）',
                    border: OutlineInputBorder(),
                  ),
                  child: _skillsLoading
                      ? const SizedBox(
                          height: 40,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _availableSkills.isEmpty
                          ? Text('未检测到已安装的技能',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
                          : Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _availableSkills.map((s) {
                                final name = s['name'] ?? '';
                                final selected = _selectedSkills.contains(name);
                                return FilterChip(
                                  label: Text(name, style: const TextStyle(fontSize: 12)),
                                  selected: selected,
                                  onSelected: (v) {
                                    setState(() {
                                      if (v) {
                                        _selectedSkills.add(name);
                                      } else {
                                        _selectedSkills.remove(name);
                                      }
                                    });
                                  },
                                  selectedColor: AppTheme.primary.withValues(alpha: 0.3),
                                  checkmarkColor: AppTheme.primary,
                                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                                  labelStyle: TextStyle(
                                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList(),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
