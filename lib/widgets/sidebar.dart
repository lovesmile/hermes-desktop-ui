import 'package:flutter/material.dart';
import '../config/theme.dart';

class Sidebar extends StatelessWidget {
  final int currentIndex;
  final bool collapsed;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onToggleCollapse;

  const Sidebar({
    super.key,
    required this.currentIndex,
    this.collapsed = false,
    required this.onItemSelected,
    required this.onToggleCollapse,
  });

  static const _navItems = [
    ('仪表盘', Icons.dashboard_outlined, Icons.dashboard),
    ('聊天', Icons.chat_outlined, Icons.chat),
    ('平台管理', Icons.devices_outlined, Icons.devices),
    ('定时任务', Icons.schedule_outlined, Icons.schedule),
    ('日志', Icons.article_outlined, Icons.article),
    ('模型与技能', Icons.memory_outlined, Icons.memory),
    ('设置', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A1A) : const Color(0xFFF8F8FF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.06);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white38 : Colors.black45;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: collapsed ? 64 : 220,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(color: borderColor),
        ),
      ),
      child: Column(
        children: [
          // Logo area
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C4DFF), Color(0xFF00E5FF)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'H',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Hermes',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Nav items
          ...List.generate(_navItems.length, (i) {
            final selected = i == currentIndex;
            final item = _navItems[i];
            return _NavItem(
              icon: selected ? item.$3 : item.$2,
              label: item.$1,
              selected: selected,
              collapsed: collapsed,
              onTap: () => onItemSelected(i),
            );
          }),
          const Spacer(),
          // Collapse toggle
          IconButton(
            onPressed: onToggleCollapse,
            icon: Icon(
              collapsed ? Icons.chevron_right : Icons.chevron_left,
              color: subTextColor,
              size: 20,
            ),
            tooltip: collapsed ? '展开侧栏' : '收起侧栏',
          ),
          const SizedBox(height: 8),
          // Version
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'v1.0.0',
                style: TextStyle(color: subTextColor, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textSecondary : Colors.black54;
    final selectedTextColor = isDark ? AppTheme.primary : AppTheme.primary;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppTheme.primary : textColor,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? selectedTextColor : textColor,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
