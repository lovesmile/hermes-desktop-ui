import 'package:flutter/material.dart';

import '../services/config_service.dart';
import '../services/gateway_service.dart';

/// 模型选择对话框返回结果
class ModelSelectionResult {
  final String model;
  final String provider;

  const ModelSelectionResult({
    required this.model,
    required this.provider,
  });
}

/// 打开模型选择对话框
Future<ModelSelectionResult?> showModelSelectionDialog(
  BuildContext context, {
  String? currentModel,
  String? currentProvider,
}) {
  return showDialog<ModelSelectionResult>(
    context: context,
    builder: (ctx) => _ModelSelectionDialog(
      currentModel: currentModel,
      currentProvider: currentProvider,
    ),
  );
}

class _ModelSelectionDialog extends StatefulWidget {
  final String? currentModel;
  final String? currentProvider;
  const _ModelSelectionDialog({this.currentModel, this.currentProvider});

  @override
  State<_ModelSelectionDialog> createState() => _ModelSelectionDialogState();
}

class _ModelSelectionDialogState extends State<_ModelSelectionDialog> {
  final _configService = ConfigService();
  final _modelCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();

  String _provider = '';
  String _model = '';
  String _baseUrl = '';
  bool _useQuickList = true;
  bool _saving = false;
  bool _loadingConfig = true;
  List<String> _configuredProviders = []; // 已配置 API Key 的 provider
  String _configModel = ''; // config.yaml 中的模型
  String _configProvider = ''; // config.yaml 中的 provider

  @override
  void initState() {
    super.initState();
    _provider = widget.currentProvider ?? 'deepseek';
    _model = widget.currentModel ?? '';
    _baseUrl = _lookupBaseUrl(_provider);
    _modelCtrl.text = _model;
    _baseUrlCtrl.text = _baseUrl;
    _loadConfiguredProviders();
  }

