import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/discover/discover_filter_state.dart';
import 'package:kisakigals/ui/fluent/fluent_dialogs.dart';
import 'package:kisakigals/ui/fluent/fluent_icons.dart';
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
    final solidDark = buildFluentTheme(
      brightness: Brightness.dark,
      preset: AccentPreset.lavender,
      systemAccent: const Color(0x00000000),
      backdrop: BackdropEffectPref.solid,
    );

    expect(lightSys.brightness, Brightness.light);
    expect(lightSys.typography.body?.fontFamily, kAppFontFamily);
    expect(lightSys.typography.title?.fontFamily, kAppFontFamily);
    expect(lightSys.accentColor.normal, sys);
    expect(lightSys.scaffoldBackgroundColor, const Color(0x00000000));
    expect(
      lightSys.navigationPaneTheme.backgroundColor,
      const Color(0x00000000),
    );
    expect(darkSakura.brightness, Brightness.dark);
    expect(darkSakura.accentColor.normal, const Color(0xFFD85C84));
    expect(solidDark.scaffoldBackgroundColor, const Color(0xFF202020));
    expect(
      solidDark.navigationPaneTheme.backgroundColor,
      const Color(0xFF202020),
    );
    expect(neutralWindowBackground(false), const Color(0xFFF3F3F3));
    expect(neutralWindowBackground(true), const Color(0xFF202020));
    expect(solidDark.accentColor.normal, kLavenderAccent);
    expect(
      resolveAccentBaseColor(AccentPreset.system, const Color(0x00000000)),
      kDefaultWin11Azure,
    );
  });

  test('resolveEffectiveBackdrop downgrades unsupported environments to solid',
      () {
    const win10 = WindowBackdropCaps(
      buildNumber: 19045,
      dwmEnabled: true,
      transparencyEnabled: true,
      isRemoteSession: false,
      highContrast: false,
    );
    expect(
      resolveEffectiveBackdrop(BackdropEffectPref.mica, win10),
      BackdropEffectPref.solid,
    );
    expect(
      resolveEffectiveBackdrop(BackdropEffectPref.tabbed, win10),
      BackdropEffectPref.solid,
    );
    expect(
      resolveEffectiveBackdrop(BackdropEffectPref.acrylic, win10),
      BackdropEffectPref.acrylic,
    );

    const win11Base = WindowBackdropCaps(
      buildNumber: 22000,
      dwmEnabled: true,
      transparencyEnabled: true,
      isRemoteSession: false,
      highContrast: false,
    );
    expect(
      resolveEffectiveBackdrop(BackdropEffectPref.mica, win11Base),
      BackdropEffectPref.mica,
    );
    expect(
      resolveEffectiveBackdrop(BackdropEffectPref.tabbed, win11Base),
      BackdropEffectPref.mica,
    );

    const win1122H2 = WindowBackdropCaps.win11Full();
    expect(
      resolveEffectiveBackdrop(BackdropEffectPref.tabbed, win1122H2),
      BackdropEffectPref.tabbed,
    );

    for (final degraded in [
      const WindowBackdropCaps(
        buildNumber: 22621,
        dwmEnabled: false,
        transparencyEnabled: true,
        isRemoteSession: false,
        highContrast: false,
      ),
      const WindowBackdropCaps(
        buildNumber: 22621,
        dwmEnabled: true,
        transparencyEnabled: false,
        isRemoteSession: false,
        highContrast: false,
      ),
      const WindowBackdropCaps(
        buildNumber: 22621,
        dwmEnabled: true,
        transparencyEnabled: true,
        isRemoteSession: true,
        highContrast: false,
      ),
      const WindowBackdropCaps(
        buildNumber: 22621,
        dwmEnabled: true,
        transparencyEnabled: true,
        isRemoteSession: false,
        highContrast: true,
      ),
      WindowBackdropCaps.fromMap(null),
    ]) {
      expect(
        resolveEffectiveBackdrop(BackdropEffectPref.mica, degraded),
        BackdropEffectPref.solid,
      );
      expect(
        resolveEffectiveBackdrop(BackdropEffectPref.acrylic, degraded),
        BackdropEffectPref.solid,
      );
    }
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
    var backgroundTapped = false;
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
        home: Align(
          alignment: Alignment.bottomLeft,
          child: Button(
            onPressed: () => backgroundTapped = true,
            child: const Text('底层按钮'),
          ),
        ),
      ),
    );

    showNotice('已保存游玩笔记');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(InfoBar), findsOneWidget);
    expect(find.text('已保存游玩笔记'), findsOneWidget);

    // 验证通知层不会阻挡下方非通知区域的点击交互
    await tester.tap(find.text('底层按钮'));
    await tester.pump();
    expect(backgroundTapped, isTrue);

    // 验证悬停关闭按钮不会因缺少 Overlay 崩溃，且可正常关闭通知
    final closeBtn = find.descendant(
      of: find.byType(InfoBar),
      matching: find.byType(IconButton),
    );
    expect(closeBtn, findsOneWidget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(closeBtn));
    await tester.pump();
    await tester.tap(closeBtn);
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
    expect(FluentMotion.standard.inMilliseconds, 220);
    expect(FluentMotion.section.inMilliseconds, 280);
    expect(FluentMotion.enterCurve, Curves.easeOutCubic);
  });

  testWidgets('Fluent surfaces and cover fallback render safely',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nsfwModeProvider.overrideWith((ref) => 'blur'),
          nsfwBlurProvider.overrideWith((ref) => 10.0),
        ],
        child: FluentApp(
          theme: buildFluentTheme(
            brightness: Brightness.dark,
            preset: AccentPreset.sakura,
            systemAccent: kSakuraAccent,
            backdrop: BackdropEffectPref.mica,
          ),
          home: ScaffoldPage(
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FluentSectionHeader(
                    title: '最近游玩',
                    subtitle: '共 3 部作品',
                    icon: FluentIcons.library_20_regular,
                  ),
                  FluentSurfaceCard(
                    onTap: () => tapped = true,
                    child: const Row(
                      children: [
                        FluentCoverImage(
                          pathOrUrl: 'nonexistent/cover.png',
                          nsfw: true,
                          width: 80,
                          height: 120,
                        ),
                        SizedBox(width: 12),
                        FluentStatusPill(status: PlayStatus.playing),
                      ],
                    ),
                  ),
                  const FluentAcrylicPanel(
                    padding: EdgeInsets.all(8),
                    child: Text('Acrylic 浮层'),
                  ),
                  const FluentEmptyState(
                    icon: FluentIcons.library_24_regular,
                    title: '暂无游戏',
                    message: '请先添加作品',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FluentSurfaceCard));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(find.text('R18 已遮罩'), findsOneWidget);
    expect(find.text('在玩'), findsOneWidget);
    expect(find.text('最近游玩'), findsOneWidget);
    expect(find.text('暂无游戏'), findsOneWidget);
  });

  testWidgets('Fluent dialogs confirm, info, and lightbox work cleanly',
      (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(
          brightness: Brightness.light,
          preset: AccentPreset.azure,
          systemAccent: kDefaultWin11Azure,
          backdrop: BackdropEffectPref.mica,
        ),
        home: Builder(
          builder: (context) => Row(
            children: [
              Button(
                onPressed: () async {
                  confirmed = await showFluentConfirmDialog(
                    context,
                    title: '删除确认',
                    content: '确定删除该条目？',
                    destructive: true,
                  );
                },
                child: const Text('打开确认'),
              ),
              Button(
                onPressed: () => showFluentInfoDialog(
                  context,
                  title: '提示信息',
                  content: '操作说明内容',
                ),
                child: const Text('打开提示'),
              ),
              Button(
                onPressed: () => showFluentLightboxDialog(
                  context,
                  pathOrUrl: 'missing/shot.png',
                  caption: '截图注释',
                ),
                child: const Text('打开灯箱'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);

    await tester.tap(find.text('打开提示'));
    await tester.pumpAndSettle();
    expect(find.text('操作说明内容'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('操作说明内容'), findsNothing);

    await tester.tap(find.text('打开灯箱'));
    await tester.pumpAndSettle();
    expect(find.text('截图注释'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('截图注释'), findsNothing);
  });

  testWidgets(
      'ensureFluentScope early-returns when scope is present and wraps missing ancestors',
      (tester) async {
    const marker = SizedBox(key: ValueKey('scope-marker'));
    late Widget directReturn;

    await tester.pumpWidget(
      FluentApp(
        home: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) {
                directReturn = ensureFluentScope(
                  context,
                  marker,
                  ensureOverlay: true,
                );
                return directReturn;
              },
            ),
          ],
        ),
      ),
    );
    expect(identical(directReturn, marker), isTrue);

    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, _) => ensureFluentScope(
          context,
          Builder(
            builder: (innerCtx) {
              expect(FluentTheme.maybeOf(innerCtx), isNotNull);
              expect(
                Localizations.of<FluentLocalizations>(
                  innerCtx,
                  FluentLocalizations,
                ),
                isNotNull,
              );
              expect(Overlay.maybeOf(innerCtx), isNotNull);
              return const Text('Scoped OK');
            },
          ),
          ensureOverlay: true,
        ),
      ),
    );
    expect(find.text('Scoped OK'), findsOneWidget);
  });

  test('KisakiFluentTokens exposes calibrated light and dark semantic colors',
      () {
    final light = buildFluentTheme(
      brightness: Brightness.light,
      preset: AccentPreset.azure,
      systemAccent: kDefaultWin11Azure,
      backdrop: BackdropEffectPref.mica,
    );
    final dark = buildFluentTheme(
      brightness: Brightness.dark,
      preset: AccentPreset.lavender,
      systemAccent: kDefaultWin11Azure,
      backdrop: BackdropEffectPref.mica,
    );

    expect(light.textPrimary.a, greaterThan(0.8));
    expect(light.textSecondary.a, greaterThan(0.5));
    expect(light.onAccentInk, isNot(equals(Colors.transparent)));
    expect(dark.textPrimary, isNot(equals(light.textPrimary)));
    expect(dark.dangerInk, isNot(equals(light.dangerInk)));
    expect(dark.favoriteInk, isNot(equals(light.favoriteInk)));
  });

  test('DiscoverFilter default onlySfw=false matches cleared() and active state',
      () {
    const def = DiscoverFilter();
    expect(def.onlySfw, isFalse);
    expect(def.hasActiveFilters, isFalse);
    expect(def.summary, contains('未筛选'));

    final sfwOnly = def.copyWith(onlySfw: true);
    expect(sfwOnly.hasActiveFilters, isTrue);
    expect(sfwOnly.summary, contains('仅全年龄'));

    final reset = sfwOnly.cleared();
    expect(reset.onlySfw, isFalse);
    expect(reset.hasActiveFilters, isFalse);
  });

  testWidgets('FluentSearchBox supports shortcutHint, clear button, and Escape',
      (tester) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    var clearedCount = 0;
    addTearDown(() {
      ctrl.dispose();
      focus.dispose();
    });

    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(
          brightness: Brightness.light,
          preset: AccentPreset.azure,
          systemAccent: kDefaultWin11Azure,
          backdrop: BackdropEffectPref.solid,
        ),
        home: StatefulBuilder(
          builder: (context, setState) => ScaffoldPage(
            content: Center(
              child: FluentSearchBox(
                controller: ctrl,
                focusNode: focus,
                placeholder: '搜索作品',
                shortcutHint: 'Ctrl+K',
                onChanged: (_) => setState(() {}),
                onCleared: () {
                  clearedCount++;
                  ctrl.clear();
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ctrl+K'), findsOneWidget);

    await tester.enterText(find.byType(TextBox), '千恋万花');
    await tester.pump();
    expect(find.text('Ctrl+K'), findsNothing);
    expect(find.byTooltip('清空搜索'), findsOneWidget);

    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(ctrl.text, isEmpty);
    expect(clearedCount, 1);

    await tester.enterText(find.byType(TextBox), 'ATRI');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(ctrl.text, isEmpty);
    expect(clearedCount, 2);
  });

  testWidgets('FluentSegmentedControl updates selection and shows tooltips',
      (tester) async {
    var current = 'grid';
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(
          brightness: Brightness.light,
          preset: AccentPreset.azure,
          systemAccent: kDefaultWin11Azure,
          backdrop: BackdropEffectPref.solid,
        ),
        home: StatefulBuilder(
          builder: (context, setState) => ScaffoldPage(
            content: Center(
              child: FluentSegmentedControl<String>(
                selected: current,
                onChanged: (next) => setState(() => current = next),
                items: const [
                  FluentSegmentItem<String>(
                    value: 'grid',
                    label: '网格视图',
                    tooltip: '网格视图',
                    icon: FluentIcons.grid_16_regular,
                    showLabel: false,
                  ),
                  FluentSegmentItem<String>(
                    value: 'list',
                    label: '列表视图',
                    tooltip: '列表视图',
                    icon: FluentIcons.text_bullet_list_16_regular,
                    showLabel: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('网格视图'), findsOneWidget);
    expect(find.byTooltip('列表视图'), findsOneWidget);
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(current, 'list');
  });
}
