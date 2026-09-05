/// KisakiGals 主题：樱花粉 × 藤紫 × 奶油白，Material 3。
library;

import 'package:flutter/material.dart';

class KisakiColors {
  // 主色：樱花粉
  static const pink = Color(0xFFEC6A9C);
  static const pinkSoft = Color(0xFFF8BBD0);
  static const pinkContainer = Color(0xFFFFE3EE);
  static const onPinkContainer = Color(0xFF5C2440);

  // 辅色：藤紫
  static const lavender = Color(0xFF9D8CD8);
  static const lavenderSoft = Color(0xFFD8CFF2);
  static const lavenderContainer = Color(0xFFEAE4FB);
  static const onLavenderContainer = Color(0xFF372A5E);

  // 浅色底
  static const cream = Color(0xFFFFF8F2);
  static const creamCard = Colors.white;
  static const ink = Color(0xFF3A2E36);
  static const inkSoft = Color(0xFF8A7580);

  // 深色底
  static const nightBg = Color(0xFF1A1520);
  static const nightCard = Color(0xFF251E2C);
  static const nightInk = Color(0xFFEFE3EA);
  static const nightInkSoft = Color(0xFFB49FB0);
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KisakiColors.pink,
    brightness: Brightness.light,
  ).copyWith(
    primary: KisakiColors.pink,
    secondary: KisakiColors.lavender,
    surface: KisakiColors.cream,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFFFFDFB),
    surfaceContainer: const Color(0xFFFFF6F0),
    surfaceContainerHigh: const Color(0xFFFBEFE8),
    surfaceContainerHighest: const Color(0xFFF7E7E0),
    onSurface: KisakiColors.ink,
    onSurfaceVariant: KisakiColors.inkSoft,
    primaryContainer: KisakiColors.pinkContainer,
    onPrimaryContainer: KisakiColors.onPinkContainer,
    secondaryContainer: KisakiColors.lavenderContainer,
    onSecondaryContainer: KisakiColors.onLavenderContainer,
  );
  return _base(scheme, Brightness.light);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KisakiColors.pink,
    brightness: Brightness.dark,
  ).copyWith(
    primary: KisakiColors.pinkSoft,
    secondary: KisakiColors.lavenderSoft,
    surface: KisakiColors.nightBg,
    surfaceContainerLowest: const Color(0xFF141019),
    surfaceContainerLow: KisakiColors.nightCard,
    surfaceContainer: const Color(0xFF2B2333),
    surfaceContainerHigh: const Color(0xFF332A3C),
    surfaceContainerHighest: const Color(0xFF3C3245),
    onSurface: KisakiColors.nightInk,
    onSurfaceVariant: KisakiColors.nightInkSoft,
  );
  return _base(scheme, Brightness.dark);
}

ThemeData _base(ColorScheme scheme, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor:
        isDark ? KisakiColors.nightBg : KisakiColors.cream,
    fontFamily: 'Microsoft YaHei UI',
    splashFactory: InkSparkle.splashFactory,
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor:
          isDark ? KisakiColors.pink.withValues(alpha: 0.25) : KisakiColors.pinkContainer,
      selectedIconTheme: IconThemeData(
          color: isDark ? KisakiColors.pinkSoft : KisakiColors.pink),
      unselectedIconTheme: IconThemeData(
          color: isDark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft),
      selectedLabelTextStyle: TextStyle(
          color: isDark ? KisakiColors.pinkSoft : KisakiColors.pink,
          fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(
          color: isDark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? KisakiColors.nightCard : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF2E2637) : const Color(0xFFFDF3EE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12),
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? KisakiColors.nightCard : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
      thickness: 1,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor:
          isDark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
      indicatorSize: TabBarIndicatorSize.label,
    ),
  );
}
