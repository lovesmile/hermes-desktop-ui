import 'package:flutter/material.dart';

/// Hermes Modern 设计规范 — 固定配色系统
///
/// 配色方案参考：desktop-ui.md
/// - 深色模式：主背景 #0E1219，强调色 D4AF6A（金）
/// - 浅色模式：主背景 #F8F9FC，强调色 C49A4C（金）
/// - 字体：Inter（正文），JetBrains Mono（等宽）
class AppTheme {
  // ── 深色模式 6 种强调色（seedColors 的别名，避免 internal 警告） ──
  static List<Color> get _darkAccents => seedColors;

  // ── 浅色模式 6 种强调色 ─────────────────────────────────────
  static const List<Color> _lightAccents = [
    Color(0xFFC49A4C), // 金色
    Color(0xFF5588B1), // 蓝色
    Color(0xFF8E5BC4), // 紫色
    Color(0xFF3A8B6E), // 绿色
    Color(0xFFD47A3A), // 橙色
    Color(0xFF3BA09D), // 青色
  ];

  /// 主题色名称（与 _darkAccents / _lightAccents 一一对应）
  static const List<String> themeNames = [
    '金色', '蓝色', '紫色', '绿色', '橙色', '青色',
  ];

  /// 色块显示用（设置页调色盘），始终显示深色模式色值
  /// 色块显示用（设置页调色盘），始终显示深色模式色值
  static const List<Color> seedColors = [
    Color(0xFFD4AF6A), // 金色
    Color(0xFF6C9FD1), // 蓝色
    Color(0xFFB385E6), // 紫色
    Color(0xFF4FB88D), // 绿色
    Color(0xFFE89B5C), // 橙色
    Color(0xFF5EC8C5), // 青色
  ];

  static Color _currentAccent(bool isDark) {
    final idx = themeColorNotifier.value;
    final list = isDark ? _darkAccents : _lightAccents;
    if (idx >= 0 && idx < list.length) return list[idx];
    return isDark ? _darkAccents[0] : _lightAccents[0];
  }

  // ── 中性色 ──────────────────────────────────────────────────
  static const Color _neutralBgDark = Color(0xFF0E1219);
  static const Color _neutralBgSecondaryDark = Color(0xFF1A1F2A);
  static const Color _neutralBgTertiaryDark = Color(0xFF252C38);
  static const Color _neutralTextPrimaryDark = Color(0xFFE8ECF2);
  static const Color _neutralTextSecondaryDark = Color(0xFF9AA6B9);
  static const Color _neutralBorderDark = Color(0xFF2C3442);
  static const Color _neutralBgLight = Color(0xFFF8F9FC);
  static const Color _neutralBgSecondaryLight = Color(0xFFF0F2F5);
  static const Color _neutralBgTertiaryLight = Color(0xFFE6E9EF);
  static const Color _neutralTextPrimaryLight = Color(0xFF1D232E);
  static const Color _neutralTextSecondaryLight = Color(0xFF5E6B82);
  static const Color _neutralBorderLight = Color(0xFFDFE3EA);
  // ── 状态色 ──────────────────────────────────────────────────
  static const Color _successDark = Color(0xFF3F9E7D);
  static const Color _warningDark = Color(0xFFE5A93D);
  static const Color _errorDark = Color(0xFFD66A5C);
  static const Color _errorLight = Color(0xFFC1574A);

  // ── 便捷访问器（兼容现有 AppTheme.xxx 调用） ────────────────
  static Color get primary => _currentAccent(true);
  static Color get secondary => _neutralTextSecondaryDark;
  static Color get tertiary => const Color(0xFF6C9FD1);
  static Color get error => _errorDark;
  static Color get surface => _neutralBgDark;
  static Color get surfaceDark => _neutralBgDark;
  static Color get card => _neutralBgSecondaryDark;

  static Color get success => _successDark;
  static Color get warning => _warningDark;
  static Color get info => const Color(0xFF6C9FD1);

  static Color get primaryContainer => const Color(0xFFD4AF6A).withValues(alpha: 0.15);
  static Color get secondaryContainer => _neutralBgTertiaryDark;
  static Color get tertiaryContainer => const Color(0xFF3F9E7D).withValues(alpha: 0.15);

  static const List<Color> logoGradient = [Color(0xFF1E293B), Color(0xFF0F172A)];

