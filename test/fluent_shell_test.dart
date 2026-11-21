import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/main.dart' show KisakiApp;
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/scraping/scraped_game.dart';
import 'package:kisakigals/services/ai_service.dart';
import 'package:kisakigals/state/ai_state.dart';
import 'package:kisakigals/ui/add/add_game_page.dart';
import 'package:kisakigals/ui/detail/game_detail_page.dart';
import 'package:kisakigals/ui/discover/discover_state.dart';
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';
import 'package:kisakigals/ui/home/home_page.dart';
import 'package:kisakigals/ui/library/library_page.dart';
import 'package:kisakigals/ui/settings/settings_page.dart';
import 'package:kisakigals/ui/shell/app_shell.dart';
import 'package:kisakigals/ui/shell/tabs.dart';

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
  void cancelSummary() {}

  @override
  void cancelRecommendations() {}

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
  tearDown(() {
    NoticeCenter.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('AppShell.tabToPaneIndex and paneIndexToTab map all 7 tabs cleanly', () {
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
      'AppShell renders NavigationView, switches panes, toggles footer actions, and searches games',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sampleGames = [
      Game(
        id: 101,
        name: 'Sabbat of the Witch',
        nameCn: '魔女的夜宴',
        developer: 'Yuzusoft',
        playStatus: PlayStatus.playing,
      ),
      Game(
        id: 102,
        name: 'Summer Pockets',
        nameCn: '夏日口袋',
        developer: 'Key',
        playStatus: PlayStatus.wish,
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        ..._shellOverrides(games: sampleGames),
        gameProvider(101).overrideWith((ref) async => sampleGames.first),
        gameSourcesProvider(101).overrideWith((ref) async => const []),
        gameTagsProvider(101).overrideWith((ref) async => const []),
        playPathProvider(101).overrideWith((ref) async => const []),
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

    expect(find.byType(NavigationView), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is TitleBar), findsOneWidget);
    expect(find.byType(AutoSuggestBox<Game>), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);

    const expectedNavLabels = <(int, String)>[
      (Tabs.home, '主页'),
      (Tabs.library, '游戏库'),
      (Tabs.discover, '探索'),
      (Tabs.stats, '统计'),
      (Tabs.ai, 'AI 助手'),
      (Tabs.add, '入库'),
      (Tabs.settings, '设置'),
    ];
    for (final (tabIdx, label) in expectedNavLabels) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('nav_tab_$tabIdx')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nav_action_nsfw')),
        matching: find.text('R18 已模糊'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nav_action_theme')),
        matching: find.text('切换深色'),
      ),
      findsOneWidget,
    );

    // Switch to Library and verify TitleBar AutoSuggestBox syncs directly with libraryFilterProvider.query
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.library}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.library);
    expect(find.byType(LibraryPage), findsOneWidget);

    await tester.enterText(find.byType(AutoSuggestBox<Game>), 'Key');
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).query, 'Key');

    // Leaving Library clears transient TitleBar text without wiping libraryFilterProvider.query,
    // and AutoSuggestBox search still works from Settings
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.settings}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).query, 'Key');

    // Switch to footer Add (pane index 5 -> Tabs.add = 6)
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.add}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.add);
    expect(find.byType(AddGamePage), findsOneWidget);

    // Switch to footer Settings (pane index 6 -> Tabs.settings = 5)
    await tester.tap(
      find.byKey(const ValueKey('nav_tab_${Tabs.settings}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.settings);
    expect(find.byType(SettingsPage), findsOneWidget);

    // Footer PaneItemActions update nsfwModeProvider & themeProvider without changing selected tab
    expect(container.read(nsfwModeProvider), 'blur');
    await tester.tap(
      find.byKey(const ValueKey('nav_action_nsfw')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(nsfwModeProvider), 'show');
    expect(container.read(tabIndexProvider), Tabs.settings);

    expect(container.read(themeProvider), ThemeModePref.light);
    await tester.tap(
      find.byKey(const ValueKey('nav_action_theme')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(themeProvider), ThemeModePref.dark);
    expect(container.read(tabIndexProvider), Tabs.settings);

    // Search AutoSuggestBox by developer / jpTitle and open GameDetailPage
    await tester.enterText(find.byType(AutoSuggestBox<Game>), 'Yuzusoft');
    await tester.pumpAndSettle();
    expect(find.text('魔女的夜宴'), findsOneWidget);
    expect(find.text('夏日口袋'), findsNothing);

    await tester.tap(find.text('魔女的夜宴'));
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailPage), findsOneWidget);
  });

  testWidgets(
      'AppShell renders active tracking pill and compact layout without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sampleGames = [
      Game(
        id: 7,
        name: 'Clannad',
        nameCn: '团子大家族',
        developer: 'Key',
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        ..._shellOverrides(games: sampleGames),
        trackingGameProvider.overrideWith((ref) => 7),
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

    expect(find.byKey(const ValueKey('active_tracking_pill')), findsOneWidget);
    expect(find.text('团子大家族'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('active_tracking_stop')));
    await tester.pumpAndSettle();
    expect(container.read(trackingGameProvider), isNull);
    NoticeCenter.instance.clear();
  });

  testWidgets('KisakiApp uses FluentApp and renders FluentNoticeHost InfoBar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _shellOverrides(),
        child: const KisakiApp(enableDesktopHooks: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FluentApp), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(FluentNoticeHost), findsOneWidget);

    showNotice('测试 Fluent 通知横幅');
    await tester.pumpAndSettle();

    expect(find.byType(InfoBar), findsOneWidget);
    expect(find.text('测试 Fluent 通知横幅'), findsOneWidget);

    NoticeCenter.instance.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('AppShell quick search caps suggestions at 20 items',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manyGames = [
      for (var i = 1; i <= 25; i++)
        Game(
          id: i,
          name: 'Key Work $i',
          nameCn: 'Key 作品 $i',
          developer: 'Key',
        ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _shellOverrides(games: manyGames),
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

    final boxFinder = find.byType(AutoSuggestBox<Game>);
    final box = tester.widget<AutoSuggestBox<Game>>(boxFinder);
    final results = box.sorter!('Key', box.items);
    expect(results.length, 20);
  });

  testWidgets(
      'AppShell renders left navigation labels at 1080x680 minimum window size',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _shellOverrides(),
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

    const expectedNavLabels = <(int, String)>[
      (Tabs.home, '主页'),
      (Tabs.library, '游戏库'),
      (Tabs.discover, '探索'),
      (Tabs.stats, '统计'),
      (Tabs.ai, 'AI 助手'),
      (Tabs.add, '入库'),
      (Tabs.settings, '设置'),
    ];
    for (final (tabIdx, label) in expectedNavLabels) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('nav_tab_$tabIdx')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });
}
