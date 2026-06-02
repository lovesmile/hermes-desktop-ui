import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/config_service.dart';
import '../services/connection_manager.dart';
import 'models_screen.dart' as ms;

/// A full-screen Material 3 setup wizard that guides the user through
/// connecting to a remote Hermes server or installing Hermes locally.
///
/// [onComplete] is called when setup finishes successfully or the user
/// explicitly chooses to skip.
class SetupScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

/// Internal step tracking for the wizard.
enum _WizardStep { welcome, remote, local, configure, installing }

class _SetupScreenState extends State<SetupScreen> {
  _WizardStep _step = _WizardStep.welcome;
  bool _working = false;
  String _statusText = '';
  String? _error;

  // --- Remote SSH form state
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _tested = false;
  bool _testSuccess = false;

  // --- Local install state

  // --- LLM Config state
  String _selectedProvider = 'deepseek';
  String _selectedModel = 'deepseek-v4-flash';
  final _providerApiKeyCtrl = TextEditingController(text: '');

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _providerApiKeyCtrl.dispose();
    super.dispose();
  }

  // ======== Remote helpers ========

  Future<void> _testRemoteConnection() async {
    setState(() {
      _working = true;
      _tested = false;
      _testSuccess = false;
      _error = null;
    });

    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final config = SshConfig(
      host: _hostCtrl.text.trim(),
      port: port,
      user: _userCtrl.text.trim(),
      password:
          _passwordCtrl.text.trim().isNotEmpty ? _passwordCtrl.text.trim() : null,
    );

    if (!config.isValid) {
      setState(() {
        _error = '请填写主机地址和用户名';
        _working = false;
        _tested = true;
        _testSuccess = false;
      });
      return;
    }

    try {
      final ok = await ConnectionManager().connectRemote(config);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _testSuccess = true;
          _tested = true;
          _working = false;
          _statusText = '连接成功!';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _tested = true;
          _working = false;
          _error = ConnectionManager().state.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _tested = true;
        _working = false;
        _error = '连接失败: $e';
      });
    }
  }

  Future<void> _saveAndConnectRemote() async {
    setState(() {
      _working = true;
      _error = null;
      _statusText = '正在连接...';
    });

    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final config = SshConfig(
      host: _hostCtrl.text.trim(),
      port: port,
      user: _userCtrl.text.trim(),
      password:
          _passwordCtrl.text.trim().isNotEmpty ? _passwordCtrl.text.trim() : null,
    );

    if (!config.isValid) {
      setState(() {
        _error = '请填写主机地址和用户名';
        _working = false;
      });
      return;
    }

    try {
      final ok = await ConnectionManager().connectRemote(config);
      if (!mounted) return;
      if (ok) {
        // connectRemote() -> _ensureRemoteKey() already saved the upgraded
        // ssh_config (with keyPath) to desktop_config.json — do not
        // overwrite it with the original password-based config here.
        final dc = await ConfigService().readDesktopConfig();
        dc['connection_mode'] = 'remote';
        await ConfigService().writeDesktopConfig(dc);
        setState(() {
          _step = _WizardStep.configure;
          _working = false;
        });
      } else {
        setState(() {
          _working = false;
          _error = ConnectionManager().state.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = '连接失败: $e';
      });
    }
  }


  Future<void> _startEmbeddedMode() async {
    setState(() {
      _working = true;
      _error = null;
      _statusText = '正在检查内嵌 Hermes...';
    });

    final exePath = '${ConnectionManager().hermesBundlePath}\\hermes.exe';
    final exeExists = await File(exePath).exists();
    if (!mounted) return;

    if (!exeExists) {
      // 先检查安装包自带的 hermes.exe（{app}\hermes\hermes.exe）
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final bundledExe = '$appDir\\hermes\\hermes.exe';
      if (await File(bundledExe).exists()) {
        await Directory(ConnectionManager().hermesBundlePath).create(recursive: true);
        await File(bundledExe).copy(exePath);
      } else {
        // 未安装 → 自动下载+安装
        setState(() => _statusText = '正在下载内嵌 Hermes...');
        try {
          final zipPath = await ConnectionManager().downloadHermesBundle(
            ConnectionManager.defaultHermesDownloadUrl,
            onProgress: (received, total) {
              if (!mounted) return;
              final pct = total > 0 ? (received * 100 ~/ total) : 0;
              setState(() => _statusText = '正在下载内嵌 Hermes... $pct%');
            },
          );
          if (!mounted) return;

          setState(() => _statusText = '正在安装...');
          await ConnectionManager().extractBundle(zipPath);
          if (!mounted) return;

          // 验证安装结果
          if (!await File(exePath).exists()) {
            setState(() {
              _working = false;
              _error = '安装失败：解压后未找到 hermes.exe';
            });
            return;
          }
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _working = false;
            _error = '下载或安装失败: $e';
          });
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() => _statusText = '正在切换到内嵌模式...');
    try {
      await ConnectionManager().switchToEmbedded();
      if (!mounted) return;

      if (ConnectionManager().state.status == ConnStatus.connected) {
        await ConfigService().writeDesktopConfig({
          ...await ConfigService().readDesktopConfig(),
          'connection_mode': 'embedded',
        });
        setState(() {
          _step = _WizardStep.configure;
          _working = false;
        });
        return;
      }

      setState(() {
        _working = false;
        _error = ConnectionManager().state.message.isNotEmpty
            ? ConnectionManager().state.message
            : '内嵌模式启动失败';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = '内嵌模式启动失败: $e';
      });
    }
  }

  // ======== Local install helpers ========

  Future<void> _startLocalInstall() async {
    setState(() {
      _step = _WizardStep.local;
      _working = true;
      _error = null;
      _statusText = '正在检测 WSL Hermes 环境...';
    });

    // Check if hermes is available inside WSL
    final hasHermes = await _checkHermesInWsl();
    if (!mounted) return;

    if (hasHermes) {
      setState(() => _statusText = '检测到 Hermes，正在连接...');
      await ConnectionManager().switchToLocal();
      if (!mounted) return;

      if (ConnectionManager().state.status == ConnStatus.connected) {
        await ConfigService().writeDesktopConfig({
          ...await ConfigService().readDesktopConfig(),
          'connection_mode': 'local',
        });
        setState(() {
          _step = _WizardStep.configure;
          _working = false;
        });
        return;
      }
    }

    // Hermes not available in WSL
    setState(() {
      _working = false;
      _error = '未在 WSL 中检测到 Hermes，请先在 WSL 中自行安装 Hermes Agent，然后点击重试。';
    });
  }

  Future<bool> _checkHermesInWsl() async {
    try {
      final distro = ConnectionManager().wslDistro;
      final r = await Process.run('wsl.exe', [
        '-d', distro, 'bash', '-c',
        'command -v hermes 2>/dev/null && echo "EXISTS" || echo ""',
      ]);
      return (r.stdout as String).trim().contains('EXISTS');
    } catch (_) {
      return false;
    }
  }

  void _openManualInstallUrl() async {
    final uri = Uri.parse('https://hermes-agent.nousresearch.com/docs');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ======== LLM Config ========

  Future<void> _saveConfig() async {
    setState(() {
      _working = true;
      _statusText = '正在保存配置...';
    });

    try {
      await ConfigService().writeDesktopConfig(
        {...await ConfigService().readDesktopConfig()},
      );

      final configService = ConfigService();
      // 通过 ConfigService 读写，自动适配 local/embedded/remote 模式
      var config = await configService.readConfig();
      config = config.replaceAll(
        RegExp(r'^(\s+)default:.*$', multiLine: true),
        '  default: $_selectedModel');
      config = config.replaceAll(
        RegExp(r'^(\s+)provider:.*$', multiLine: true),
        '  provider: $_selectedProvider');
      await configService.writeConfig(config);

      if (_providerApiKeyCtrl.text.trim().isNotEmpty) {
        var envContent = await configService.readEnvFile();
        final providerUpper = _selectedProvider.toUpperCase();
        final keyVar = '${providerUpper}_API_KEY';
        if (envContent.contains('$keyVar=')) {
          envContent = envContent.replaceAll(
            RegExp('^$keyVar=.*' r'$', multiLine: true),
            '$keyVar=${_providerApiKeyCtrl.text.trim()}',
          );
        } else {
          envContent += '\n$keyVar=${_providerApiKeyCtrl.text.trim()}\n';
        }
        final baseUrl = ms.providerBaseUrls[_selectedProvider] ?? '';
        if (baseUrl.isNotEmpty) {
          final urlVar = '${providerUpper}_BASE_URL';
          if (envContent.contains('$urlVar=')) {
            envContent = envContent.replaceAll(
              RegExp('^$urlVar=.*' r'$', multiLine: true),
              '$urlVar=$baseUrl');
          } else {
            envContent += '\n$urlVar=$baseUrl\n';
          }
        }
        await configService.writeEnvFile(envContent);
      }

      if (!mounted) return;
      setState(() {
        _step = _WizardStep.installing;
        _statusText = '配置已保存';
        _working = false;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = '保存配置失败: $e';
      });
    }
  }

  void _skipConfig() {
    setState(() {
      _step = _WizardStep.installing;
      _statusText = '跳过配置';
      _working = false;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) widget.onComplete();
    });
  }

  Widget _buildConfigure(ColorScheme cs) {
    final models = ms.providerModels[_selectedProvider] ?? [];
    return Column(
      key: const ValueKey('configure'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _step = _WizardStep.welcome;
                _error = null;
              }),
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'LLM 配置',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '配置模型提供商和 API Key，也可稍后在设置中完成',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),

        // Provider
        Text('模型提供商', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedProvider,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: ms.allProviders.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedProvider = v;
              final newModels = ms.providerModels[v] ?? [];
              if (newModels.isNotEmpty) _selectedModel = newModels.first;
            });
          },
        ),
        const SizedBox(height: 12),

        // Model
        if (models.isNotEmpty) ...[
          Text('模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: models.contains(_selectedModel) ? _selectedModel : models.first,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: models.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedModel = v);
            },
          ),
          const SizedBox(height: 12),
        ],

        // Provider API Key
        TextField(
          controller: _providerApiKeyCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Provider API Key',
            hintText: 'LLM 服务商的 API Key',
            prefixIcon: Icon(Icons.vpn_key_outlined, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 24),

        // Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _working ? null : _skipConfig,
                child: const Text('跳过'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _working ? null : _saveConfig,
                icon: _working
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存并完成'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ),
        ],
      ],
    );
  }

  // ======== Build ========

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildStepContent(cs),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(ColorScheme cs) {
    switch (_step) {
      case _WizardStep.welcome:
        return _buildWelcome(cs);
      case _WizardStep.remote:
        return _buildRemoteForm(cs);
      case _WizardStep.local:
        return _buildLocalInstall(cs);
      case _WizardStep.configure:
        return _buildConfigure(cs);
      case _WizardStep.installing:
        return _buildInstalling(cs);
    }
  }

  // --- Welcome

  Widget _buildWelcome(ColorScheme cs) {
    return Column(
      key: const ValueKey('welcome'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              'H',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 36,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '欢迎使用 Hermes Desktop',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '未检测到 Hermes Gateway，请选择连接方式继续。',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),

        // 选项 1：远程服务器
        _WizardCard(
          icon: Icons.dns_outlined,
          title: '连接远程服务器',
          subtitle: '通过 SSH 连接已运行 Hermes 的远程主机',
          onTap: () => setState(() {
            _step = _WizardStep.remote;
            _error = null;
            _tested = false;
          }),
        ),
        const SizedBox(height: 16),

        // 选项 2：内嵌模式
        _WizardCard(
          icon: Icons.memory_outlined,
          title: '内嵌模式',
          subtitle: '使用 Hermes Desktop 内置的 Hermes 环境，无需额外安装',
          onTap: () => _startEmbeddedMode(),
        ),
        const SizedBox(height: 16),

        // 选项 3：本地安装
        _WizardCard(
          icon: Icons.download_outlined,
          title: 'WSL 本地模式',
          subtitle: '连接用户 WSL 环境中自行安装的 Hermes',
          onTap: () => _startLocalInstall(),
        ),
        const SizedBox(height: 32),

        // Status/progress during embedded install
        if (_working) ...[
          _buildStatusItem(cs, Icons.download, _statusText, true),
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 12),
        ],

        // Error during embedded install
        if (_error != null && !_working)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 12, color: cs.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _startEmbeddedMode(),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重试'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        TextButton(
          onPressed: widget.onComplete,
          child: const Text('稍后再说'),
        ),
      ],
    );
  }

  // Remote SSH Form ---

  Widget _buildRemoteForm(ColorScheme cs) {
    return Column(
      key: const ValueKey('remote'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _step = _WizardStep.welcome;
                _error = null;
                _tested = false;
              }),
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '连接远程服务器',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '填写远程服务器的 SSH 连接信息',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),

        //  Host
        TextField(
          controller: _hostCtrl,
          decoration: const InputDecoration(
            labelText: '主机地址',
            hintText: '192.168.1.100 或 example.com',
            prefixIcon: Icon(Icons.computer, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // Port
        TextField(
          controller: _portCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '端口',
            hintText: '22',
            prefixIcon: Icon(Icons.settings_ethernet, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // User
        TextField(
          controller: _userCtrl,
          decoration: const InputDecoration(
            labelText: '用户名',
            hintText: 'root',
            prefixIcon: Icon(Icons.person_outline, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // Password
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码（可选）',
            hintText: 'SSH 登录密码',
            prefixIcon: Icon(Icons.lock_outline, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 24),

        // --- Test result indicator
        if (_tested)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Icon(
                  _testSuccess ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: _testSuccess ? Colors.green : cs.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _testSuccess ? '连接测试成功' : (_error ?? '连接测试失败'),
                    style: TextStyle(
                      fontSize: 13,
                      color: _testSuccess ? Colors.green : cs.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // --- Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _working ? null : _testRemoteConnection,
                icon: _working && !_tested
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find, size: 18),
                label: const Text('测试连接'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _working ? null : _saveAndConnectRemote,
                icon: _working
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存并连接'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // --- Error display
        if (_error != null && !_tested)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: cs.error),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- Local Install ---

  Widget _buildLocalInstall(ColorScheme cs) {
    return Column(
      key: const ValueKey('local'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_working) return;
                setState(() {
                  _step = _WizardStep.welcome;
                  _error = null;
                });
              },
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'WSL 本地模式',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Status / progress
        if (_working) ...[
          _buildStatusItem(cs, Icons.terminal, _statusText, true),
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 12),
        ],

        // Error — show manual install prompt
        if (_error != null && !_working) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Text(
                      '未检测到 Hermes',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _startLocalInstall(),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重试'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openManualInstallUrl,
                        icon: const Icon(Icons.open_in_browser, size: 16),
                        label: const Text('查看文档'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusItem(
    ColorScheme cs,
    IconData icon,
    String text,
    bool active,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: active ? cs.primary : cs.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: active ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // --- Installing (success)

  Widget _buildInstalling(ColorScheme cs) {
    return Column(
      key: const ValueKey('installing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 32),
        Icon(
          Icons.check_circle_outline,
          size: 80,
          color: Colors.green,
        ),
        const SizedBox(height: 24),
        Text(
          '设置完成!',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          _statusText,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// Reusable card widget for the welcome-step options.
class _WizardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WizardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}