  // ── 构建 ColorScheme ────────────────────────────────────────
  static ColorScheme _buildColorScheme(bool isDark) {
    final accent = _currentAccent(isDark);

    if (isDark) {
      return ColorScheme.dark(
        primary: accent,
        onPrimary: _neutralBgDark,
        primaryContainer: accent.withValues(alpha: 0.15),
        onPrimaryContainer: _neutralTextPrimaryDark,
        secondary: _neutralTextSecondaryDark,
        onSecondary: _neutralBgDark,
        secondaryContainer: _neutralBgTertiaryDark,
        onSecondaryContainer: _neutralTextPrimaryDark,
        tertiary: const Color(0xFF6C9FD1),
        onTertiary: _neutralBgDark,
        tertiaryContainer: const Color(0xFF6C9FD1).withValues(alpha: 0.15),
        error: _errorDark,
        onError: _neutralBgDark,
        errorContainer: _errorDark.withValues(alpha: 0.15),
        onErrorContainer: _errorDark,
        surface: _neutralBgDark,
        onSurface: _neutralTextPrimaryDark,
        surfaceContainerHighest: _neutralBgSecondaryDark,
        surfaceContainerHigh: _neutralBgSecondaryDark,
        surfaceContainerLow: _neutralBgDark,
        onSurfaceVariant: _neutralTextSecondaryDark,
        outline: _neutralBorderDark,
        outlineVariant: _neutralBorderDark,
        inverseSurface: _neutralBgLight,
        onInverseSurface: _neutralTextPrimaryLight,
        inversePrimary: _lightAccents[themeColorNotifier.value.clamp(0, _lightAccents.length - 1)],
      );
    } else {
      return ColorScheme.light(
        primary: accent,
        onPrimary: Colors.white,
        primaryContainer: accent.withValues(alpha: 0.15),
        onPrimaryContainer: _neutralTextPrimaryLight,
        secondary: _neutralTextSecondaryLight,
        onSecondary: Colors.white,
        secondaryContainer: _neutralBgTertiaryLight,
        onSecondaryContainer: _neutralTextPrimaryLight,
        tertiary: const Color(0xFF5588B1),
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFF5588B1).withValues(alpha: 0.15),
        error: _errorLight,
        onError: Colors.white,
        errorContainer: _errorLight.withValues(alpha: 0.15),
        onErrorContainer: _errorLight,
        surface: _neutralBgLight,
        onSurface: _neutralTextPrimaryLight,
        surfaceContainerHighest: _neutralBgSecondaryLight,
        surfaceContainerHigh: _neutralBgSecondaryLight,
        surfaceContainerLow: _neutralBgLight,
        onSurfaceVariant: _neutralTextSecondaryLight,
        outline: _neutralBorderLight,
        outlineVariant: _neutralBorderLight,
        inverseSurface: _neutralBgDark,
        onInverseSurface: _neutralTextPrimaryDark,
        inversePrimary: _darkAccents[themeColorNotifier.value.clamp(0, _darkAccents.length - 1)],
      );
    }
  }

  // ── Shape scheme ────────────────────────────────────────────
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

  // ── Typography (Inter 正文 + JetBrains Mono 等宽) ──────────
  static TextTheme _textTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final Color textColor = isDark ? _neutralTextPrimaryDark : _neutralTextPrimaryLight;
    final Color subtleColor = isDark ? _neutralTextSecondaryDark : _neutralTextSecondaryLight;

    final base = TextTheme(
      // Display
      displayLarge: _txtStyle(57, FontWeight.w600, -0.25, textColor),
      displayMedium: _txtStyle(48, FontWeight.w600, 0, textColor),
      displaySmall: _txtStyle(40, FontWeight.w600, 0, textColor),
      // Headline
      headlineLarge: _txtStyle(36, FontWeight.w600, 0, textColor),
      headlineMedium: _txtStyle(32, FontWeight.w600, 0, textColor),
      headlineSmall: _txtStyle(28, FontWeight.w600, 0, textColor),
      // Title (SemiBold)
      titleLarge: _txtStyle(22, FontWeight.w600, 0, textColor),
      titleMedium: _txtStyle(18, FontWeight.w600, 0.15, textColor),
      titleSmall: _txtStyle(16, FontWeight.w600, 0.1, textColor),
      // Body (Regular)
      bodyLarge: _txtStyle(18, FontWeight.w400, 0.5, textColor),
      bodyMedium: _txtStyle(16, FontWeight.w400, 0.25, textColor),
      bodySmall: _txtStyle(14, FontWeight.w400, 0.4, subtleColor),
      // Label (Medium)
      labelLarge: _txtStyle(16, FontWeight.w500, 0.1, textColor),
      labelMedium: _txtStyle(14, FontWeight.w500, 0.5, textColor),
      labelSmall: _txtStyle(13, FontWeight.w500, 0.5, subtleColor),
    );
    return base;
  }

  static TextStyle _txtStyle(double size, FontWeight weight, double letterSpacing, Color color) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      fontFamilyFallback: ['PingFang SC', 'Microsoft YaHei', 'Noto Sans SC', 'sans-serif'],
    );
  }

  /// 等宽字体样式（代码块、日志、终端等使用）
  static TextStyle monoStyle(double size, {Color? color, FontWeight weight = FontWeight.w400}) {
    return TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  // ── ThemeData ────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return _buildTheme(_buildColorScheme(true), Brightness.dark);
  }

  static ThemeData get lightTheme {
    return _buildTheme(_buildColorScheme(false), Brightness.light);
  }

  static ThemeData _buildTheme(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final Color bg = isDark ? _neutralBgDark : _neutralBgLight;
    final Color cardBg = isDark ? _neutralBgSecondaryDark : _neutralBgSecondaryLight;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Inter',

      // ── Card ────────────────────────────────────────────────
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

      // ── Dialog ──────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        elevation: 3,
      ),

      // ── Chip ────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        disabledColor: scheme.surfaceContainerLow,
        labelStyle: TextStyle(fontSize: 12, color: scheme.onSurface, fontWeight: FontWeight.w400),
        secondaryLabelStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
        side: BorderSide(color: scheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ── Input ──────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
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

      // ── NavigationRail ──────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bg,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
        minWidth: 80,
        groupAlignment: -0.5,
      ),

      // ── SnackBar ────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Divider ─────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
      ),

      // ── Switch ──────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primaryContainer;
          return scheme.surfaceContainerHighest;
        }),
      ),

      // ── FAB ─────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
      ),

      // ── ProgressIndicator ───────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),

      // ── AppBar ──────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
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
  ThemeModeNotifier() : super(true);
  void toggle() => value = !value;
}

final themeModeNotifier = ThemeModeNotifier();

/// Theme color index notifier (global, selects from AppTheme 6 accent colors)
class ThemeColorNotifier extends ValueNotifier<int> {
  ThemeColorNotifier() : super(0);
}

final themeColorNotifier = ThemeColorNotifier();