  Future<void> _loadConfiguredProviders() async {
    try {
      // 读取 .env 中实际配置的 API Key
      final envVars = await _configService.getEnvVars();
      // 读取 config.yaml 当前模型配置
      final cfg = await _configService.readModelConfig();
      _configModel = cfg['model'] ?? '-';
      _configProvider = cfg['provider'] ?? '-';

      final configured = <String>[];
      for (final p in GatewayService.allProviders) {
        if (p == 'custom') continue; // 自定义在完整表单中配置
        final keyName = _envKeyForProvider(p);
        if (keyName.isEmpty) {
          // 无需 API Key 的 provider（如 ollama），只有是当前在用时才显示
          if (p == widget.currentProvider) configured.add(p);
          continue;
        }
        if (envVars.containsKey(keyName) &&
            (envVars[keyName] ?? '').isNotEmpty) {
          configured.add(p);
        }
      }
      // 始终包含当前正在使用的 provider（可能通过其他方式配置）
      if (widget.currentProvider != null &&
          !configured.contains(widget.currentProvider)) {
        configured.add(widget.currentProvider!);
      }
      if (mounted) {
        setState(() {
          _configuredProviders = configured;
          _loadingConfig = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _configuredProviders = List.from(GatewayService.allProviders);
          _loadingConfig = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  String _lookupBaseUrl(String provider) =>
      GatewayService.providerBaseUrls[provider] ?? '';

  String _providerLabel(String key) {
    switch (key) {
      case 'openai': return 'OpenAI';
      case 'anthropic': return 'Anthropic';
      case 'gemini': return 'Google Gemini';
      case 'deepseek': return 'DeepSeek';
      case 'openrouter': return 'OpenRouter';
      case 'kimi': return 'Kimi (月之暗面)';
      case 'ollama': return 'Ollama (本地)';
      case 'glm': return 'GLM (智谱)';
      case 'minimax': return 'MiniMax';
      case 'arcee': return 'Arcee';
      case 'opencode-zen': return 'OpenCode Zen';
      case 'opencode-go': return 'OpenCode Go';
      case 'huggingface': return 'HuggingFace';
      case 'qwen': return 'Qwen (阿里通义)';
      case 'xiaomi': return 'Xiaomi (小米)';
      case 'custom': return '自定义';
      default: return key;
    }
  }

  void _setProvider(String p) {
    setState(() {
      _provider = p;
      _baseUrl = _lookupBaseUrl(p);
      _baseUrlCtrl.text = _baseUrl;
      final models = GatewayService.providerModels[p] ?? [];
      if (models.isNotEmpty && !models.contains(_model)) {
        _model = models.first;
        _modelCtrl.text = _model;
      }
    });
  }

  void _selectModel(String model, String provider) {
    setState(() {
      _model = model;
      _provider = provider;
      _modelCtrl.text = model;
      _baseUrl = _lookupBaseUrl(provider);
      _baseUrlCtrl.text = _baseUrl;
    });
  }

  Future<void> _saveAndRestart() async {
    final m = _modelCtrl.text.trim();
    final b = _baseUrlCtrl.text.trim();
    final k = _apiKeyCtrl.text.trim();
    if (m.isEmpty) return;

    setState(() => _saving = true);

    // 写 config.yaml
    try {
      var config = await _configService.readConfig();
      final lines = config.split('\n');
      int modelSectionStart = -1;
      int modelSectionEnd = -1;
      bool foundDefault = false;
      bool foundProvider = false;
      bool foundBaseUrl = false;

      for (int i = 0; i < lines.length; i++) {
        final t = lines[i].trim();
        final indent = lines[i].length - lines[i].trimLeft().length;
        if (t == 'model:' && indent == 0) {
          modelSectionStart = i;
          continue;
        }
        if (modelSectionStart >= 0 && modelSectionEnd < 0) {
          // 遇到下一个顶层 key 或列表项则退出
          if (lines[i].isNotEmpty && t.endsWith(':') && indent == 0 && !t.startsWith('-')) {
            modelSectionEnd = i;
            break;
          }
          if (t.startsWith('default:')) {
            lines[i] = '  default: $m';
            foundDefault = true;
          } else if (t.startsWith('provider:')) {
            lines[i] = '  provider: $_provider';
            foundProvider = true;
          } else if (t.startsWith('base_url:') || t.startsWith('baseUrl:')) {
            if (b.isNotEmpty) {
              lines[i] = '  base_url: $b';
            }
            foundBaseUrl = true;
          }
        }
      }
      if (modelSectionStart >= 0 && modelSectionEnd < 0) {
        modelSectionEnd = lines.length;
      }

      final buf = StringBuffer();
      if (modelSectionStart >= 0 &&
          foundDefault && foundProvider && (b.isEmpty || foundBaseUrl)) {
        // 所有字段都已找到并修改，保存完整 config
        config = lines.join('\n');
      } else {
        // ★ 安全模式：始终保留原始 config 的全部内容，不删除任何 section
        // 遍历原始行，替换或追加 model section
        bool sectionWritten = false;
        for (int i = 0; i < lines.length; i++) {
          if (i == modelSectionStart) {
            // 替换现有 model section
            buf.writeln('model:');
            buf.writeln('  default: $m');
            buf.writeln('  provider: $_provider');
            if (b.isNotEmpty) buf.writeln('  base_url: $b');
            i = modelSectionEnd - 1;
            sectionWritten = true;
          } else {
            buf.writeln(lines[i]);
          }
        }
        if (!sectionWritten) {
          // 原本无 model section，追加到末尾
          if (buf.length > 0) buf.writeln('');
          buf.writeln('model:');
          buf.writeln('  default: $m');
          buf.writeln('  provider: $_provider');
          if (b.isNotEmpty) buf.writeln('  base_url: $b');
        }
        config = buf.toString();
      }

      bool ok = await _configService.writeConfig(config);

      // 写 .env（api key）
      if (k.isNotEmpty && ok) {
        try {
          var envContent = await _configService.readEnvFile();
          final keyVar = _envKeyForProvider(_provider);
          if (envContent.contains(keyVar)) {
            envContent = envContent.replaceAll(
              RegExp('$keyVar=.*'),
              '$keyVar=$k',
            );
          } else {
            envContent += '\n$keyVar=$k\n';
          }
          await _configService.writeEnvFile(envContent);
        } catch (_) {}
      }

      if (ok) {
        await GatewayService().restartGateway();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '已保存配置，Gateway 重启中...' : '保存失败'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      Navigator.of(context).pop(ModelSelectionResult(
        model: m,
        provider: _provider,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  String _envKeyForProvider(String provider) {
    switch (provider) {
      case 'deepseek': return 'DEEPSEEK_API_KEY';
      case 'openai': return 'OPENAI_API_KEY';
      case 'anthropic': return 'ANTHROPIC_API_KEY';
      case 'gemini': return 'GEMINI_API_KEY';
      case 'openrouter': return 'OPENROUTER_API_KEY';
      case 'kimi': return 'KIMI_API_KEY';
      case 'glm': return 'GLM_API_KEY';
      case 'minimax': return 'MINIMAX_API_KEY';
      case 'qwen': return 'QWEN_API_KEY';
      case 'xiaomi': return 'XIAOMI_API_KEY';
      case 'huggingface': return 'HF_TOKEN';
      case 'arcee': return 'ARCEE_API_KEY';
      case 'ollama': return ''; // 本地无需 key
      default: return '${provider.toUpperCase()}_API_KEY';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('模型配置'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 快速列表模式切换 ──
              Row(
                children: [
                  Text('配置方式',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('快速选择', style: TextStyle(fontSize: 12)),
                    selected: _useQuickList,
                    onSelected: (_) => setState(() => _useQuickList = true),
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('完整表单', style: TextStyle(fontSize: 12)),
                    selected: !_useQuickList,
                    onSelected: (_) => setState(() => _useQuickList = false),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_useQuickList)
                _buildQuickList(scheme)
              else
                _buildForm(scheme),

              const SizedBox(height: 8),

              // ── 提示 ──
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '修改后保存配置并重启 Gateway 生效。',
                        style: TextStyle(fontSize: 11, color: scheme.primary),
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
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _saveAndRestart,
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('保存配置并重启'),
        ),
      ],
    );
  }

  // ── 快速列表模式 ──
  Widget _buildQuickList(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前配置信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text('全局配置',
                      style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '模型: ${_configModel.isNotEmpty && _configModel != '-' ? _configModel : "未配置"}',
                style: TextStyle(fontSize: 12, color: scheme.onSurface),
              ),
              Text(
                'Provider: ${_configProvider.isNotEmpty && _configProvider != '-' ? _providerLabel(_configProvider) : "未配置"}',
                style: TextStyle(fontSize: 12, color: scheme.onSurface),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_loadingConfig)
          const Center(child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else ...[
          // Provider 选择（只显示已配置的）
          DropdownButtonFormField<String>(
            value: _configuredProviders.contains(_provider) ? _provider : null,
            decoration: const InputDecoration(
              labelText: 'Provider',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: _configuredProviders
                .map((p) => DropdownMenuItem(value: p, child: Text(_providerLabel(p))))
                .toList(),
            onChanged: (v) {
              if (v != null) _setProvider(v);
            },
          ),
          const SizedBox(height: 12),

          // 模型名输入
          Text('模型名',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              hintText: '输入模型名称，如 deepseek-v4-flash',
            ),
            onChanged: (v) => _model = v,
          ),
        ],
      ],
    );
  }

  // ── 完整表单模式 ──
  Widget _buildForm(ColorScheme scheme) {
    final models = GatewayService.providerModels[_provider] ?? [];
    final isCustom = !models.contains(_model);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Provider
        Text('Provider',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: GatewayService.allProviders.contains(_provider) ? _provider : null,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: GatewayService.allProviders
              .map((p) => DropdownMenuItem(value: p, child: Text(_providerLabel(p))))
              .toList(),
          onChanged: (v) {
            if (v != null) _setProvider(v);
          },
        ),
        const SizedBox(height: 12),

        // 模型
        Text('模型',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        if (models.isNotEmpty)
          DropdownButtonFormField<String>(
            value: isCustom ? '__custom__' : _model,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              ...models.map((m) => DropdownMenuItem(value: m, child: Text(m))),
              const DropdownMenuItem(value: '__custom__', child: Text('其他（自定义模型名）')),
            ],
            onChanged: (v) {
              if (v == '__custom__') {
                _modelCtrl.clear();
                setState(() => _model = '');
              } else if (v != null) {
                _selectModel(v, _provider);
              }
            },
          ),
        if (isCustom)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                hintText: '输入模型名称',
              ),
              onChanged: (v) => _model = v,
            ),
          ),
        const SizedBox(height: 12),

        // Base URL
        Text('Base URL',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextField(
          controller: _baseUrlCtrl,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            hintText: 'https://api.deepseek.com/v1',
          ),
          onChanged: (v) => _baseUrl = v,
        ),
        const SizedBox(height: 12),

        // API Key
        Text('API Key（留空则不修改）',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextField(
          controller: _apiKeyCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            hintText: '新的 API Key（存 ~/.hermes/.env）',
          ),
        ),
      ],
    );
  }
}

/// AppBar 上显示的模型选择按钮
class ModelSwitcher extends StatelessWidget {
  final String? currentModel;
  final String? currentProvider;
  final ValueChanged<ModelSelectionResult>? onModelSelected;

  const ModelSwitcher({
    super.key,
    this.currentModel,
    this.currentProvider,
    this.onModelSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final model = currentModel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          final result = await showModelSelectionDialog(
            context,
            currentModel: model,
            currentProvider: currentProvider,
          );
          if (result != null && onModelSelected != null) {
            onModelSelected!(result);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                model ?? '配置模型',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              Icon(Icons.arrow_drop_down, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
