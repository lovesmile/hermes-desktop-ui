import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../services/connection_manager.dart';

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
enum _WizardStep { welcome, remote, local, installing }

class _SetupScreenState extends State<SetupScreen> {
  _WizardStep _step = _WizardStep.welcome;
  bool _working = false;
  String _statusText = '';
  double _progress = 0;
  String? _error;

  // ── Remote SSH form state ─────────────────────────────────────────
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _tested = false;
  bool _testSuccess = false;

  // ── Local install state ───────────────────────────────────────────
  bool _pipAvailable = false;
  bool _pipChecked = false;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════
  //  Remote helpers
  // ════════════════════════════════════════════════════════════════════

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
        setState(() {
          _step = _WizardStep.installing;
          _statusText = '远程连接成功!';
          _working = false;
        });
        // Small delay to show the success state, then complete.
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) widget.onComplete();
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

  // ════════════════════════════════════════════════════════════════════
  //  Local install helpers
  // ════════════════════════════════════════════════════════════════════

  Future<void> _startLocalInstall() async {
    setState(() {
      _step = _WizardStep.local;
      _working = true;
      _error = null;
      _statusText = '自动检测 Hermes...';
    });

    // 1. Check if hermes is already available
    final hermesAvailable = await _checkCommand('hermes');
    if (hermesAvailable) {
      if (!mounted) return;
      setState(() => _statusText = 'Hermes 已安装，正在启动...');
      final started = await ConnectionManager().startLocalGateway();
      if (!mounted) return;
      if (started) {
        setState(() {
          _step = _WizardStep.installing;
          _statusText = 'Hermes 已就绪!';
          _working = false;
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) widget.onComplete();
        return;
      }
    }

    // 2. Check if pip is available
    final pipOk = await _checkCommand('pip');
    if (!mounted) return;
    if (pipOk) {
      _pipAvailable = true;
    }
    _pipChecked = true;

    if (pipOk) {
      // Try pip install
      setState(() {
        _statusText = '正在安装 Hermes Agent (pip install)...';
        _progress = 0;
      });

      try {
        final result = await Process.run('pip', ['install', 'hermes-agent']);
        if (!mounted) return;
        if (result.exitCode == 0) {
          setState(() {
            _statusText = '安装完成，正在启动...';
            _progress = 0.8;
          });
          final started = await ConnectionManager().startLocalGateway();
          if (!mounted) return;
          if (started) {
            setState(() {
              _step = _WizardStep.installing;
              _statusText = 'Hermes 已就绪!';
              _progress = 1.0;
              _working = false;
            });
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) widget.onComplete();
            return;
          } else {
            setState(() {
              _error = 'pip 安装成功但无法启动 Hermes Gateway，请手动启动';
              _working = false;
            });
            return;
          }
        } else {
          setState(() {
            _error = 'pip install 失败:\n${result.stderr}';
            _working = false;
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'pip install 出错: $e';
          _working = false;
        });
        return;
      }
    }

    // 3. pip not available — try bundle download
    setState(() {
      _statusText = '正在下载 Hermes Bundle...';
      _progress = 0;
    });

    try {
      final bundlePath = await ConnectionManager().downloadHermesBundle(
        ConnectionManager.defaultHermesDownloadUrl,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? received / total : 0;
            final receivedMB = received / 1024 / 1024;
            final totalMB = total / 1024 / 1024;
            if (total > 0) {
              _statusText =
                  '正在下载... ${receivedMB.toStringAsFixed(1)} MB / ${totalMB.toStringAsFixed(1)} MB';
            } else {
              _statusText = '正在下载... ${receivedMB.toStringAsFixed(1)} MB';
            }
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _statusText = '正在解压安装...';
        _progress = 0.9;
      });

      await ConnectionManager().extractBundle(bundlePath);

      if (!mounted) return;

      setState(() {
        _statusText = '正在启动 Hermes Gateway...';
      });

      final started = await ConnectionManager().startLocalGateway();

      if (!mounted) return;

      if (started) {
        setState(() {
          _step = _WizardStep.installing;
          _statusText = 'Hermes 已就绪!';
          _progress = 1.0;
          _working = false;
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) widget.onComplete();
      } else {
        setState(() {
          _error = '解压成功但无法启动 Gateway，请手动启动';
          _working = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '安装失败: $e';
        _working = false;
      });
    }
  }

  Future<bool> _checkCommand(String cmd) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [cmd],
      );
      return result.exitCode == 0;
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

  // ════════════════════════════════════════════════════════════════════
  //  Build
  // ════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
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
      case _WizardStep.installing:
        return _buildInstalling(cs);
    }
  }

  // ── Welcome ───────────────────────────────────────────────────────

  Widget _buildWelcome(ColorScheme cs) {
    return Column(
      key: const ValueKey('welcome'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo / icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6750A4), Color(0xFFD0BCFF)],
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

        // Title
        Text(
          '欢迎使用 Hermes Desktop',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '未检测到 Hermes Gateway，请选择连接方式',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),

        // ── Option 1: Remote server ──
        _WizardCard(
          icon: Icons.dns_outlined,
          title: '连接远程服务器',
          subtitle: '通过 SSH 连接到已运行 Hermes 的远程主机',
          onTap: () => setState(() => _step = _WizardStep.remote),
        ),
        const SizedBox(height: 16),

        // ── Option 2: Local install ──
        _WizardCard(
          icon: Icons.download_outlined,
          title: '本地安装',
          subtitle: '在本机安装并运行 Hermes Gateway',
          onTap: () => _startLocalInstall(),
        ),
        const SizedBox(height: 32),

        // ── Skip ──
        TextButton(
          onPressed: widget.onComplete,
          child: const Text('稍后再说'),
        ),
      ],
    );
  }

  // ── Remote SSH Form ───────────────────────────────────────────────

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
              onPressed: () => setState(() => _step = _WizardStep.welcome),
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

        // ── Host ──
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

        // ── Port ──
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

        // ── User ──
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

        // ── Password ──
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码（可选）',
            hintText: 'SSH 密码或留空使用密钥认证',
            prefixIcon: Icon(Icons.lock_outline, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 24),

        // ── Test result indicator ──
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

        // ── Actions ──
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

        // ── Error display ──
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

  // ── Local Install ─────────────────────────────────────────────────

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
                setState(() => _step = _WizardStep.welcome);
              },
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '本地安装',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Progress / Status ──
        if (_working || _error == null) ...[
          _buildStatusItem(cs, Icons.terminal, '检测 Hermes 环境...', true),
          const SizedBox(height: 8),
          if (_pipChecked)
            _buildStatusItem(
              cs,
              _pipAvailable ? Icons.check_circle : Icons.cancel_outlined,
              _pipAvailable ? '检测到 pip' : '未检测到 pip',
              _pipAvailable,
            ),
          if (_pipChecked && _pipAvailable) ...[
            const SizedBox(height: 8),
            _buildStatusItem(cs, Icons.download, '通过 pip 安装 Hermes Agent...', true),
          ],
        ],

        const SizedBox(height: 24),

        // ── Linear progress ──
        if (_working) ...[
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 4,
          ),
          const SizedBox(height: 12),
          Text(
            _statusText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],

        // ── Error — show manual install fallback ──
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
                    Icon(Icons.error_outline, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Text(
                      '自动安装失败',
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
                const SizedBox(height: 12),
                Text(
                  '请尝试手动安装:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'pip install hermes-agent',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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

        // ── If pip not found — show manual install info ──
        if (_pipChecked && !_pipAvailable && !_working && _error == null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: cs.tertiary),
                    const SizedBox(width: 8),
                    Text(
                      '正在下载 Hermes Bundle...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
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

  // ── Installing (success) ──────────────────────────────────────────

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
        if (_progress > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 4,
              color: Colors.green,
            ),
          ),
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
