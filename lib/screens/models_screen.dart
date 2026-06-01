import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/config_service.dart';
import '../services/connection_manager.dart';
import '../services/gateway_service.dart';
import '../services/hermes_file_service.dart';
import 'chat_screen.dart';

/// Provider → 可选模型列表
const Map<String, List<String>> providerModels = {
  'deepseek': [
    'deepseek-v4-flash', 'deepseek-v3', 'deepseek-r1',
    'deepseek-r1-distill-qwen-32b',
  ],
  'openrouter': [
    'anthropic/claude-sonnet-4', 'anthropic/claude-opus-4', 'anthropic/claude-haiku-4',
    'openai/gpt-4o', 'openai/gpt-4o-mini', 'openai/gpt-4.1', 'openai/o3', 'openai/o4-mini',
    'google/gemini-2.5-pro', 'google/gemini-2.5-flash',
    'deepseek/deepseek-v4-flash', 'deepseek/deepseek-v3', 'deepseek/deepseek-r1',
    'meta-llama/llama-4', 'meta-llama/llama-3.3-70b',
    'cohere/command-r7', 'cohere/command-r-plus',
    'mistralai/mistral-large', 'mistralai/mistral-saba',
    'qwen/qwen-max', 'qwen/qwen-plus',
  ],
  'anthropic': [
    'claude-sonnet-4', 'claude-opus-4', 'claude-haiku-4',
    'claude-sonnet-4-20250514', 'claude-opus-4-20250514',
  ],
  'openai': [
    'gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'gpt-4.1-nano',
    'o3', 'o3-mini', 'o4-mini',
    'gpt-4.1-2025-04-14', 'gpt-4o-2024-08-06',
  ],
  'gemini': [
    'gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.5-flash-lite',
    'gemini-2.0-flash', 'gemini-1.5-pro', 'gemini-1.5-flash',
  ],
  'kimi': [
    'kimi-k2.5', 'kimi-k2', 'kimi-v1.5',
  ],
  'ollama': [
    'llama-3.3-70b', 'llama-3.1-8b', 'qwen-2.5-72b', 'qwen-2.5-32b',
    'mistral-large', 'mixtral-8x22b', 'deepseek-r1-70b',
    'gemma-3-27b', 'phi-4', 'nomic-embed-text',
  ],
  'glm': [
    'glm-4-plus', 'glm-4-air', 'glm-4-long', 'glm-4-flash',
    'glm-5', 'glm-5-flash',
  ],
  'minimax': [
    'minimax-m2.5', 'minimax-m1', 'minimax-text-01',
  ],
  'arcee': [
    'trinity-mini', 'trinity-large', 'trinity-medium',
    'arcee-neo', 'arcee-7b',
  ],
  'opencode-zen': [
    'gpt-4o', 'claude-sonnet-4', 'gemini-2.5-pro',
    'deepseek-v4-flash', 'qwen-max',
  ],
  'opencode-go': [
    'glm-5', 'kimi-k2.5', 'minimax-m2.5',
    'qwen-plus', 'deepseek-v3',
  ],
  'huggingface': [
    'meta-llama/Llama-4', 'meta-llama/Llama-3.3-70B-Instruct',
    'mistralai/Mistral-Large', 'mistralai/Mistral-Saba',
    'Qwen/Qwen2.5-72B-Instruct', 'deepseek-ai/DeepSeek-R1',
    'google/gemma-3-27b-it',
  ],
  'qwen': [
    'qwen-max', 'qwen-plus', 'qwen-turbo', 'qwen-long',
    'qwen-max-2026-01-25',
  ],
  'xiaomi': [
    'mimo-v2-pro', 'mimo-v2-flash', 'mimo-v2-omni',
    'mimo-v2-vision',
  ],
};

