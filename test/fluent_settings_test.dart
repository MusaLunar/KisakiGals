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

Future<void> _settle(WidgetTester tester, [int ms = 300]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
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
      'SettingsPage renders 5 sections in bare ProviderScope and highlights AI section 3',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsSectionProvider.overrideWith((ref) => 3),
        ],
        child: const FluentApp(home: SettingsPage()),
      ),
    );
    await _settle(tester, 450);

    expect(find.text('外观与个性化'), findsWidgets);
    expect(find.text('启动与热键'), findsWidgets);
    expect(find.text('库与账号隐私'), findsWidgets);
    expect(find.text('AI 服务设置'), findsWidgets);
    expect(find.text('备份与更新'), findsWidgets);
    expect(find.byKey(const ValueKey('settings_section_active_3')),
        findsOneWidget);
  });

  testWidgets(
      'clicking section nav items and narrow sticky pills syncs settingsSectionProvider',
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
    await _settle(tester, 100);

    expect(container.read(settingsSectionProvider), 0);

    await tester.tap(find.byKey(const ValueKey('settings_nav_3')));
    await _settle(tester, 100);
    expect(container.read(settingsSectionProvider), 3);

    await tester.tap(find.byKey(const ValueKey('settings_nav_4')));
    await _settle(tester, 100);
    expect(container.read(settingsSectionProvider), 4);

    // Narrow window switches to sticky pill nav without overflow
    await tester.binding.setSurfaceSize(const Size(720, 800));
    await _settle(tester, 100);

    await tester.tap(find.byKey(const ValueKey('settings_nav_1')));
    await _settle(tester, 100);
    expect(container.read(settingsSectionProvider), 1);

    // External provider update updates active marker
    container.read(settingsSectionProvider.notifier).state = 2;
    await _settle(tester, 100);
    expect(find.byKey(const ValueKey('settings_section_active_2')),
        findsOneWidget);
  });

  testWidgets(
      'appearance controls update themeProvider, accentPresetProvider, and backdropEffectProvider',
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
    await _settle(tester, 100);

    // Change ThemeModePref via ComboBox
    await _selectComboItem(
      tester,
      find.byKey(const ValueKey('settings_theme_combo')),
      '深色模式',
    );
    expect(container.read(themeProvider), ThemeModePref.dark);

    // Select Sakura accent preset swatch card
    await tester.tap(find.byKey(const ValueKey('settings_accent_sakura')));
    await _settle(tester, 100);
    expect(container.read(accentPresetProvider), AccentPreset.sakura);

    // Change BackdropEffectPref via ComboBox
    await _selectComboItem(
      tester,
      find.byKey(const ValueKey('settings_backdrop_combo')),
      'Acrylic 亚克力',
    );
    expect(container.read(backdropEffectProvider), BackdropEffectPref.acrylic);
  });

  testWidgets('NSFW mode and blur sliders update Riverpod providers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        ..._safeAppearanceOverrides(),
        settingsSectionProvider.overrideWith((ref) => 2),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _fluentHost(container: container, child: const SettingsPage()),
    );
    await _settle(tester, 100);

    await tester.ensureVisible(find.byKey(const ValueKey('settings_nsfw_show')));
    await _settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey('settings_nsfw_show')));
    await _settle(tester, 100);
    expect(container.read(nsfwModeProvider), 'show');

    await tester.tap(find.byKey(const ValueKey('settings_nsfw_placeholder')));
    await _settle(tester, 100);
    expect(container.read(nsfwModeProvider), 'placeholder');

    await tester.tap(find.byKey(const ValueKey('settings_nsfw_blur')));
    await _settle(tester, 100);
    expect(container.read(nsfwModeProvider), 'blur');
    expect(
        find.byKey(const ValueKey('settings_nsfw_blur_slider')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('settings_nsfw_blur_slider')),
      const Offset(40, 0),
    );
    await _settle(tester, 100);
    expect(container.read(nsfwBlurProvider), isNot(12));
  });

  testWidgets('AI preset selection populates fields and missing config warns cleanly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        ..._safeAppearanceOverrides(),
        settingsSectionProvider.overrideWith((ref) => 3),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _fluentHost(container: container, child: const SettingsPage()),
    );
    await _settle(tester, 100);

    final presetCombo = find.byKey(const ValueKey('settings_ai_preset_combo'));
    await tester.ensureVisible(presetCombo);
    await _settle(tester, 100);
    await _selectComboItem(tester, presetCombo, 'OpenAI');

    final baseUrlBox = tester.widget<TextBox>(
      find.byKey(const ValueKey('settings_ai_base_url')),
    );
    final modelBox = tester.widget<TextBox>(
      find.byKey(const ValueKey('settings_ai_model')),
    );
    expect(baseUrlBox.controller?.text, 'https://api.openai.com/v1');
    expect(modelBox.controller?.text, 'gpt-4o-mini');

    // Trigger Save & Test without API Key -> shows warning InfoBar
    final testBtn = find.byKey(const ValueKey('settings_ai_test_btn'));
    await tester.ensureVisible(testBtn);
    await _settle(tester, 100);
    await tester.tap(testBtn);
    await _settle(tester, 100);

    expect(find.byType(InfoBar), findsWidgets);
    expect(find.text('请先填写完整配置'), findsOneWidget);
  });

  testWidgets(
      'headless safe states render Hotkey recorder, OAuth, Sources, Plugins, and Update check',
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
    await _settle(tester, 100);

    // Section 1: Hotkey recorder listens and captures F8
    final recordBtn = find.byKey(const ValueKey('settings_hotkey_record_btn'));
    await tester.ensureVisible(recordBtn);
    await _settle(tester, 100);
    await tester.tap(recordBtn);
    await _settle(tester, 100);
    expect(find.textContaining('请按下快捷键'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await _settle(tester, 100);
    expect(find.textContaining('F8'), findsWidgets);
    NoticeCenter.instance.clear();
    await tester.pump();

    // Section 2: OAuth empty state + deduplicated sources
    await tester.tap(find.byKey(const ValueKey('settings_nav_2')));
    await _settle(tester, 100);
    expect(find.text('OAuth 浏览器登录'), findsOneWidget);
    expect(find.text('尚未记录游戏库根目录'), findsOneWidget);
    expect(find.text(KisakiSources.labels[KisakiSources.cngal]!), findsOneWidget);

    // Section 4: Plugins empty state + Check Updates
    await tester.tap(find.byKey(const ValueKey('settings_nav_4')));
    await _settle(tester, 100);
    expect(find.text('尚未导入外部插件'), findsOneWidget);
    expect(find.text('检查更新'), findsWidgets);
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

    expect(find.text('外观与个性化'), findsWidgets);
    expect(find.text('AI 服务设置'), findsWidgets);
  });
}
