import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/gateway_service.dart';
import '../models/log_entry.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with SingleTickerProviderStateMixin {
  final _gateway = GatewayService();
  final _searchController = TextEditingController();
  late TabController _tabController;

  List<LogEntry> _allLogs = [];
  bool _loading = true;
  String _selectedLevel = '';
  bool _autoScroll = true;
  final _scrollController = ScrollController();

  static const _tabs = ['Agent 日志', 'Gateway 日志', '错误日志'];
  static const _sources = ['agent', 'gateway', 'error'];
  static const _levels = ['ALL', 'INFO', 'WARN', 'ERROR', 'DEBUG'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadLogs();
    });
    _loadLogs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final source = _sources[_tabController.index];
      final logs = await _gateway.getLogs(
        source: source,
        level: _selectedLevel.isEmpty ? null : _selectedLevel,
        keyword: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      setState(() {
        _allLogs = logs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Color _levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return AppTheme.error;
      case 'WARN':
        return AppTheme.warning;
      case 'INFO':
        return AppTheme.info;
      case 'DEBUG':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('日志'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.white54,
          indicatorColor: AppTheme.primary,
        ),
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                bottom:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                // Level chips
                ..._levels.map((l) => Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(l, style: TextStyle(fontSize: 11)),
                        selected: _selectedLevel == l ||
                            (l == 'ALL' && _selectedLevel.isEmpty),
                        onSelected: (_) {
                          setState(() {
                            _selectedLevel = l == 'ALL' ? '' : l;
                          });
                          _loadLogs();
                        },
                        selectedColor: AppTheme.primary.withValues(alpha: 0.3),
                        backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: _selectedLevel == l ||
                                  (l == 'ALL' && _selectedLevel.isEmpty)
                              ? AppTheme.primary
                              : Colors.white54,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    )),
                const Spacer(),
                // Search
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '搜索日志...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onSubmitted: (_) => _loadLogs(),
                  ),
                ),
                SizedBox(width: 8),
                // Refresh
                IconButton(
                  icon: Icon(Icons.refresh, size: 20),
                  onPressed: _loadLogs,
                  tooltip: '刷新',
                ),
                SizedBox(width: 4),
                // Clear display
                IconButton(
                  icon: Icon(Icons.clear_all, size: 20),
                  onPressed: () {
                    setState(() => _allLogs = []);
                  },
                  tooltip: '清空显示',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: 4),
                // Auto-scroll toggle
                IconButton(
                  icon: Icon(
                    _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _autoScroll = !_autoScroll),
                  tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
                  color: _autoScroll ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          // Log list
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _allLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article_outlined,
                                size: 48,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            SizedBox(height: 12),
                            Text('暂无日志',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: _allLogs.length,
                        itemBuilder: (context, i) {
                          final log = _allLogs[i];
                          return _buildLogEntry(log);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 140,
            child: Text(
              '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // Level badge
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: _levelColor(log.level).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              log.level,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: _levelColor(log.level),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 8),
          // Message
          Expanded(
            child: Text(
              log.message,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
