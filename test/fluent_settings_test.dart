import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';
import 'package:kisakigals/ui/settings/settings_page.dart';

class _FakeThemeController extends StateNotifier<ThemeModePref>
    implements ThemeController {
  _FakeThemeController([super.initial = ThemeModePref.system]);

  @override
  Future<void> set(ThemeModePref pref) async {
    state = pref;
  }
}

class _FakeAccentPresetController extends StateNotifier<AccentPreset>
    implements AccentPresetController {
  _FakeAccentPresetController([super.initial = AccentPreset.system]);

  @override
  Future<void> set(AccentPreset preset) async {
    state = preset;
  }
}

class _FakeBackdropEffectController extends StateNotifier<BackdropEffectPref>
    implements BackdropEffectController {
  _FakeBackdropEffectController([super.initial = BackdropEffectPref.mica]);

  @override
  Future<void> set(BackdropEffectPref effect) async {
    state = effect;
  }
}

List<Override> _safeAppearanceOverrides() => [
      themeProvider.overrideWith((ref) => _FakeThemeController()),
      accentPresetProvider.overrideWith((ref) => _FakeAccentPresetController()),
      backdropEffectProvider
          .overrideWith((ref) => _FakeBackdropEffectController()),
      systemAccentColorProvider.overrideWith((ref) => kDefaultWin11Azure),
    ];

Widget _fluentHost({
  required Widget child,
  List<Override> overrides = const [],
  ProviderContainer? container,
}) {
  final theme = buildFluentTheme(
    brightness: Brightness.light,
    preset: AccentPreset.azure,
    systemAccent: kDefaultWin11Azure,
    backdrop: BackdropEffectPref.solid,
  );
  final app = FluentApp(
    theme: theme,
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: inner ?? const SizedBox.shrink(),
    ),
    home: child,
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return ProviderScope(overrides: overrides, child: app);
}

