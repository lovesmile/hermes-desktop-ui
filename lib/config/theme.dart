import 'package:flutter/material.dart';

class AppTheme {
  // 颜色常量 — 亮一点，低对比时更清晰
  static const Color _primaryColor = Color(0xFF7C4DFF);
  static const Color _secondaryColor = Color(0xFF00BCD4);
  static const Color _surfaceColor = Color(0xFF1E1E2E);
  static const Color _backgroundColor = Color(0xFF282840);
  static const Color _cardColor = Color(0xFF363652);
  static const Color _navColor = Color(0xFF1A1A2E);
  static const Color _success = Color(0xFF66BB6A);
  static const Color _warning = Color(0xFFFFCA28);
  static const Color _error = Color(0xFFEF5350);
  static const Color _info = Color(0xFF42A5F5);
  static const Color _textPrimary = Color(0xFFF0F0FF);
  static const Color _textSecondary = Color(0xFFB0B0C0);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _primaryColor,
        secondary: _secondaryColor,
        surface: _surfaceColor,
        error: _error,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: _textPrimary,
      ),
      scaffoldBackgroundColor: _backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: _navColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: _textSecondary),
      ),
      cardTheme: CardThemeData(
        color: _cardColor,
        elevation: 3,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: _navColor,
        indicatorColor: _primaryColor.withValues(alpha: 0.35),
        selectedLabelTextStyle: const TextStyle(
            fontSize: 12, color: _primaryColor, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            const TextStyle(fontSize: 12, color: _textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(color: _textSecondary),
        labelStyle: const TextStyle(color: _textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _cardColor,
        selectedColor: _primaryColor.withValues(alpha: 0.3),
        labelStyle: const TextStyle(fontSize: 12, color: _textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      dividerTheme:
          DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 28),
        headlineMedium: TextStyle(
            color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 22),
        titleLarge: TextStyle(
            color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
        titleMedium: TextStyle(
            color: _textPrimary, fontWeight: FontWeight.w500, fontSize: 16),
        bodyLarge: TextStyle(color: _textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: _textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: _textSecondary, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white30),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: _primaryColor),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _primaryColor;
          return Colors.white54;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _primaryColor.withValues(alpha: 0.4);
          }
          return Colors.white24;
        }),
      ),
    );
  }

  // 工具颜色
  static Color get success => _success;
  static Color get warning => _warning;
  static Color get error => _error;
  static Color get info => _info;
  static Color get primary => _primaryColor;
  static Color get secondary => _secondaryColor;
  static Color get surface => _surfaceColor;
  static Color get card => _cardColor;
  static Color get textPrimary => _textPrimary;
  static Color get textSecondary => _textSecondary;

  /// 浅色主题
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: _primaryColor,
        secondary: _secondaryColor,
        surface: Color(0xFFF5F5F5),
        error: _error,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: Colors.black87,
      ),
      scaffoldBackgroundColor: const Color(0xFFF0F0F0),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.black87,
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black87, fontSize: 15),
        bodyMedium: TextStyle(color: Colors.black54, fontSize: 14),
        bodySmall: TextStyle(color: Colors.black45, fontSize: 12),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
    );
  }
}

/// 全局主题模式切换
class ThemeModeNotifier extends ValueNotifier<bool> {
  ThemeModeNotifier() : super(true); // true = dark, false = light

  void toggle() {
    value = !value;
  }
}

final themeModeNotifier = ThemeModeNotifier();
