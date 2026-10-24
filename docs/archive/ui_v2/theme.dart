/// KisakiGals 主题规范：曜石金黑 (Luminous Frosted Obsidian) × 山茶花粉 (Camellia Rose).
///
/// 视觉与工艺准则 (Impeccable & Designable):
/// - 纯净克制的高阶视觉小说审美，消除假工程粗线条与刺眼荧光黄；
/// - 浅色为冷瓷白 (Cool Porcelain) + 柔和漫反射；深色为深曜石 (Frosted Obsidian) + 镜面光晕；
/// - 强调色为和风山茶花粉与绯红 (Camellia Rose)，温润、优雅且具备 ≥ 4.5:1 严格对比度；
/// - 遵循全平台光学排印与连续曲率平滑圆角。
library;

import 'package:flutter/material.dart';

import 'design.dart';

class KisakiColors {
  // 品牌核心强调色：优雅的山茶花粉 (Camellia Rose)
  static const primaryRose = Color(0xFFE85583);
  static const primaryRoseDark = Color(0xFFFF6997);
  static const primaryRoseSoft = Color(0xFFFF85AA);
  static const primaryRoseContainerLight = Color(0xFFFFD9E2);
  static const primaryRoseContainerDark = Color(0xFF561129);
  static const onPrimaryRoseContainerLight = Color(0xFF3B071B);
  static const onPrimaryRoseContainerDark = Color(0xFFFFD9E2);

  // 语义别名（完全向后兼容业务代码）
  static const signal = primaryRose;
  static const signalSoft = primaryRoseSoft;
  static const signalContainer = primaryRoseContainerLight;
  static const onSignalContainer = onPrimaryRoseContainerLight;

  static const pink = primaryRose;
  static const pinkSoft = primaryRoseSoft;
  static const pinkContainer = primaryRoseContainerLight;
  static const onPinkContainer = onPrimaryRoseContainerLight;

  // 次要强调色：紫藤/鸢尾紫 (Iris Lavender)
  static const lavender = Color(0xFF755BB4);
  static const lavenderSoft = Color(0xFF9E86E3);
  static const lavenderContainer = Color(0xFFECE6F8);
  static const onLavenderContainer = Color(0xFF281850);

  // 语义反馈色
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);
  static const star = Color(0xFFFBBF24);

  // 浅色底：冷瓷粉灰阶
  static const cream = Color(0xFFF8F7F9);
  static const creamCard = Color(0xFFFFFFFF);
  static const ink = Color(0xFF181920);
  static const inkSoft = Color(0xFF656776);

  // 深色底：曜石暗墨阶
  static const nightBg = Color(0xFF0D0F14);
  static const nightCard = Color(0xFF151821);
  static const nightInk = Color(0xFFF2F3F7);
  static const nightInkSoft = Color(0xFFA2A5B8);

  /// 页面内容区底色
  static Color pageSurface(bool dark) =>
      dark ? const Color(0xFF11141B) : const Color(0xFFFAF9FB);

  /// 0.5px 极细镜面描边
  static Color outline(bool dark) => dark
      ? Colors.white.withValues(alpha: 0.09)
      : Colors.black.withValues(alpha: 0.08);
}

