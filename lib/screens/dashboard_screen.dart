import 'dart:io';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../services/local_db.dart';
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
  final _localDb = LocalDatabase();
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

      final hermesHome = ConfigService.resolveHermesHome();

      // 从本地数据库读取会话数
      final localSessions = await _localDb.getSessions();
      int sessions = localSessions.length;

      final skills = await _configService.getSkills();

      int logBytes = 0;
      final logDir = Directory('$hermesHome/logs');
      if (await logDir.exists()) {
        await for (final f in logDir.list()) {
          if (f is File) logBytes += await f.length();
        }
      }

      // 只读 model: 段下的 provider
      final config = await _configService.readConfig();
      String model = '-';
      String provider = '-';
      String? configSection;
      for (final line in config.split('\n')) {
        final indent = line.length - line.trimLeft().length;
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        if (indent == 0 && t.endsWith(':') && !t.startsWith('-')) {
          configSection = t.substring(0, t.length - 1);
          continue;
        }
        if (configSection == 'model' && indent > 0) {
          if (t.startsWith('default:')) {
            final sep = t.indexOf(':');
            model = t.substring(sep + 1).trim();
          } else if (t.startsWith('provider:')) {
            final sep = t.indexOf(':');
            provider = t.substring(sep + 1).trim();
          }
        }
      }

      if (mounted) {
        setState(() {
          _gatewayOnline = online;
          _sessionCount = sessions;
          _skillCount = skills.length;
          _logSizeKb = logBytes ~/ 1024;
          _currentModel = model;
          _currentProvider = provider;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gatewayOnline = false;
          _loading = false;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_gatewayOnline) _loadData();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表盘'),
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
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text('加载中...', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            : !_gatewayOnline
                ? _buildOffline(cs)
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 统计卡片 — IntrinsicHeight 保证等高
                        IntrinsicHeight(
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
                                  onTap: () => widget.onNavigate?.call(1),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: StatsCard(
                                  icon: Icons.auto_awesome,
                                  value: '$_skillCount',
                                  label: '已装技能',
                                  color: AppTheme.info,
                                  onTap: () => widget.onNavigate?.call(5),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: StatsCard(
                                  icon: Icons.article_outlined,
                                  value: '$_logSizeKb KB',
                                  label: '日志大小',
                                  color: AppTheme.secondary,
                                  onTap: () => widget.onNavigate?.call(4),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: StatsCard(
                                  icon: Icons.wifi,
                                  value: _gatewayOnline ? '在线' : '离线',
                                  label: 'Gateway',
                                  color: _gatewayOnline
                                      ? AppTheme.success
                                      : AppTheme.error,
                                  onTap: () => widget.onNavigate?.call(6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // 当前模型配置
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('模型配置',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface)),
                                const SizedBox(height: 16),
                                _infoRow('当前模型', _currentModel, cs),
                                _infoRow('Provider', _currentProvider, cs),
                                _infoRow('Gateway', _gateway.baseUrl, cs),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 快捷导航
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('快捷导航',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface)),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _quickAction(
                                      Icons.chat_outlined,
                                      '会话历史',
                                      AppTheme.primary,
                                      () => widget.onNavigate?.call(1),
                                    ),
                                    _quickAction(
                                      Icons.auto_awesome,
                                      '技能列表',
                                      AppTheme.info,
                                      () => widget.onNavigate?.call(5),
                                    ),
                                    _quickAction(
                                      Icons.schedule_outlined,
                                      '定时任务',
                                      AppTheme.secondary,
                                      () => widget.onNavigate?.call(3),
                                    ),
                                    _quickAction(
                                      Icons.settings_outlined,
                                      '设置',
                                      AppTheme.warning,
                                      () => widget.onNavigate?.call(6),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '也可使用左侧导航栏切换页面',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // API Server 状态
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('API Server 状态',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface)),
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
                                      _gateway.baseUrl,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
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
    final color = _gatewayOnline ? AppTheme.success : AppTheme.error;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              _gatewayOnline ? '在线' : '离线',
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
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
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('重新连接'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
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

  Widget _quickAction(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
