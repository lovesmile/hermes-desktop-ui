import 'dart:convert';
import 'dart:io';

import 'connection_manager.dart';
import 'hermes_file_service.dart';

/// 注册表中的技能条目
class RegistrySkill {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final String category;
  final int stars;
  final String repoUrl;
  final String path; // 子目录路径，monorepo 模式使用
  final String readme; // README 文件名

  RegistrySkill({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.category,
    required this.stars,
    required this.repoUrl,
    this.path = '',
    this.readme = 'SKILL.md',
  });

  factory RegistrySkill.fromJson(Map<String, dynamic> json) {
    return RegistrySkill(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      author: json['author'] ?? '',
      version: json['version'] ?? '1.0.0',
      category: json['category'] ?? 'general',
      stars: json['stars'] ?? 0,
      repoUrl: json['repo_url'] ?? '',
      path: json['path'] ?? '',
      readme: json['readme'] ?? 'SKILL.md',
    );
  }
}

/// 从多个 CDN 镜像并发拉取注册表，多镜像容灾
class RegistryService {
  static const String _registryRepo = 'lovesmile/hermes-skills-registry';
  static const String _registryFile = 'index.json';

  /// CDN 镜像列表（按优先级）
  static const List<String> _mirrors = [
    'https://raw.githubusercontent.com/$_registryRepo/main/$_registryFile',
    'https://fastly.jsdelivr.net/gh/$_registryRepo@main/$_registryFile',
    'https://ghproxy.com/https://raw.githubusercontent.com/$_registryRepo/main/$_registryFile',
    'https://cdn.staticaly.com/gh/$_registryRepo@main/$_registryFile',
  ];

  /// 从镜像列表中并发拉取，返回第一个成功结果
  Future<List<RegistrySkill>> fetchIndex({Duration timeout = const Duration(seconds: 10)}) async {
    final futures = _mirrors.map((url) => _fetchFromMirror(url, timeout));
    final results = await Future.wait(futures);

    for (final result in results) {
      if (result != null) return result;
    }
    return [];
  }

  Future<List<RegistrySkill>?> _fetchFromMirror(String url, Duration timeout) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      client.connectionTimeout = timeout;

      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      client.close();

      final body = utf8.decode(bytes, allowMalformed: true);
      final List<dynamic> list = jsonDecode(body);
      return list.map((e) => RegistrySkill.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  /// 安装技能到 ~/.hermes/skills/<category>/<id>/
  /// 返回 null 成功，错误信息字符串失败
  Future<String?> installSkill(RegistrySkill skill) async {
    final cm = ConnectionManager();
    final mode = cm.state.mode;

    // 目标路径
    final destPath = _skillDestPath(skill.category, skill.id);

    // 步骤 1：确保分类目录存在
    final mkdirResult = await cm.runShell(
      'mkdir -p "${destPath.substring(0, destPath.lastIndexOf('/'))}"',
      allowFailure: true,
    );
    if (mkdirResult.exitCode != 0) {
      return '创建目录失败: ${mkdirResult.stderr}';
    }

    // 步骤 2：判断安装模式
    if (skill.path.isEmpty) {
      // 独立仓库模式：直接 git clone
      final cloneResult = await cm.runShell(
        'cd "${destPath.substring(0, destPath.lastIndexOf('/'))}" && '
            'git clone --depth 1 "${skill.repoUrl}" "${skill.id}" 2>&1',
        allowFailure: true,
        timeout: 60,
      );
      if (cloneResult.exitCode != 0) {
        return '克隆仓库失败: ${cloneResult.stderr}';
      }
    } else {
      // Monorepo 模式：克隆到 /tmp，再移动子目录
      final tmpPath = '/tmp/hermes-skill-install-${DateTime.now().millisecondsSinceEpoch}';
      final cloneResult = await cm.runShell(
        'git clone --depth 1 "${skill.repoUrl}" "$tmpPath" 2>&1',
        allowFailure: true,
        timeout: 60,
      );
      if (cloneResult.exitCode != 0) {
        return '克隆仓库失败: ${cloneResult.stderr}';
      }

      // 移动子目录
      final moveResult = await cm.runShell(
        'cp -r "$tmpPath/${skill.path}" "$destPath" && rm -rf "$tmpPath"',
        allowFailure: true,
      );
      if (moveResult.exitCode != 0) {
        return '提取技能目录失败: ${moveResult.stderr}';
      }
    }

    return null; // 成功
  }

  /// 卸载技能（删除目录）
  Future<String?> uninstallSkill(String category, String id) async {
    final cm = ConnectionManager();
    final destPath = _skillDestPath(category, id);

    final result = await cm.runShell(
      'rm -rf "$destPath"',
      allowFailure: true,
    );
    if (result.exitCode != 0) {
      return '删除失败: ${result.stderr}';
    }
    return null;
  }

  /// 获取已安装技能列表（来自 HermesFileService）
  Future<List<Map<String, String>>> getInstalledSkills() async {
    return HermesFileService().getSkills();
  }

  String _skillDestPath(String category, String id) {
    // 目标路径格式：~/.hermes/skills/<category>/<id>
    // ConnectionManager.runShell 在 Linux/WSL 下展开 ~
    return '~/.hermes/skills/$category/$id';
  }
}
