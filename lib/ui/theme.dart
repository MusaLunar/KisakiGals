/// KisakiGals 主题规范：誌面 (Shimen) 铜版纸象牙白 × 凹版暗墨 × 印刷四色 (CMYK Four-Ink System).
///
/// 色彩职能分配（一色一义，严格遵循 WCAG AA ≥ 4.5:1 对比度）：
/// - 纸张与底版 (Paper & Ground)：
///   - 浅色铜版纸：暖象牙白 (#FAF7F2) 底页、纯白 (#FFFFFF) 图版、米灰 (#F2ECE4) 书脊与容器
///   - 深色凹版墨：深石墨 (#0F1015) 底槽、暗页 (#13151C) 主版、暗炭 (#161820) 图版
/// - 专色洋红 (Process Magenta — M)：#E4005A (Light) / #FF2E7E (Dark)，专用于主启动按钮、选中态与书脊激活标尺
/// - 专色青蓝 (Process Cyan — C)：#0088B8 (Light) / #29B6E8 (Dark)，专用于游玩时长、实时计时与时间序列图表
/// - 专色铭黄 (Process Yellow-Gold — Y)：#D49400 (Light) / #FFC42E (Dark)，专用于评分星级与荣誉徽标
/// - 定位黑墨 (Registration K)：#16151A (Light) / #F4F1EA (Dark)，用于正文排版与 1px 裁切细线
library;

import 'package:flutter/material.dart';

import 'design.dart';

class KisakiColors {
  // 专色洋红 (Process Magenta — M)：主交互、启动按钮与书脊激活色
  static const magenta = Color(0xFFE4005A);
  static const magentaDark = Color(0xFFFF2E7E);
  static const magentaSoft = Color(0xFFFF669E);
  static const magentaContainerLight = Color(0xFFFFE0EC);
  static const magentaContainerDark = Color(0xFF4D0824);
  static const onMagentaContainerLight = Color(0xFF3D0017);
  static const onMagentaContainerDark = Color(0xFFFFD9E6);

  // 向后兼容别名 (Rose / Pink / Signal -> Process Magenta)
  static const primaryRose = magenta;
  static const primaryRoseDark = magentaDark;
  static const primaryRoseSoft = magentaSoft;
  static const primaryRoseContainerLight = magentaContainerLight;
  static const primaryRoseContainerDark = magentaContainerDark;
  static const onPrimaryRoseContainerLight = onMagentaContainerLight;
  static const onPrimaryRoseContainerDark = onMagentaContainerDark;

  static const signal = magenta;
  static const signalSoft = magentaSoft;
  static const signalContainer = magentaContainerLight;
  static const onSignalContainer = onMagentaContainerLight;

  static const pink = magenta;
  static const pinkSoft = magentaSoft;
  static const pinkContainer = magentaContainerLight;
  static const onPinkContainer = onMagentaContainerLight;

  // 专色青蓝 (Process Cyan — C)：游玩时长、实时计时与时间趋势图表
  static const cyan = Color(0xFF0088B8);
  static const cyanSoft = Color(0xFF29B6E8);
  static const cyanContainer = Color(0xFFE0F4FA);
  static const cyanContainerDark = Color(0xFF0A3242);
  static const onCyanContainer = Color(0xFF002B3D);
  static const onCyanContainerDark = Color(0xFFC7EEFF);

  // 向后兼容别名 (Lavender -> Process Cyan 时间数据专色)
  static const lavender = cyan;
  static const lavenderSoft = cyanSoft;
  static const lavenderContainer = cyanContainer;
  static const onLavenderContainer = onCyanContainer;

