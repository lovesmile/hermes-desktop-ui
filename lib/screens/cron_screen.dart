import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/connection_manager.dart';
import '../services/config_service.dart';
import '../services/hermes_file_service.dart';
import '../services/gateway_service.dart';
import '../models/cron_job.dart';

class CronScreen extends StatefulWidget {
  const CronScreen({super.key});
  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> with SingleTickerProviderStateMixin {
  final _cm = ConnectionManager();
  final _gateway = GatewayService();
  final _configService = ConfigService();
  final _fileService = HermesFileService();
  late final TabController _tabController;
  List<CronJob> _jobs = [];
  List<CronJob> _systemJobs = [];
  String _systemCrontabRaw = '';
  List<String> _skillsCache = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    unawaited(_prefetchSkills());
    _loadJobs();
    GatewayService().refreshNotifier.addListener(_onModeChanged);
  }

  @override
  void dispose() {
    GatewayService().refreshNotifier.removeListener(_onModeChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onModeChanged() {
    _skillsCache.clear();
    _loadJobs();
    unawaited(_prefetchSkills());
  }

  Future<List<CronJob>> _readJobsFromFile() async {
    try {
      final hermesHome = await _fileService.resolveHermesHome();
      final content = await _fileService.readText('$hermesHome/cron/jobs.json');
      if (content.isEmpty) return [];
      final json = jsonDecode(content);
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
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeJobsToFile(List jobsData) async {
    try {
      final hermesHome = await _fileService.resolveHermesHome();
      final jsonStr = jsonEncode({'jobs': jobsData});
      await _fileService.writeText('$hermesHome/cron/jobs.json', jsonStr);
    } catch (_) {}
  }

  Future<void> _loadJobs() async {
    setState(() => _loading = true);
    try {
      final jobs = await _readJobsFromFile();
      final systemJobs = await _readSystemCrontab();
      if (mounted) setState(() { _jobs = jobs; _systemJobs = systemJobs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<CronJob>> _readSystemCrontab() async {
    if (_cm.state.mode == ConnectionMode.embedded) return [];
    try {
      final result = await _cm.runShell('crontab -l 2>/dev/null', allowFailure: true);
      final output = result.stdout;
      _systemCrontabRaw = output;
      if (output.trim().isEmpty) return [];

      final jobs = <CronJob>[];
      for (final rawLine in output.split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('@reboot')) continue;
        if (RegExp(r'^[A-Za-z_]\w*\s*=').hasMatch(line)) continue;

        // 解析可能被 # 暂停的任务行
        final isPaused = line.startsWith('#');
        final effective = isPaused ? line.substring(1).trim() : line;

        String schedule;
        String command;
        if (effective.startsWith('@')) {
          const aliasMap = {
            '@hourly': '0 * * * *',
            '@daily': '0 0 * * *',
            '@weekly': '0 0 * * 0',
            '@monthly': '0 0 1 * *',
            '@yearly': '0 0 1 1 *',
            '@annually': '0 0 1 1 *',
          };
          final alias = effective.split(RegExp(r'\s+')).first;
          final aliasSched = aliasMap[alias];
          if (aliasSched == null) continue;
          schedule = aliasSched;
          command = effective.substring(alias.length).trim();
        } else {
          final parts = effective.split(RegExp(r'\s+'));
          if (parts.length < 6) continue; // 不是 cron 行，跳过（普通注释）
          schedule = parts.take(5).join(' ');
          command = parts.skip(5).join(' ');
        }

        if (command.isEmpty) continue;
        final cmdDisplay = command.length > 50 ? '${command.substring(0, 50)}...' : command;
        final id = 'sys_${_simpleHash('$schedule|$command')}';
        jobs.add(CronJob(
          id: id,
          name: cmdDisplay,
          schedule: schedule,
          prompt: command,
          status: isPaused ? 'paused' : 'active',
          createdAt: DateTime.now(),
        ));
      }
      return jobs;
    } catch (_) {
      return [];
    }
  }

  String _simpleHash(String input) {
    int hash = 0;
    for (final byte in utf8.encode(input)) {
      hash = ((hash << 5) - hash) + byte;
      hash = hash & hash;
    }
    return hash.toRadixString(16);
  }

  String? _extractJobId(String output) {
    try {
      final json = jsonDecode(output);
      if (json is Map && json['id'] != null) return json['id'].toString();
    } catch (_) {}
    final m = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        .firstMatch(output);
    return m?.group(0);
  }

  // ── 系统 crontab 管理 ──────────────────────────────────────────

  Future<String> _readRawCrontab() async {
    if (_cm.state.mode == ConnectionMode.embedded) return '';
    final result = await _cm.runShell('crontab -l 2>/dev/null', allowFailure: true);
    return result.stdout;
  }

  Future<void> _writeRawCrontab(String content) async {
    final escaped = content.replaceAll("'", "'\\''");
    await _cm.runShell(
      "printf '%s' '$escaped' > /tmp/_hcron.tmp && crontab /tmp/_hcron.tmp && rm -f /tmp/_hcron.tmp",
      allowFailure: true,
    );
  }

  bool _isSystemJobPaused(CronJob job) {
    final target = '${job.schedule} ${job.prompt}'.trim();
    for (final line in _systemCrontabRaw.split('\n')) {
      if (line.trim() == '#$target') return true;
    }
    return false;
  }

  Future<void> _toggleSystemJob(CronJob job) async {
    try {
      final raw = await _readRawCrontab();
      final lines = raw.split('\n');
      final target = '${job.schedule} ${job.prompt}'.trim();
      bool modified = false;
      final newLines = lines.map((line) {
        if (modified) return line;
        final trimmed = line.trim();
        final isCommented = trimmed.startsWith('#');
        final effective = isCommented ? trimmed.substring(1).trim() : trimmed;
        if (effective == target) {
          modified = true;
          return isCommented ? line.replaceFirst('#', '') : '#$line';
        }
        return line;
      }).toList();
      if (!modified) throw Exception('未找到匹配的定时任务行');
      final newCrontab = newLines.join('\n');
      await _writeRawCrontab(newCrontab);
      _systemCrontabRaw = newCrontab;
      if (mounted) {
        final nowPaused = _isSystemJobPaused(job);
        setState(() {
          final idx = _systemJobs.indexWhere((j) => j.id == job.id);
          if (idx >= 0) {
            final old = _systemJobs[idx];
            _systemJobs[idx] = CronJob(
              id: old.id,
              name: old.name,
              schedule: old.schedule,
              prompt: old.prompt,
              status: nowPaused ? 'paused' : 'active',
              createdAt: old.createdAt,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(nowPaused ? '已暂停 ${job.name}' : '已恢复 ${job.name}')),
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

  Future<void> _runSystemJob(CronJob job) async {
    try {
      final result = await _cm.runShell(job.prompt, allowFailure: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('命令已执行 (exit ${result.exitCode})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('执行失败: $e')),
        );
      }
    }
  }

  Future<void> _editSystemJob(CronJob job) async {
    final schedController = TextEditingController(text: job.schedule);
    final cmdController = TextEditingController(text: job.prompt);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑系统定时任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: schedController,
              decoration: const InputDecoration(
                labelText: '执行时间 (cron 表达式)',
                hintText: '0 9 * * *',
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: cmdController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '命令',
                isDense: true,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'schedule': schedController.text.trim(),
              'command': cmdController.text.trim(),
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    final newSched = result['schedule'] ?? '';
    final newCmd = result['command'] ?? '';
    if (newSched.isEmpty || newCmd.isEmpty) return;

    try {
      final raw = await _readRawCrontab();
      final lines = raw.split('\n');
      final target = '${job.schedule} ${job.prompt}'.trim();
      final newLines = lines.map((line) {
        final trimmed = line.trim();
        if (trimmed == target || trimmed == '#$target') {
          return '$newSched $newCmd';
        }
        return line;
      }).toList();
      final newCrontab = newLines.join('\n');
      await _writeRawCrontab(newCrontab);
      _systemCrontabRaw = newCrontab;
      if (mounted) {
        setState(() {
          final idx = _systemJobs.indexWhere((j) => j.id == job.id);
          if (idx >= 0) {
            final old = _systemJobs[idx];
            _systemJobs[idx] = CronJob(
              id: old.id,
              name: newCmd.length > 50 ? '${newCmd.substring(0, 50)}...' : newCmd,
              schedule: newSched,
              prompt: newCmd,
              status: old.status,
              createdAt: old.createdAt,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteSystemJob(CronJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除系统定时任务「${job.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final raw = await _readRawCrontab();
      final lines = raw.split('\n');
      final target = '${job.schedule} ${job.prompt}'.trim();
      final newLines = <String>[];
      bool found = false;
      for (final line in lines) {
        if (!found) {
          final trimmed = line.trim();
          if (trimmed == target || trimmed == '#$target') {
            found = true;
            continue;
          }
        }
        newLines.add(line);
      }
      if (!found) throw Exception('未找到匹配的定时任务行');
      await _writeRawCrontab(newLines.join('\n'));
      if (mounted) {
        setState(() => _systemJobs.removeWhere((j) => j.id == job.id));
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
      if (mounted) {
        setState(() {
          final idx = _jobs.indexWhere((j) => j.id == job.id);
          if (idx >= 0) {
            final old = _jobs[idx];
            _jobs[idx] = CronJob(
              id: old.id,
              name: old.name,
              schedule: old.schedule,
              prompt: old.prompt,
              status: job.isActive ? 'paused' : 'active',
              createdAt: old.createdAt,
              skillNames: old.skillNames,
            );
          }
        });
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
        if (mounted) {
          setState(() => _jobs.removeWhere((j) => j.id == job.id));
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
    String customCronExpr = '';
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
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
                    items: ['每天', '工作日', '自定义']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => scheduleType = v!),
                  ),
                  const SizedBox(height: 12),
                  if (scheduleType == '自定义')
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          decoration: const InputDecoration(
                            hintText: 'cron 表达式，如 0 9 * * 1',
                            isDense: true,
                          ),
                          onChanged: (v) => setDialogState(() => customCronExpr = v),
                        ),
                        const SizedBox(height: 6),
                        Text('分钟 小时 日期 月份 星期  （* = 任意, */N = 每N, 1-5 = 范围, 1,3,5 = 列表）',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    )
                  else
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
                            'customCron': customCronExpr,
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
        '自定义' => (result['customCron'] as String?)?.trim() ?? '',
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

      // 增量刷新：从输出提取 job id，取不到用临时 id，始终不触发全量刷新
      final jobId = _extractJobId(out) ?? 'new_${DateTime.now().millisecondsSinceEpoch}';
      if (mounted) {
        setState(() {
          _jobs.insert(0, CronJob(
            id: jobId,
            name: name,
            schedule: cronExpr,
            prompt: prompt,
            status: 'active',
            createdAt: DateTime.now(),
            skillNames: skills.isNotEmpty ? skills : null,
          ));
        });
      }

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
          SnackBar(content: Text('创建失败: $e'), backgroundColor: AppTheme.error),
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
    String customCronExpr;
    if (parts.length < 5) {
      scheduleType = '自定义';
      customCronExpr = schedule;
    } else if (dayField == '*') {
      scheduleType = parts.length > 4 && parts[4] == '1-5' ? '工作日' : '每天';
      customCronExpr = '';
    } else {
      scheduleType = '自定义';
      customCronExpr = schedule;
    }
    final dayOfMonth = int.tryParse(dayField) ?? 1;

    final result = await _showEditJobDialog(
      initialName: name,
      initialPrompt: prompt,
      initialScheduleType: scheduleType,
      initialHour: hour,
      initialMinute: minute,
      initialDayOfMonth: 1,
      initialCustomCron: customCronExpr,
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
        '自定义' => (result['customCron'] as String?)?.trim() ?? '',
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

      if (mounted) {
        setState(() {
          final idx = _jobs.indexWhere((j) => j.id == job.id);
          if (idx >= 0) {
            final old = _jobs[idx];
            _jobs[idx] = CronJob(
              id: old.id,
              name: newName,
              schedule: cronExpr,
              prompt: newPrompt,
              status: old.status,
              createdAt: old.createdAt,
              skillNames: skills.isNotEmpty ? skills : null,
            );
          }
        });
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
    required String initialCustomCron,
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
    String customCronExpr = initialCustomCron;
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
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
                    items: ['每天', '工作日', '自定义']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => scheduleType = v!),
                  ),
                  const SizedBox(height: 12),
                  if (scheduleType == '自定义')
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          decoration: const InputDecoration(
                            hintText: 'cron 表达式，如 0 9 * * 1',
                            isDense: true,
                          ),
                          onChanged: (v) => setDialogState(() => customCronExpr = v),
                        ),
                        const SizedBox(height: 6),
                        Text('分钟 小时 日期 月份 星期  （* = 任意, */N = 每N, 1-5 = 范围, 1,3,5 = 列表）',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    )
                  else
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
                            'customCron': customCronExpr,
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Hermes 定时任务'),
            Tab(text: '系统定时任务'),
          ],
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadJobs, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddJobDialog, tooltip: '添加任务'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildHermesTab(cs),
                _buildSystemTab(cs),
              ],
            ),
    );
  }

  Widget _buildHermesTab(ColorScheme cs) {
    if (_jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('暂无 Hermes 定时任务', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('由 Hermes 管理的任务，支持完整的启用/暂停/编辑/删除操作',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        ..._jobs.map((j) => _buildJobCard(j, cs)),
      ],
    );
  }

  Widget _buildSystemTab(ColorScheme cs) {
    if (_systemJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.computer_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('暂无系统定时任务', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('系统 crontab 中的任务，通过注释/取消注释行来启停',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        ..._systemJobs.map((j) => _buildSystemJobCard(j, cs)),
      ],
    );
  }

  Widget _buildSystemJobCard(CronJob job, ColorScheme cs) {
    final paused = _isSystemJobPaused(job);
    final statusColor = paused ? cs.onSurfaceVariant : AppTheme.success;
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
                      Flexible(child: Text(job.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: paused ? cs.onSurfaceVariant.withValues(alpha: 0.12) : AppTheme.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          paused ? '已暂停' : '系统',
                          style: TextStyle(fontSize: 10, color: paused ? cs.onSurfaceVariant : AppTheme.success, fontWeight: FontWeight.w500),
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
              SelectableText(job.prompt,
                  style: TextStyle(fontSize: 12, fontFamily: 'JetBrainsMono', color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _toggleSystemJob(job),
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 16),
                  label: Text(paused ? '启用' : '暂停', style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _runSystemJob(job),
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text('立即执行', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _editSystemJob(job),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _deleteSystemJob(job),
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
                      Flexible(child: Text(job.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
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