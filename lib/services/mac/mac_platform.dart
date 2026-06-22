import 'dart:io';

class MacPlatform {
  static final MacPlatform _instance = MacPlatform._();
  factory MacPlatform() => _instance;
  MacPlatform._();

  String get homeDir =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  String get hermesBundlePath => '$homeDir/.hermes-desktop/hermes';

  String get hermesBinaryName => 'hermes';

  String hermesExePath(String bundlePath) => '$bundlePath/hermes';

  Future<void> killProcess(String name) async {
    await Process.run('pkill', ['-f', name]);
  }

  Future<void> killProcessByPid(int pid) async {
    Process.killPid(pid);
  }

  String get hermesDownloadUrl =>
      'https://github.com/lovesmile/hermes-desktop-ui/releases/latest/download/hermes-bundle-macos.tar.gz';

  Future<void> extractBundle(String archivePath, String destDir) async {
    await Directory(destDir).create(recursive: true);
    await Process.run('tar', ['-xzf', archivePath, '-C', destDir]);
  }

  String pathJoin(List<String> parts) => parts.join('/');

  String get shellExecutable => '/bin/bash';

  List<String> shellArgs(String command) => ['-c', command];

  String get sshKeyDir => '$homeDir/.hermes/ssh';

  String sshKeyPath(String host) => '$sshKeyDir/id_ed25519_$host';

  Future<bool> uploadSshKey({
    required String publicKey,
    required String user,
    required String host,
    required int port,
    String? password,
  }) async {
    // macOS 直接用 ssh，无需 wsl.exe 中转
    final sshArgs = <String>[
      '-o', 'StrictHostKeyChecking=accept-new',
      '-o', 'ConnectTimeout=10',
    ];
    if (port != 22) sshArgs.addAll(['-p', port.toString()]);

    if (password != null && password.isNotEmpty) {
      // 用 sshpass 支持密码认证
      final escapedPw = "'${password.replaceAll("'", "'\\''")}'";
      final proc = await Process.start('sshpass', [
        '-p', escapedPw, 'ssh', ...sshArgs,
        '$user@$host',
        'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
        'cat >> ~/.ssh/authorized_keys && '
        'chmod 600 ~/.ssh/authorized_keys',
      ]);
      proc.stdin.writeln(publicKey);
      proc.stdin.close();
      return await proc.exitCode == 0;
    }

    final proc = await Process.start('ssh', [
      ...sshArgs,
      '$user@$host',
      'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
      'cat >> ~/.ssh/authorized_keys && '
      'chmod 600 ~/.ssh/authorized_keys',
    ]);
    proc.stdin.writeln(publicKey);
    proc.stdin.close();
    return await proc.exitCode == 0;
  }
}
