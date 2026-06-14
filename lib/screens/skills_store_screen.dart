import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/hermes_file_service.dart';
import '../services/registry_service.dart';
import 'chat_screen.dart';

class SkillsStoreScreen extends StatefulWidget {
  final void Function(int index) onNavigate;

  const SkillsStoreScreen({super.key, required this.onNavigate});

  @override
  State<SkillsStoreScreen> createState() => _SkillsStoreScreenState();
}

class _SkillsStoreScreenState extends State<SkillsStoreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _registryService = RegistryService();

  // "我的技能" 状态
  List<Map<String, String>> _installedSkills = [];
  bool _installedLoading = true;

  // "发现商店" 状态
  List<RegistrySkill> _registrySkills = [];
  bool _storeLoading = true;
  String? _storeError;

  // 安装中的技能 ID
  final Set<String> _installing = {};
  final Set<String> _uninstalling = {};

  // 已安装的技能 ID 集合（用于判断是否已安装）
  Set<String> _installedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInstalled();
    _loadStore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalled() async {
    setState(() => _installedLoading = true);
    try {
      final skills = await _registryService.getInstalledSkills();
      _installedIds = skills.map((s) => s['name'] ?? '').toSet();
      if (mounted) {
        setState(() {
          _installedSkills = skills;
          _installedLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _installedLoading = false);
    }
  }

  Future<void> _loadStore() async {
    setState(() {
      _storeLoading = true;
      _storeError = null;
    });
    try {
      final skills = await _registryService.fetchIndex();
      if (mounted) {
        setState(() {
          _registrySkills = skills;
          _storeLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _storeError = '加载失败: $e';
          _storeLoading = false;
        });
      }
    }
  }

  Future<void> _installSkill(RegistrySkill skill) async {
    setState(() => _installing.add(skill.id));
    final error = await _registryService.installSkill(skill);
    if (mounted) {
      setState(() => _installing.remove(skill.id));
      if (error == null) {
        _installedIds.add(skill.id);
        setState(() {}); // 刷新"已安装"标记
        _loadInstalled();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「${skill.name}」安装成功'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('安装失败: $error'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _uninstallSkill(RegistrySkill skill) async {
    setState(() => _uninstalling.add(skill.id));
    final error = await _registryService.uninstallSkill(skill.category, skill.id);
    if (mounted) {
      setState(() => _uninstalling.remove(skill.id));
      if (error == null) {
        _installedIds.remove(skill.id);
        _loadInstalled();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「${skill.name}」已卸载'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('卸载失败: $error'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmUninstallInstalled(String path, String name) async {
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
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
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
          _installedIds.removeWhere((id) => id == name);
          _loadInstalled();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('「$name」已删除')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除「$name」失败')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('技能商店'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '我的技能'),
            Tab(text: '发现商店'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              if (_tabController.index == 0) {
                _loadInstalled();
              } else {
                _loadStore();
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInstalledTab(),
          _buildDiscoverTab(),
        ],
      ),
    );
  }

  /// "我的技能" Tab
  Widget _buildInstalledTab() {
    if (_installedLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_installedSkills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无已安装的技能',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.store, size: 16),
              label: const Text('去商店发现'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadInstalled(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _installedSkills.length,
        itemBuilder: (ctx, i) {
          final skill = _installedSkills[i];
          final name = skill['name'] ?? '';
          final version = skill['version'] ?? '';
          final description = skill['description'] ?? '';
          final path = skill['path'] ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
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
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
                          const SizedBox(width: 8),
                          Text('删除', style: TextStyle(color: AppTheme.error)),
                        ],
                      ),
                    ),
                  ],
                ).then((value) {
                  if (value == 'invoke') {
                    if (name.isNotEmpty) {
                      ChatScreen.skillInvocationNotifier.value = name;
                      widget.onNavigate(1); // 跳到聊天页
                    }
                  } else if (value == 'delete') {
                    _confirmUninstallInstalled(path, name);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: AppTheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                description,
                                maxLines: 1,
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
                    if (version.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'v$version',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: AppTheme.error.withValues(alpha: 0.7),
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: '删除技能',
                      onPressed: () => _confirmUninstallInstalled(path, name),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// "发现商店" Tab
  Widget _buildDiscoverTab() {
    if (_storeLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_storeError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _storeError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadStore,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_registrySkills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '商店暂无内容',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadStore(),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 340,
          mainAxisExtent: 160,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _registrySkills.length,
        itemBuilder: (ctx, i) {
          final skill = _registrySkills[i];
          final isInstalled = _installedIds.contains(skill.id);
          final isInstalling = _installing.contains(skill.id);
          final isUninstalling = _uninstalling.contains(skill.id);
          final isBusy = isInstalling || isUninstalling;

          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showSkillDetailSheet(skill, isInstalled),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部行：图标 + Star
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _categoryIcon(skill.category),
                            size: 18,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Spacer(),
                        if (skill.stars > 0) ...[
                          Icon(Icons.star, size: 13, color: Colors.amber.shade600),
                          const SizedBox(width: 3),
                          Text(
                            '${skill.stars}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 名称
                    Text(
                      skill.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 描述
                    Expanded(
                      child: Text(
                        skill.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 底部行：版本 + 安装按钮
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'v${skill.version}',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            skill.category,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.secondary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (isBusy)
                          const SizedBox(
                            width: 72,
                            height: 28,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        else if (isInstalled)
                          SizedBox(
                            width: 72,
                            height: 28,
                            child: OutlinedButton(
                              onPressed: () => _confirmUninstall(skill),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.error,
                                side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('卸载', style: TextStyle(fontSize: 12)),
                            ),
                          )
                        else
                          SizedBox(
                            width: 72,
                            height: 28,
                            child: FilledButton(
                              onPressed: () => _installSkill(skill),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('安装', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSkillDetailSheet(RegistrySkill skill, bool isInstalled) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖动条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 标题
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _categoryIcon(skill.category),
                      size: 24,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          skill.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'by ${skill.author} · v${skill.version}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 描述
              Text(
                skill.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              // 元信息
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metaChip(Icons.category, skill.category),
                  if (skill.stars > 0) _metaChip(Icons.star, '${skill.stars} stars'),
                  _metaChip(Icons.code, skill.repoUrl.split('/').last),
                ],
              ),
              const SizedBox(height: 20),
              // 操作按钮
              if (isInstalled)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmUninstall(skill);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('卸载此技能'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _installSkill(skill);
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: Text('安装「${skill.name}」'),
                  ),
                ),
              const SizedBox(height: 12),
              // 仓库链接
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    // TODO: 用 url_launcher 或系统浏览器打开
                  },
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(
                    skill.repoUrl,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUninstall(RegistrySkill skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载技能'),
        content: Text('确定要卸载「${skill.name}」吗？\n\n此操作会删除该技能目录，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _uninstallSkill(skill);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'devops':
        return Icons.settings_applications;
      case 'data-science':
        return Icons.analytics;
      case 'mlops':
        return Icons.memory;
      case 'creative':
        return Icons.palette;
      case 'productivity':
        return Icons.work;
      case 'social-media':
        return Icons.share;
      case 'gaming':
        return Icons.games;
      case 'research':
        return Icons.science;
      case 'finance':
        return Icons.trending_up;
      case 'media':
        return Icons.movie;
      case 'email':
        return Icons.email;
      case 'smart-home':
        return Icons.home;
      default:
        return Icons.extension;
    }
  }
}
