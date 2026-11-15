# KisakiGals Fluent 2 Full UI/UX Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completely discard KisakiGals' existing `lib/ui/` and Material Design 3 root shell and rebuild every screen, dialog, flyout menu, notification, animation, and the Win32 tray popup on top of `fluent_ui`, `flutter_acrylic`, `system_theme`, `fluentui_system_icons`, and `flutter_animate`.

**Architecture:** Build a zero-Material `lib/ui/fluent/` primitive layer (`FluentTheme`, `SystemTheme` listener, dynamic `flutter_acrylic` window effect bridge, `InfoBar` notice host, `MenuFlyout`/`ContentDialog` helpers, `flutter_animate` motion primitives, and `fluentui_system_icons` wrapper), then rewrite all leaf widgets/pages against that layer before switching `AppShell` + `main.dart` to `FluentApp` + `NavigationView`, purging old M3/UI files, and syncing dynamic accent colors into the Win32 tray popup. Every task keeps `dart analyze` clean across the workspace.

**Tech Stack:** Flutter 3.47.7 (stable), Dart 3.13.5, `fluent_ui ^4.17.0`, `flutter_acrylic ^1.1.4`, `system_theme ^3.3.0`, `fluentui_system_icons ^1.1.273`, `flutter_animate ^4.5.2`, `flutter_riverpod ^2.5.1`, `fl_chart ^0.69.0`, `window_manager ^0.4.3`, `tray_manager ^0.2.3`, `desktop_drop ^0.4.4`, `file_picker ^8.1.2`, `cached_network_image ^3.4.1`, MSVC Windows Desktop C++ runner.

## Global Constraints

- **Import conflict rule**: Both `package:fluent_ui/fluent_ui.dart` and `package:fluentui_system_icons/fluentui_system_icons.dart` export a class named `FluentIcons`. Every UI file importing Fluent UI MUST use `import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;` and obtain icons exclusively from `package:kisakigals/ui/fluent/fluent_icons.dart` (`FluentIcons` from `fluentui_system_icons`).
- **Zero Material rule**: No file under `lib/ui/` or `lib/main.dart` may import `package:flutter/material.dart`. Standard `package:flutter/widgets.dart`, `package:flutter/services.dart`, `package:flutter/foundation.dart`, and `package:fluent_ui/fluent_ui.dart hide FluentIcons` provide all primitives.
- **Preserved non-UI boundary**: Do NOT alter database schemas, scraping adapters, OAuth, backup archives, or business models except adding two optional `SettingsStore` appearance keys and updating the `showNotice` import path in `lib/services/game_launch_service.dart` and `lib/state/ai_state.dart`.
- **Mandatory UX invariants**:
  1. R18 badge (`nsfw == true`) ALWAYS renders BEFORE rating badges in Home Spotlight, Detail Hero, and Explore Hero.
  2. Download resources in Discover ("资源" mode) and Game Explore ("下载" tab) NEVER show an "入库" (Add to Library) button.
  3. Play Path hotkey capture (`F12` configurable) + note authoring, `jumpToSettingsSection(ref, 3)` (AI settings), and `jumpToLibraryFiltered(...)` MUST keep exact functional parity.
- **Flutter SDK executable on this machine**: `C:\src\flutter\bin\flutter.bat`.

---

## File Map (Target State)

- Modify: `pubspec.yaml`, `lib/data/settings_store.dart`, `lib/providers.dart`, `lib/services/game_launch_service.dart`, `lib/state/ai_state.dart`, `lib/main.dart`, `windows/runner/tray_popup.h`, `windows/runner/tray_popup.cpp`, `windows/runner/flutter_window.cpp`, `test/ui_redesign_test.dart`
- Create (`lib/ui/fluent/`): `fluent_icons.dart`, `fluent_theme.dart`, `fluent_motion.dart`, `fluent_surfaces.dart`, `fluent_notices.dart`, `fluent_dialogs.dart`
- Rewrite (`lib/ui/`): `shell/tabs.dart`, `shell/app_shell.dart`, `home/home_page.dart`, `library/game_actions.dart`, `library/game_card.dart`, `library/game_list_tile.dart`, `library/filter_rail.dart`, `library/library_page.dart`, `detail/save_backup_dialog.dart`, `detail/play_path_tab.dart`, `detail/edit_dialog.dart`, `detail/rate_dialog.dart`, `detail/game_detail_page.dart`, `discover/discover_state.dart`, `discover/discover_filter_state.dart`, `discover/resource_links.dart`, `discover/discover_page.dart`, `discover/game_explore_page.dart`, `stats/word_cloud.dart`, `stats/stats_page.dart`, `ai/ai_page.dart`, `add/scrape_search_dialog.dart`, `add/add_game_page.dart`, `settings/settings_page.dart`, `widgets/image_picker_dialog.dart`, `widgets/save_dir_picker_dialog.dart`
- Delete obsolete legacy UI files: `lib/ui/design.dart`, `lib/ui/kit.dart`, `lib/ui/theme.dart`, `lib/ui/shell/title_bar.dart`, `lib/ui/widgets/common.dart`, `lib/ui/widgets/filter_sidebar.dart`, `lib/ui/widgets/floating_anchor_nav.dart`, `lib/ui/widgets/image_picker.dart`, `lib/ui/widgets/notifications.dart`, `lib/ui/widgets/save_backup_dialog.dart`, `lib/ui/widgets/save_dir_picker_dialog.dart`, `lib/ui/widgets/scrape_search_sheet.dart`, `lib/ui/library/game_card_actions.dart`, `lib/ui/detail/edit_sheet.dart`

---

### Task 1: Dependencies, Appearance Settings Keys, and Riverpod Appearance State

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/data/settings_store.dart:100-146`
- Modify: `lib/ui/shell/tabs.dart:1-30`
- Modify: `lib/providers.dart:1-35`
- Test: `test/fluent_theme_state_test.dart`

**Interfaces:**
- Consumes: `SettingsStore`, `AppServices.I.settings`, `SystemTheme.accentColor`
- Produces:
  - `SettingsStore.kAccentPreset` (`'appearance.accent_preset'`), `SettingsStore.kBackdropEffect` (`'appearance.backdrop_effect'`)
  - `enum AccentPreset { system, sakura, lavender, azure }` with `.id`, `.label`, `.fromId(String)`
  - `enum BackdropEffectPref { mica, tabbed, acrylic, solid }` with `.id`, `.label`, `.fromId(String)`
  - `Tabs.add = 6`, `Tabs.count = 7` (keeping `Tabs.home=0..Tabs.settings=5` unchanged)
  - Providers: `accentPresetProvider`, `backdropEffectProvider`, `systemAccentColorProvider`

- [ ] **Step 1: Add packages to `pubspec.yaml` and resolve dependencies**

Run:
```powershell
C:\src\flutter\bin\flutter.bat pub add fluent_ui:^4.17.0 system_theme:^3.3.0 fluentui_system_icons:^1.1.273 flutter_animate:^4.5.2
```
Expected: Resolving dependencies succeeds with exit code 0 and updates `pubspec.yaml` + `pubspec.lock`.

- [ ] **Step 2: Write failing unit test for appearance prefs & Tabs compatibility**

Create `test/fluent_theme_state_test.dart`:
```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/ui/shell/tabs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('SettingsStore persists AccentPreset and BackdropEffectPref', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );
    addTearDown(() => db.close());

    final store = SettingsStore(db);
    expect(await store.accentPreset(), AccentPreset.system);
    expect(await store.backdropEffect(), BackdropEffectPref.mica);

    await store.setString(SettingsStore.kAccentPreset, AccentPreset.sakura.id);
    await store.setString(
      SettingsStore.kBackdropEffect,
      BackdropEffectPref.acrylic.id,
    );

    expect(await store.accentPreset(), AccentPreset.sakura);
    expect(await store.backdropEffect(), BackdropEffectPref.acrylic);
    expect(AccentPreset.fromId('unknown'), AccentPreset.system);
    expect(BackdropEffectPref.fromId('unknown'), BackdropEffectPref.mica);
  });

  test('Tabs preserves 0..5 indices and exposes Tabs.add = 6', () {
    expect(Tabs.home, 0);
    expect(Tabs.library, 1);
    expect(Tabs.discover, 2);
    expect(Tabs.stats, 3);
    expect(Tabs.ai, 4);
    expect(Tabs.settings, 5);
    expect(Tabs.add, 6);
    expect(Tabs.count, 7);
    expect(const Color(0xFF0078D4), isNotNull);
  });
}
```

- [ ] **Step 3: Run test to confirm failure before implementing enums**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_theme_state_test.dart`
Expected: FAIL — `AccentPreset`, `BackdropEffectPref`, `kAccentPreset`, `kBackdropEffect`, `Tabs.add` undefined.

- [ ] **Step 4: Implement appearance enums & accessors in `lib/data/settings_store.dart` and extend `Tabs`**

