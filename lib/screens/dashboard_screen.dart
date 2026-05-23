import 'dart:io';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/config_service.dart';
import '../widgets/stats_card.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int index)? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _gateway = GatewayService();
  final _configService = ConfigService();
  bool _gatewayOnline = false;
  bool _loading = true;

  int _sessionCount = 0;
  int _skillCount = 0;
  int _logSizeKb = 0;
  String _currentModel = '-';
  String _currentProvider = '-';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      await _gateway.refreshBaseUrl();
      final online = await _gateway.checkHealth();

      // 统计会话文件
      int sessions = 0;
      final sessDir = Directory(
          '${Platform.environment['HOME'] ?? '/home/tian'}/.hermes/sessions');
      if (await sessDir.exists()) {
        sessions = await sessDir
            .list()
            .where((e) => e.path.endsWith('.jsonl') || e.path.endsWith('.json'))
            .length;
      }

      // 统计技能数量
      final skills = await _configService.getSkills();

      // 日志文件大小
      int logBytes = 0;
      final logDir = Directory(
          '${Platform.environment['HOME'] ?? '/home/tian'}/.hermes/logs');
      if (await logDir.exists()) {
        await for (final f in logDir.list()) {
          if (f is File) logBytes += await f.length();
        }
      }

      // 从 config.yaml 读取 model 配置
      final config = await _configService.readConfig();
      String model = '-';
      String provider = '-';
      for (final line in config.split('\n')) {
        final t = line.trim();
        if (t.startsWith('default:')) {
          final parts = t.split(':');
          if (parts.length > 1) model = parts.sublist(1).join(':').trim();
        }
        if (t.startsWith('provider:')) {
          final parts = t.split(':');
          if (parts.length > 1)
            provider = parts.sublist(1).join(':').trim();
        }
      }

      setState(() {
        _gatewayOnline = online;
        _sessionCount = sessions;
        _skillCount = skills.length;
        _logSizeKb = logBytes ~/ 1024;
        _currentModel = model;
        _currentProvider = provider;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes Desktop'),
        actions: [
          _buildStatusChip(),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: '刷新',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats row
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        Expanded(
                          child: StatsCard(
                            icon: Icons.chat_bubble_outline,
                            value: '$_sessionCount',
                            label: '会话文件 → 聊天',
                            color: AppTheme.primary,
                            onTap: () => widget.onNavigate?.call(1),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatsCard(
                            icon: Icons.auto_awesome,
                            value: '$_skillCount',
                            label: '已安装技能 → 模型与技能',
                            color: AppTheme.secondary,
                            onTap: () => widget.onNavigate?.call(5),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatsCard(
                            icon: Icons.article_outlined,
                            value: '$_logSizeKb KB',
                            label: '日志大小',
                            color: AppTheme.info,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatsCard(
                            icon: Icons.wifi,
                            value: _gatewayOnline ? '在线' : '离线',
                            label: 'Gateway',
                            color: _gatewayOnline
                                ? AppTheme.success
                                : AppTheme.error,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatsCard(
                            icon: Icons.schedule_outlined,
                            value: '定时',
                            label: '定时任务 → 管理',
                            color: AppTheme.warning,
                            onTap: () => widget.onNavigate?.call(3),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatsCard(
                            icon: Icons.settings_outlined,
                            value: '设置',
                            label: '设置 → 配置',
                            color: Colors.white38,
                            onTap: () => widget.onNavigate?.call(6),
                          ),
                        ),
                      ],
                    ),
                    ),
                    const SizedBox(height: 32),

                    // 当前模型配置
                    if (_currentModel != '-')
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('模型配置',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 16),
                              _infoRow('当前模型', _currentModel),
                              _infoRow('Provider', _currentProvider),
                              _infoRow('Gateway 地址',
                                  'http://localhost:8642'),
                              _infoRow('Hermes 目录',
                                  '~/.hermes'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // API 状态
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('API Server 状态',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (_gatewayOnline
                                            ? AppTheme.success
                                            : AppTheme.error)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _gatewayOnline ? '运行中' : '未运行',
                                    style: TextStyle(
                                      color: _gatewayOnline
                                          ? AppTheme.success
                                          : AppTheme.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'localhost:8642',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '需在 ~/.hermes/.env 中设置 API_SERVER_ENABLED=true',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatusChip() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (_gatewayOnline ? AppTheme.success : AppTheme.error)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _gatewayOnline ? AppTheme.success : AppTheme.error,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _gatewayOnline ? '在线' : '离线',
              style: TextStyle(
                fontSize: 13,
                color: _gatewayOnline ? AppTheme.success : AppTheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                )),
          ),
        ],
      ),
    );
  }
}