/// Provider → 默认 Base URL
const Map<String, String> providerBaseUrls = {
  'deepseek': 'https://api.deepseek.com/v1',
  'openrouter': 'https://openrouter.ai/api/v1',
  'anthropic': 'https://api.anthropic.com/v1',
  'openai': 'https://api.openai.com/v1',
  'gemini': 'https://generativelanguage.googleapis.com/v1beta/openai',
  'kimi': 'https://api.moonshot.cn/v1',
  'ollama': 'https://ollama.com/v1',
  'glm': 'https://api.z.ai/api/paas/v4',
  'minimax': 'https://api.minimax.io/v1',
  'arcee': 'https://api.arcee.ai/v1',
  'opencode-zen': 'https://opencode.ai/zen/v1',
  'opencode-go': 'https://opencode.ai/zen/go/v1',
  'huggingface': 'https://api-inference.huggingface.co/v1',
  'qwen': 'https://portal.qwen.ai/v1',
  'xiaomi': 'https://api.xiaomimimo.com/v1',
};

const allProviders = [
  'deepseek', 'openrouter', 'anthropic', 'openai', 'gemini', 'kimi',
  'ollama', 'glm', 'minimax', 'arcee',
  'opencode-zen', 'opencode-go', 'huggingface', 'qwen', 'xiaomi',
];

class ModelsScreen extends StatefulWidget {
  final void Function(int index) onNavigate;

  const ModelsScreen({super.key, required this.onNavigate});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final _configService = ConfigService();
  List<Map<String, String>> _skills = [];
  Map<String, String> _modelConfig = {};
  bool _loading = true;
  late final VoidCallback _onRefresh;

