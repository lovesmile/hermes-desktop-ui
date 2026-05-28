import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // 鈹€鈹€ Remote SSH form state 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _tested = false;
  bool _testSuccess = false;

  // 鈹€鈹€ Local install state 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
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

  // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
  //  Remote helpers
  // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

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
        _error = '璇峰～鍐欎富鏈哄湴鍧€鍜岀敤鎴峰悕';
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
          _statusText = '杩炴帴鎴愬姛!';
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
        _error = '杩炴帴澶辫触: $e';
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

  
  Future<void> _startEmbeddedMode() async {
    setState(() {
      _working = true;
      _error = null;
      _statusText = '正在切换到内嵌模式...';
    });

    try {
      await ConnectionManager().switchToEmbedded();
      if (!mounted) return;

      final state = ConnectionManager().state;
      if (state.status == ConnStatus.connected) {
        setState(() {
          _step = _WizardStep.installing;
          _statusText = '内嵌模式已就绪';
          _working = false;
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) widget.onComplete();
        return;
      }

      setState(() {
        _working = false;
        _error = state.message.isNotEmpty
            ? state.message
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

  // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
  //  Local install helpers
  // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

  Future<void> _startLocalInstall() async {
    setState(() {
      _step = _WizardStep.local;
      _working = true;
      _error = null;
      _statusText = '鑷姩妫€娴?Hermes...';
    });

    // 1. Check if hermes is already available
    final hermesAvailable = await _checkCommand('hermes');
    if (hermesAvailable) {
      if (!mounted) return;
      setState(() => _statusText = 'Hermes 宸插畨瑁咃紝姝ｅ湪鍚姩...');
      final started = await ConnectionManager().startLocalGateway();
      if (!mounted) return;
      if (started) {
        setState(() {
          _step = _WizardStep.installing;
          _statusText = 'Hermes 宸插氨缁?';
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
        _statusText = '姝ｅ湪瀹夎 Hermes Agent (pip install)...';
        _progress = 0;
      });

      try {
        final result = await Process.run('pip', ['install', 'hermes-agent']);
        if (!mounted) return;
        if (result.exitCode == 0) {
          setState(() {
            _statusText = '瀹夎瀹屾垚锛屾鍦ㄥ惎鍔?..';
            _progress = 0.8;
          });
          final started = await ConnectionManager().startLocalGateway();
          if (!mounted) return;
          if (started) {
            setState(() {
              _step = _WizardStep.installing;
              _statusText = 'Hermes 宸插氨缁?';
              _progress = 1.0;
              _working = false;
            });
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) widget.onComplete();
            return;
          } else {
            setState(() {
              _error = 'pip 瀹夎鎴愬姛浣嗘棤娉曞惎鍔?Hermes Gateway锛岃鎵嬪姩鍚姩';
              _working = false;
            });
            return;
          }
        } else {
          setState(() {
            _error = 'pip install 澶辫触:\n${result.stderr}';
            _working = false;
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'pip install 鍑洪敊: $e';
          _working = false;
        });
        return;
      }
    }

    // 3. pip not available 鈥?try bundle download
    setState(() {
      _statusText = '姝ｅ湪涓嬭浇 Hermes Bundle...';
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
                  '姝ｅ湪涓嬭浇... ${receivedMB.toStringAsFixed(1)} MB / ${totalMB.toStringAsFixed(1)} MB';
            } else {
              _statusText = '姝ｅ湪涓嬭浇... ${receivedMB.toStringAsFixed(1)} MB';
            }
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _statusText = '姝ｅ湪瑙ｅ帇瀹夎...';
        _progress = 0.9;
      });

      await ConnectionManager().extractBundle(bundlePath);

      if (!mounted) return;

      setState(() {
        _statusText = '姝ｅ湪鍚姩 Hermes Gateway...';
      });

      final started = await ConnectionManager().startLocalGateway();

      if (!mounted) return;

      if (started) {
        setState(() {
          _step = _WizardStep.installing;
          _statusText = 'Hermes 宸插氨缁?';
          _progress = 1.0;
          _working = false;
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) widget.onComplete();
      } else {
        setState(() {
          _error = '瑙ｅ帇鎴愬姛浣嗘棤娉曞惎鍔?Gateway锛岃鎵嬪姩鍚姩';
          _working = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '瀹夎澶辫触: $e';
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

  // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
  //  Build
  // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

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

  // 鈹€鈹€ Welcome 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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
          onTap: () => setState(() => _step = _WizardStep.remote),
        ),
        const SizedBox(height: 16),

        // 选项 2：内嵌模式
        _WizardCard(
          icon: Icons.memory_outlined,
          title: '内嵌模式',
          subtitle: '直接在 Windows 环境运行 Hermes',
          onTap: () => _startEmbeddedMode(),
        ),
        const SizedBox(height: 16),

        // 选项 3：本地安装
        _WizardCard(
          icon: Icons.download_outlined,
          title: '本地安装',
          subtitle: '在本机安装并运行 Hermes Gateway',
          onTap: () => _startLocalInstall(),
        ),
        const SizedBox(height: 32),

        TextButton(
          onPressed: widget.onComplete,
          child: const Text('稍后再说'),
        ),
      ],
    );
  }

  // Remote SSH Form 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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
          '濉啓杩滅▼鏈嶅姟鍣ㄧ殑 SSH 杩炴帴淇℃伅',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),

        // 鈹€鈹€ Host 鈹€鈹€
        TextField(
          controller: _hostCtrl,
          decoration: const InputDecoration(
            labelText: '涓绘満鍦板潃',
            hintText: '192.168.1.100 鎴?example.com',
            prefixIcon: Icon(Icons.computer, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // 鈹€鈹€ Port 鈹€鈹€
        TextField(
          controller: _portCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '绔彛',
            hintText: '22',
            prefixIcon: Icon(Icons.settings_ethernet, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // 鈹€鈹€ User 鈹€鈹€
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

        // 鈹€鈹€ Password 鈹€鈹€
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '瀵嗙爜锛堝彲閫夛級',
            hintText: 'SSH 密码，可为空使用密钥认证',
            prefixIcon: Icon(Icons.lock_outline, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 24),

        // 鈹€鈹€ Test result indicator 鈹€鈹€
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
                    _testSuccess ? '杩炴帴娴嬭瘯鎴愬姛' : (_error ?? '杩炴帴娴嬭瘯澶辫触'),
                    style: TextStyle(
                      fontSize: 13,
                      color: _testSuccess ? Colors.green : cs.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 鈹€鈹€ Actions 鈹€鈹€
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
                label: const Text('娴嬭瘯杩炴帴'),
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

        // 鈹€鈹€ Error display 鈹€鈹€
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

  // 鈹€鈹€ Local Install 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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
              '鏈湴瀹夎',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 鈹€鈹€ Progress / Status 鈹€鈹€
        if (_working || _error == null) ...[
          _buildStatusItem(cs, Icons.terminal, '妫€娴?Hermes 鐜...', true),
          const SizedBox(height: 8),
          if (_pipChecked)
            _buildStatusItem(
              cs,
              _pipAvailable ? Icons.check_circle : Icons.cancel_outlined,
              _pipAvailable ? '妫€娴嬪埌 pip' : '鏈娴嬪埌 pip',
              _pipAvailable,
            ),
          if (_pipChecked && _pipAvailable) ...[
            const SizedBox(height: 8),
            _buildStatusItem(cs, Icons.download, '閫氳繃 pip 瀹夎 Hermes Agent...', true),
          ],
        ],

        const SizedBox(height: 24),

        // 鈹€鈹€ Linear progress 鈹€鈹€
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

        // 鈹€鈹€ Error 鈥?show manual install fallback 鈹€鈹€
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
                      '鑷姩瀹夎澶辫触',
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
                  '璇峰皾璇曟墜鍔ㄥ畨瑁?',
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
                        label: const Text('閲嶈瘯'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openManualInstallUrl,
                        icon: const Icon(Icons.open_in_browser, size: 16),
                        label: const Text('鏌ョ湅鏂囨。'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // 鈹€鈹€ If pip not found 鈥?show manual install info 鈹€鈹€
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
                      '姝ｅ湪涓嬭浇 Hermes Bundle...',
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

  // 鈹€鈹€ Installing (success) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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
          '璁剧疆瀹屾垚!',
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


