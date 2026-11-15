import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/scraping/scraped_game.dart';
import 'package:kisakigals/services/ai_service.dart';
import 'package:kisakigals/state/ai_state.dart';
import 'package:kisakigals/ui/add/add_game_page.dart';
import 'package:kisakigals/ui/ai/ai_page.dart';
import 'package:kisakigals/ui/discover/discover_page.dart';
import 'package:kisakigals/ui/discover/discover_state.dart';
import 'package:kisakigals/ui/fluent/fluent_icons.dart';
import 'package:kisakigals/ui/fluent/fluent_motion.dart';
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_surfaces.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';
import 'package:kisakigals/ui/home/home_page.dart';
import 'package:kisakigals/ui/library/library_page.dart';
import 'package:kisakigals/ui/settings/settings_page.dart';
import 'package:kisakigals/ui/shell/app_shell.dart';
import 'package:kisakigals/ui/shell/tabs.dart';
import 'package:kisakigals/ui/stats/stats_page.dart';

class _FakeGamesNotifier extends GamesController {
  _FakeGamesNotifier(this._games);
  final List<Game> _games;

  @override
  Future<List<Game>> build() async => _games;
}

class _FakeThemeController extends StateNotifier<ThemeModePref>
    implements ThemeController {
  _FakeThemeController([super.initial = ThemeModePref.light]);

  @override
  Future<void> set(ThemeModePref pref) async {
    state = pref;
  }
}

class _FakeAccentPresetController extends StateNotifier<AccentPreset>
    implements AccentPresetController {
  _FakeAccentPresetController([super.initial = AccentPreset.azure]);

  @override
  Future<void> set(AccentPreset preset) async {
    state = preset;
  }
}

class _FakeBackdropEffectController extends StateNotifier<BackdropEffectPref>
    implements BackdropEffectController {
  _FakeBackdropEffectController([super.initial = BackdropEffectPref.solid]);

  @override
  Future<void> set(BackdropEffectPref effect) async {
    state = effect;
  }
}

class _FakeDiscoverFeed extends DiscoverFeed {
  @override
  Future<DiscoverFeedState> build() async => DiscoverFeedState(
        items: const <ScrapedGame>[],
        page: 1,
        hasMore: false,
        preloading: false,
        filterKey: ref.watch(discoverFilterProvider).key,
      );
}

class _FakeAiController extends StateNotifier<AiState> implements AiController {
  _FakeAiController() : super(const AiState());

  @override
  Future<void> addRecommendation(AiRecommendation rec) async {}

  @override
  Future<void> generateRecommendations() async {}

  @override
  Future<void> generateSummary() async {}

  @override
  Future<String> gatherPlayData() async => '';
}

HomeData _emptyHomeData() => HomeData(
      week: AggStats(),
      month: AggStats(),
      all: AggStats(),
      recentGames: const [],
      activity: const [],
      gameCount: 0,
    );

List<Override> _shellOverrides({
  List<Game> games = const [],
  ThemeModePref initialTheme = ThemeModePref.light,
}) =>
    [
      homeDataProvider.overrideWith((ref) async => _emptyHomeData()),
      gamesProvider.overrideWith(() => _FakeGamesNotifier(games)),
      allTagsProvider.overrideWith((ref) async => const []),
      developersProvider.overrideWith((ref) async => const []),
      usedSourcesProvider.overrideWith((ref) async => const []),
      platformRatingsProvider.overrideWith((ref) async => const {}),
      discoverFeedProvider.overrideWith(() => _FakeDiscoverFeed()),
      discoverLibraryIndexProvider.overrideWith((ref) async => const {}),
      statsProvider(StatsPeriod.month).overrideWith((ref) async => AggStats()),
      tagCloudProvider(StatsPeriod.month).overrideWith((ref) async => const []),
      ratedGamesProvider.overrideWith((ref) async => const []),
      aiStateProvider.overrideWith((ref) => _FakeAiController()),
      themeProvider.overrideWith((ref) => _FakeThemeController(initialTheme)),
      accentPresetProvider.overrideWith((ref) => _FakeAccentPresetController()),
      backdropEffectProvider
          .overrideWith((ref) => _FakeBackdropEffectController()),
      systemAccentColorProvider.overrideWith((ref) => kDefaultWin11Azure),
    ];

