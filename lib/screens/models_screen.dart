import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/config_service.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final _configService = ConfigService();
  List<Map<String, String>> _skills = [];
  Map<String, String> _modelConfig = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 读取模型配置
      final config = await _configService.readConfig();
      final modelInfo = <String, String>{};
      for (final line in config.split('\n')) {
        final t = line.trim();
        if (t.startsWith('default:')) {
          modelInfo['model'] = t.split(':').sublist(1).join(':').trim();
        }
        if (t.startsWith('provider:')) {
          modelInfo['provider'] = t.split(':').sublist(1).join(':').trim();
        }
        if (t.startsWith('base_url:') || t.startsWith('baseUrl:')) {
          modelInfo['base_url'] = t.split(':').sublist(1).join(':').trim();
        }
      }

      // 读取技能列表
      final skills = await _configService.getSkills();

      setState(() {
        _modelConfig = modelInfo;
        _skills = skills;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型与技能')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 当前模型配置
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.memory_outlined,
                                  color: AppTheme.primary, size: 20),
                              const SizedBox(width: 10),
                              const Text('当前模型',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_modelConfig.isEmpty)
                            Text('未读取到模型配置',
                                style: TextStyle(
                                    color: AppTheme.textSecondary))
                          else
                          ..._modelConfig.entries.map((e) => _configRow(
                              e.key, e.value)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _showModelSelector,
                                icon: const Icon(Icons.swap_horiz, size: 16),
                                label: const Text('切换模型', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '修改 ~/.hermes/config.yaml 中的 model.default 和 model.provider',
                                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 环境变量
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.settings_suggest,
                                  color: AppTheme.info, size: 20),
                              const SizedBox(width: 10),
                              const Text('环境变量',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          FutureBuilder<Map<String, String>>(
                            future: _configService.getEnvVars(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData ||
                                  snapshot.data!.isEmpty) {
                                return Text('无环境变量',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary));
                              }
                              return Column(
                                children: snapshot.data!.entries.map((e) {
                                  final isSecret = e.key
                                      .toLowerCase()
                                      .contains('key');
                                  return _configRow(
                                    e.key,
                                    isSecret
                                        ? '••••${e.value.substring(max(0, e.value.length - 4))}'
                                        : e.value,
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 技能列表标题
                  Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          color: AppTheme.secondary, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        '已安装技能 (${_skills.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 技能列表
                  if (_skills.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.auto_awesome_outlined,
                                  size: 48,
                                  color: Colors.white.withValues(alpha: 0.15)),
                              const SizedBox(height: 12),
                              Text('未找到技能',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ..._skills.map((skill) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.auto_awesome,
                                      size: 18,
                                      color: AppTheme.secondary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        skill['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if ((skill['description'] ?? '')
                                          .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            skill['description'] ?? '',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if ((skill['version'] ?? '').isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white
                                          .withValues(alpha: 0.06),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'v${skill['version']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  void _showModelSelector() {
    final models = [
      'deepseek-v4-flash', 'deepseek-v3', 'deepseek-r1',
      'claude-sonnet-4', 'claude-opus-4', 'claude-haiku-4',
      'gpt-4o', 'gpt-4o-mini',
      'gemini-2.5-pro', 'gemini-2.5-flash',
    ];
    final providers = ['deepseek', 'openrouter', 'anthropic', 'openai', 'gemini'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换模型'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择 Provider:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _modelConfig['provider'] ?? 'deepseek',
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: providers.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) {
                  if (v != null) _modelConfig['provider'] = v;
                },
              ),
              const SizedBox(height: 16),
              Text('选择模型:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _modelConfig['model'] ?? models[0],
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: models.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) {
                  if (v != null) _modelConfig['model'] = v;
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppTheme.warning),
                    SizedBox(width: 6),
                    Expanded(child: Text('修改会写入 ~/.hermes/config.yaml，需要重启 Gateway 生效', style: TextStyle(fontSize: 11, color: AppTheme.warning))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              _saveModelConfig();
              Navigator.pop(ctx);
            },
            child: const Text('保存并重启 Gateway'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveModelConfig() async {
    final provider = _modelConfig['provider'] ?? 'deepseek';
    final model = _modelConfig['model'] ?? 'deepseek-v4-flash';
    // Read current config, update model section
    try {
      final file = File('${Platform.environment['HOME'] ?? '/home/tian'}/.hermes/config.yaml');
      if (await file.exists()) {
        var content = await file.readAsString();
        content = content.replaceAll(RegExp(r'^default:.*$', multiLine: true), 'default: $model');
        content = content.replaceAll(RegExp(r'^provider:.*$', multiLine: true), 'provider: $provider');
        await file.writeAsString(content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('配置已保存，请重启 Gateway')),
          );
          _loadData();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Widget _configRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              key,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
