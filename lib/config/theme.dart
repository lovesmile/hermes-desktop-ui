import 'package:flutter/material.dart';

/// Material Design 3 theme for Hermes Desktop UI
/// References: https://m3.material.io/
class AppTheme {
  // ── Seed colors ──────────────────────────────────────────────
  static const Color _seedColor = Color(0xFF6750A4); // M3 default seed
  static const Color _errorColor = Color(0xFFB3261E);

  // ── Dynamic color scheme from seed ────────────────────────────
  static ColorScheme _lightScheme() => ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
        error: _errorColor,
      );

  static ColorScheme _darkScheme() => ColorScheme.fromSeed(
        seedColor: _seedColor,
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
  static Color get primary => _seedColor;
  static Color get secondary => const Color(0xFF625B71);
  static Color get tertiary => const Color(0xFF7D5260);
  static Color get error => _errorColor;
  static Color get surface => const Color(0xFFFFFBFE);
  static Color get surfaceDark => const Color(0xFF1C1B1F);
  static Color get card => const Color(0xFFF3EDF7);

  static Color get success => const Color(0xFF4CAF50);
  static Color get warning => const Color(0xFFFFA726);
  static Color get info => const Color(0xFF42A5F5);

  static Color get primaryContainer => const Color(0xFFEADDFF);
  static Color get secondaryContainer => const Color(0xFFE8DEF8);
  static Color get tertiaryContainer => const Color(0xFFFFD8E4);

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
      // Title
      titleLarge: _textStyle(brightness, 22, FontWeight.w500, 0),
      titleMedium: _textStyle(brightness, 16, FontWeight.w500, 0.15),
      titleSmall: _textStyle(brightness, 14, FontWeight.w500, 0.1),
      // Body
      bodyLarge: _textStyle(brightness, 16, FontWeight.w400, 0.5),
      bodyMedium: _textStyle(brightness, 14, FontWeight.w400, 0.25),
      bodySmall: _textStyle(brightness, 12, FontWeight.w400, 0.4),
      // Label
      labelLarge: _textStyle(brightness, 14, FontWeight.w500, 0.1),
      labelMedium: _textStyle(brightness, 12, FontWeight.w500, 0.5),
      labelSmall: _textStyle(brightness, 11, FontWeight.w500, 0.5),
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
        color: scheme.surfaceContainerLow,
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
          fontWeight: FontWeight.w500,
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
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
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
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w500,
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
