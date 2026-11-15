/// KisakiGals 主题规范：Material Design 3 (M3 Expressive Tonal System).
///
/// 核心三原色与表面层级（围绕 `#DA839C` 柔瑰粉、`#D0C0F5` 熏衣紫、`#EDABA0` 暖桃珊瑚构建）：
/// - **Primary (`m3Rose`)**: `#DA839C`（主按钮、激活态胶囊、焦点轮廓与主品牌标识）
/// - **Secondary (`m3Lavender`)**: `#D0C0F5`（实时游玩、统计趋势与次级 tonal 容器）
/// - **Tertiary (`m3Peach`)**: `#EDABA0`（暖调高光、徽章点缀与渐变融合）
/// - **Navigation / Shell (`spineSurface`)**: Light `#F6F1F5` / Dark `#151215`
/// - **Page Surface (`pageSurface`)**: Light `#FFFBFD` / Dark `#1B171B`
/// - **Card Surface (`elevatedSurface`)**: Light `#FFFFFF` / Dark `#241F24`
library;

import 'package:flutter/material.dart';

import 'design.dart';

class KisakiColors {
  // Material Design 3 三原色主色板
  static const m3Rose = Color(0xFFDA839C);
  static const m3Lavender = Color(0xFFD0C0F5);
  static const m3Peach = Color(0xFFEDABA0);

  static const m3RoseDeep = Color(0xFF9C3E5C);
  static const m3LavenderDeep = Color(0xFF6B53B8);
  static const m3PeachDeep = Color(0xFF9E5142);

  // Primary Brand Accent (M3 Rose Ramp)
  static const magenta = m3Rose;
  static const magentaDark = m3Rose;
  static const magentaContainerLight = Color(0xFFFCE8EE);
  static const magentaContainerDark = Color(0xFF4A2532);
  static const onMagentaContainerLight = Color(0xFF3E0F20);
  static const onMagentaContainerDark = Color(0xFFFFD9E3);

  static const pink = m3Rose;
  static const pinkSoft = m3Peach;
  static const pinkContainer = magentaContainerLight;
  static const onPinkContainer = onMagentaContainerLight;

  // Secondary Accent (M3 Lavender Ramp)
  static const cyan = m3LavenderDeep;
  static const cyanContainer = Color(0xFFEDE6FD);
  static const cyanContainerDark = Color(0xFF382E58);
  static const onCyanContainer = Color(0xFF28194E);
  static const onCyanContainerDark = Color(0xFFEBE3FD);

  // Tertiary Accent (M3 Peach Ramp)
  static const peachContainer = Color(0xFFFDECE9);
  static const peachContainerDark = Color(0xFF522D28);
  static const onPeachContainer = Color(0xFF461B15);
  static const onPeachContainerDark = Color(0xFFFFE5E0);

  static const lavender = m3Lavender;
  static const lavenderSoft = m3Lavender;
  static const onLavenderContainer = onCyanContainer;

  // Caution / Rating & Semantic Status Ramps
  static const star = Color(0xFFE99F67);

  static const success = Color(0xFF2A7B56);
  static const successDark = Color(0xFF7AD6A8);
  static const warning = Color(0xFFA85B37);
  static const danger = Color(0xFFC93B4B);
  static const info = m3LavenderDeep;

  /// 根据明暗模式返回具备高对比度的玫粉文本强调色
  static Color roseInk(bool dark) => dark ? m3Rose : m3RoseDeep;

  /// 根据明暗模式返回具备高对比度的评分/暖桃强调色
  static Color ratingInk(bool dark) => dark ? m3Peach : m3PeachDeep;

  /// 根据明暗模式返回熏衣紫强调色
  static Color temporalInk(bool dark) => dark ? m3Lavender : m3LavenderDeep;

  /// 根据明暗模式返回语义成功色
  static Color successInk(bool dark) => dark ? successDark : success;

  // 浅色材质层级 (M3 Light Tonal Surfaces)
  static const paperSunken = Color(0xFFF6F1F5); // Navigation Shell / surfaceContainerLow
  static const paper = Color(0xFFFFFBFD); // Main Surface
  static const paperElevated = Color(0xFFFFFFFF); // Card Surface
  static const cream = paper;
  static const creamCard = paperElevated;
  static const paperContainer = Color(0xFFF0E9EE); // surfaceContainerHigh
  static const ink = Color(0xFF1F1A1D); // onSurface
  static const inkMedium = Color(0xFF554A50); // onSurfaceVariant
  static const inkSoft = Color(0xFF7B6F76);

  // 深色材质层级 (M3 Dark Tonal Surfaces)
  static const nightBg = Color(0xFF151215); // Navigation Shell
  static const nightCard = Color(0xFF241F24); // surfaceContainer
  static const nightContainer = Color(0xFF2E282E); // surfaceContainerHigh
  static const nightElevated = Color(0xFF362F36); // surfaceContainerHighest
  static const nightInk = Color(0xFFF5EDF2); // onSurface
  static const nightInkMedium = Color(0xFFCBBFC6); // onSurfaceVariant
  static const nightInkSoft = Color(0xFF988B93);

  /// 外壳底色（标题栏与左侧 NavigationDrawer 导航槽）
  static Color spineSurface(bool dark) => dark ? nightBg : paperSunken;

