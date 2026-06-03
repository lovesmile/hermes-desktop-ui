import 'package:flutter/material.dart';
import '../config/theme.dart';

class StatsCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final String? trend;
  final bool trendUp;
  final VoidCallback? onTap;
  final double fontScale;

  const StatsCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.trend,
    this.trendUp = true,
    this.onTap,
    this.fontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = color ?? AppTheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 22),
                  ),
                  if (trend != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          trendUp ? Icons.trending_up : Icons.trending_down,
                          color: trendUp ? AppTheme.success : AppTheme.error,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          trend!,
                          style: TextStyle(
                            fontSize: 12,
                            color: trendUp ? AppTheme.success : AppTheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: TextStyle(
                  fontSize: 28 * fontScale,
                  fontWeight: FontWeight.w500,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13 * fontScale,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
