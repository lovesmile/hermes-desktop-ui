import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/connection_manager.dart';
import '../services/gateway_service.dart';
import '../services/local_db.dart';
import '../services/config_service.dart';
import '../services/hermes_file_service.dart';
import '../widgets/stats_card.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int index)? onNavigate;
  final ValueNotifier<int>? tabNotifier;

  const DashboardScreen({super.key, this.onNavigate, this.tabNotifier});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _cm = ConnectionManager();
  final _configService = ConfigService();
  final _localDb = LocalDatabase();
  final _fileService = HermesFileService();
  bool _dashboardLoading = false;
  late final VoidCallback _onRefresh;

  int _sessionCount = 0;
  int _skillCount = 0;
  int _logSizeKb = 0;
  String _currentModel = '-';
  String _currentProvider = '-';
  String _currentBaseUrl = '-';

  // 文件数 — 暂时禁用
  int _fileCount = 0;
  int _cronCount = 0;
  String _homePath = '';

  // 机器状态
  Map<String, dynamic>? _machineStatus;
  // Token 用量 — 暂时禁用
  Map<String, int>? _tokenUsage;

  @override
  void initState() {
    super.initState();
    _loadData(showLoading: true);
    widget.tabNotifier?.addListener(_onTabChanged);
    _cm.stateNotifier.addListener(_onConnectionChanged);
    _onRefresh = () => _loadData();
    GatewayService().refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    widget.tabNotifier?.removeListener(_onTabChanged);
    _cm.stateNotifier.removeListener(_onConnectionChanged);
    GatewayService().refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (_cm.state.status == ConnStatus.connected) {
      _loadData();
    }
  }

  void _onTabChanged() {
    if (widget.tabNotifier?.value == 0) {
      _loadData();
    }
  }

  Future<void> _loadData({bool showLoading = false}) async {
    if (showLoading) setState(() => _dashboardLoading = true);
    try {
      final localSessions = await _localDb.getSessions();
      int sessions = localSessions.length;

      final skillsCount = await _fileService.countSkills();

      // 日志总大小
      final logsSize = await _fileService.getLogsSize();

      // 文件数
      int fileCount = 0;
      final hermesHome = await _fileService.resolveHermesHome();
      final filesDir = '$hermesHome/files';
      if (await _fileService.dirExists(filesDir)) {
        fileCount = (await _fileService.listFiles(filesDir)).length;
      }

      // 解析 home 路径
      final homePath = await _fileService.resolveHermesHome();

      // 模型配置 — 复用 ConfigService 解析，不重复实现
      final modelCfg = await _configService.readModelConfig();
      final model = modelCfg['model'] ?? '-';
      final provider = modelCfg['provider'] ?? '-';
      _currentBaseUrl = modelCfg['base_url'] ?? '-';

      // 定时任务数 — 从 cron/jobs.json 取 Hermes 任务 + crontab 系统任务
      int cronCount = 0;
      try {
        final hermesHome = await _fileService.resolveHermesHome();
        final content = await _fileService.readText('$hermesHome/cron/jobs.json');
        if (content.isNotEmpty) {
          final json = jsonDecode(content);
          if (json is Map && json['jobs'] is List) cronCount = (json['jobs'] as List).length;
        }
      } catch (_) {}
      // 加系统 crontab 任务数（含暂停的 # 行，用 -E 兼容所有环境）
      final sysCron = await _cm.runShell(
        "crontab -l 2>/dev/null | grep -cE '^#?[[:space:]]*[0-9*@]' || true",
        allowFailure: true,
      );
      cronCount += int.tryParse(sysCron.stdout.trim()) ?? 0;

      // 获取机器状态
      final machineStatus = await _cm.getMachineStatus();
      // 获取 Token 用量 — 暂时禁用
      Map<String, int>? tokenUsage;

      if (mounted) {
        setState(() {
          _sessionCount = sessions;
          _skillCount = skillsCount;
          _logSizeKb = logsSize ~/ 1024;
          _currentModel = model;
          _currentProvider = provider;
          _fileCount = fileCount;
          _cronCount = cronCount;
          _homePath = homePath;
          _machineStatus = machineStatus;
          _tokenUsage = tokenUsage;
          _dashboardLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dashboardLoading = false;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _loadData();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOnline = _cm.state.status == ConnStatus.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表盘'),
        actions: [
          // ── 在线状态指示器 ──
          _buildStatusIndicator(cs),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(showLoading: true),
            tooltip: '刷新',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !isOnline
          ? _buildOffline(cs)
          : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 统计行: 6 卡片合并为单行，字体自适应宽度 ──
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final double availableWidth = constraints.maxWidth;
                            const int cardCount = 6;
                            final double gapWidth = (cardCount - 1) * 12.0;
                            final double cardWidth = (availableWidth - gapWidth) / cardCount;
                            final double fontScale = (cardWidth / 200).clamp(0.6, 1.2);

                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Flexible(
                                    flex: 1,
                                    child: StatsCard(
                                      icon: Icons.chat_bubble_outline,
                                      value: '$_sessionCount',
                                      label: '总会话数',
                                      color: AppTheme.primary,
                                      fontScale: fontScale,
                                      onTap: () => widget.onNavigate?.call(1),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    flex: 1,
                                    child: StatsCard(
                                      icon: Icons.auto_awesome,
                                      value: '$_skillCount',
                                      label: '已装技能',
                                      color: AppTheme.info,
                                      fontScale: fontScale,
                                      onTap: () => widget.onNavigate?.call(5),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    flex: 1,
                                    child: StatsCard(
                                      icon: Icons.article_outlined,
                                      value: '$_logSizeKb KB',
                                      label: '日志大小',
                                      color: AppTheme.secondary,
                                      fontScale: fontScale,
                                      onTap: () => widget.onNavigate?.call(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    flex: 1,
                                    child: StatsCard(
                                      icon: Icons.schedule_outlined,
                                      value: '$_cronCount',
                                      label: '定时任务',
                                      color: AppTheme.secondary,
                                      fontScale: fontScale,
                                      onTap: () => widget.onNavigate?.call(3),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    flex: 1,
                                    child: StatsCard(
                                      icon: Icons.folder_outlined,
                                      value: '~',
                                      label: '文件浏览',
                                      color: AppTheme.info,
                                      fontScale: fontScale,
                                      onTap: () => widget.onNavigate?.call(6),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    flex: 1,
                                    child: StatsCard(
                                      icon: Icons.settings_outlined,
                                      value: '',
                                      label: '设置',
                                      color: AppTheme.warning,
                                      fontScale: fontScale,
                                      onTap: () => widget.onNavigate?.call(7),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // ═══════════════════════════════════════════════
                        //  模型配置
                        // ═══════════════════════════════════════════════
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('模型配置',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface)),
                                const SizedBox(height: 12),
                                _infoRow('当前模型', _currentModel, cs),
                                _infoRow('Provider', _currentProvider, cs),
                                _infoRow('Base URL', _currentBaseUrl, cs),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ═══════════════════════════════════════════════
                        //  机器状态
                        // ═══════════════════════════════════════════════
                        _buildMachineCard(cs),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
  }

  // ═══════════════════════════════════════════════
  //  在线状态指示器
  // ═══════════════════════════════════════════════

  Widget _buildStatusIndicator(ColorScheme cs) {
    final status = _cm.state.status;
    Color dotColor;
    String label;

    switch (status) {
      case ConnStatus.connected:
        dotColor = AppTheme.success;
        label = '在线';
      case ConnStatus.connecting:
        dotColor = AppTheme.warning;
        label = '连接中...';
      case ConnStatus.disconnected:
        dotColor = cs.error;
        label = '离线';
      case ConnStatus.error:
        dotColor = cs.error;
        label = '错误';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_dashboardLoading)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: dotColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  机器状态格式化（inline，适配 getMachineStatus 返回格式）
  // ═══════════════════════════════════════════════

  /// 格式化 CPU（来自 getMachineStatus 的 cpu 字段）
  String _formatMachineCpu(dynamic cpu) {
    if (cpu == null) return '-';
    if (cpu is num) return '${cpu.toStringAsFixed(1)}%';
    return cpu.toString();
  }

  /// 格式化内存（来自 getMachineStatus 的 memory 字段，值为 MB）
  String _formatMachineMemory(dynamic memory) {
    if (memory == null) return '-';
    if (memory is Map) {
      final used = memory['used'];
      final total = memory['total'];
      if (used is num && total is num) {
        // 值以 MB 为单位 → 转 GB
        return '${(used / 1024).toStringAsFixed(1)} GB / ${(total / 1024).toStringAsFixed(1)} GB';
      }
      return '${_fmt(used)} / ${_fmt(total)}';
    }
    return memory.toString();
  }

  /// 格式化磁盘（来自 getMachineStatus 的 disk 字段，值为 df -h 的字符串）
  String _formatMachineDisk(dynamic disk) {
    if (disk == null) return '-';
    if (disk is Map) {
      return '${_fmt(disk['used'])} / ${_fmt(disk['total'])}';
    }
    return disk.toString();
  }

  /// 格式化运行时间（来自 getMachineStatus 的 uptime 字段，值为 uptime -p 的字符串）
  String _formatMachineUptime(dynamic uptime) {
    if (uptime == null) return '-';
    // uptime -p 已经返回 "up X days" 格式
    return uptime.toString();
  }

  // ═══════════════════════════════════════════════
  //  格式化辅助方法
  // ═══════════════════════════════════════════════

  /// 安全转字符串，null → "-"
  String _fmt(Object? value) => value?.toString() ?? '-';

  Widget _buildMachineCard(ColorScheme cs) {
    final ms = _machineStatus;
    if (ms == null) return const SizedBox.shrink();
    // 内嵌模式不支持 shell 命令查看机器状态
    if (ms['uptime'] == 'embedded') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('机器状态',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('内嵌模式不支持机器状态监控',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('机器状态',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 12),
            Row(
              children: [
                _machineStat(Icons.memory_outlined, 'CPU',
                    _formatMachineCpu(ms['cpu']), cs),
                const SizedBox(width: 24),
                _machineStat(Icons.storage_outlined, '内存',
                    _formatMachineMemory(ms['memory']), cs),
                const SizedBox(width: 24),
                _machineStat(Icons.disc_full_outlined, '磁盘',
                    _formatMachineDisk(ms['disk']), cs),
                const SizedBox(width: 24),
                _machineStat(Icons.timer_outlined, '运行时间',
                    _formatMachineUptime(ms['uptime']), cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _machineStat(IconData icon, String label, String value, ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildOffline(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('Hermes Gateway 未运行',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text('请确保 Hermes Gateway 已启动 (hermes gateway run)',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _loadData(showLoading: true),
            icon: const Icon(Icons.refresh),
            label: const Text('重新连接'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}