Update `lib/data/settings_store.dart` after `kScreenshotHotkey`:
```dart
  /// 外观强调色来源：system（跟随 Windows）/ sakura / lavender / azure
  static const kAccentPreset = 'appearance.accent_preset';

  /// 窗口材质效果：mica / tabbed / acrylic / solid
  static const kBackdropEffect = 'appearance.backdrop_effect';

  Future<AccentPreset> accentPreset() async =>
      AccentPreset.fromId(await getString(kAccentPreset, AccentPreset.system.id));

  Future<BackdropEffectPref> backdropEffect() async =>
      BackdropEffectPref.fromId(
        await getString(kBackdropEffect, BackdropEffectPref.mica.id),
      );
```
And append enums at bottom of `lib/data/settings_store.dart`:
```dart
enum AccentPreset {
  system('system', '跟随系统'),
  sakura('sakura', '绯樱'),
  lavender('lavender', '薰衣草'),
  azure('azure', 'Win11 天蓝');

  final String id;
  final String label;
  const AccentPreset(this.id, this.label);

  static AccentPreset fromId(String raw) => AccentPreset.values.firstWhere(
        (e) => e.id == raw,
        orElse: () => AccentPreset.system,
      );
}

enum BackdropEffectPref {
  mica('mica', 'Mica 云母'),
  tabbed('tabbed', 'Tabbed 通透云母'),
  acrylic('acrylic', 'Acrylic 亚克力'),
  solid('solid', '纯色底面');

  final String id;
  final String label;
  const BackdropEffectPref(this.id, this.label);

  static BackdropEffectPref fromId(String raw) =>
      BackdropEffectPref.values.firstWhere(
        (e) => e.id == raw,
        orElse: () => BackdropEffectPref.mica,
      );
}
```
Update `lib/ui/shell/tabs.dart`:
```dart
class Tabs {
  const Tabs._();

  static const home = 0;
  static const library = 1;
  static const discover = 2;
  static const stats = 3;
  static const ai = 4;
  static const settings = 5;
  static const add = 6;

  static const count = 7;
}
```
Update `lib/providers.dart` (lines 1-30) adding `AccentPresetController`, `BackdropEffectController`, `accentPresetProvider`, `backdropEffectProvider`, and `systemAccentColorProvider`:
```dart
import 'dart:ui' show Color;
import 'package:system_theme/system_theme.dart';
```
```dart
class AccentPresetController extends StateNotifier<AccentPreset> {
  AccentPresetController() : super(AccentPreset.system) {
    AppServices.I.settings.accentPreset().then((p) {
      if (mounted) state = p;
    });
  }

  Future<void> set(AccentPreset preset) async {
    state = preset;
    await AppServices.I.settings.setString(SettingsStore.kAccentPreset, preset.id);
  }
}

final accentPresetProvider =
    StateNotifierProvider<AccentPresetController, AccentPreset>(
        (ref) => AccentPresetController());

class BackdropEffectController extends StateNotifier<BackdropEffectPref> {
  BackdropEffectController() : super(BackdropEffectPref.mica) {
    AppServices.I.settings.backdropEffect().then((e) {
      if (mounted) state = e;
    });
  }

  Future<void> set(BackdropEffectPref effect) async {
    state = effect;
    await AppServices.I.settings
        .setString(SettingsStore.kBackdropEffect, effect.id);
  }
}

final backdropEffectProvider =
    StateNotifierProvider<BackdropEffectController, BackdropEffectPref>(
        (ref) => BackdropEffectController());

/// 最新的 Windows 系统强调色（由 main.dart 启动时及 SystemTheme.onChange 刷新）。
final systemAccentColorProvider = StateProvider<Color>(
  (ref) => SystemTheme.accentColor.accent,
);
```

- [ ] **Step 5: Run tests & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_theme_state_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/data/settings_store.dart lib/providers.dart lib/ui/shell/tabs.dart
git add pubspec.yaml pubspec.lock lib/data/settings_store.dart lib/providers.dart lib/ui/shell/tabs.dart test/fluent_theme_state_test.dart
git commit -m "chore: add fluent_ui stack dependencies and appearance state providers"
```
Expected: PASS (2 tests) and clean analyzer.

---

### Task 2: Build Core `lib/ui/fluent/` Primitives & Rewire Non-UI Notice Imports

**Files:**
- Create: `lib/ui/fluent/fluent_icons.dart`
- Create: `lib/ui/fluent/fluent_theme.dart`
- Create: `lib/ui/fluent/fluent_motion.dart`
- Create: `lib/ui/fluent/fluent_surfaces.dart`
- Create: `lib/ui/fluent/fluent_notices.dart`
- Create: `lib/ui/fluent/fluent_dialogs.dart`
- Modify: `lib/services/game_launch_service.dart:18`
- Modify: `lib/state/ai_state.dart:28`
- Test: `test/fluent_primitives_test.dart`

**Interfaces:**
- Consumes: `fluent_ui ^4.17.0`, `flutter_acrylic ^1.1.4`, `system_theme ^3.3.0`, `fluentui_system_icons ^1.1.273`, `flutter_animate ^4.5.2`, `AccentPreset`, `BackdropEffectPref`, `nsfwModeProvider`, `nsfwBlurProvider`
- Produces:
  - `FluentIcons` re-exported cleanly from `package:fluentui_system_icons/fluentui_system_icons.dart`
  - `resolveAccentBaseColor(AccentPreset, Color systemAccent)`, `buildFluentTheme({required Brightness brightness, required AccentPreset preset, required Color systemAccent, required BackdropEffectPref backdrop})`, `syncWindowBackdrop({required BackdropEffectPref effect, required bool dark})`
  - `FluentMotion` constants (`fast = 140ms`, `standard = 220ms`, `section = 280ms`, `curve = Curves.easeOutCubic`), `Widget.fluentEntrance({int index, bool disabled})`, `Widget.fluentShimmer({bool disabled})`
  - `FluentSurfaceCard`, `FluentAcrylicPanel`, `FluentCoverImage`, `FluentBadge`, `FluentR18ScoreRow`, `FluentStatusPill`, `FluentEmptyState`, `FluentSectionHeader`
  - `NoticeCenter`, `showNotice(String message, {bool error = false, Duration? duration})`, `FluentNoticeHost`
  - `showFluentConfirmDialog(...)`, `showFluentLightboxDialog(...)`, `showFluentInfoDialog(...)`

- [ ] **Step 1: Write failing widget/unit tests for `lib/ui/fluent/` primitives**

Create `test/fluent_primitives_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/ui/fluent/fluent_motion.dart';
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_surfaces.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';

