import 'package:flutter/material.dart';
import 'package:hermes_desktop/config/theme.dart';

/// Global key for root ScaffoldMessenger (SnackBar fallback).
final GlobalKey<ScaffoldMessengerState> rootScaffoldKey =
    GlobalKey<ScaffoldMessengerState>();

/// Global key for root Navigator (used by [showTopNotification]).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Show a floating notification at the very top of the window,
/// above all dialogs and overlays. Auto-dismisses after [duration].
void showTopNotification(
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 3),
}) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;

  final context = navigator.context;
  final overlay = Overlay.of(context);

  OverlayEntry? entry;

  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: _NotifBar(
          message: message,
          color: backgroundColor ?? AppTheme.success,
        ),
      ),
    ),
  );

  overlay.insert(entry);

  Future.delayed(duration, () {
    entry?.remove();
    entry = null;
  });
}

/// Internal widget for the notification bar.
class _NotifBar extends StatelessWidget {
  final String message;
  final Color color;

  const _NotifBar({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              color == AppTheme.error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
