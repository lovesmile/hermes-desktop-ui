import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/connection_manager.dart';
import '../services/config_service.dart';
import '../services/gateway_service.dart';
import '../models/cron_job.dart';

class CronScreen extends StatefulWidget {
  const CronScreen({super.key});
  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> {
  final _cm = ConnectionManager();
  final _gateway = GatewayService();
  final _configService = ConfigService();
  List<CronJob> _jobs = [];
  List<String> _skillsCache = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_prefetchSkills());
    _loadJobs();
  }

  Future<List<CronJob>> _readJobsFromFile() async {
    final homeRes = await _cm.runShell('echo \$HOME', allowFailure: true);
    final home = homeRes.stdout.trim().isNotEmpty ? homeRes.stdout.trim() : r'$HOME';
    final result = await _cm.execBash('cat "$home/.hermes/cron/jobs.json" 2>/dev/null');
    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) return [];
    final json = jsonDecode(stdout);
    final list = json['jobs'] as List? ?? [];
    return list.map((j) {
      final map = j as Map<String, dynamic>;
      final sched = map['schedule'];
      String schedStr;
      if (sched is Map) {
        schedStr = sched['expr'] as String? ?? sched['kind'] as String? ?? '0 9 * * *';
      } else {
        schedStr = sched as String? ?? '0 9 * * *';
      }
      return CronJob(
        id: map['id'] ?? '',
        name: map['name'] ?? '未知任务',
        schedule: schedStr,
        prompt: map['prompt'] ?? '',
        status: map['status'] ?? (map['enabled'] == false ? 'paused' : 'active'),
        createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
        skillNames: map['skills'] != null ? List<String>.from(map['skills']) : null,
      );
    }).toList();
  }

  Future<void> _writeJobsToFile(List jobsData) async {
    final homeRes = await _cm.runShell('echo \$HOME', allowFailure: true);
    final home = homeRes.stdout.trim().isNotEmpty ? homeRes.stdout.trim() : r'$HOME';
    final jsonStr = jsonEncode({'jobs': jobsData});
    final b64 = base64Encode(utf8.encode(jsonStr));
    await _cm.execBash('echo "$b64" | base64 -d > "$home/.hermes/cron/jobs.json"');
  }

  Future<void> _loadJobs() async {
    setState(() => _loading = true);
    try {
      final jobs = await _readJobsFromFile();
      if (mounted) setState(() { _jobs = jobs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _prefetchSkills() async {
    try {
      final skills = await _configService.getSkills();
      final names = skills
          .map((s) => (s['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (mounted) {
        setState(() => _skillsCache = names);
      } else {
        _skillsCache = names;
      }
    } catch (_) {}
  }

  Future<void> _toggleJob(CronJob job) async {
    try {
      final cmd = job.isActive ? 'pause' : 'resume';
      final result = await _cm.runHermesCron([cmd, job.id], allowFailure: true);
      final out = result.stdout.trim();
      if (result.exitCode != 0) {
        throw Exception(out.isNotEmpty ? out : 'hermes cron $cmd failed (exit ${result.exitCode})');
      }
      _loadJobs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(job.isActive ? '已暂停 ${job.name}' : '已恢复 ${job.name}')),
        );
      }
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
      final result = await _cm.runHermesCron(['run', job.id], allowFailure: true);
      final out = result.stdout.trim();
      if (result.exitCode != 0) {
        throw Exception(out.isNotEmpty ? out : 'hermes cron run failed (exit ${result.exitCode})');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('任务已触发 ${job.name}')),
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
        title: const Text('确认删除'),
        content: Text('确定要删除定时任务「${job.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error)),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final result = await _cm.runHermesCron(['remove', job.id], allowFailure: true);
        final out = result.stdout.trim();
        if (result.exitCode != 0) {
          throw Exception(out.isNotEmpty ? out : 'hermes cron remove failed (exit ${result.exitCode})');
        }
        _loadJobs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除 ${job.name}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _showAddJobDialog() async {
    final nameController = TextEditingController();
    final skillSearchController = TextEditingController();
    final promptController = TextEditingController();
    String scheduleType = '每天';
    int hour = 9;
    int minute = 0;
    int dayOfMonth = 1;
    List<String> selectedSkills = [];
    if (_skillsCache.isEmpty) {
      await _prefetchSkills();
    }
    final allSkills = List<String>.from(_skillsCache);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      useSafeArea: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredSkills = allSkills.where((s) =>
              skillSearchController.text.isEmpty ||
              s.toLowerCase().contains(skillSearchController.text.toLowerCase())
          ).toList();

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('添加定时任务',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '任务名称', hintText: '输入任务名称',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: scheduleType,
                    decoration: const InputDecoration(labelText: '执行时间', isDense: true),
                    items: ['每天', '工作日', '每月', '自定义']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => scheduleType = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: hour,
                          decoration: const InputDecoration(labelText: '小时', isDense: true),
                          items: List.generate(24, (i) => DropdownMenuItem(
                            value: i, child: Text(i.toString().padLeft(2, '0')),
                          )),
                          onChanged: (v) => setDialogState(() => hour = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: minute,
                          decoration: const InputDecoration(labelText: '分钟', isDense: true),
                          items: List.generate(60, (i) => DropdownMenuItem(
                            value: i, child: Text(i.toString().padLeft(2, '0')),
                          )),
                          onChanged: (v) => setDialogState(() => minute = v!),
                        ),
                      ),
                      if (scheduleType == '每月') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: dayOfMonth,
                            decoration: const InputDecoration(labelText: '日期', isDense: true),
                            items: List.generate(28, (i) => DropdownMenuItem(
                              value: i + 1, child: Text('${i + 1}日'),
                            )),
                            onChanged: (v) => setDialogState(() => dayOfMonth = v!),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('技能选择', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索技能...', isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (v) => setDialogState(() {}),
                    controller: skillSearchController,
                  ),
                  const SizedBox(height: 4),
                  if (selectedSkills.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 6, runSpacing: 4,
                        children: selectedSkills.map((skill) => Chip(
                          label: Text(skill, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onDeleted: () => setDialogState(() => selectedSkills.remove(skill)),
                        )).toList(),
                      ),
                    ),
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: allSkills.isEmpty
                        ? Center(
                            child: Text('暂无可用技能',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)))
                        : ListView(
                            padding: EdgeInsets.zero,
                            children: filteredSkills.map((skill) {
                              final selected = selectedSkills.contains(skill);
                              return CheckboxListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                title: Text(skill, style: const TextStyle(fontSize: 13)),
                                value: selected,
                                onChanged: (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selectedSkills.add(skill);
                                    } else {
                                      selectedSkills.remove(skill);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: promptController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '执行描述',
                      hintText: '输入任务执行描述',
                      isDense: true,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          final cronMap = {
                            'name': name,
                            'scheduleType': scheduleType,
                            'hour': hour,
                            'minute': minute,
                            'dayOfMonth': dayOfMonth,
                            'skills': selectedSkills,
                            'prompt': promptController.text.trim(),
                          };
                          Navigator.pop(ctx, cronMap);
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result == null) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在创建定时任务...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final cronExpr = switch (result['scheduleType'] as String) {
        '每天' => '${result['minute']} ${result['hour']} * * *',
        '工作日' => '${result['minute']} ${result['hour']} * * 1-5',
        '每月' => '${result['minute']} ${result['hour']} ${result['dayOfMonth']} * *',
        _ => '${result['minute']} ${result['hour']} * * *',
      };

      final name = (result['name'] as String).trim();
      final prompt = (result['prompt'] as String).trim();
      final skills = result['skills'] as List<String>? ?? [];

      final args = <String>['create', cronExpr];
      if (prompt.isNotEmpty) args.add(prompt);
      args.addAll(['--name', name]);
      for (final s in skills) {
        args.addAll(['--skill', s]);
      }

      final cmdResult = await _cm.runHermesCron(args, allowFailure: true);
      final out = cmdResult.stdout.trim();
      if (cmdResult.exitCode != 0) {
        throw Exception(out.isNotEmpty ? out : 'hermes cron create failed (exit ${cmdResult.exitCode})');
      }

      await _loadJobs();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务已创建')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    }
  }

  Future<void> _editJob(CronJob job) async {
    final name = job.name;
    final prompt = job.prompt;
    final schedule = job.schedule;
    final parts = schedule.split(' ');
    final hour = parts.length > 1 ? int.tryParse(parts[1]) ?? 9 : 9;
    final minute = parts.length > 0 ? int.tryParse(parts[0]) ?? 0 : 0;
    final dayField = parts.length > 2 ? parts[2] : '*';
    String scheduleType;
    if (dayField == '*') {
      scheduleType = parts.length > 4 && parts[4] == '1-5' ? '工作日' : '每天';
    } else {
      scheduleType = '每月';
    }
    final dayOfMonth = int.tryParse(dayField) ?? 1;

    final result = await _showEditJobDialog(
      initialName: name,
      initialPrompt: prompt,
      initialScheduleType: scheduleType,
      initialHour: hour,
      initialMinute: minute,
      initialDayOfMonth: scheduleType == '每月' ? dayOfMonth : 1,
      initialSkills: job.skillNames ?? [],
    );
    if (result == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在更新定时任务...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final cronExpr = switch (result['scheduleType'] as String) {
        '每天' => '${result['minute']} ${result['hour']} * * *',
        '工作日' => '${result['minute']} ${result['hour']} * * 1-5',
        '每月' => '${result['minute']} ${result['hour']} ${result['dayOfMonth']} * *',
        _ => '${result['minute']} ${result['hour']} * * *',
      };

      final newName = (result['name'] as String).trim();
      final newPrompt = (result['prompt'] as String).trim();
      final skills = result['skills'] as List<String>? ?? [];

      final args = <String>['edit', job.id, '--schedule', cronExpr];
      if (newName != name) {
        args.addAll(['--name', newName]);
      }
      if (newPrompt != prompt) {
        args.addAll(['--prompt', newPrompt]);
      }
      if (skills.isNotEmpty) {
        args.add('--clear-skills');
        for (final s in skills) {
          args.addAll(['--skill', s]);
        }
      }

      final cmdResult = await _cm.runHermesCron(args, allowFailure: true);
      final out = cmdResult.stdout.trim();
      if (cmdResult.exitCode != 0) {
        throw Exception(out.isNotEmpty ? out : 'hermes cron edit failed (exit ${cmdResult.exitCode})');
      }

      await _loadJobs();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showEditJobDialog({
    required String initialName,
    required String initialPrompt,
    required String initialScheduleType,
    required int initialHour,
    required int initialMinute,
    required int initialDayOfMonth,
    required List<String> initialSkills,
  }) async {
    if (_skillsCache.isEmpty) {
      await _prefetchSkills();
    }
    final nameController = TextEditingController(text: initialName);
    final skillSearchController = TextEditingController();
    final promptController = TextEditingController(text: initialPrompt);
    String scheduleType = initialScheduleType;
    int hour = initialHour;
    int minute = initialMinute;
    int dayOfMonth = initialDayOfMonth;
    List<String> selectedSkills = List.from(initialSkills);
    final allSkills = List<String>.from(_skillsCache);

    return showDialog<Map<String, dynamic>>(
      context: context,
      useSafeArea: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredSkills = allSkills.where((s) =>
              skillSearchController.text.isEmpty ||
              s.toLowerCase().contains(skillSearchController.text.toLowerCase())
          ).toList();

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('编辑定时任务',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '任务名称', hintText: '输入任务名称',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: scheduleType,
                    decoration: const InputDecoration(labelText: '执行时间', isDense: true),
                    items: ['每天', '工作日', '每月', '自定义']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => scheduleType = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: hour,
                          decoration: const InputDecoration(labelText: '小时', isDense: true),
                          items: List.generate(24, (i) => DropdownMenuItem(
                            value: i, child: Text(i.toString().padLeft(2, '0')),
                          )),
                          onChanged: (v) => setDialogState(() => hour = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: minute,
                          decoration: const InputDecoration(labelText: '分钟', isDense: true),
                          items: List.generate(60, (i) => DropdownMenuItem(
                            value: i, child: Text(i.toString().padLeft(2, '0')),
                          )),
                          onChanged: (v) => setDialogState(() => minute = v!),
                        ),
                      ),
                      if (scheduleType == '每月') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: dayOfMonth,
                            decoration: const InputDecoration(labelText: '日期', isDense: true),
                            items: List.generate(28, (i) => DropdownMenuItem(
                              value: i + 1, child: Text('${i + 1}日'),
                            )),
                            onChanged: (v) => setDialogState(() => dayOfMonth = v!),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('技能选择', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索技能...', isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (v) => setDialogState(() {}),
                    controller: skillSearchController,
                  ),
                  const SizedBox(height: 4),
                  if (selectedSkills.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 6, runSpacing: 4,
                        children: selectedSkills.map((skill) => Chip(
                          label: Text(skill, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onDeleted: () => setDialogState(() => selectedSkills.remove(skill)),
                        )).toList(),
                      ),
                    ),
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: allSkills.isEmpty
                        ? Center(
                            child: Text('暂无可用技能',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)))
                        : ListView(
                            padding: EdgeInsets.zero,
                            children: filteredSkills.map((skill) {
                              final selected = selectedSkills.contains(skill);
                              return CheckboxListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                title: Text(skill, style: const TextStyle(fontSize: 13)),
                                value: selected,
                                onChanged: (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selectedSkills.add(skill);
                                    } else {
                                      selectedSkills.remove(skill);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: promptController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '执行描述',
                      hintText: '输入任务执行描述',
                      isDense: true,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          Navigator.pop(ctx, {
                            'name': name,
                            'scheduleType': scheduleType,
                            'hour': hour,
                            'minute': minute,
                            'dayOfMonth': dayOfMonth,
                            'skills': selectedSkills,
                            'prompt': promptController.text.trim(),
                          });
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _describeSchedule(CronJob job) {
    final s = job.schedule;
    if (s.startsWith('0 ')) {
      final parts = s.split(' ');
      if (parts.length >= 3) {
        final hour = parts[1];
        final day = parts[2];
        if (day == '*') return '每天 ${hour.padLeft(2, '0')}:00';
        return '每月${day}日 ${hour.padLeft(2, '0')}:00';
      }
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('定时任务'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadJobs, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddJobDialog, tooltip: '添加任务'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _jobs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_outlined, size: 48, color: cs.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text('暂无定时任务', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _jobs.length,
                  itemBuilder: (_, i) => _buildJobCard(_jobs[i], cs),
                ),
    );
  }

  Widget _buildJobCard(CronJob job, ColorScheme cs) {
    final statusColor = job.isActive ? AppTheme.success : cs.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: Text(job.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          job.isActive ? '运行中' : '已暂停',
                          style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(_describeSchedule(job), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            if (job.prompt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(job.prompt, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
            if (job.skillNames != null && job.skillNames!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4, runSpacing: 4,
                children: job.skillNames!.map((s) =>
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(s, style: TextStyle(fontSize: 11, color: AppTheme.info)),
                  ),
                ).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _toggleJob(job),
                  icon: Icon(job.isActive ? Icons.pause : Icons.play_arrow, size: 16),
                  label: Text(job.isActive ? '暂停' : '启用', style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _runJob(job),
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text('立即执行', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _editJob(job),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _deleteJob(job),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}