  // 专色铭黄 (Process Yellow-Gold — Y) 与状态反馈色
  static const yellowInk = Color(0xFFD49400);
  static const star = Color(0xFFFFC42E);
  static const success = Color(0xFF0D9488);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFE11D48);
  static const info = cyan;

  /// 根据明暗模式返回具备高对比度的评分铭黄色
  static Color ratingInk(bool dark) => dark ? star : yellowInk;

  /// 根据明暗模式返回时间/时长专色青蓝
  static Color temporalInk(bool dark) => dark ? cyanSoft : cyan;

  // 浅色底：铜版纸象牙白阶 (Coated Warm Ivory Stock)
  static const cream = Color(0xFFFAF7F2);
  static const creamCard = Color(0xFFFFFFFF);
  static const paperContainer = Color(0xFFF2ECE4);
  static const ink = Color(0xFF16151A);
  static const inkSoft = Color(0xFF5E5B66);

  // 深色底：凹版暗墨阶 (Gravure Dark Stock)
  static const nightBg = Color(0xFF0F1015);
  static const nightCard = Color(0xFF161820);
  static const nightContainer = Color(0xFF1D202A);
  static const nightInk = Color(0xFFF4F1EA);
  static const nightInkSoft = Color(0xFF9E9BA6);

  /// 书脊导览槽底色 (Fore-Edge Spine Rail Ground)
  static Color spineSurface(bool dark) =>
      dark ? const Color(0xFF0B0C10) : const Color(0xFFF0EAE1);

  /// 主版面纸页底色 (Active Spread Sheet Ground)
  static Color pageSurface(bool dark) =>
      dark ? const Color(0xFF13151C) : const Color(0xFFFAF7F2);

  /// 1px 印刷定位裁切线
  static Color outline(bool dark) => dark
      ? Colors.white.withValues(alpha: 0.09)
      : const Color(0xFF16151A).withValues(alpha: 0.09);
}

ThemeData buildLightTheme() => _theme(Brightness.light);
ThemeData buildDarkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? KisakiColors.magentaDark : KisakiColors.magenta;
  final onPrimary = dark ? const Color(0xFF1F000C) : Colors.white;
  final secondary = dark ? KisakiColors.cyanSoft : KisakiColors.cyan;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: dark
        ? KisakiColors.magentaContainerDark
        : KisakiColors.magentaContainerLight,
    onPrimaryContainer: dark
        ? KisakiColors.onMagentaContainerDark
        : KisakiColors.onMagentaContainerLight,
    secondary: secondary,
    onSecondary: dark ? const Color(0xFF001F2B) : Colors.white,
    secondaryContainer:
        dark ? KisakiColors.cyanContainerDark : KisakiColors.cyanContainer,
    onSecondaryContainer:
        dark ? KisakiColors.onCyanContainerDark : KisakiColors.onCyanContainer,
    surface: dark ? KisakiColors.nightBg : KisakiColors.cream,
    onSurface: dark ? KisakiColors.nightInk : KisakiColors.ink,
    onSurfaceVariant: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
    surfaceContainerLowest:
        dark ? const Color(0xFF0B0C10) : KisakiColors.creamCard,
    surfaceContainerLow: dark ? KisakiColors.nightCard : Colors.white,
    surfaceContainer:
        dark ? KisakiColors.nightContainer : KisakiColors.paperContainer,
    surfaceContainerHigh:
        dark ? const Color(0xFF242834) : const Color(0xFFE8E0D5),
    surfaceContainerHighest:
        dark ? const Color(0xFF2E3342) : const Color(0xFFDDD3C5),
    outline: KisakiColors.outline(dark),
    outlineVariant:
        KisakiColors.outline(dark).withValues(alpha: dark ? 0.16 : 0.20),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        elevation: 0,
        textStyle: Type.label,
        backgroundColor: primary,
        foregroundColor: onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.20)
              : const Color(0xFF16151A).withValues(alpha: 0.16),
          width: 1,
        ),
        foregroundColor: scheme.onSurface,
        textStyle: Type.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        textStyle: Type.label,
        foregroundColor: primary,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: outline, width: 1),
      ),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor:
          dark ? KisakiColors.nightContainer : KisakiColors.paperContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: outline, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: outline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: Radii.chip),
      side: BorderSide(color: outline, width: 1),
      showCheckmark: false,
      labelStyle: Type.caption,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.sheet,
        side: BorderSide(color: outline, width: 1),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: outline, width: 1),
      ),
      textStyle: Type.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md)),
      elevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF242834) : const Color(0xFF1E1D24),
        borderRadius: BorderRadius.circular(Radii.sm),
        boxShadow: Elev.overlay(dark),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: Colors.white),
      waitDuration: const Duration(milliseconds: 380),
    ),
    dividerTheme: DividerThemeData(
      color: outline,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? Colors.white70 : Colors.white)),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? primary
              : (dark ? Colors.white24 : const Color(0xFFD5CEC4))),
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
        dark
            ? Colors.white.withValues(alpha: 0.20)
            : const Color(0xFF16151A).withValues(alpha: 0.16),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md)),
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