ThemeData buildLightTheme() => _theme(Brightness.light);
ThemeData buildDarkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? KisakiColors.primaryRoseDark : KisakiColors.primaryRose;
  final onPrimary = dark ? const Color(0xFF20030E) : Colors.white;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: dark
        ? KisakiColors.primaryRoseContainerDark
        : KisakiColors.primaryRoseContainerLight,
    onPrimaryContainer: dark
        ? KisakiColors.onPrimaryRoseContainerDark
        : KisakiColors.onPrimaryRoseContainerLight,
    secondary: dark ? KisakiColors.lavenderSoft : KisakiColors.lavender,
    onSecondary: dark ? const Color(0xFF1B0B3B) : Colors.white,
    secondaryContainer: dark
        ? const Color(0xFF2E1C4D)
        : KisakiColors.lavenderContainer,
    onSecondaryContainer: dark
        ? const Color(0xFFE9DCFF)
        : KisakiColors.onLavenderContainer,
    surface: dark ? KisakiColors.nightBg : KisakiColors.cream,
    onSurface: dark ? KisakiColors.nightInk : KisakiColors.ink,
    onSurfaceVariant: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
    surfaceContainerLowest:
        dark ? const Color(0xFF08090D) : KisakiColors.creamCard,
    surfaceContainerLow: dark ? KisakiColors.nightCard : Colors.white,
    surfaceContainer:
        dark ? const Color(0xFF181C26) : const Color(0xFFF2EFF4),
    surfaceContainerHigh:
        dark ? const Color(0xFF202533) : const Color(0xFFE9E5EC),
    surfaceContainerHighest:
        dark ? const Color(0xFF282F40) : const Color(0xFFDED9E2),
    outline: KisakiColors.outline(dark),
    outlineVariant: KisakiColors.outline(dark).withValues(alpha: dark ? 0.16 : 0.22),
    error: KisakiColors.danger,
    onError: Colors.white,
  );

  final cardColor = dark ? KisakiColors.nightCard : Colors.white;
  final outline = KisakiColors.outline(dark);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: dark ? KisakiColors.nightBg : KisakiColors.cream,
    fontFamily: Type.fontFamily,
    fontFamilyFallback: Type.fontFallback,
    textTheme: _textTheme(scheme.onSurface, scheme.onSurfaceVariant),
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        elevation: 0,
        textStyle: Type.label,
        backgroundColor: primary,
        foregroundColor: onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.black.withValues(alpha: 0.15),
          width: 1,
        ),
        foregroundColor: scheme.onSurface,
        textStyle: Type.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        textStyle: Type.label,
        foregroundColor: primary,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: outline, width: 0.5),
      ),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF181C26) : const Color(0xFFF2EFF4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: outline, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: outline, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: Radii.chip),
      side: BorderSide(color: outline, width: 0.5),
      showCheckmark: false,
      labelStyle: Type.caption,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.sheet,
        side: BorderSide(color: outline, width: 0.5),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: outline, width: 0.5),
      ),
      textStyle: Type.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      elevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF262C3A) : const Color(0xFF2E2B33),
        borderRadius: BorderRadius.circular(Radii.sm),
        boxShadow: Elev.overlay(dark),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: Colors.white),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dividerTheme: DividerThemeData(
      color: outline,
      thickness: 0.5,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? Colors.white
          : (dark ? Colors.white70 : Colors.white)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? primary
          : (dark ? Colors.white24 : const Color(0xFFD6D0D8))),
      trackOutlineColor:
          WidgetStateProperty.resolveWith((_) => Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 5,
      linearTrackColor: outline,
      borderRadius: BorderRadius.circular(999),
      color: primary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(999),
      thumbColor: WidgetStateProperty.all(
          dark ? Colors.white.withValues(alpha: 0.20) : Colors.black.withValues(alpha: 0.16)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      iconColor: scheme.onSurfaceVariant,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      selectedIconTheme: IconThemeData(color: primary),
      unselectedIconTheme: IconThemeData(
          color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor:
          dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: Type.label,
      unselectedLabelStyle: Type.label,
    ),
  );
}

TextTheme _textTheme(Color ink, Color inkSoft) {
  TextStyle t(TextStyle base, {Color? color, FontWeight? weight}) =>
      base.copyWith(color: color ?? ink, fontWeight: weight);

  return TextTheme(
    displayLarge: t(Type.display),
    displayMedium: t(Type.display),
    displaySmall: t(Type.title),
    headlineLarge: t(Type.title),
    headlineMedium: t(Type.title),
    headlineSmall: t(Type.title),
    titleLarge: t(Type.title),
    titleMedium: t(Type.label),
    titleSmall: t(Type.label),
    bodyLarge: t(Type.body),
    bodyMedium: t(Type.body),
    bodySmall: t(Type.caption, color: inkSoft),
    labelLarge: t(Type.label),
    labelMedium: t(Type.caption),
    labelSmall: t(Type.micro, color: inkSoft),
  );
}
