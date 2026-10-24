/// KisakiGals 主题：Endfield 式场工程中性色 × 单一信号黄。
///
/// 视觉约束：中性色占绝大多数，黄色只负责当前选择/主动作，绿色只表达
/// 在线或游玩中状态；圆角与阴影克制，让封面和标题承担视觉重量。
library;

import 'package:flutter/material.dart';

import 'design.dart';

class KisakiColors {
  // Endfield 信号色：只用于选中、主动作与进度。
  static const signal = Color(0xFFFFFA00);
  static const signalSoft = Color(0xFFFFF76A);
  static const signalContainer = Color(0xFFFFFBC2);
  static const onSignalContainer = Color(0xFF3A3700);

  // 旧命名保留为语义别名，避免业务组件逐个改动造成行为风险。
  static const pink = signal;
  static const pinkSoft = signalSoft;
  static const pinkContainer = signalContainer;
  static const onPinkContainer = onSignalContainer;
  static const lavender = Color(0xFF1E9B83);
  static const lavenderSoft = Color(0xFF62D6BD);
  static const lavenderContainer = Color(0xFFD9F5EE);
  static const onLavenderContainer = Color(0xFF073D32);

  // 语义色（参考 ReinaManager：语义色只用于语义，不参与装饰）
  static const success = Color(0xFF00A878);
  static const warning = Color(0xFFB7791F);
  static const danger = Color(0xFFC43D3D);
  static const info = Color(0xFF2C76A8);
  static const star = Color(0xFFB58B00);

  // 浅色底：近明度两级（底色略暖灰，卡片纯白）
  static const cream = Color(0xFFF2F2F0);
  static const creamCard = Color(0xFFFAFAF8);
  static const ink = Color(0xFF191919);
  static const inkSoft = Color(0xFF626262);

  // 深色底
  static const nightBg = Color(0xFF111313);
  static const nightCard = Color(0xFF1C1E1D);
  static const nightInk = Color(0xFFF1F1EC);
  static const nightInkSoft = Color(0xFFB4B5AE);

  /// 外壳内容区底色（页面面板）：与 app_shell 使用同一 token，
  /// 视图固定的渐变遮罩末色必须用它才能无缝衔接。
  static Color pageSurface(bool dark) =>
      dark ? const Color(0xFF171918) : const Color(0xFFF7F7F4);

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
    seedColor: KisakiColors.signal,
    brightness: brightness,
  ).copyWith(
    primary: dark ? KisakiColors.signal : KisakiColors.signal,
    onPrimary: KisakiColors.ink,
    secondary: dark ? KisakiColors.lavenderSoft : KisakiColors.lavender,
    onSecondary: KisakiColors.ink,
    surface: dark ? KisakiColors.nightBg : KisakiColors.cream,
    surfaceContainerLowest: dark ? const Color(0xFF0D0F0E) : KisakiColors.creamCard,
    surfaceContainerLow: dark ? KisakiColors.nightCard : Colors.white,
    surfaceContainer: dark ? const Color(0xFF252826) : const Color(0xFFF7F7F4),
    surfaceContainerHigh: dark ? const Color(0xFF2D302E) : const Color(0xFFE9E9E5),
    surfaceContainerHighest: dark ? const Color(0xFF383B38) : const Color(0xFFD9DAD5),
    onSurface: dark ? KisakiColors.nightInk : KisakiColors.ink,
    onSurfaceVariant: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
    primaryContainer: dark ? const Color(0xFF474600) : KisakiColors.signalContainer,
    onPrimaryContainer:
        dark ? const Color(0xFFFFFCA8) : KisakiColors.onSignalContainer,
    secondaryContainer:
        dark ? const Color(0xFF15352E) : KisakiColors.lavenderContainer,
    onSecondaryContainer:
        dark ? const Color(0xFFB6F7E8) : KisakiColors.onLavenderContainer,
    outline: KisakiColors.outline(dark),
    outlineVariant: KisakiColors.outline(dark).withValues(alpha: dark ? 0.12 : 0.18),
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
    // 主动作是矩形信号块：在桌面端更像“启动/确认”而非标签。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        elevation: 0,
        textStyle: Type.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        // 描边与文字都加深：outlined 按钮常出现在毛玻璃卡/背景图之上，
        // 过淡会看不清（视觉评审实测「评分 / 评价」对比度仅约 2:1）
        side: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.16)),
        foregroundColor: scheme.onSurface,
        textStyle: Type.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: Type.label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: outline),
      ),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF252826) : const Color(0xFFE9E9E5),
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
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: outline),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
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
