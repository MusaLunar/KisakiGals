/// Fluent 2 主题映射：SystemTheme 强调色 + flutter_acrylic 窗口材质动态同步。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import '../../data/settings_store.dart';

const Color kDefaultWin11Azure = Color(0xFF0078D4);
const Color kSakuraAccent = Color(0xFFD85C84);
const Color kLavenderAccent = Color(0xFF7B61D6);

const String kAppFontFamily = 'SourceHanSansCN';

const List<String> _kFontFallback = [
  'Microsoft YaHei UI',
  'Segoe UI',
  'Yu Gothic UI',
];

Color neutralWindowBackground(bool isDark) =>
    isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);

class WindowBackdropCaps {
  final int buildNumber;
  final bool dwmEnabled;
  final bool transparencyEnabled;
  final bool isRemoteSession;
  final bool highContrast;

  const WindowBackdropCaps({
    required this.buildNumber,
    required this.dwmEnabled,
    required this.transparencyEnabled,
    required this.isRemoteSession,
    required this.highContrast,
  });

  const WindowBackdropCaps.unsupported()
      : buildNumber = 0,
        dwmEnabled = false,
        transparencyEnabled = false,
        isRemoteSession = false,
        highContrast = false;

  const WindowBackdropCaps.win11Full()
      : buildNumber = 22621,
        dwmEnabled = true,
        transparencyEnabled = true,
        isRemoteSession = false,
        highContrast = false;

  factory WindowBackdropCaps.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const WindowBackdropCaps.unsupported();
    int readInt(String key) {
      final v = map[key];
      return v is num ? v.toInt() : 0;
    }

    bool readBool(String key, bool fallback) {
      final v = map[key];
      return v is bool ? v : fallback;
    }

    return WindowBackdropCaps(
      buildNumber: readInt('buildNumber'),
      dwmEnabled: readBool('dwmEnabled', false),
      transparencyEnabled: readBool('transparencyEnabled', true),
      isRemoteSession: readBool('isRemoteSession', false),
      highContrast: readBool('highContrast', false),
    );
  }
}

BackdropEffectPref resolveEffectiveBackdrop(
  BackdropEffectPref requested,
  WindowBackdropCaps caps,
) {
  if (requested == BackdropEffectPref.solid) {
    return BackdropEffectPref.solid;
  }
  if (!caps.dwmEnabled ||
      !caps.transparencyEnabled ||
      caps.isRemoteSession ||
      caps.highContrast) {
    return BackdropEffectPref.solid;
  }
  return switch (requested) {
    BackdropEffectPref.solid => BackdropEffectPref.solid,
    BackdropEffectPref.tabbed => caps.buildNumber >= 22621
        ? BackdropEffectPref.tabbed
        : (caps.buildNumber >= 22000
            ? BackdropEffectPref.mica
            : BackdropEffectPref.solid),
    BackdropEffectPref.mica => caps.buildNumber >= 22000
        ? BackdropEffectPref.mica
        : BackdropEffectPref.solid,
    BackdropEffectPref.acrylic => caps.buildNumber >= 17763
        ? BackdropEffectPref.acrylic
        : BackdropEffectPref.solid,
  };
}

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
  const fontFamily = kAppFontFamily;
  final neutralBg = neutralWindowBackground(isDark);

  // Mica / Tabbed / Acrylic 需保留透明窗体底衬，仅 Solid 使用不透明中性底。
  final scaffoldBg =
      backdrop == BackdropEffectPref.solid ? neutralBg : Colors.transparent;

  return FluentThemeData(
    brightness: brightness,
    accentColor: accentSwatch,
    resources: resources,
    scaffoldBackgroundColor: scaffoldBg,
    micaBackgroundColor: neutralBg,
    cardColor: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFFBFBFB),
    fontFamily: fontFamily,
    typography: _buildFluentTypography(brightness, resources, fontFamily),
    visualDensity: VisualDensity.standard,
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor:
          backdrop == BackdropEffectPref.solid ? neutralBg : Colors.transparent,
      overlayBackgroundColor:
          isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF9F9F9),
      highlightColor: accentSwatch.defaultBrushFor(brightness),
    ),
  );
}

/// 同步 Windows DWM Mica/Tabbed/Acrylic/Solid 窗体材质与明暗态；不支持时安全回退 Solid。
Future<bool> syncWindowBackdrop({
  required BackdropEffectPref effect,
  required bool dark,
  WindowBackdropCaps? caps,
}) async {
  if (!Platform.isWindows) return false;
  final effective =
      caps == null ? effect : resolveEffectiveBackdrop(effect, caps);
  final neutralBg = neutralWindowBackground(dark);
  try {
    try {
      await windowManager.setBackgroundColor(
        effective == BackdropEffectPref.solid ? neutralBg : Colors.transparent,
      );
    } catch (_) {}
    final winEffect = switch (effective) {
      BackdropEffectPref.mica => acrylic.WindowEffect.mica,
      BackdropEffectPref.tabbed => acrylic.WindowEffect.tabbed,
      BackdropEffectPref.acrylic => acrylic.WindowEffect.acrylic,
      BackdropEffectPref.solid => acrylic.WindowEffect.solid,
    };
    final tintColor = switch (effective) {
      BackdropEffectPref.acrylic =>
        dark ? const Color(0xCC202020) : const Color(0xCCF3F3F3),
      BackdropEffectPref.solid => neutralBg,
      BackdropEffectPref.mica ||
      BackdropEffectPref.tabbed =>
        Colors.transparent,
    };
    await acrylic.Window.setEffect(
      effect: winEffect,
      color: tintColor,
      dark: dark,
    );
    return effective == effect;
  } catch (e) {
    if (kDebugMode) debugPrint('syncWindowBackdrop skipped: $e');
    try {
      await windowManager.setBackgroundColor(neutralBg);
    } catch (_) {}
    return false;
  }
}

/// Fluent 2 语义化配色扩展，避免直接使用默认高饱和/纯黑白 `inactiveColor` 或硬编码十六进制色。
extension KisakiFluentTokens on FluentThemeData {
  bool get isDark => brightness == Brightness.dark;

  Color get textPrimary => resources.textFillColorPrimary;
  Color get textSecondary => resources.textFillColorSecondary;
  Color get textTertiary => resources.textFillColorTertiary;
  Color get textDisabled => resources.textFillColorDisabled;

  Color get accentInk => accentColor.defaultBrushFor(brightness);
  Color get onAccentInk => resources.textOnAccentFillColorPrimary;
  Color get accentTint => accentInk.withValues(alpha: isDark ? 0.18 : 0.12);

  Color get dangerInk =>
      isDark ? const Color(0xFFFF99A4) : const Color(0xFFC42B1C);
  Color get dangerFill =>
      isDark ? const Color(0xFFC42B1C) : const Color(0xFFD13438);
  Color get dangerTint => dangerInk.withValues(alpha: isDark ? 0.16 : 0.10);

  Color get successInk =>
      isDark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F);
  Color get warningInk =>
      isDark ? const Color(0xFFFCE100) : const Color(0xFF9D5D00);
  Color get favoriteInk =>
      isDark ? const Color(0xFFFF7AA2) : const Color(0xFFC4315B);

  Color get surfaceCard => resources.cardBackgroundFillColorDefault;
  Color get surfaceCardSecondary => resources.cardBackgroundFillColorSecondary;
  Color get surfaceStroke => resources.cardStrokeColorDefault;
  Color get dividerHairline => resources.dividerStrokeColorDefault;
  Color get subtleHover => resources.subtleFillColorSecondary;
  Color get subtlePressed => resources.subtleFillColorTertiary;
}