  /// 主版面底色（大圆角内容区）
  static Color pageSurface(bool dark) => dark ? const Color(0xFF1B171B) : paper;

  /// M3 卡片表面底色
  static Color elevatedSurface(bool dark) => dark ? nightCard : paperElevated;

  /// M3 Tonal 1px 描边
  static Color outline(bool dark) =>
      dark ? const Color(0x1AFFFFFF) : const Color(0x142A1B23);
}

ThemeData buildLightTheme() => _theme(Brightness.light);
ThemeData buildDarkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const primary = KisakiColors.m3Rose;
  const onPrimary = Color(0xFF3A0E1E);
  const secondary = KisakiColors.m3Lavender;
  const onSecondary = Color(0xFF27184B);
  const tertiary = KisakiColors.m3Peach;
  const onTertiary = Color(0xFF421A14);

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
    onSecondary: onSecondary,
    secondaryContainer:
        dark ? KisakiColors.cyanContainerDark : KisakiColors.cyanContainer,
    onSecondaryContainer:
        dark ? KisakiColors.onCyanContainerDark : KisakiColors.onCyanContainer,
    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer:
        dark ? KisakiColors.peachContainerDark : KisakiColors.peachContainer,
    onTertiaryContainer:
        dark ? KisakiColors.onPeachContainerDark : KisakiColors.onPeachContainer,
    surface: KisakiColors.pageSurface(dark),
    onSurface: dark ? KisakiColors.nightInk : KisakiColors.ink,
    onSurfaceVariant:
        dark ? KisakiColors.nightInkMedium : KisakiColors.inkMedium,
    surfaceContainerLowest:
        dark ? KisakiColors.nightBg : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        dark ? const Color(0xFF1D191D) : KisakiColors.paperSunken,
    surfaceContainer:
        dark ? KisakiColors.nightCard : const Color(0xFFFDF8FB),
    surfaceContainerHigh:
        dark ? KisakiColors.nightContainer : KisakiColors.paperContainer,
    surfaceContainerHighest:
        dark ? KisakiColors.nightElevated : const Color(0xFFE7DDE4),
    outline: KisakiColors.outline(dark),
    outlineVariant:
        dark ? const Color(0x22FFFFFF) : const Color(0x1C2A1B23),
    error: KisakiColors.danger,
    onError: Colors.white,
  );

  final cardColor = dark ? KisakiColors.nightCard : KisakiColors.paperElevated;
  final outline = KisakiColors.outline(dark);
  final ctrlBorder = Elev.controlBorder(dark);
  final textAccent = KisakiColors.roseInk(dark);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: KisakiColors.spineSurface(dark),
    fontFamily: Type.fontFamily,
    fontFamilyFallback: Type.fontFallback,
    textTheme: _textTheme(scheme.onSurface, scheme.onSurfaceVariant),
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        elevation: 0,
        textStyle: Type.label,
        backgroundColor: primary,
        foregroundColor: onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        backgroundColor: dark ? KisakiColors.nightContainer : Colors.white,
        side: BorderSide(color: ctrlBorder, width: 1),
        foregroundColor: scheme.onSurface,
        textStyle: Type.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: Type.label,
        foregroundColor: textAccent,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        shape: const StadiumBorder(),
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
      fillColor: dark ? KisakiColors.nightContainer : const Color(0xFFFAF5F8),
      hoverColor:
          dark ? KisakiColors.nightElevated : const Color(0xFFF5EEF3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: ctrlBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: ctrlBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: primary, width: 1.8),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: ctrlBorder, width: 1),
      showCheckmark: false,
      labelStyle: Type.caption,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xxl),
        side: BorderSide(color: outline, width: 1),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 10,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? KisakiColors.nightElevated : KisakiColors.paperElevated,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: outline, width: 1),
      ),
      textStyle: Type.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      elevation: 4,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? KisakiColors.nightElevated : KisakiColors.paperElevated,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: outline, width: 1),
        boxShadow: Elev.overlay(dark),
      ),
      textStyle: TextStyle(
        fontSize: 12,
        color: dark ? KisakiColors.nightInk : KisakiColors.ink,
      ),
      waitDuration: const Duration(milliseconds: 420),
    ),
    dividerTheme: DividerThemeData(
      color: outline,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? onPrimary
              : (dark ? const Color(0xFFCBBFC6) : const Color(0xFF6B5F66))),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? primary
              : (dark ? const Color(0xFF2B242B) : const Color(0xFFF0E9EE))),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Colors.transparent
              : (dark ? const Color(0xFF7B6F76) : const Color(0xFF9C8F96))),
      trackOutlineWidth: WidgetStateProperty.all(1.3),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 5,
      linearTrackColor: outline,
      borderRadius: BorderRadius.circular(999),
      color: primary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(5),
      radius: const Radius.circular(999),
      thumbColor: WidgetStateProperty.all(
        dark
            ? secondary.withValues(alpha: 0.24)
            : primary.withValues(alpha: 0.28),
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
      selectedIconTheme: const IconThemeData(color: primary),
      unselectedIconTheme: IconThemeData(
          color: dark ? KisakiColors.nightInkMedium : KisakiColors.inkMedium),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: textAccent,
      unselectedLabelColor:
          dark ? KisakiColors.nightInkMedium : KisakiColors.inkMedium,
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