void main() {
  tearDown(() {
    NoticeCenter.instance.clear();
  });

  test('buildFluentTheme resolves AccentColor presets and Brightness', () {
    const sys = Color(0xFF2288CC);
    final lightSys = buildFluentTheme(
      brightness: Brightness.light,
      preset: AccentPreset.system,
      systemAccent: sys,
      backdrop: BackdropEffectPref.mica,
    );
    final darkSakura = buildFluentTheme(
      brightness: Brightness.dark,
      preset: AccentPreset.sakura,
      systemAccent: sys,
      backdrop: BackdropEffectPref.acrylic,
    );

    expect(lightSys.brightness, Brightness.light);
    expect(lightSys.accentColor.normal, sys);
    expect(lightSys.scaffoldBackgroundColor, const Color(0x00000000));
    expect(darkSakura.brightness, Brightness.dark);
    expect(darkSakura.accentColor.normal, const Color(0xFFD85C84));
  });

  test('NoticeCenter caps active notices at 3 and dismisses cleanly', () {
    final c = NoticeCenter.instance;
    c.show('msg 1');
    c.show('msg 2');
    c.show('msg 3');
    c.show('msg 4', error: true);

    expect(c.items.length, 3);
    expect(c.items.first.message, 'msg 2');
    expect(c.items.last.error, true);

    c.dismiss(c.items.first.id);
    expect(c.items.length, 2);
  });

  testWidgets('FluentNoticeHost renders InfoBar stack inside FluentApp',
      (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(
          brightness: Brightness.light,
          preset: AccentPreset.azure,
          systemAccent: const Color(0xFF0078D4),
          backdrop: BackdropEffectPref.mica,
        ),
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            const Positioned.fill(child: FluentNoticeHost()),
          ],
        ),
        home: const SizedBox.shrink(),
      ),
    );

    showNotice('已保存游玩笔记');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(InfoBar), findsOneWidget);
    expect(find.text('已保存游玩笔记'), findsOneWidget);

    NoticeCenter.instance.clear();
    await tester.pumpAndSettle();
    expect(find.byType(InfoBar), findsNothing);
  });

  testWidgets('FluentR18ScoreRow places R18 pill strictly before Score pill',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: FluentApp(
          home: const FluentR18ScoreRow(
            nsfw: true,
            scoreText: '9.2',
            voteText: '128 票',
          ).fluentEntrance(index: 0, disable: true),
        ),
      ),
    );

    final r18Box = tester.getTopLeft(find.text('R18'));
    final scoreBox = tester.getTopLeft(find.textContaining('9.2'));
    expect(r18Box.dx, lessThan(scoreBox.dx));
    expect(FluentMotion.fast.inMilliseconds, 140);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_primitives_test.dart`
Expected: FAIL — `lib/ui/fluent/*.dart` files do not exist yet.

- [ ] **Step 3: Create `lib/ui/fluent/fluent_icons.dart`, `fluent_theme.dart`, and `fluent_motion.dart`**

Create `lib/ui/fluent/fluent_icons.dart`:
```dart
/// 统一导出 Microsoft Fluent System Icons，避免与 fluent_ui 自带 MDL2 图标重名冲突。
library;

export 'package:fluentui_system_icons/fluentui_system_icons.dart'
    show FluentIcons;
```

Create `lib/ui/fluent/fluent_theme.dart`:
```dart
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

Color resolveAccentBaseColor(AccentPreset preset, Color systemAccent) {
  return switch (preset) {
    AccentPreset.system =>
      systemAccent.alpha == 0 ? kDefaultWin11Azure : systemAccent,
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

FluentThemeData buildFluentTheme({
  required Brightness brightness,
  required AccentPreset preset,
  required Color systemAccent,
  required BackdropEffectPref backdrop,
}) {
  final isDark = brightness == Brightness.dark;
  final baseAccent = resolveAccentBaseColor(preset, systemAccent);
  final accentSwatch = buildFluentAccentSwatch(baseAccent);

  // Mica / Tabbed / Acrylic 需保留透明窗体底衬，仅 Solid 使用不透明中性底。
  final scaffoldBg = backdrop == BackdropEffectPref.solid
      ? (isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3))
      : Colors.transparent;

  return FluentThemeData(
    brightness: brightness,
    accentColor: accentSwatch,
    scaffoldBackgroundColor: scaffoldBg,
    micaBackgroundColor:
        isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
    cardColor: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFFBFBFB),
    fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
    fontFamilyFallback: const ['NotoSansSC', 'Microsoft YaHei UI', 'Segoe UI'],
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
```

Create `lib/ui/fluent/fluent_motion.dart`:
```dart
/// Fluent 2 动效原语（基于 flutter_animate，遵守系统无障碍减少动画）。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

class FluentMotion {
  const FluentMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration section = Duration(milliseconds: 280);
  static const Curve enterCurve = Curves.easeOutCubic;
}

extension FluentMotionWidgetExt on Widget {
  /// 轻量级交错入场（仅首屏前 6 项递增延迟，避免长列表累积等待）。
  Widget fluentEntrance({
    int index = 0,
    double slideYOffset = 0.035,
    bool disable = false,
  }) {
    if (disable) return this;
    final capped = index.clamp(0, 6);
    final delay = Duration(milliseconds: 22 * capped);
    return animate(delay: delay)
        .fadeIn(duration: FluentMotion.standard, curve: FluentMotion.enterCurve)
        .slideY(
          begin: slideYOffset,
          end: 0,
          duration: FluentMotion.standard,
          curve: FluentMotion.enterCurve,
        );
  }

  /// 页面主体柔和滑入过渡。
  Widget fluentPageTransition({bool disable = false}) {
    if (disable) return this;
    return animate()
        .fadeIn(duration: FluentMotion.standard, curve: FluentMotion.enterCurve)
        .slideY(
          begin: 0.02,
          end: 0,
          duration: FluentMotion.standard,
          curve: FluentMotion.enterCurve,
        );
  }

  /// 加载骨架微光效果。
  Widget fluentShimmer({bool disable = false, required Color highlightColor}) {
    if (disable) return this;
    return animate(onPlay: (c) => c.repeat())
        .shimmer(duration: const Duration(milliseconds: 1200), color: highlightColor);
  }
}

bool fluentAnimationsDisabled(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
```

- [ ] **Step 4: Create `lib/ui/fluent/fluent_surfaces.dart`, `fluent_notices.dart`, and `fluent_dialogs.dart`**

Create `lib/ui/fluent/fluent_surfaces.dart`:
```dart
/// Fluent 2 表面、R18 保护封面与通用展示原语。
library;

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media_paths.dart';
import '../../providers.dart';
import 'fluent_icons.dart';

/// 标准 Win11 卡片容器：中性层 + 1px 微妙描边 + 8px 圆角 + 可选悬停高亮。
class FluentSurfaceCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final bool elevated;
  final Color? backgroundColor;

  const FluentSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = 8,
    this.elevated = false,
    this.backgroundColor,
  });

  @override
  State<FluentSurfaceCard> createState() => _FluentSurfaceCardState();
}

class _FluentSurfaceCardState extends State<FluentSurfaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseBg = widget.backgroundColor ??
        (isDark
            ? const Color(0xD82C2C2C)
            : const Color(0xEBFFFFFF));
    final hoverBg = isDark ? const Color(0xE8353535) : const Color(0xFFFFFFFF);
    final borderColor = _hovered && widget.onTap != null
        ? theme.accentColor.defaultBrushFor(theme.brightness).withValues(alpha: 0.65)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.07));

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _hovered && widget.onTap != null ? hoverBg : baseBg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: widget.elevated || (_hovered && widget.onTap != null)
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                  blurRadius: _hovered ? 16 : 8,
                  offset: Offset(0, _hovered ? 6 : 2),
                ),
              ]
            : null,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return box;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: box,
      ),
    );
  }
}

/// 局部 Fluent Acrylic 玻璃层，适合浮层提示/英雄横幅渐变蒙版/拖拽覆盖层。
class FluentAcrylicPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final double luminosityAlpha;
  final double tintAlpha;

  const FluentAcrylicPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 10,
    this.tint,
    this.luminosityAlpha = 0.72,
    this.tintAlpha = 0.72,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Acrylic(
        luminosityAlpha: luminosityAlpha,
        tintAlpha: tintAlpha,
        tint: tint ??
            (isDark ? const Color(0xFF232323) : const Color(0xFFF6F6F6)),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.black.withValues(alpha: 0.07),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 小标签胶囊（状态、数量、来源、评分）。
class FluentBadge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? foreground;
  final Color? background;
  final VoidCallback? onTap;

  const FluentBadge({
    super.key,
    required this.text,
    this.icon,
    this.foreground,
    this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = foreground ??
        (isDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF1E1E1E));
    final bg = background ??
        (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05));

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: (foreground ?? bg).withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.15,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// R18 徽章强制位于评分徽章之前（产品规范强制不变量）。
class FluentR18ScoreRow extends StatelessWidget {
  final bool nsfw;
  final String? scoreText;
  final String? voteText;
  final List<Widget> trailing;

  const FluentR18ScoreRow({
    super.key,
    required this.nsfw,
    this.scoreText,
    this.voteText,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (nsfw)
          const FluentBadge(
            text: 'R18',
            foreground: Color(0xFFD13438),
            background: Color(0x22D13438),
          ),
        if (scoreText != null && scoreText!.isNotEmpty)
          FluentBadge(
            icon: FluentIcons.star_16_filled,
            text: voteText != null && voteText!.isNotEmpty
                ? '$scoreText · $voteText'
                : scoreText!,
            foreground: accent,
            background: accent.withValues(alpha: 0.14),
          ),
        ...trailing,
      ],
    );
  }
}

/// 封面渲染组件：同时支持本地路径与网络 URL，并集成 R18 模糊保护与点击揭露。
class FluentCoverImage extends ConsumerStatefulWidget {
  final String pathOrUrl;
  final bool nsfw;
  final BoxFit fit;
  final double radius;
  final double? width;
  final double? height;
  final bool allowRevealOnHover;

  const FluentCoverImage({
    super.key,
    required this.pathOrUrl,
    this.nsfw = false,
    this.fit = BoxFit.cover,
    this.radius = 6,
    this.width,
    this.height,
    this.allowRevealOnHover = true,
  });

  @override
  ConsumerState<FluentCoverImage> createState() => _FluentCoverImageState();
}

class _FluentCoverImageState extends ConsumerState<FluentCoverImage> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(nsfwModeProvider);
    final blurSigma = ref.watch(nsfwBlurProvider);
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget buildPlaceholder() => Container(
          width: widget.width,
          height: widget.height,
          color: isDark ? const Color(0xFF282828) : const Color(0xFFEBEBEB),
          child: Center(
            child: Icon(
              FluentIcons.image_24_regular,
              size: 28,
              color: theme.inactiveColor.withValues(alpha: 0.45),
            ),
          ),
        );

    final hideAsPlaceholder = widget.nsfw && mode == 'placeholder' && !_revealed;
    final applyBlur = widget.nsfw && mode == 'blur' && !_revealed;

    Widget img;
    if (hideAsPlaceholder || widget.pathOrUrl.trim().isEmpty) {
      img = buildPlaceholder();
    } else if (widget.pathOrUrl.startsWith('http://') ||
        widget.pathOrUrl.startsWith('https://')) {
      img = CachedNetworkImage(
        imageUrl: widget.pathOrUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (_, __) => buildPlaceholder(),
        errorWidget: (_, __, ___) => buildPlaceholder(),
      );
    } else {
      final resolved = MediaPaths.instance.resolveStored(widget.pathOrUrl);
      final f = File(resolved);
      if (!f.existsSync()) {
        img = buildPlaceholder();
      } else {
        img = Image.file(
          f,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => buildPlaceholder(),
        );
      }
    }

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          img,
          if (applyBlur)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: img,
              ),
            ),
          if ((applyBlur || hideAsPlaceholder))
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.28),
                alignment: Alignment.center,
                child: const FluentBadge(
                  icon: FluentIcons.eye_off_16_regular,
                  text: 'R18 已遮罩',
                  foreground: Colors.white,
                  background: Color(0xAA1F1F1F),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.nsfw && widget.allowRevealOnHover && mode != 'show') {
      content = MouseRegion(
        onEnter: (_) => setState(() => _revealed = true),
        onExit: (_) => setState(() => _revealed = false),
        child: content,
      );
    }
    return content;
  }
}

class FluentSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  const FluentSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 18,
            color: theme.accentColor.defaultBrushFor(theme.brightness),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.typography.subtitle),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class FluentEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const FluentEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: theme.inactiveColor.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.typography.bodyLarge),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
```

Create `lib/ui/fluent/fluent_notices.dart`:
```dart
/// Fluent 2 全局通知中心（InfoBar 浮层队列）。
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_animate/flutter_animate.dart';

class AppNotice {
  final int id;
  final String message;
  final bool error;
  const AppNotice({required this.id, required this.message, this.error = false});
}

class NoticeCenter extends ChangeNotifier {
  NoticeCenter._();
  static final NoticeCenter instance = NoticeCenter._();

  final List<AppNotice> _items = [];
  final Map<int, Timer> _timers = {};
  int _nextId = 1;

  List<AppNotice> get items => List.unmodifiable(_items);

  void show(String message, {bool error = false, Duration? duration}) {
    final id = _nextId++;
    _items.add(AppNotice(id: id, message: message, error: error));
    while (_items.length > 3) {
      final oldest = _items.first;
      _timers.remove(oldest.id)?.cancel();
      _items.removeAt(0);
    }
    _timers[id]?.cancel();
    _timers[id] = Timer(duration ?? const Duration(milliseconds: 3600), () {
      dismiss(id);
    });
    notifyListeners();
  }

  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    final before = _items.length;
    _items.removeWhere((n) => n.id == id);
    if (_items.length != before) notifyListeners();
  }

  void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _items.clear();
    notifyListeners();
  }
}

void showNotice(String message, {bool error = false, Duration? duration}) =>
    NoticeCenter.instance.show(message, error: error, duration: duration);

class FluentNoticeHost extends StatefulWidget {
  const FluentNoticeHost({super.key});

  @override
  State<FluentNoticeHost> createState() => _FluentNoticeHostState();
}

class _FluentNoticeHostState extends State<FluentNoticeHost> {
  @override
  void initState() {
    super.initState();
    NoticeCenter.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    NoticeCenter.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = NoticeCenter.instance.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return IgnorePointer(
      ignoring: false,
      child: Align(
        alignment: Alignment.topRight,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 54, right: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final n in items)
                    Padding(
                      key: ValueKey(n.id),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _NoticeInfoCard(
                        notice: n,
                        disableAnim: disableAnim,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeInfoCard extends StatelessWidget {
  final AppNotice notice;
  final bool disableAnim;

  const _NoticeInfoCard({required this.notice, required this.disableAnim});

  @override
  Widget build(BuildContext context) {
    final bar = InfoBar(
      title: Text(notice.error ? '操作提示' : '通知'),
      content: Text(notice.message),
      severity: notice.error ? InfoBarSeverity.error : InfoBarSeverity.info,
      isLong: notice.message.length > 34,
      onClose: () => NoticeCenter.instance.dismiss(notice.id),
    );
    if (disableAnim) return bar;
    return bar
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 160))
        .slideX(
          begin: 0.08,
          end: 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
  }
}
```

Create `lib/ui/fluent/fluent_dialogs.dart`:
```dart
/// Fluent 2 标准 ContentDialog 辅助工具。
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

import '../../core/media_paths.dart';
import 'fluent_icons.dart';

Future<bool> showFluentConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => ContentDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        Button(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        destructive
            ? Button(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                    const Color(0xFFD13438),
                  ),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              )
            : FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
      ],
    ),
  );
  return result == true;
}

Future<void> showFluentLightboxDialog(
  BuildContext context, {
  required String pathOrUrl,
  String title = '图片预览',
  String? caption,
}) async {
  final isNet =
      pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');
  final resolved = isNet ? pathOrUrl : MediaPaths.instance.resolveStored(pathOrUrl);

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ContentDialog(
      constraints: const BoxConstraints(maxWidth: 960, maxHeight: 740),
      title: Row(
        children: [
          const Icon(FluentIcons.image_20_regular, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(FluentIcons.dismiss_20_regular, size: 16),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: isNet
                    ? CachedNetworkImage(imageUrl: resolved, fit: BoxFit.contain)
                    : Image.file(File(resolved), fit: BoxFit.contain),
              ),
            ),
          ),
          if (caption != null && caption.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(caption),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 5: Rewire `lib/services/game_launch_service.dart` and `lib/state/ai_state.dart` notice import**

Edit `lib/services/game_launch_service.dart` line 18:
`import '../ui/fluent/fluent_notices.dart';`

Edit `lib/state/ai_state.dart` line 28:
`import '../ui/fluent/fluent_notices.dart';`

- [ ] **Step 6: Run tests & analyze**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_primitives_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/ui/fluent/ lib/services/game_launch_service.dart lib/state/ai_state.dart
git add lib/ui/fluent/ lib/services/game_launch_service.dart lib/state/ai_state.dart test/fluent_primitives_test.dart
git commit -m "feat(ui): build core Fluent 2 primitives layer and InfoBar notice host"
```
Expected: PASS (all 4 tests in `test/fluent_primitives_test.dart`) and clean analyzer.

---

### Task 3: Fluent Shared Dialogs (Save Backup, Save Dir Picker, Image Picker, Scrape Search)

**Files:**
- Create: `lib/ui/widgets/image_picker_dialog.dart`
- Create: `lib/ui/widgets/save_dir_picker_dialog.dart`
- Create: `lib/ui/detail/save_backup_dialog.dart`
- Create: `lib/ui/add/scrape_search_dialog.dart`
- Test: `test/fluent_dialogs_test.dart`

**Interfaces:**
- Consumes: `AppServices.I`, `SaveBackupService`, `SaveDirDetector`, `MetadataFetcher`, `ScrapeApplier`, `showNotice`, `fluent_dialogs.dart`
- Produces:
  - `showImagePickerDialog(BuildContext context, {required String title, List<String> candidates = const []})` -> `Future<String?>`
  - `showSaveDirPickerDialog(BuildContext context, Game game)` -> `Future<String?>`
  - `showSaveBackupDialog(BuildContext context, WidgetRef ref, Game game)` -> `Future<void>`
  - `showScrapeSearchDialog(BuildContext context, WidgetRef ref, Game game, {String? initialQuery})` -> `Future<bool>`

- [ ] **Step 1: Write failing widget test for shared Fluent dialogs**

Create `test/fluent_dialogs_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/ui/widgets/image_picker_dialog.dart';

void main() {
  testWidgets('ImagePickerDialog renders Fluent ContentDialog and cancels',
      (tester) async {
    String? picked = 'initial';
    await tester.pumpWidget(
      ProviderScope(
        child: FluentApp(
          home: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  picked = await showImagePickerDialog(
                    context,
                    title: '选择封面',
                    candidates: const ['https://example.com/a.jpg'],
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text('选择封面'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(Game(name: 'Test').displayName, 'Test');
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_dialogs_test.dart`
Expected: FAIL — `image_picker_dialog.dart` does not exist yet.

- [ ] **Step 3: Implement `lib/ui/widgets/image_picker_dialog.dart` and `lib/ui/widgets/save_dir_picker_dialog.dart`**

Implement `lib/ui/widgets/image_picker_dialog.dart`:
- Uses `ContentDialog` (`maxWidth: 720`), `TextBox` for custom local/URL path input, `Button` to trigger `FilePicker.platform.pickFiles(type: FileType.image)`, responsive `Wrap`/`GridView` of candidate thumbnails (`FluentCoverImage` + selection ring), and `FilledButton` returning selected URL/local path.

Implement `lib/ui/widgets/save_dir_picker_dialog.dart`:
- Uses `SaveDirDetector.detect(game)` to populate `List<SaveDirCandidate>` inside a `ContentDialog` (`maxWidth: 640`), displaying `ProgressRing` while scanning, radio-clickable `FluentSurfaceCard` candidates showing confidence badge (`candidate.confidenceLevel`), shortPath & reason, plus a "手动浏览目录" button using `FilePicker.platform.getDirectoryPath()`.

- [ ] **Step 4: Implement `lib/ui/detail/save_backup_dialog.dart` and `lib/ui/add/scrape_search_dialog.dart`**

Implement `lib/ui/detail/save_backup_dialog.dart`:
- `ContentDialog` managing `SaveBackupService` (`list(game.id!)`, `backup`, `restore`, `remove`): shows current `game.savePath` (with one-click detect via `showSaveDirPickerDialog`), "立即备份" `FilledButton`, scrollable list of `SaveBackupEntry` rows (`auto` badge, timestamp, `displaySize`, file count, "恢复" + destructive confirm "删除"). Calls `showNotice(...)` on completion/error.

Implement `lib/ui/add/scrape_search_dialog.dart`:
- `ContentDialog` (`maxWidth: 780, maxHeight: 680`) for re-scraping or matching metadata for an existing `Game`: `TextBox` keyword + source filter toggle pills (`KisakiSources.labels`), "搜索" `FilledButton`, `AppServices.I.fetcher.searchGrouped(...)` grouped results inside `Expander` rows, candidate preview + "应用到当前作品" calling `ScrapeApplier(AppServices.I.repo, AppServices.I.fetcher).apply(game, ...)` and `bumpLibrary(ref)`.

- [ ] **Step 5: Run tests & analyze & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_dialogs_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/ui/widgets/image_picker_dialog.dart lib/ui/widgets/save_dir_picker_dialog.dart lib/ui/detail/save_backup_dialog.dart lib/ui/add/scrape_search_dialog.dart
git add lib/ui/widgets/image_picker_dialog.dart lib/ui/widgets/save_dir_picker_dialog.dart lib/ui/detail/save_backup_dialog.dart lib/ui/add/scrape_search_dialog.dart test/fluent_dialogs_test.dart
git commit -m "feat(ui): add Fluent shared dialogs for image, save dir, backups, and scrape"
```
Expected: PASS and clean analyzer.

---

### Task 4: Rewrite Home Page (`HomePage`) & Library Subsystem (`LibraryPage`, `FilterRail`, `GameCard`, `GameListTile`, `GameActions`)

**Files:**
- Create: `lib/ui/library/game_actions.dart`
- Create: `lib/ui/library/filter_rail.dart`
- Rewrite: `lib/ui/library/game_card.dart`
- Rewrite: `lib/ui/library/game_list_tile.dart`
- Rewrite: `lib/ui/library/library_page.dart`
- Rewrite: `lib/ui/home/home_page.dart`
- Test: `test/fluent_home_library_test.dart`

**Interfaces:**
- Consumes: `homeDataProvider`, `gamesProvider`, `libraryFilterProvider`, `libraryLayoutProvider`, `librarySidebarProvider`, `allTagsProvider`, `developersProvider`, `usedSourcesProvider`, `platformRatingsProvider`, `trackingGameProvider`, `GameLaunchService.launchAndTrack`, `FluentCoverImage`, `FluentR18ScoreRow`, `showSaveBackupDialog`, `openGameDetail`, `openGameExplore`
- Produces:
  - `openGameDetail(BuildContext, int gameId)` helper
  - `openGameExplore(BuildContext, {required ScrapedGame seedGame, int? localGameId, List<SourceRecord> knownSources = const []})` helper (opens `GameExplorePage(seedGame: seedGame, localGameId: localGameId, knownSources: knownSources)` — compatible with both pre-Task-6 and Task-6 `GameExplorePage`)
  - `showGameContextMenu(...)` using `FlyoutController` + `MenuFlyout`
  - `HomePage`, `LibraryPage`, `FluentGameCard`, `FluentGameListTile`, `FilterRail`

- [ ] **Step 1: Write failing widget test for HomePage & LibraryPage in `FluentApp`**

Create `test/fluent_home_library_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/home/home_page.dart';
import 'package:kisakigals/ui/library/game_card.dart';

void main() {
  testWidgets('HomePage renders Spotlight and KPI cards in FluentApp',
      (tester) async {
    final fakeHome = HomeData(
      week: AggStats(totalSeconds: 7200, sessionCount: 3, activeDays: 2),
      month: AggStats(totalSeconds: 18000, sessionCount: 8, activeDays: 5),
      all: AggStats(totalSeconds: 36000, sessionCount: 15, activeDays: 12),
      recentGames: [
        Game(
          id: 1,
          name: 'Sakura Demo',
          nameCn: '樱花测试作',
          developer: 'Yuzusoft',
          nsfw: true,
          userRating: 9.4,
          totalSeconds: 36000,
          lastPlayedAt: DateTime(2026, 11, 14),
        ),
      ],
      activity: const [],
      gameCount: 12,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeDataProvider.overrideWith((ref) async => fakeHome),
        ],
        child: const FluentApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('樱花测试作'), findsWidgets);
    expect(find.text('R18'), findsWidgets);
    // R18 appears strictly before rating in Spotlight
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('9.4').first).dx;
    expect(r18Dx, lessThan(scoreDx));
  });

  testWidgets('FluentGameCard shows title and status without Material errors',
      (tester) async {
    final g = Game(id: 2, name: 'TestVN', nameCn: '测试视觉小说', userRating: 8.5);
    await tester.pumpWidget(
      ProviderScope(
        child: FluentApp(
          home: Center(
            child: SizedBox(
              width: 220,
              height: 320,
              child: FluentGameCard(game: g),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试视觉小说'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_home_library_test.dart`
Expected: FAIL — `FluentGameCard` and new `HomePage` APIs not implemented yet.

- [ ] **Step 3: Implement `lib/ui/library/game_actions.dart`, `game_card.dart`, `game_list_tile.dart`, `filter_rail.dart`**

Create `lib/ui/library/game_actions.dart`:
- `MenuFlyout` + `FlyoutController` context menu builder (`showGameMenuFlyout` triggered via `onSecondaryTapUp` & `FlyoutTarget`):
  - 启动游戏 (`FluentIcons.play_16_regular`)
  - LE 转区启动 (`FluentIcons.translate_16_regular`)
  - 查看详情 (`FluentIcons.open_16_regular`)
  - 探索百科 (`FluentIcons.compass_northwest_16_regular`)
  - 收藏 / 取消收藏 (`FluentIcons.heart_16_regular` / `filled`)
  - 编辑信息 / 评分 / 存档备份 / 打开目录 / 移出库 (`MenuFlyoutSeparator` + danger item)
- Also exports centralized helpers:
  - `openGameDir(Game g)` (`explorer /select,...` or directory)
  - `confirmDeleteGame(BuildContext, WidgetRef, Game)` using `showFluentConfirmDialog`

Rewrite `lib/ui/library/game_card.dart` (`FluentGameCard`) & `lib/ui/library/game_list_tile.dart` (`FluentGameListTile`):
- Wrap root in `FlyoutTarget(controller: _flyoutCtrl)` and `GestureDetector(onTap: openDetail, onSecondaryTapUp: (d) => showGameMenuFlyout(...))`.
- Hover reveals subtle `Acrylic` bottom action strip (`启动` + `更多...`) + accent border highlight.
- `FluentR18ScoreRow` renders R18 pill strictly before rating pill.

Create `lib/ui/library/filter_rail.dart`:
- 250px collapsible Win11 `FluentSurfaceCard` sidebar listening to `libraryFilterProvider`: status segmented list (`全部`, `PlayStatus.values`), `favoriteOnly` `ToggleSwitch`, developer `ComboBox`, source `ComboBox`, scrollable tag `FluentBadge` filter pills, and "清除筛选" button.

- [ ] **Step 4: Rewrite `lib/ui/library/library_page.dart` and `lib/ui/home/home_page.dart`**

Rewrite `lib/ui/library/library_page.dart`:
- Full `DropTarget` (`desktop_drop`) wrapper showing centered `FluentAcrylicPanel` drop hint ("拖入 .exe / .lnk / 游戏目录快速入库") on drag enter, routing dropped file path directly into Add Game flow or direct import prompt.
- Top Fluent `CommandBar` with primary items (添加游戏, 刷新库, 切换筛选栏, 网格/列表切换) + `TextBox` keyword filter + `ComboBox<GameSort>` sort picker.
- Responsive `SliverGrid` / `ListView.builder` with `flutter_animate` `.fluentEntrance(index: i, disable: disableAnim)`.

Rewrite `lib/ui/home/home_page.dart`:
- Spotlight Hero Banner (`FluentAcrylicPanel` overlay on blurred cover background, crisp 160x220 `FluentCoverImage`, `FluentR18ScoreRow` with R18 strictly before rating, `FilledButton` Launch / Stop session, `Button` Detail & Explore).
- 4-column responsive KPI `FluentSurfaceCard` row (总入库 / 本周游玩 / 总游玩 / 活跃天数).
- Horizontal "最近游玩" & "库中动态 / 待玩" shelf sections with hover arrows and right-click `MenuFlyout`.

- [ ] **Step 5: Verify compilation & run tests**

*(Note: until Task 5 & 6 land, `game_actions.dart` can invoke `Navigator.push` via temporary or direct route calls once Task 5/6 pages are updated, OR rewrite Task 5 & 6 imports cleanly right now by keeping stub class names compatible? Check: existing `GameDetailPage(gameId: id)` and `GameExplorePage(seedGame: seed, libraryGameId: id)` already share those exact class signatures! So importing `detail/game_detail_page.dart` and `discover/game_explore_page.dart` compiles against existing files during Tasks 4–6 and against rewritten files in Tasks 5–6! Verify their constructor names right now with `Select-String` if needed!)*

Let's double-check `GameDetailPage` and `GameExplorePage` constructor parameters before saving the plan (already verified `GameDetailPage` takes `int gameId`? Let's make sure in the plan Task 5/6 keep `GameDetailPage({super.key, required this.gameId})` and `GameExplorePage({super.key, required this.seedGame, this.libraryGameId})` or check via one quick grep right now!). Wait — writing the plan can specify exact constructor signatures cleanly because Tasks 5 and 6 define them explicitly in `Produces:`!

Run tests:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_home_library_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/ui/home/ lib/ui/library/
git add lib/ui/home/ lib/ui/library/ test/fluent_home_library_test.dart
git commit -m "feat(ui): rewrite HomePage and Library subsystem in Fluent 2"
```
Expected: PASS and clean analyzer.

---

### Task 5: Rewrite Game Detail, Play Path Timeline, Edit Dialog, and Rate Dialog

**Files:**
- Create: `lib/ui/detail/play_path_tab.dart`
- Rewrite: `lib/ui/detail/rate_dialog.dart`
- Create: `lib/ui/detail/edit_dialog.dart`
- Rewrite: `lib/ui/detail/game_detail_page.dart`
- Test: `test/fluent_detail_test.dart`

**Interfaces:**
- Consumes: `gameProvider(id)`, `gameSourcesProvider(id)`, `gameTagsProvider(id)`, `playPathProvider(id)`, `trackingGameProvider`, `detailBgBlurProvider`, `playPathVersionProvider`, `showSaveBackupDialog`, `showImagePickerDialog`, `showScrapeSearchDialog`, `showFluentLightboxDialog`
- Produces:
  - `GameDetailPage({super.key, required this.gameId})`
  - `PlayPathTab({super.key, required this.game})`
  - `showEditGameDialog(BuildContext context, WidgetRef ref, Game game)` -> `Future<bool>`
  - `showRateGameDialog(BuildContext context, WidgetRef ref, Game game)` -> `Future<bool>`

- [ ] **Step 1: Write failing widget test for Detail Hero (R18 before score) & Play Path**

Create `test/fluent_detail_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/detail/game_detail_page.dart';

void main() {
  testWidgets('GameDetailPage shows R18 before score and Play Path tab',
      (tester) async {
    final g = Game(
      id: 7,
      name: 'DetailVN',
      nameCn: '详情作品',
      developer: 'Key',
      nsfw: true,
      userRating: 9.6,
      totalSeconds: 10800,
    );
    final nodes = [
      PlayPathNode(id: 1, gameId: 7, note: '第一章结局选择记录'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameProvider(7).overrideWith((ref) async => g),
          gameSourcesProvider(7).overrideWith((ref) async => const []),
          gameTagsProvider(7).overrideWith((ref) async => const []),
          playPathProvider(7).overrideWith((ref) async => nodes),
        ],
        child: const FluentApp(home: GameDetailPage(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('详情作品'), findsWidgets);
    expect(find.text('R18'), findsWidgets);
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('9.6').first).dx;
    expect(r18Dx, lessThan(scoreDx));

    expect(find.text('游玩路径'), findsOneWidget);
    expect(find.text('第一章结局选择记录'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_detail_test.dart`
Expected: FAIL against old Material `GameDetailPage` (fails under `FluentApp`).

- [ ] **Step 3: Implement `lib/ui/detail/rate_dialog.dart` and `lib/ui/detail/edit_dialog.dart`**

Implement `rate_dialog.dart`:
- Fluent `ContentDialog` with interactive `Slider` (`0` to `10`, step `0.1`), quick clear button, live badge preview (`9.2 / 10`), and multiline `TextBox` review note, saving via `AppServices.I.repo.updateGame` + `bumpLibrary(ref)` + `showNotice('已保存评分')`.

Implement `edit_dialog.dart`:
- Fluent `ContentDialog` (`maxWidth: 840, maxHeight: 720`) with a horizontal anchor bar ("基本信息" / "启动与目录" / "存档与备份" / "视觉封面") that smoothly scrolls via `Scrollable.ensureVisible` to `GlobalKey` `Expander` sections (`initiallyExpanded: true`), featuring `TextBox`, `ComboBox<PlayStatus>`, `ToggleSwitch` (NSFW / LE 转区 / 收藏), path browse buttons (`FilePicker`), cover/background pickers (`showImagePickerDialog`), and save button.

- [ ] **Step 4: Implement `lib/ui/detail/play_path_tab.dart` and `lib/ui/detail/game_detail_page.dart`**

Implement `play_path_tab.dart`:
- Top inline quick-composer `FluentSurfaceCard`: note `TextBox` + "导入截图" (`FilePicker.platform.pickFiles(type: FileType.image)`) + "添加节点" `FilledButton`, plus live hotkey indicator reading `SettingsStore.kScreenshotHotkey` ("游戏中按 F12 自动截屏保存至此处").
- Timeline node cards (`playPathProvider(game.id!)`): vertical Win11 timeline spine, timestamp, thumbnail (`InkWell`/`GestureDetector` calling `showFluentLightboxDialog` on click), editable note text (`ContentDialog` quick edit), and delete confirm (`AppServices.I.repo.deletePlayPathNode`). Animated with `.fluentEntrance(index: i)`.

Implement `game_detail_page.dart`:
- Top `BreadcrumbBar` (`游戏库` -> `game.displayName`) + `CommandBar` (Launch / Stop, LE Launch, Explore, Edit, Rate, Save Backup, Scrape, Open Folder, Delete).
- Split Hero header using `FluentAcrylicPanel` over blurred `backgroundUrl`/`coverPath` (`detailBgBlurProvider`) + crisp `FluentCoverImage` + `FluentR18ScoreRow` (**R18 strictly before rating**).
- Segmented Fluent Tab switcher / `TabView` switching between **「游玩路径」**, **「档案与标签」** (summary, aliases, multi-source ratings, clickable `FluentBadge` tags calling `jumpToLibraryFiltered`), and **「会话与存档」**.

- [ ] **Step 5: Run tests, analyze & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_detail_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/ui/detail/
git add lib/ui/detail/ test/fluent_detail_test.dart
git commit -m "feat(ui): rewrite GameDetailPage, PlayPath timeline, and Edit/Rate dialogs in Fluent 2"
```
Expected: PASS and clean analyzer.

---

### Task 6: Rewrite Discover Page, Resource Search, and Game Explore Encyclopedia

**Files:**
- Rewrite: `lib/ui/discover/discover_state.dart`
- Rewrite: `lib/ui/discover/discover_filter_state.dart`
- Rewrite: `lib/ui/discover/resource_links.dart`
- Rewrite: `lib/ui/discover/discover_page.dart`
- Rewrite: `lib/ui/discover/game_explore_page.dart`
- Test: `test/fluent_explore_test.dart`

**Interfaces:**
- Consumes: `MetadataFetcher`, `GameExploreService.instance.loadWorkDetail`, `ResourceSearchService`, `resourceQueryProvider`, `discoverLayoutProvider`, `ScrapeApplier`, `showNotice`, `FluentCoverImage`, `FluentR18ScoreRow`
- Produces:
  - `DiscoverPage({super.key})`
  - `GameExplorePage({super.key, required this.seedGame, this.knownSources = const [], this.localGameId, this.onAdd, this.initialDetail})`
  - 10 clean sub-views inside Explore tabs: 发行资料, 角色与声优, 制作人员, 相关游戏, 媒体, 动画, 音乐, 漫画, 轻小说, 下载资源

- [ ] **Step 1: Write failing widget test enforcing Explore layout & Download tab rule**

Create `test/fluent_explore_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/scraping/scraped_game.dart';
import 'package:kisakigals/services/game_explore_service.dart';
import 'package:kisakigals/ui/discover/game_explore_page.dart';

void main() {
  testWidgets('GameExplorePage renders R18 before score and hides add-to-library on Download tab',
      (tester) async {
    const detail = ExploreWorkDetail(
      cacheKey: 'vndb:v17',
      seedGame: ScrapedGame(source: 'vndb', sourceId: 'v17', name: 'TestWork'),
      title: '测试百科作品',
      nsfw: true,
      ratings: [
        ExploreSourceRating(
          source: 'vndb',
          label: 'VNDB',
          score: 8.9,
          displayScore: '8.9',
          voteCount: 512,
        ),
      ],
      mediaLinks: [
        ExploreExternalLink(
          source: 'steam',
          label: 'Steam 商店页',
          url: 'https://store.steampowered.com',
          isStore: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: FluentApp(
          home: GameExplorePage(
            seedGame: detail.seedGame,
            initialDetail: detail,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No legacy "The Order 全景展台" banner
    expect(find.textContaining('The Order'), findsNothing);

    // R18 before score
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('8.9').first).dx;
    expect(r18Dx, lessThan(scoreDx));

    // Switch to 下载资源 tab & ensure no "入库" button sits on download cards
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.text('Steam 商店页'), findsOneWidget);
    expect(find.text('入库下载'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_explore_test.dart`
Expected: FAIL — `initialDetail` param / Fluent Explore rewrite not yet implemented.

- [ ] **Step 3: Rewrite `discover_state.dart`, `discover_filter_state.dart`, `resource_links.dart`, and `discover_page.dart`**

Preserve existing provider/service queries (`discoverFilterProvider`, `discoverStateProvider`, `resourceQueryProvider` one-shot consumption) using Fluent widgets only:
- Top mode switcher (`发现聚合` vs `资源检索`), `CommandBar` with source selector (`VNDB` / `Bangumi` / `YmGal` etc.), keyword `TextBox`, sort/genre `ComboBox`, grid/list layout toggle, and collapsible right/left Fluent filter rail.
- In "资源检索" mode (`resource_links.dart`), stream `ResourceSearchUpdate` per site using `ProgressBar` / `ProgressRing` and render clean `FluentSurfaceCard` link rows (no "入库" button on download resources).

- [ ] **Step 4: Rewrite `lib/ui/discover/game_explore_page.dart`**

Build a crisp, spacious Windows 11 layout with `ExploreWorkDetail? initialDetail` injection support for fast deterministic testing:
- Top `BreadcrumbBar` (`探索` > `detail.title`) + right refresh/open-library actions (no "The Order 全景展台" promo banner).
- Clean two-column Hero Overview: blurred backdrop + `Acrylic` scrim, left `FluentCoverImage`, right title/aliases/developers/release date, **`FluentR18ScoreRow` enforcing R18 before rating**, summary, and single Hero "一键入库 / 在库中查看" button.
- Fluent horizontal pill/Tab strip switching across: `概览与发行` / `角色与声优` / `制作人员` / `相关游戏` / `媒体` / `动画` / `音乐` / `漫画` / `轻小说` / `下载` (no "入库" buttons inside download cards; clicking Related Works pushes a new `GameExplorePage` seamlessly; clicking screenshots opens `showFluentLightboxDialog`).

- [ ] **Step 5: Run tests, analyze & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_explore_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/ui/discover/
git add lib/ui/discover/ test/fluent_explore_test.dart
git commit -m "feat(ui): rewrite Discover, Resource Search, and GameExplorePage in Fluent 2"
```
Expected: PASS and clean analyzer.

---

### Task 7: Rewrite Stats & Word Cloud, AI Assistant, and Add Game Page

**Files:**
- Rewrite: `lib/ui/stats/word_cloud.dart`
- Rewrite: `lib/ui/stats/stats_page.dart`
- Rewrite: `lib/ui/ai/ai_page.dart`
- Rewrite: `lib/ui/add/add_game_page.dart`
- Test: `test/fluent_secondary_pages_test.dart`

**Interfaces:**
- Consumes: `statsProvider(period)`, `tagCloudProvider(period)`, `ratedGamesProvider`, `aiStateProvider`, `jumpToSettingsSection`, `jumpToLibraryFiltered`, `desktop_drop`, `file_picker`
- Produces:
  - `StatsPage({super.key})` + `FluentTagWordCloud`
  - `AiPage({super.key})`
  - `AddGamePage({super.key, this.initialDropPath})`

- [ ] **Step 1: Write failing widget test for Stats, AI, and AddGamePage inside `FluentApp`**

Create `test/fluent_secondary_pages_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/state/ai_state.dart';
import 'package:kisakigals/ui/add/add_game_page.dart';
import 'package:kisakigals/ui/ai/ai_page.dart';
import 'package:kisakigals/ui/stats/stats_page.dart';

void main() {
  testWidgets('StatsPage renders fl_chart and KPIs inside FluentApp',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statsProvider(StatsPeriod.month).overrideWith(
            (ref) async => AggStats(
              totalSeconds: 14400,
              sessionCount: 6,
              activeDays: 4,
              byWeekday: const [1200, 0, 3600, 0, 2400, 3600, 3600],
            ),
          ),
          tagCloudProvider(StatsPeriod.month).overrideWith(
            (ref) async => [TagItem(name: '纯爱', weight: 12)],
          ),
          ratedGamesProvider.overrideWith((ref) async => const []),
        ],
        child: const FluentApp(home: StatsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('游玩统计'), findsOneWidget);
    expect(find.text('纯爱'), findsOneWidget);
  });

  testWidgets('AiPage shows unconfigured InfoBar linking to settings section 3',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiStateProvider.overrideWith(
            (ref) => _FakeAiController(ref),
          ),
        ],
        child: const FluentApp(home: AiPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InfoBar), findsOneWidget);
    expect(find.textContaining('前往设置'), findsOneWidget);
  });

  testWidgets('AddGamePage shows local drop and online scrape cards',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FluentApp(home: AddGamePage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('本地游戏导入'), findsOneWidget);
    expect(find.text('在线元信息刮削'), findsOneWidget);
  });
}

class _FakeAiController extends AiController {
  _FakeAiController(super.ref) {
    state = const AiState(summaryError: kAiNotConfiguredMsg);
  }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_secondary_pages_test.dart`
Expected: FAIL against old Material pages.

- [ ] **Step 3: Rewrite `lib/ui/stats/word_cloud.dart` and `lib/ui/stats/stats_page.dart`**

- `word_cloud.dart`: Interactive spiral/wrap tag cloud using `FluentTheme.of(context).accentColor` opacity scale + Fluent `Tooltip` + click callback (`jumpToLibraryFiltered(ref, tag: tag.name)`). Zero `material.dart`.
- `stats_page.dart`: Period selector (`StatsPeriod.values`), 4 KPI `FluentSurfaceCard`s, `fl_chart` `BarChart` / `LineChart` styled solely with `FluentTheme.of(context)` colors (`accentColor`, `typography.caption`, `inactiveColor`) and explicit `BarTouchTooltipData(getTooltipColor: (_) => ...)` so `fl_chart` never reads missing Material theme data, plus rated games wall (`ratedGamesProvider`).

- [ ] **Step 4: Rewrite `lib/ui/ai/ai_page.dart` and `lib/ui/add/add_game_page.dart`**

- `ai_page.dart`: Watches `aiStateProvider`. Renders Fluent `InfoBar` with `FilledButton` calling `jumpToSettingsSection(ref, 3)` when `summaryError == kAiNotConfiguredMsg` or `recommendationsError == kAiNotConfiguredMsg`. Displays summary card + recommendation cards (with `ProgressRing` / `Added` / `Exists` state pills from `RecAddState`) and `.fluentShimmer` placeholders while loading.
- `add_game_page.dart`: Wraps page in `DropTarget` for `.exe`/`.lnk`/directory drag-drop, paired with side-by-side Fluent entry cards (Browse local `.exe`/dir vs Online keyword search across `KisakiSources`) and inline `Expander` search results allowing direct one-click library add via `ScrapeApplier`.

- [ ] **Step 5: Run tests, analyze & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_secondary_pages_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/ui/stats/ lib/ui/ai/ lib/ui/add/
git add lib/ui/stats/ lib/ui/ai/ lib/ui/add/ test/fluent_secondary_pages_test.dart
git commit -m "feat(ui): rewrite Stats, AI Assistant, and AddGamePage in Fluent 2"
```
Expected: PASS and clean analyzer.

---

### Task 8: Rewrite Windows 11 Settings Center (`SettingsPage`)

**Files:**
- Rewrite: `lib/ui/settings/settings_page.dart`
- Test: `test/fluent_settings_test.dart`

**Interfaces:**
- Consumes: `themeProvider`, `accentPresetProvider`, `backdropEffectProvider`, `systemAccentColorProvider`, `nsfwModeProvider`, `nsfwBlurProvider`, `detailBgBlurProvider`, `settingsSectionProvider`, `KunOAuthService.instance`, `GithubUpdateChecker`, `BackupService`, `AutostartService`, `AppServices.I.settings`
- Produces: `SettingsPage({super.key})` with all 5 sections (`0`: 外观, `1`: 启动与热键, `2`: 库与账号隐私, `3`: AI 配置, `4`: 备份与更新) responding reactively to `settingsSectionProvider`.

- [ ] **Step 1: Write failing widget test for Settings sections, appearance controls & section 3 AI jump**

Create `test/fluent_settings_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/settings/settings_page.dart';

void main() {
  testWidgets('SettingsPage renders 5 sections and highlights AI section 3',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsSectionProvider.overrideWith((ref) => 3),
        ],
        child: const FluentApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外观与个性化'), findsWidgets);
    expect(find.text('AI 服务设置'), findsWidgets);
    expect(find.text('备份与更新'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_settings_test.dart`
Expected: FAIL against old Material `SettingsPage`.

- [ ] **Step 3: Implement `lib/ui/settings/settings_page.dart`**

Structure with left compact Win11 section list (or sticky top Pill nav on narrow windows) synced bidirectionally with `settingsSectionProvider` + `Scrollable.ensureVisible`:
- **Section 0 (`外观与个性化`)**:
  - ThemeMode `ComboBox<ThemeModePref>` (`system` / `light` / `dark`)
  - Accent Preset visual swatch cards (`AccentPreset.values`) showing live color dot (`systemAccentColorProvider` for `system`)
  - Window Backdrop `ComboBox<BackdropEffectPref>` (`mica` / `tabbed` / `acrylic` / `solid`) calling `ref.read(backdropEffectProvider.notifier).set(...)`
- **Section 1 (`启动、追踪与游玩路径`)**:
  - Autostart `ToggleSwitch` (`AutostartService`)
  - Tracking mode `ComboBox`, after-launch `ComboBox`, close behavior `ComboBox`, focus-on-exit `ToggleSwitch`
  - Locale Emulator path `TextBox` + Browse `Button`
  - Screenshot Hotkey selector / key-press recorder (`kScreenshotHotkey` + `AppServices.I.tracker.reloadCaptureHotkey`)
- **Section 2 (`游戏库、刮削源与隐私`)**:
  - Library roots manager (`kLibraryRoots`), enabled sources `ToggleSwitch` list (`KisakiSources.defaultEnabled`), SearchGal API URL `TextBox`
  - KunGal OAuth Connect / Disconnect card (`KunOAuthService.instance.login/logout`)
  - NSFW mode (`blur` / `placeholder` / `show`) + NSFW blur & Detail bg blur `Slider`s
- **Section 3 (`AI 服务设置`)**:
  - Base URL, API Key (`PasswordBox`), Model name, Max Tokens `NumberBox`, Save & Test Connection `FilledButton`
- **Section 4 (`备份与更新`)**:
  - Data directory indicator/migration, Auto backup `ToggleSwitch` + interval `NumberBox`, Exit backup `ToggleSwitch`, Save backup keep count `NumberBox`, Manual backup / Restore `.kgbak` (`FilePicker`), Check GitHub Updates (`GithubUpdateChecker`) with inline release notes `InfoBar`/`ContentDialog`.

- [ ] **Step 4: Run tests, analyze & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_settings_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/ui/settings/
git add lib/ui/settings/ test/fluent_settings_test.dart
git commit -m "feat(ui): rewrite SettingsPage as Windows 11 Settings center"
```
Expected: PASS and clean analyzer.

---

### Task 9: Rewrite Fluent `AppShell` (`NavigationView`) and Switch `lib/main.dart` to `FluentApp`

**Files:**
- Rewrite: `lib/ui/shell/app_shell.dart`
- Modify: `lib/main.dart:1-388`
- Test: `test/fluent_shell_test.dart`

**Interfaces:**
- Consumes: `tabIndexProvider`, `themeProvider`, `accentPresetProvider`, `backdropEffectProvider`, `systemAccentColorProvider`, `gamesProvider`, `trackingGameProvider`, `nsfwModeProvider`, `Tabs`, `FluentNoticeHost`, `syncWindowBackdrop`, `resolveAccentBaseColor`, all 7 rewritten pages
- Produces:
  - `AppShell({super.key})` built on Fluent `NavigationView` + `NavigationAppBar` + `AutoSuggestBox` + `WindowCaption` + explicit `paneIndexToTab`/`tabToPaneIndex` mapping
  - `KisakiApp` root `FluentApp` with `SystemTheme.onChange` listener, dynamic `syncWindowBackdrop`, `FluentNoticeHost`, and `accentArgb` tray payload

- [ ] **Step 1: Write failing widget test for Fluent `AppShell` navigation mapping**

Create `test/fluent_shell_test.dart`:
```dart
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/shell/app_shell.dart';
import 'package:kisakigals/ui/shell/tabs.dart';

void main() {
  testWidgets('AppShell renders NavigationView and maps pane indices to Tabs accurately',
      (tester) async {
    expect(AppShell.tabToPaneIndex(Tabs.home), 0);
    expect(AppShell.tabToPaneIndex(Tabs.ai), 4);
    expect(AppShell.tabToPaneIndex(Tabs.add), 5);
    expect(AppShell.tabToPaneIndex(Tabs.settings), 6);
    expect(AppShell.paneIndexToTab(5), Tabs.add);
    expect(AppShell.paneIndexToTab(6), Tabs.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeDataProvider.overrideWith(
            (ref) async => HomeData(
              week: AggStats(),
              month: AggStats(),
              all: AggStats(),
              recentGames: const [],
              activity: const [],
              gameCount: 0,
            ),
          ),
          gamesProvider.overrideWith(() => _EmptyGamesNotifier()),
        ],
        child: const FluentApp(home: AppShell(enableWindowHooks: false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationView), findsOneWidget);
    expect(find.byType(AutoSuggestBox<Game>), findsOneWidget);
  });
}

class _EmptyGamesNotifier extends GamesController {
  @override
  Future<List<Game>> build() async => const [];
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `C:\src\flutter\bin\flutter.bat test test/fluent_shell_test.dart`
Expected: FAIL — `AppShell.tabToPaneIndex` / `enableWindowHooks` / `NavigationView` not implemented yet.

- [ ] **Step 3: Rewrite `lib/ui/shell/app_shell.dart`**

Implement `AppShell`:
- Parameter `final bool enableWindowHooks;` (default `true`; disables `windowManager` listener in headless widget tests).
- Static explicit index mapper:
  - `items`: `0=Tabs.home`, `1=Tabs.library`, `2=Tabs.discover`, `3=Tabs.stats`, `4=Tabs.ai`
  - `footerItems` (`PaneItem`s only): `5=Tabs.add`, `6=Tabs.settings` (+ `PaneItemAction` toggles for R18 Blur and Dark/Light theme, which do not consume pane indices!)
- `NavigationAppBar`:
  - `leading`: conditional Fluent Back `IconButton` when nested Navigator can pop, or 20x20 KisakiGals app emblem.
  - `title`: `DragToMoveArea` wrapping compact title + center-constrained `AutoSuggestBox<Game>` searching `gamesProvider.valueOrNull ?? []` and opening `GameDetailPage` on select.
  - `actions`: active tracking pill (`trackingGameProvider`) + custom Win11 Fluent Minimize / Maximize-Restore / Close caption buttons (`windowManager`).
- Body inside active pane: `_LazyKeepAliveTabStack` preserving page state & scroll offsets, transitioning tabs cleanly via `flutter_animate`.
- Preserves `HardwareKeyboard.instance.addHandler` `F12` forwarding/session-end listeners (`AppServices.I.tracker.onSessionEnd`, `onScreenshotCaptured`).

- [ ] **Step 4: Rewrite `lib/main.dart` to initialize `SystemTheme`, `FluentApp`, `FluentLocalizations`, and `accentArgb` tray payload**

Update `lib/main.dart`:
- Remove `package:flutter/material.dart` and old UI imports (`design.dart`, `theme.dart`, `notifications.dart`).
- In `main()`:
  ```dart
  SystemTheme.fallbackColor = kDefaultWin11Azure;
  await SystemTheme.accentColor.load();
  ```
- In `_KisakiAppState`:
  - Listen to `SystemTheme.onChange` -> update `systemAccentColorProvider`.
  - Use `WidgetsBindingObserver` + `ref.listen` on `themeProvider` and `backdropEffectProvider` to call `syncWindowBackdrop(effect: ..., dark: ...)`.
  - Render `FluentApp` with `theme` / `darkTheme` (`buildFluentTheme`), `localizationsDelegates: const [FluentLocalizations.delegate, GlobalWidgetsLocalizations.delegate]` (or `FluentLocalizations.supportedLocales`), `builder` injecting `FluentNoticeHost()` in an `Overlay` over the app child, and `home: const AppShell()`.
  - Extend `_showCustomTrayPopup` IPC payload with `'accentArgb': resolveAccentBaseColor(ref.read(accentPresetProvider), ref.read(systemAccentColorProvider)).toARGB32()`.

- [ ] **Step 5: Run tests, analyze & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat test test/fluent_shell_test.dart
C:\src\flutter\bin\flutter.bat analyze lib/
git add lib/ui/shell/app_shell.dart lib/main.dart test/fluent_shell_test.dart
git commit -m "feat(ui): switch KisakiApp and AppShell to FluentApp and NavigationView"
```
Expected: PASS and clean analyzer across all of `lib/`.

---

### Task 10: Purge Obsolete Legacy UI Files & Assert Zero Material Imports

**Files:**
- Delete:
  - `lib/ui/design.dart`
  - `lib/ui/kit.dart`
  - `lib/ui/theme.dart`
  - `lib/ui/shell/title_bar.dart`
  - `lib/ui/widgets/common.dart`
  - `lib/ui/widgets/filter_sidebar.dart`
  - `lib/ui/widgets/floating_anchor_nav.dart`
  - `lib/ui/widgets/image_picker.dart`
  - `lib/ui/widgets/notifications.dart`
  - `lib/ui/widgets/save_backup_dialog.dart`
  - `lib/ui/widgets/save_dir_picker_dialog.dart`
  - `lib/ui/widgets/scrape_search_sheet.dart`
  - `lib/ui/library/game_card_actions.dart`
  - `lib/ui/detail/edit_sheet.dart`

- [ ] **Step 1: Verify no remaining references to legacy UI files**

Run:
```powershell
Get-ChildItem -Path lib -Recurse -Filter *.dart | Select-String -Pattern "(design|kit|theme|title_bar|floating_anchor_nav|scrape_search_sheet|game_card_actions|edit_sheet|widgets/common|widgets/filter_sidebar|widgets/image_picker|widgets/notifications|widgets/save_backup_dialog|widgets/save_dir_picker_dialog|flutter/material)\.dart"
```
Expected: Zero matches (or only `test/ui_redesign_test.dart` outside `lib/`, which Task 12 replaces; handle Task 12 right after or delete cleanly now—WAIT: if `test/ui_redesign_test.dart` imports deleted files, rewrite `test/ui_redesign_test.dart` BEFORE or IN this step so `flutter test` stays green!).
Let's delete the obsolete files AND update `test/ui_redesign_test.dart` stub/new tests atomically in Task 12, or run Task 10 cleanup + immediately verify `dart analyze lib/`.

- [ ] **Step 2: Delete obsolete legacy UI files and run `dart analyze lib/`**

Run:
```powershell
Remove-Item `
  lib/ui/design.dart, `
  lib/ui/kit.dart, `
  lib/ui/theme.dart, `
  lib/ui/shell/title_bar.dart, `
  lib/ui/widgets/common.dart, `
  lib/ui/widgets/filter_sidebar.dart, `
  lib/ui/widgets/floating_anchor_nav.dart, `
  lib/ui/widgets/image_picker.dart, `
  lib/ui/widgets/notifications.dart, `
  lib/ui/widgets/save_backup_dialog.dart, `
  lib/ui/widgets/save_dir_picker_dialog.dart, `
  lib/ui/widgets/scrape_search_sheet.dart, `
  lib/ui/library/game_card_actions.dart, `
  lib/ui/detail/edit_sheet.dart -Force
C:\src\flutter\bin\flutter.bat analyze lib/
git add -A lib/
git commit -m "chore(ui): remove discarded legacy Material/custom UI files"
```
Expected: `dart analyze lib/` reports `No issues found!`.

---

### Task 11: Sync Win32 Native Tray Popup Palette to Windows 11 Fluent + `accentArgb`

**Files:**
- Modify: `windows/runner/tray_popup.h:20-26`
- Modify: `windows/runner/flutter_window.cpp` (`showPopup` argument extraction)
- Modify: `windows/runner/tray_popup.cpp:294-355`

**Interfaces:**
- Consumes: `MethodChannel('kisaki/tray_menu')` `"showPopup"` map optional `'accentArgb'` (`int` ARGB32, e.g. `0xFF0078D4`)
- Produces: Native Windows 11 Neutral surfaces + dynamic `accent_argb` highlights, active status tint, and border/corner consistency in `KisakiTrayPopup`.

- [ ] **Step 1: Add `accent_argb` field to `TrayPopupData` in `windows/runner/tray_popup.h`**

```cpp
struct TrayPopupData {
  bool dark = false;
  uint32_t accent_argb = 0xFF0078D4;
  std::wstring version;
  std::wstring running_title;
  std::vector<TrayRecentGame> recent_games;
};
```
*(Add `#include <cstdint>` to `tray_popup.h`.)*

- [ ] **Step 2: Parse optional `"accentArgb"` in `windows/runner/flutter_window.cpp`**

Locate `"showPopup"` extraction inside `flutter_window.cpp`:
```cpp
auto accent_it = args->find(flutter::EncodableValue("accentArgb"));
if (accent_it != args->end()) {
  if (auto* v32 = std::get_if<int32_t>(&accent_it->second)) {
    data.accent_argb = static_cast<uint32_t>(*v32);
  } else if (auto* v64 = std::get_if<int64_t>(&accent_it->second)) {
    data.accent_argb = static_cast<uint32_t>(*v64);
  }
}
```

- [ ] **Step 3: Replace hardcoded M3 palette in `windows/runner/tray_popup.cpp` (`Paint`)**

Replace lines 303-347 in `windows/runner/tray_popup.cpp`:
```cpp
  const uint32_t raw_accent =
      data_.accent_argb == 0 ? 0xFF0078D4u : data_.accent_argb;
  const BYTE ar = static_cast<BYTE>((raw_accent >> 16) & 0xFF);
  const BYTE ag = static_cast<BYTE>((raw_accent >> 8) & 0xFF);
  const BYTE ab = static_cast<BYTE>(raw_accent & 0xFF);

  // Windows 11 Fluent 2 Neutral surfaces + dynamic system accent
  const Gdiplus::Color bg_color =
      dark ? Gdiplus::Color(255, 32, 32, 32)
           : Gdiplus::Color(255, 243, 243, 243);
  const Gdiplus::Color card_bg =
      dark ? Gdiplus::Color(255, 44, 44, 44)
           : Gdiplus::Color(255, 255, 255, 255);
  const Gdiplus::Color hover_bg =
      dark ? Gdiplus::Color(255, 56, 56, 56)
           : Gdiplus::Color(255, 234, 234, 234);
  const Gdiplus::Color border_color =
      dark ? Gdiplus::Color(255, 68, 68, 68)
           : Gdiplus::Color(255, 224, 224, 224);
  const Gdiplus::Color ink_color =
      dark ? Gdiplus::Color(255, 245, 245, 245)
           : Gdiplus::Color(255, 27, 27, 27);
  const Gdiplus::Color ink_soft =
      dark ? Gdiplus::Color(255, 178, 178, 178)
           : Gdiplus::Color(255, 108, 108, 108);

  const Gdiplus::Color accent = Gdiplus::Color(255, ar, ag, ab);
  const Gdiplus::Color accent_tint =
      dark ? Gdiplus::Color(48, ar, ag, ab)
           : Gdiplus::Color(32, ar, ag, ab);
  const float luma = 0.2126f * ar + 0.7152f * ag + 0.0722f * ab;
  const Gdiplus::Color on_primary_ink =
      luma > 152.0f ? Gdiplus::Color(255, 20, 20, 20)
                    : Gdiplus::Color(255, 255, 255, 255);
```
Map existing local brush variable usages (`crimson` -> danger/stop `#D13438`, `cyan`/`cyan_ink`/`cyan_tint`/`peach` -> `accent` / `accent_tint`) cleanly across the remainder of `Paint()`, tightening outer border radius to `12.0f` and cards to `8.0f`.

- [ ] **Step 4: Compile C++ runner via Debug/Release build check & commit**

Run:
```powershell
C:\src\flutter\bin\flutter.bat build windows --release
git add windows/runner/tray_popup.h windows/runner/tray_popup.cpp windows/runner/flutter_window.cpp
git commit -m "feat(windows): sync Win32 tray popup palette with Fluent 2 and system accent"
```
Expected: `Built build\windows\x64\runner\Release\kisakigals.exe` succeeds cleanly with 0 C++ errors.

---

### Task 12: Rewrite `test/ui_redesign_test.dart` & Final Full-Suite Verification

**Files:**
- Rewrite: `test/ui_redesign_test.dart`

- [ ] **Step 1: Rewrite `test/ui_redesign_test.dart` for Fluent 2 Architecture**

Replace old M3 assertions with Fluent 2 regression invariants:
- `buildFluentTheme` light/dark/system-accent/preset swatches and transparent scaffolding for `mica`/`tabbed`/`acrylic`.
- `Tabs` + `AppShell.tabToPaneIndex` / `paneIndexToTab` round-trip verification (`0..6`).
- `FluentR18ScoreRow` guarantees R18 badge left of Score badge.
- `NoticeCenter` + `FluentNoticeHost` renders `InfoBar` with `InfoBarSeverity.info`/`error`.
- Full zero-`material.dart` guard check or pure Fluent widget pump across key components.

- [ ] **Step 2: Run full static analysis, full test suite, and clean Windows Release build**

Run:
```powershell
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test
C:\src\flutter\bin\flutter.bat build windows --release
```
Expected:
- `flutter analyze`: `No issues found!`
- `flutter test`: All tests pass (0 failed, 0 skipped)
- `flutter build windows --release`: Built `build\windows\x64\runner\Release\kisakigals.exe` successfully.

- [ ] **Step 3: Commit final test verification & inspect repository state**

Run:
```powershell
git add test/ui_redesign_test.dart
git commit -m "test(ui): rewrite ui_redesign_test for Fluent 2 architecture and verify release build"
git status -s
```