Future<void> _settle(WidgetTester tester, [int ms = 50]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> _selectComboItem(
  WidgetTester tester,
  Finder combo,
  String itemText,
) async {
  await tester.tap(combo);
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    NoticeCenter.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
      'SettingsPage renders 7 sections in bare ProviderScope and highlights AI section',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsSectionProvider.overrideWith((ref) => SettingsSections.ai),
        ],
        child: const FluentApp(home: SettingsPage()),
      ),
    );
    await _settle(tester, 450);

    expect(find.text('外观与显示'), findsWidgets);
    expect(find.text('游戏与启动'), findsWidgets);
    expect(find.text('游戏库与网络'), findsWidgets);
    expect(find.text('账号与云同步'), findsWidgets);
    expect(find.text('AI 服务设置'), findsWidgets);
    expect(find.text('存储与备份'), findsWidgets);
    expect(find.text('插件与关于'), findsWidgets);
    expect(
      find.byKey(const ValueKey('settings_section_active_${SettingsSections.ai}')),
      findsOneWidget,
    );
  });

  testWidgets(
      'section nav, narrow sticky pills, and appearance controls sync Riverpod providers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: _safeAppearanceOverrides(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _fluentHost(container: container, child: const SettingsPage()),
    );
    await tester.pump();

    expect(container.read(settingsSectionProvider), 0);

    // Change ThemeModePref via ComboBox
    await _selectComboItem(
      tester,
      find.byKey(const ValueKey('settings_theme_combo')),
      '深色模式',
    );
    expect(container.read(themeProvider), ThemeModePref.dark);

    // Select Sakura accent preset swatch card
    await tester.tap(find.byKey(const ValueKey('settings_accent_sakura')));
    await tester.pump();
    expect(container.read(accentPresetProvider), AccentPreset.sakura);

    // Change BackdropEffectPref via ComboBox
    await _selectComboItem(
      tester,
      find.byKey(const ValueKey('settings_backdrop_combo')),
      'Acrylic 亚克力',
    );
    expect(container.read(backdropEffectProvider), BackdropEffectPref.acrylic);

    // Wide nav rail clicks sync settingsSectionProvider
    await tester.tap(find.byKey(const ValueKey('settings_nav_4')));
    await tester.pump();
    expect(container.read(settingsSectionProvider), 4);

    await tester.tap(find.byKey(const ValueKey('settings_nav_6')));
    await tester.pump();
    expect(container.read(settingsSectionProvider), 6);

    // Narrow window switches to sticky pill nav without overflow
    await tester.binding.setSurfaceSize(const Size(720, 800));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings_nav_1')));
    await tester.pump();
    expect(container.read(settingsSectionProvider), 1);

    // External provider update updates active marker
    container.read(settingsSectionProvider.notifier).state = 2;
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('settings_section_active_2')),
        findsOneWidget);
  });

  testWidgets(
      'NSFW controls, AI presets, Hotkey recorder, and headless safe states work cleanly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: _safeAppearanceOverrides(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _fluentHost(container: container, child: const SettingsPage()),
    );
    await tester.pump();

    // Section 0: NSFW mode & blur slider (merged into Appearance & Display)
    await tester.ensureVisible(find.byKey(const ValueKey('settings_nsfw_show')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings_nsfw_show')));
    await tester.pump();
    expect(container.read(nsfwModeProvider), 'show');

    await tester.tap(find.byKey(const ValueKey('settings_nsfw_placeholder')));
    await tester.pump();
    expect(container.read(nsfwModeProvider), 'placeholder');

    await tester.tap(find.byKey(const ValueKey('settings_nsfw_blur')));
    await tester.pump();
    expect(container.read(nsfwModeProvider), 'blur');
    expect(
        find.byKey(const ValueKey('settings_nsfw_blur_slider')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('settings_nsfw_blur_slider')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(container.read(nsfwBlurProvider), isNot(12));

    // Section 1: Hotkey recorder listens and captures F8
    await tester.tap(find.byKey(const ValueKey('settings_nav_1')));
    await tester.pump();
    final recordBtn = find.byKey(const ValueKey('settings_hotkey_record_btn'));
    await tester.ensureVisible(recordBtn);
    await tester.pump();
    await tester.tap(recordBtn);
    await tester.pump();
    expect(find.textContaining('请按下快捷键'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    expect(find.textContaining('F8'), findsWidgets);
    NoticeCenter.instance.clear();
    await tester.pump();

    // Section 2 & 3: Library & Network + Accounts & Sync headless safe states
    await tester.tap(find.byKey(const ValueKey('settings_nav_2')));
    await tester.pump();
    expect(find.text('尚未记录游戏库根目录'), findsOneWidget);
    expect(find.text(KisakiSources.labels[KisakiSources.cngal]!), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings_nav_3')));
    await tester.pump();
    expect(find.text('OAuth 浏览器登录'), findsOneWidget);

    // Section 4: AI preset populates fields and missing config warns cleanly
    await tester.tap(find.byKey(const ValueKey('settings_nav_4')));
    await tester.pump();
    final presetCombo = find.byKey(const ValueKey('settings_ai_preset_combo'));
    await tester.ensureVisible(presetCombo);
    await tester.pump();
    await _selectComboItem(tester, presetCombo, 'OpenAI');

    final baseUrlBox = tester.widget<TextBox>(
      find.byKey(const ValueKey('settings_ai_base_url')),
    );
    final modelBox = tester.widget<TextBox>(
      find.byKey(const ValueKey('settings_ai_model')),
    );
    expect(baseUrlBox.controller?.text, 'https://api.openai.com/v1');
    expect(modelBox.controller?.text, 'gpt-4o-mini');

    final testBtn = find.byKey(const ValueKey('settings_ai_test_btn'));
    await tester.ensureVisible(testBtn);
    await tester.pump();
    await tester.tap(testBtn);
    await _settle(tester);

    expect(find.byType(InfoBar), findsWidgets);
    expect(find.text('请先填写完整配置'), findsOneWidget);

    // Section 6: Plugins empty state + Marketplace + Check Updates
    await tester.tap(find.byKey(const ValueKey('settings_nav_6')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('尚未安装任何插件'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_open_marketplace_btn')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_import_plugin_zip_btn')),
        findsOneWidget);
    expect(find.text('检查更新'), findsWidgets);

    // Open Plugin Marketplace dialog and verify curated plugins load safely offline
    await tester.tap(find.byKey(const ValueKey('settings_open_marketplace_btn')));
    await tester.pumpAndSettle();
    expect(find.text('KisakiGals 插件市场'), findsOneWidget);
    expect(find.text('Locale Emulator 转区启动'), findsOneWidget);
    expect(find.text('久坐提醒'), findsNothing);
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();
    expect(find.text('KisakiGals 插件市场'), findsNothing);
  });

  testWidgets('SettingsPage renders inside non-Fluent shell via ensureFluentTheme fallback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _safeAppearanceOverrides(),
        child: WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (_, __) => const SettingsPage(),
        ),
      ),
    );
    await _settle(tester, 450);

    expect(find.text('外观与显示'), findsWidgets);
    expect(find.text('AI 服务设置'), findsWidgets);
  });
}