void main() {
  setUpAll(() {
    Animate.restartOnHotReload = false;
  });

  tearDownAll(() {
    Animate.restartOnHotReload = true;
  });

  tearDown(() {
    NoticeCenter.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('fluentAnimationsDisabled respects MediaQuery.disableAnimations', () {
    // Verified via widget pump test below
  });

  testWidgets(
      'fluentAnimationsDisabled accurately detects animation preferences',
      (tester) async {
    late bool disabledWhenTrue;
    late bool disabledWhenFalse;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            disabledWhenTrue = fluentAnimationsDisabled(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(disabledWhenTrue, isTrue);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(
          builder: (context) {
            disabledWhenFalse = fluentAnimationsDisabled(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(disabledWhenFalse, isFalse);
  });

  test('buildFluentTheme correctly builds light/dark themes and accent swatches',
      () {
    const customAccent = Color(0xFF1E88E5);

    // Light Theme with Azure preset
    final lightAzure = buildFluentTheme(
      brightness: Brightness.light,
      preset: AccentPreset.azure,
      systemAccent: customAccent,
      backdrop: BackdropEffectPref.mica,
    );
    expect(lightAzure.brightness, Brightness.light);
    expect(lightAzure.accentColor.normal, kDefaultWin11Azure);
    expect(lightAzure.scaffoldBackgroundColor, Colors.transparent);
    expect(lightAzure.micaBackgroundColor, const Color(0xFFF3F3F3));
    expect(lightAzure.cardColor, const Color(0xFFFBFBFB));

    // Dark Theme with Sakura preset
    final darkSakura = buildFluentTheme(
      brightness: Brightness.dark,
      preset: AccentPreset.sakura,
      systemAccent: customAccent,
      backdrop: BackdropEffectPref.tabbed,
    );
    expect(darkSakura.brightness, Brightness.dark);
    expect(darkSakura.accentColor.normal, kSakuraAccent);
    expect(darkSakura.scaffoldBackgroundColor, Colors.transparent);
    expect(darkSakura.micaBackgroundColor, const Color(0xFF202020));
    expect(darkSakura.cardColor, const Color(0xFF2B2B2B));

    // Dark Theme with Lavender preset
    final darkLavender = buildFluentTheme(
      brightness: Brightness.dark,
      preset: AccentPreset.lavender,
      systemAccent: customAccent,
      backdrop: BackdropEffectPref.acrylic,
    );
    expect(darkLavender.accentColor.normal, kLavenderAccent);
    expect(darkLavender.scaffoldBackgroundColor, Colors.transparent);

    // System Accent Preset
    final sysTheme = buildFluentTheme(
      brightness: Brightness.light,
      preset: AccentPreset.system,
      systemAccent: customAccent,
      backdrop: BackdropEffectPref.mica,
    );
    expect(sysTheme.accentColor.normal, customAccent);

    // Fallback when system accent is empty (alpha == 0)
    final sysFallback = buildFluentTheme(
      brightness: Brightness.light,
      preset: AccentPreset.system,
      systemAccent: const Color(0x00000000),
      backdrop: BackdropEffectPref.mica,
    );
    expect(sysFallback.accentColor.normal, kDefaultWin11Azure);

    // Solid backdrop uses opaque neutral scaffold background
    final solidLight = buildFluentTheme(
      brightness: Brightness.light,
      preset: AccentPreset.azure,
      systemAccent: customAccent,
      backdrop: BackdropEffectPref.solid,
    );
    expect(solidLight.scaffoldBackgroundColor, const Color(0xFFF3F3F3));

    final solidDark = buildFluentTheme(
      brightness: Brightness.dark,
      preset: AccentPreset.azure,
      systemAccent: customAccent,
      backdrop: BackdropEffectPref.solid,
    );
    expect(solidDark.scaffoldBackgroundColor, const Color(0xFF202020));

    // AccentColor swatch contains all shades
    final swatch = buildFluentAccentSwatch(customAccent);
    expect(swatch.normal, customAccent);
    expect(swatch.darkest, isNotNull);
    expect(swatch.darker, isNotNull);
    expect(swatch.dark, isNotNull);
    expect(swatch.light, isNotNull);
    expect(swatch.lighter, isNotNull);
    expect(swatch.lightest, isNotNull);
  });

  test('Tabs indices (0..6) and AppShell pane conversions round-trip seamlessly',
      () {
    expect(Tabs.home, 0);
    expect(Tabs.library, 1);
    expect(Tabs.discover, 2);
    expect(Tabs.stats, 3);
    expect(Tabs.ai, 4);
    expect(Tabs.settings, 5);
    expect(Tabs.add, 6);
    expect(Tabs.count, 7);

    // Round-trip mapping for all 7 pane items (0..6)
    for (int paneIndex = 0; paneIndex < 7; paneIndex++) {
      final tab = AppShell.paneIndexToTab(paneIndex);
      final mappedPane = AppShell.tabToPaneIndex(tab);
      expect(
        mappedPane,
        paneIndex,
        reason: 'Pane $paneIndex mapped to tab $tab should map back to $paneIndex',
      );
    }

    // Direct mappings check
    expect(AppShell.tabToPaneIndex(Tabs.home), 0);
    expect(AppShell.tabToPaneIndex(Tabs.library), 1);
    expect(AppShell.tabToPaneIndex(Tabs.discover), 2);
    expect(AppShell.tabToPaneIndex(Tabs.stats), 3);
    expect(AppShell.tabToPaneIndex(Tabs.ai), 4);
    expect(AppShell.tabToPaneIndex(Tabs.add), 5);
    expect(AppShell.tabToPaneIndex(Tabs.settings), 6);
    expect(AppShell.tabToPaneIndex(99), 0);

    expect(AppShell.paneIndexToTab(0), Tabs.home);
    expect(AppShell.paneIndexToTab(1), Tabs.library);
    expect(AppShell.paneIndexToTab(2), Tabs.discover);
    expect(AppShell.paneIndexToTab(3), Tabs.stats);
    expect(AppShell.paneIndexToTab(4), Tabs.ai);
    expect(AppShell.paneIndexToTab(5), Tabs.add);
    expect(AppShell.paneIndexToTab(6), Tabs.settings);
    expect(AppShell.paneIndexToTab(99), Tabs.home);
  });

  testWidgets(
      'FluentR18ScoreRow guarantees R18 badge is placed strictly to the left of Score badge',
      (tester) async {
    // When nsfw is true, both R18 and Score badges are present
    await tester.pumpWidget(
      ProviderScope(
        child: FluentApp(
          theme: buildFluentTheme(
            brightness: Brightness.light,
            preset: AccentPreset.azure,
            systemAccent: kDefaultWin11Azure,
            backdrop: BackdropEffectPref.solid,
          ),
          home: const ScaffoldPage(
            content: Center(
              child: FluentR18ScoreRow(
                nsfw: true,
                scoreText: '9.4',
                voteText: '256 票',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final r18Finder = find.text('R18');
    final scoreFinder = find.textContaining('9.4');
    expect(r18Finder, findsOneWidget);
    expect(scoreFinder, findsOneWidget);
    expect(find.byIcon(FluentIcons.star_16_filled), findsOneWidget);

    final r18Position = tester.getTopLeft(r18Finder);
    final scorePosition = tester.getTopLeft(scoreFinder);
    expect(
      r18Position.dx,
      lessThan(scorePosition.dx),
      reason: 'R18 badge must strictly precede Score badge horizontally',
    );

    // When nsfw is false, R18 badge is absent while Score badge remains
    await tester.pumpWidget(
      ProviderScope(
        child: FluentApp(
          theme: buildFluentTheme(
            brightness: Brightness.light,
            preset: AccentPreset.azure,
            systemAccent: kDefaultWin11Azure,
            backdrop: BackdropEffectPref.solid,
          ),
          home: const ScaffoldPage(
            content: Center(
              child: FluentR18ScoreRow(
                nsfw: false,
                scoreText: '8.8',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('R18'), findsNothing);
    expect(find.textContaining('8.8'), findsOneWidget);
  });

  testWidgets(
      'NoticeCenter and FluentNoticeHost render InfoBar with info and error severities',
      (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(
          brightness: Brightness.light,
          preset: AccentPreset.azure,
          systemAccent: kDefaultWin11Azure,
          backdrop: BackdropEffectPref.solid,
        ),
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            const Positioned.fill(child: FluentNoticeHost()),
          ],
        ),
        home: const ScaffoldPage(
          content: Center(child: Text('Notice Test Host')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Show regular info notice
    showNotice('游戏已成功添加至游戏库');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('游戏已成功添加至游戏库'), findsOneWidget);
    final infoBars = tester.widgetList<InfoBar>(find.byType(InfoBar)).toList();
    expect(infoBars.isNotEmpty, isTrue);
    expect(infoBars.any((bar) => bar.severity == InfoBarSeverity.info), isTrue);

    // 2. Show error notice
    showNotice('路径解析失败，文件不存在', error: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('路径解析失败，文件不存在'), findsOneWidget);
    final currentBars = tester.widgetList<InfoBar>(find.byType(InfoBar)).toList();
    expect(currentBars.length, 2);
    expect(currentBars.any((bar) => bar.severity == InfoBarSeverity.error), isTrue);

    // 3. Queue more notices to verify capping at 3 items
    showNotice('通知 3');
    showNotice('通知 4');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(NoticeCenter.instance.items.length, 3);

    // 4. Dismiss via NoticeCenter
    NoticeCenter.instance.clear();
    await tester.pumpAndSettle();
    expect(find.byType(InfoBar), findsNothing);
  });

  testWidgets(
      'AppShell renders NavigationView and allows switching primary tabs without exceptions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sampleGames = [
      Game(
        id: 1,
        name: 'Senren Banka',
        nameCn: '千恋＊万花',
        developer: 'Yuzusoft',
        playStatus: PlayStatus.played,
      ),
      Game(
        id: 2,
        name: 'ATRI -My Dear Moments-',
        nameCn: '亚托莉 -我挚爱的时光-',
        developer: 'ANIPLEX.EXE',
        playStatus: PlayStatus.playing,
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        ..._shellOverrides(games: sampleGames),
        gameProvider(1).overrideWith((ref) async => sampleGames[0]),
        gameProvider(2).overrideWith((ref) async => sampleGames[1]),
        gameSourcesProvider(1).overrideWith((ref) async => const []),
        gameSourcesProvider(2).overrideWith((ref) async => const []),
        gameTagsProvider(1).overrideWith((ref) async => const []),
        gameTagsProvider(2).overrideWith((ref) async => const []),
        playPathProvider(1).overrideWith((ref) async => const []),
        playPathProvider(2).overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: FluentApp(
          theme: buildFluentTheme(
            brightness: Brightness.light,
            preset: AccentPreset.azure,
            systemAccent: kDefaultWin11Azure,
            backdrop: BackdropEffectPref.solid,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AppShell(enableWindowHooks: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial Home tab is loaded
    expect(find.byType(NavigationView), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);

    // Switch to Library tab
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.library}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.library);
    expect(find.byType(LibraryPage), findsOneWidget);

    // Switch to Stats tab
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.stats}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.stats);
    expect(find.byType(StatsPage), findsOneWidget);

    // Switch to AI Assistant tab
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.ai}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.ai);
    expect(find.byType(AiPage), findsOneWidget);

    // Switch to Discover tab
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.discover}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.discover);
    expect(find.byType(DiscoverPage), findsOneWidget);

    // Switch to Add tab (footer pane index 5 -> Tabs.add = 6)
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.add}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.add);
    expect(find.byType(AddGamePage), findsOneWidget);

    // Switch to Settings tab (footer pane index 6 -> Tabs.settings = 5)
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.settings}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.settings);
    expect(find.byType(SettingsPage), findsOneWidget);

    // Switch back to Home tab cleanly
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.home}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.home);
    expect(find.byType(HomePage), findsOneWidget);
  });
}
