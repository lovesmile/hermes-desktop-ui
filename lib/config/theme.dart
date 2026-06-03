import 'package:flutter/material.dart';

/// Material Design 3 theme for Hermes Desktop UI
/// References: https://m3.material.io/
class AppTheme {
  // ── Seed colors ──────────────────────────────────────────────
  static const Color _defaultSeed = Color(0xFF2563EB); // 科技蓝 — 默认
  static const Color _errorColor = Color(0xFFB3261E);

  /// 可选主题色列表（与 themeNames 一一对应）
  static const List<Color> seedColors = [
    Color(0xFF2563EB), // 科技蓝
    Color(0xFF10B981), // 翡翠绿
    Color(0xFF7C3AED), // 罗兰紫
    Color(0xFFE11D48), // 玫瑰红
    Color(0xFFF97316), // 暖橙
    Color(0xFF06B6D4), // 青色
  ];

  /// 主题色名称（与 seedColors 一一对应）
  static const List<String> themeNames = [
    '科技蓝', '翡翠绿', '罗兰紫', '玫瑰红', '暖橙', '青色',
  ];

  static Color _currentSeed() {
    final idx = themeColorNotifier.value;
    if (idx >= 0 && idx < seedColors.length) return seedColors[idx];
    return _defaultSeed;
  }

  // ── Dynamic color scheme from seed ────────────────────────────
  static ColorScheme _lightScheme() => ColorScheme.fromSeed(
        seedColor: _currentSeed(),
        brightness: Brightness.light,
        error: _errorColor,
      );

  static ColorScheme _darkScheme() => ColorScheme.fromSeed(
        seedColor: _currentSeed(),
        brightness: Brightness.dark,
        error: _errorColor,
      );

  // ── Shape scheme (M3 levels) ─────────────────────────────────
  static const ShapeBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  static const ShapeBorder dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(28)),
  );
  static const ShapeBorder chipShape = StadiumBorder();
  static const ShapeBorder buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(20)),
  );

  // ── Convenient color accessors (backward compat) ──────────────
  static Color get primary => _currentSeed();
  static Color get secondary => const Color(0xFF475569);
  static Color get tertiary => const Color(0xFFD97706);
  static Color get error => _errorColor;
  static Color get surface => const Color(0xFFF8FAFC);
  static Color get surfaceDark => const Color(0xFF0F172A);
  static Color get card => const Color(0xFFEFF6FF);

  static Color get success => const Color(0xFF10B981);
  static Color get warning => const Color(0xFFF59E0B);
  static Color get info => const Color(0xFF38BDF8);

  static Color get primaryContainer => const Color(0xFFDBEAFE);
  static Color get secondaryContainer => const Color(0xFFE2E8F0);
  static Color get tertiaryContainer => const Color(0xFFF0FDF4);

  /// 渐变配色 — 匹配 logo (#1E293B → #0F172A)
  static const List<Color> logoGradient = [Color(0xFF1E293B), Color(0xFF0F172A)];

  // ── Typography (M3 type scale) ───────────────────────────────
  static TextTheme _textTheme(Brightness brightness) {
    return TextTheme(
      // Display
      displayLarge: _textStyle(brightness, 57, FontWeight.w400, -0.25),
      displayMedium: _textStyle(brightness, 45, FontWeight.w400, 0),
      displaySmall: _textStyle(brightness, 36, FontWeight.w400, 0),
      // Headline
      headlineLarge: _textStyle(brightness, 32, FontWeight.w400, 0),
      headlineMedium: _textStyle(brightness, 28, FontWeight.w400, 0),
      headlineSmall: _textStyle(brightness, 24, FontWeight.w400, 0),
      // Title (统一用 w400，和 body 一致)
      titleLarge: _textStyle(brightness, 22, FontWeight.w400, 0),
      titleMedium: _textStyle(brightness, 16, FontWeight.w400, 0.15),
      titleSmall: _textStyle(brightness, 14, FontWeight.w400, 0.1),
      // Body
      bodyLarge: _textStyle(brightness, 16, FontWeight.w400, 0.5),
      bodyMedium: _textStyle(brightness, 14, FontWeight.w400, 0.25),
      bodySmall: _textStyle(brightness, 12, FontWeight.w400, 0.4),
      // Label (统一 w400)
      labelLarge: _textStyle(brightness, 14, FontWeight.w400, 0.1),
      labelMedium: _textStyle(brightness, 12, FontWeight.w400, 0.5),
      labelSmall: _textStyle(brightness, 11, FontWeight.w400, 0.5),
    );
  }

  static TextStyle _textStyle(Brightness brightness, double size,
      FontWeight weight, double letterSpacing) {
    final isDark = brightness == Brightness.dark;
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: isDark ? Colors.white : const Color(0xFF1C1B1F),
    );
  }

  // ── M3 Dark Theme ────────────────────────────────────────────
  static ThemeData get darkTheme {
    final colorScheme = _darkScheme();
    return _buildTheme(colorScheme, Brightness.dark);
  }

  // ── M3 Light Theme ───────────────────────────────────────────
  static ThemeData get lightTheme {
    final colorScheme = _lightScheme();
    return _buildTheme(colorScheme, Brightness.light);
  }

  // ── Build theme from scheme ──────────────────────────────────
  static ThemeData _buildTheme(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,

      // ── Shape ──────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        color: cardBg,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        elevation: 3,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        disabledColor: scheme.surfaceContainerLow,
        labelStyle: TextStyle(
          fontSize: 12,
          color: scheme.onSurface,
          fontWeight: FontWeight.w400,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
        shape: StadiumBorder(
          side: BorderSide(color: scheme.outline),
        ),
        side: BorderSide(color: scheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outline),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bgColor,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
        minWidth: 80,
        groupAlignment: -0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer;
          }
          return scheme.surfaceContainerHighest;
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      scaffoldBackgroundColor: bgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
      ),
      textTheme: _textTheme(brightness),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      primaryIconTheme: IconThemeData(color: scheme.primary),
    );
  }
}

/// Theme mode notifier (global toggle)
class ThemeModeNotifier extends ValueNotifier<bool> {
  ThemeModeNotifier() : super(false);

  void toggle() => value = !value;
}

final themeModeNotifier = ThemeModeNotifier();

/// Theme color index notifier (global, selects from AppTheme.seedColors)
class ThemeColorNotifier extends ValueNotifier<int> {
  ThemeColorNotifier() : super(0);
}

final themeColorNotifier = ThemeColorNotifier();
