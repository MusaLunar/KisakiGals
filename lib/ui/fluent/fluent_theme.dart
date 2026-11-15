/// Fluent 2 主题映射：SystemTheme 强调色 + flutter_acrylic 窗口材质动态同步。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;

import '../../data/settings_store.dart';

const Color kDefaultWin11Azure = Color(0xFF0078D4);
const Color kSakuraAccent = Color(0xFFD85C84);
const Color kLavenderAccent = Color(0xFF7B61D6);

const List<String> _kFontFallback = [
  'NotoSansSC',
  'Microsoft YaHei UI',
  'Segoe UI',
];

Color resolveAccentBaseColor(AccentPreset preset, Color systemAccent) {
  return switch (preset) {
    AccentPreset.system =>
      systemAccent.a == 0 ? kDefaultWin11Azure : systemAccent,
    AccentPreset.sakura => kSakuraAccent,
    AccentPreset.lavender => kLavenderAccent,
    AccentPreset.azure => kDefaultWin11Azure,
  };
}

AccentColor buildFluentAccentSwatch(Color base) {
  final hsl = HSLColor.fromColor(base);
  Color shift(double deltaL, [double deltaS = 0]) {
    return hsl
        .withLightness((hsl.lightness + deltaL).clamp(0.12, 0.92))
        .withSaturation((hsl.saturation + deltaS).clamp(0.08, 1.0))
        .toColor();
  }

  return AccentColor.swatch({
    'darkest': shift(-0.24),
    'darker': shift(-0.16),
    'dark': shift(-0.08),
    'normal': base,
    'light': shift(0.10, -0.04),
    'lighter': shift(0.20, -0.06),
    'lightest': shift(0.30, -0.10),
  });
}

Typography _buildFluentTypography(
  Brightness brightness,
  ResourceDictionary resources,
  String? fontFamily,
) {
  final base = Typography.fromBrightness(
    brightness: brightness,
    color: resources.textFillColorPrimary,
  );
  TextStyle? patch(TextStyle? style) => style?.copyWith(
        fontFamily: fontFamily,
        fontFamilyFallback: _kFontFallback,
      );

  return Typography.raw(
    display: patch(base.display),
    titleLarge: patch(base.titleLarge),
    title: patch(base.title),
    subtitle: patch(base.subtitle),
    bodyLarge: patch(base.bodyLarge),
    bodyStrong: patch(base.bodyStrong),
    body: patch(base.body),
    caption: patch(base.caption),
  );
}

FluentThemeData buildFluentTheme({
  required Brightness brightness,
  required AccentPreset preset,
  required Color systemAccent,
  required BackdropEffectPref backdrop,
}) {
  final isDark = brightness == Brightness.dark;
  final baseAccent = resolveAccentBaseColor(preset, systemAccent);
  final accentSwatch = buildFluentAccentSwatch(baseAccent);
  final resources = isDark
      ? const ResourceDictionary.dark()
      : const ResourceDictionary.light();
  final fontFamily = Platform.isWindows ? 'Microsoft YaHei UI' : null;

  // Mica / Tabbed / Acrylic 需保留透明窗体底衬，仅 Solid 使用不透明中性底。
  final scaffoldBg = backdrop == BackdropEffectPref.solid
      ? (isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3))
      : Colors.transparent;

  return FluentThemeData(
    brightness: brightness,
    accentColor: accentSwatch,
    resources: resources,
    scaffoldBackgroundColor: scaffoldBg,
    micaBackgroundColor:
        isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
    cardColor: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFFBFBFB),
    fontFamily: fontFamily,
    typography: _buildFluentTypography(brightness, resources, fontFamily),
    visualDensity: VisualDensity.standard,
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor: Colors.transparent,
      overlayBackgroundColor:
          isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF9F9F9),
      highlightColor: accentSwatch.defaultBrushFor(brightness),
    ),
  );
}

/// 同步 Windows DWM Mica/Tabbed/Acrylic/Solid 窗体材质与明暗态。
Future<void> syncWindowBackdrop({
  required BackdropEffectPref effect,
  required bool dark,
}) async {
  if (!Platform.isWindows) return;
  try {
    final winEffect = switch (effect) {
      BackdropEffectPref.mica => acrylic.WindowEffect.mica,
      BackdropEffectPref.tabbed => acrylic.WindowEffect.tabbed,
      BackdropEffectPref.acrylic => acrylic.WindowEffect.acrylic,
      BackdropEffectPref.solid => acrylic.WindowEffect.solid,
    };
    final tintColor = switch (effect) {
      BackdropEffectPref.acrylic =>
        dark ? const Color(0xCC202020) : const Color(0xCCF3F3F3),
      BackdropEffectPref.solid =>
        dark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
      BackdropEffectPref.mica || BackdropEffectPref.tabbed => Colors.transparent,
    };
    await acrylic.Window.setEffect(
      effect: winEffect,
      color: tintColor,
      dark: dark,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('syncWindowBackdrop skipped: $e');
  }
}