  @override
  void initState() {
    super.initState();
    _onRefresh = () => _loadData(forceRefresh: true);
    _loadData();
    GatewayService().refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    GatewayService().refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (forceRefresh) HermesFileService.clearCache();
    setState(() => _loading = true);
    try {
      // 批量读取配置 + 技能（local/remote 只需 1 次 SSH 往返）
      final result = await _configService.readConfigAndSkills();
      final config = result.config;

      final modelInfo = <String, String>{};
      String? currentSection;
      for (final line in config.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;

        // 顶层 section 标记（缩进为0且以:结尾）
        final indent = line.length - line.trimLeft().length;
        if (indent == 0 && t.endsWith(':') && !t.startsWith('-')) {
          currentSection = t.substring(0, t.length - 1);
          continue;
        }

        // 在 model: section 内解析 key: value
        if (currentSection == 'model' && indent > 0 && t.contains(':')) {
          final sep = t.indexOf(':');
          final key = t.substring(0, sep).trim();
          final val = t.substring(sep + 1).trim();
          if (key == 'default' || key == 'model') {
            modelInfo['model'] = val;
          } else if (key == 'provider') {
            modelInfo['provider'] = val;
          } else if (key == 'base_url' || key == 'baseUrl') {
            modelInfo['base_url'] = val;
          }
        }

        // 也兼容根级 key（旧配置格式）
        if (indent == 0) {
          if ((t.startsWith('default:') || t.startsWith('model:')) && !modelInfo.containsKey('model')) {
            final sep = t.indexOf(':');
            modelInfo['model'] = t.substring(sep + 1).trim();
          }
          if (t.startsWith('provider:') && !modelInfo.containsKey('provider')) {
            final sep = t.indexOf(':');
            modelInfo['provider'] = t.substring(sep + 1).trim();
          }
          if ((t.startsWith('base_url:') || t.startsWith('baseUrl:')) && !modelInfo.containsKey('base_url')) {
            final sep = t.indexOf(':');
            modelInfo['base_url'] = t.substring(sep + 1).trim();
          }
        }
      }

      final skills = result.skills;

      setState(() {
        _modelConfig = modelInfo;
        _skills = skills;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmDeleteSkill(String path, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除技能'),
        content: Text('确定要删除技能「$name」吗？\n\n此操作会从磁盘上删除该技能目录，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await HermesFileService().deleteDir(path);
      if (mounted) {
        if (ok) {
          setState(() => _skills.removeWhere((s) => s['path'] == path));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '已删除「$name」' : '删除失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型与技能')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadData(forceRefresh: true),
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('未读取到模型配置',
                                    style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                if (ConnectionManager().state.mode == ConnectionMode.embedded) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline, size: 14, color: AppTheme.warning),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '内嵌模式配置文件可能不存在，请点击"切换模型"配置后保存',
                                          style: TextStyle(fontSize: 12, color: AppTheme.warning),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            )
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
                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
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
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(height: 12),
                              Text('未找到技能',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ..._skills.map((skill) => GestureDetector(
                          onSecondaryTapUp: (details) {
                            showMenu<String>(
                              context: context,
                              position: RelativeRect.fromLTRB(
                                details.globalPosition.dx,
                                details.globalPosition.dy,
                                details.globalPosition.dx + 1,
                                details.globalPosition.dy + 1,
                              ),
                              items: [
                                PopupMenuItem(
                                  value: 'invoke',
                                  child: Row(
                                    children: [
                                      Icon(Icons.play_arrow, size: 16, color: AppTheme.primary),
                                      const SizedBox(width: 8),
                                      const Text('调用'),
                                    ],
                                  ),
                                ),
                              ],
                            ).then((value) {
                              if (value == 'invoke') {
                                final skillName = skill['name'] ?? '';
                                if (skillName.isNotEmpty) {
                                  ChatScreen.skillInvocationNotifier.value = skillName;
                                  widget.onNavigate(1);
                                }
                              }
                            });
                          },
                          child: Card(
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
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        size: 16,
                                        color: AppTheme.error.withValues(alpha: 0.7)),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: '删除技能',
                                    onPressed: () => _confirmDeleteSkill(skill['path'] ?? '', skill['name'] ?? ''),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  /// 切换模型弹窗 — 可滚动 + Provider 联动模型 + 默认 Base URL
  void _showModelSelector() {
    String selectedProvider = _modelConfig['provider'] ?? 'deepseek';
    String selectedModel = _modelConfig['model'] ?? 'deepseek-v4-flash';
    String baseUrl = _modelConfig['base_url'] ?? providerBaseUrls[selectedProvider] ?? '';
    bool showCustomModel = false; // 是否显示自定义模型输入

    final baseUrlCtrl = TextEditingController(text: baseUrl);
    final apiKeyCtrl = TextEditingController(text: '');
    final modelCtrl = TextEditingController(text: selectedModel);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final models = providerModels[selectedProvider] ?? [];
          final isCustom = showCustomModel || !models.contains(selectedModel);

          return AlertDialog(
            title: const Text('切换模型'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Provider ──
                    Text('Provider',
                        style: TextStyle(fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedProvider,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: allProviders
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          selectedProvider = v;
                          // 自动填充 Base URL
                          baseUrl = providerBaseUrls[v] ?? '';
                          baseUrlCtrl.text = baseUrl;
                          // 自动选第一个模型
                          final newModels = providerModels[v] ?? [];
                          if (newModels.isNotEmpty) {
                            selectedModel = newModels.first;
                            modelCtrl.text = selectedModel;
                          } else {
                            selectedModel = '';
                            modelCtrl.text = '';
                          }
                          showCustomModel = false;
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── 模型 ──
                    Text('模型',
                        style: TextStyle(fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    if (models.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: isCustom ? '__custom__' : selectedModel,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          ...models.map((m) =>
                              DropdownMenuItem(value: m, child: Text(m))),
                          const DropdownMenuItem(
                              value: '__custom__',
                              child: Text('其他（自定义模型名）')),
                        ],
                        onChanged: (v) {
                          if (v == '__custom__') {
                            setDialogState(() {
                              showCustomModel = true;
                              modelCtrl.text = selectedModel;
                            });
                          } else if (v != null) {
                            setDialogState(() {
                              showCustomModel = false;
                              selectedModel = v;
                              modelCtrl.text = v;
                            });
                          }
                        },
                      ),
                    if (isCustom)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextField(
                          controller: modelCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            hintText: '输入模型名称',
                          ),
                          onChanged: (v) => selectedModel = v,
                        ),
                      ),
                    const SizedBox(height: 12),

                    // ── Base URL ──
                    Text('Base URL',
                        style: TextStyle(fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: baseUrlCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        hintText: 'https://api.deepseek.com/v1',
                      ),
                      onChanged: (v) => baseUrl = v,
                    ),
                    const SizedBox(height: 12),

                    // ── API Key ──
                    Text('API Key（留空则不修改）',
                        style: TextStyle(fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: apiKeyCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        hintText: '新的 API Key（存 ~/.hermes/.env）',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── 提示 ──
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 14, color: AppTheme.warning),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '修改会写入 ~/.hermes/config.yaml（和 .env），需要重启 Gateway 生效',
                              style: TextStyle(fontSize: 11, color: AppTheme.warning),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  _saveModelConfig(
                    provider: selectedProvider,
                    model: modelCtrl.text.trim(),
                    baseUrl: baseUrlCtrl.text.trim(),
                    apiKey: apiKeyCtrl.text.trim(),
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('保存并重启 Gateway'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveModelConfig({
    required String provider,
    required String model,
    String baseUrl = '',
    String apiKey = '',
  }) async {
    if (model.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模型名称不能为空')),
        );
      }
      return;
    }
    try {
      // 通过 ConfigService 读写，自动适配 local/embedded/remote 模式
      var config = await _configService.readConfig();

      // config.yaml 不存在时生成最小模板
      if (config.isEmpty || config == 'config not found') {
        config = 'model:\n  default: $model\n  provider: $provider\n';
        if (baseUrl.isNotEmpty) config += '  base_url: $baseUrl\n';
      } else {
        // model/default 都可能用作模型名
        config = config.replaceAll(
            RegExp(r'^(\s+)(?:default|model):.*$', multiLine: true), '  default: $model');
        config = config.replaceAll(
            RegExp(r'^(\s+)provider:.*$', multiLine: true), '  provider: $provider');
        if (baseUrl.isNotEmpty) {
          config = config.replaceAll(
              RegExp(r'^(\s+)base_url:.*$', multiLine: true), '  base_url: $baseUrl');
        }
      }
      final saved = await _configService.writeConfig(config);
      if (!saved) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('配置写入失败，请检查文件权限')),
          );
        }
        return;
      }

      // 写 .env（API Key + Base URL 的环境变量）
      if (apiKey.isNotEmpty) {
        var envContent = await _configService.readEnvFile();
        final providerUpper = provider.toUpperCase();
        final keyVar = '${providerUpper}_API_KEY';
        if (envContent.contains('$keyVar=')) {
          envContent = envContent.replaceAll(
            RegExp('^$keyVar=.*' r'$', multiLine: true),
            '$keyVar=$apiKey',
          );
        } else {
          envContent += '\n$keyVar=$apiKey\n';
        }
        if (baseUrl.isNotEmpty) {
          final urlVar = '${providerUpper}_BASE_URL';
          if (envContent.contains('$urlVar=')) {
            envContent = envContent.replaceAll(
              RegExp('^$urlVar=.*' r'$', multiLine: true),
              '$urlVar=$baseUrl',
            );
          } else {
            envContent += '\n$urlVar=$baseUrl\n';
          }
        }
        await _configService.writeEnvFile(envContent);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已保存，正在重启 Gateway...')),
        );
      }

      // 重启 Gateway 使新配置生效
      final cm = ConnectionManager();
      if (cm.state.mode == ConnectionMode.embedded) {
        await cm.restartEmbeddedGateway();
      } else {
        await GatewayService().restartGateway();
        // 本地/远程模式等待 Gateway 重新就绪（最长 10s）
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (await cm.checkLocal()) break;
        }
      }

      if (mounted) {
        _loadData(forceRefresh: true);
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int max(int a, int b) => a > b ? a : b;
