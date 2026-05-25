import 'package:flutter/foundation.dart';
import 'config_service.dart';
import 'gateway_service.dart';
import 'local_db.dart';
import 'ssh_file_service.dart';

/// 连接模式 — 本地 WSL / 远程 SSH
class ConnectionModeNotifier extends ChangeNotifier {
  String _mode = 'local'; // 'local' or 'remote'
  bool _initialized = false;

  String get mode => _mode;
  bool get isRemote => _mode == 'remote';
  bool get isLocal => _mode == 'local';
  bool get initialized => _initialized;

  /// 启动时从 desktop_config 加载模式
  Future<void> initialize() async {
    if (_initialized) return;
    final config = await ConfigService().readDesktopConfig();
    final savedMode = config['connection_mode'] as String? ?? 'local';
    await _applyMode(savedMode, notify: false);
    _initialized = true;
  }

  /// 切换连接模式
  Future<void> setMode(String mode) async {
    if (mode == _mode) return;
    await _applyMode(mode, notify: true);

    // 持久化到配置文件
    final config = await ConfigService().readDesktopConfig();
    config['connection_mode'] = mode;
    await ConfigService().writeDesktopConfig(config);
  }

  Future<void> _applyMode(String mode, {bool notify = true}) async {
    _mode = mode;

    // 通知所有服务切换数据源
    await LocalDatabase().setMode(mode);

    if (mode == 'remote') {
      // 初始化 SSH 连接
      final config = await ConfigService().readDesktopConfig();
      await SshFileService().initFromConfig(config);
    }

    if (notify) notifyListeners();
  }

  /// 测试 SSH 连接
  Future<bool> testSshConnection() async {
    if (_mode != 'remote') return false;
    return SshFileService().isConnected;
  }
}
