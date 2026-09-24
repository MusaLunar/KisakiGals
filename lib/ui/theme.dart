/// KisakiGals 主题：樱花粉 × 藤紫 × 奶油白。
///
/// 风格合成：
/// - **简约**（参考 ReinaManager）：大圆角（卡片 20 / 对话框 24）、药丸按钮、
///   近明度两级底色（浅灰底 + 纯白卡）、1px 中性描边、去渐变、次要信息弱化。
/// - **精致**（参考 ChronoTide）：极细低对比描边、常态硬阴影 → hover 柔光、
///   微上浮与微缩放、按压回弹（见 ui/design.dart）。
library;

import 'package:flutter/material.dart';

import 'design.dart';

class KisakiColors {
  // 主色：樱花粉
  static const pink = Color(0xFFE8629A);
  static const pinkSoft = Color(0xFFF7B6D0);
  static const pinkContainer = Color(0xFFFFE4EF);
  static const onPinkContainer = Color(0xFF5C2440);

  // 辅色：藤紫
  static const lavender = Color(0xFF9583D6);
  static const lavenderSoft = Color(0xFFD5CBF2);
  static const lavenderContainer = Color(0xFFEAE5FB);
  static const onLavenderContainer = Color(0xFF372A5E);

  // 语义色（参考 ReinaManager：语义色只用于语义，不参与装饰）
  static const success = Color(0xFF2E7D5B);
  static const warning = Color(0xFFB8791F);
  static const danger = Color(0xFFC4344A);
  static const info = Color(0xFF2A76C4);
  static const star = Color(0xFFD4A017);

  // 浅色底：近明度两级（底色略暖灰，卡片纯白）
  static const cream = Color(0xFFF7F4F2);
  static const creamCard = Colors.white;
  static const ink = Color(0xFF2E2730);
  static const inkSoft = Color(0xFF7A7078);

  // 深色底
  static const nightBg = Color(0xFF16131A);
  static const nightCard = Color(0xFF201C26);
  static const nightInk = Color(0xFFEDE7EC);
  static const nightInkSoft = Color(0xFFA79CA6);

  /// 外壳内容区底色（页面面板）：与 app_shell 使用同一 token，
  /// 视图固定的渐变遮罩末色必须用它才能无缝衔接。
  static Color pageSurface(bool dark) =>
      dark ? const Color(0xFF1B1721) : const Color(0xFFFCFBFA);

  // 描边（低对比、极细）
  static Color outline(bool dark) => dark
      ? Colors.white.withValues(alpha: 0.09)
      : const Color(0xFF7A7078).withValues(alpha: 0.16);
}

ThemeData buildLightTheme() => _theme(Brightness.light);
ThemeData buildDarkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: KisakiColors.pink,
    brightness: brightness,
  ).copyWith(
    primary: dark ? KisakiColors.pinkSoft : KisakiColors.pink,
    secondary: dark ? KisakiColors.lavenderSoft : KisakiColors.lavender,
    surface: dark ? KisakiColors.nightBg : KisakiColors.cream,
    surfaceContainerLowest: dark ? const Color(0xFF120F16) : Colors.white,
    surfaceContainerLow: dark ? KisakiColors.nightCard : Colors.white,
    surfaceContainer: dark ? const Color(0xFF272130) : const Color(0xFFFDFBFA),
    surfaceContainerHigh: dark ? const Color(0xFF2F2839) : const Color(0xFFF3EEF1),
    surfaceContainerHighest: dark ? const Color(0xFF383043) : const Color(0xFFEBE4E8),
    onSurface: dark ? KisakiColors.nightInk : KisakiColors.ink,
    onSurfaceVariant: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
    primaryContainer: dark ? const Color(0xFF43273A) : KisakiColors.pinkContainer,
    onPrimaryContainer:
        dark ? const Color(0xFFFFD9E8) : KisakiColors.onPinkContainer,
    secondaryContainer:
        dark ? const Color(0xFF322B4D) : KisakiColors.lavenderContainer,
    onSecondaryContainer:
        dark ? const Color(0xFFE0D8FF) : KisakiColors.onLavenderContainer,
    outline: KisakiColors.outline(dark),
    outlineVariant: KisakiColors.outline(dark).withValues(alpha: dark ? 0.06 : 0.10),
    error: KisakiColors.danger,
  );

  final cardColor = dark ? KisakiColors.nightCard : Colors.white;
  final outline = KisakiColors.outline(dark);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: dark ? KisakiColors.nightBg : KisakiColors.cream,
    // 字体：拉丁/数字用 Segoe UI（Windows 原生、字形清晰），
    // 中文自动回退微软雅黑（Type.fontFallback）
    fontFamily: Type.fontFamily,
    fontFamilyFallback: Type.fontFallback,
    // 统一文字阶梯：中文行高比 Material 默认更大，且不使用负字距
    textTheme: _textTheme(scheme.onSurface, scheme.onSurfaceVariant),
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    // 药丸按钮（参考 ReinaManager 的 999 圆角）
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        elevation: 0,
        textStyle: Type.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        side: BorderSide(color: outline),
        textStyle: Type.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: Type.label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outline),
      ),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF272130) : const Color(0xFFF6F1F4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: Radii.chip),
      side: BorderSide(color: outline),
      showCheckmark: false,
      labelStyle: Type.caption,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: outline),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: outline),
      ),
      textStyle: Type.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3A3342) : const Color(0xFF3A333C),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: Colors.white),
      waitDuration: const Duration(milliseconds: 500),
    ),
    dividerTheme: DividerThemeData(
      color: outline,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? scheme.primary
          : (dark ? Colors.white70 : Colors.white)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? scheme.primary.withValues(alpha: 0.45)
          : (dark ? Colors.white24 : const Color(0xFFD3C8CE))),
      trackOutlineColor:
          WidgetStateProperty.resolveWith((_) => Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 6,
      linearTrackColor: outline,
      borderRadius: BorderRadius.circular(999),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(999),
      thumbColor: WidgetStateProperty.all(
          dark ? Colors.white24 : Colors.black.withValues(alpha: 0.18)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconColor: scheme.onSurfaceVariant,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      selectedIconTheme:
          IconThemeData(color: dark ? KisakiColors.pinkSoft : KisakiColors.pink),
      unselectedIconTheme: IconThemeData(
          color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor:
          dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: Type.label,
      unselectedLabelStyle: Type.label,
    ),
  );
}

/// 统一文字阶梯：把 design.dart 的 Type token 映射到 Material 的 TextTheme，
/// 使未显式指定样式的组件（按钮、列表、对话框等）也使用同一套中文排印参数。
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
