import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// SSH 文件读取服务
/// 远程模式时通过 SSH 读取远程服务器的 Hermes 文件
class SshFileService {
  static final SshFileService _instance = SshFileService._();
  factory SshFileService() => _instance;
  SshFileService._();

  String _host = '';
  int _port = 22;
  String _user = '';
  String? _keyPath;
  String? _password;
  bool _initialized = false;

  bool get isConnected => _initialized && _host.isNotEmpty;

  /// 从桌面配置初始化
  Future<void> initFromConfig(Map<String, dynamic> config) async {
    final sshConfig = config['ssh_config'] as Map<String, dynamic>? ?? {};
    _host = sshConfig['host'] as String? ?? '';
    _port = sshConfig['port'] as int? ?? 22;
    _user = sshConfig['user'] as String? ?? '';
    _keyPath = sshConfig['keyPath'] as String?;
    _password = sshConfig['password'] as String?;
    _initialized = _host.isNotEmpty && _user.isNotEmpty;
  }

  /// 读取远程文件内容
  Future<String> readFile(String path) async {
    if (!isConnected) return '';
    try {
      final result = await Process.run('ssh', _sshArgs('cat "$path" 2>/dev/null || true'));
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return '';
  }

  /// 读取远程文件最后 N 行
  Future<String> readTail(String path, {int lines = 200}) async {
    if (!isConnected) return '';
    try {
      final result = await Process.run('ssh', _sshArgs('tail -n $lines "$path" 2>/dev/null || true'));
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return '';
  }

  /// 检查远程文件是否存在
  Future<bool> fileExists(String path) async {
    if (!isConnected) return false;
    try {
      final result = await Process.run('ssh', _sshArgs('test -f "$path" && echo YES || echo NO'));
      return result.exitCode == 0 && (result.stdout as String).trim() == 'YES';
    } catch (_) {
      return false;
    }
  }

  /// 检查远程目录是否存在
  Future<bool> dirExists(String path) async {
    if (!isConnected) return false;
    try {
      final result = await Process.run('ssh', _sshArgs('test -d "$path" && echo YES || echo NO'));
      return result.exitCode == 0 && (result.stdout as String).trim() == 'YES';
    } catch (_) {
      return false;
    }
  }

  /// 列出远程目录（文件名列表）
  Future<List<String>> listFiles(String dirPath) async {
    if (!isConnected) return [];
    try {
      final result = await Process.run('ssh', _sshArgs('ls -1A "$dirPath" 2>/dev/null || true'));
      if (result.exitCode != 0) return [];
      return (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 列出远程目录下所有子目录
  Future<List<String>> listDirs(String dirPath) async {
    if (!isConnected) return [];
    try {
      final result = await Process.run('ssh', _sshArgs(
          'find "$dirPath" -maxdepth 1 -type d 2>/dev/null | tail -n +2 || true'));
      if (result.exitCode != 0) return [];
      return (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => l.split('/').last)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 构建 SSH 参数
  List<String> _sshArgs(String command) {
    final args = <String>[
      '-o', 'StrictHostKeyChecking=accept-new',
      '-o', 'ServerAliveInterval=30',
    ];
    if (_keyPath != null && _keyPath!.isNotEmpty) {
      args.addAll(['-i', _keyPath!]);
    }
    if (_port != 22) {
      args.addAll(['-p', _port.toString()]);
    }
    args.add('$_user@$_host');
    args.add(command);
    return args;
  }
}
