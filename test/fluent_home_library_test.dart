import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';
import 'package:kisakigals/ui/home/home_page.dart';
import 'package:kisakigals/ui/library/filter_rail.dart';
import 'package:kisakigals/ui/library/game_card.dart';
import 'package:kisakigals/ui/library/game_list_tile.dart';
import 'package:kisakigals/ui/library/library_page.dart';
import 'package:kisakigals/ui/shell/tabs.dart';

Widget _fluentHost({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: FluentApp(
      theme: buildFluentTheme(
        brightness: Brightness.light,
        preset: AccentPreset.azure,
        systemAccent: kDefaultWin11Azure,
        backdrop: BackdropEffectPref.solid,
      ),
      home: child,
    ),
  );
}

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
      activity: [
        ActivityItem(
          type: 'played',
          gameId: 1,
          gameName: '樱花测试作',
          coverPath: '',
          at: DateTime(2026, 11, 14),
        ),
      ],
      gameCount: 12,
    );

    await tester.pumpWidget(
      _fluentHost(
        overrides: [
          homeDataProvider.overrideWith((ref) async => fakeHome),
          gamesProvider.overrideWith(() => _FakeGamesController([
                Game(
                  id: 2,
                  name: 'Wish Game',
                  nameCn: '待玩测试作',
                  playStatus: PlayStatus.wish,
                ),
              ])),
          allTagsProvider.overrideWith((ref) async => const []),
        ],
        child: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('樱花测试作'), findsWidgets);
    expect(find.text('R18'), findsWidgets);
    expect(find.text('总入库'), findsOneWidget);
    expect(find.text('本周游玩'), findsOneWidget);
    expect(find.text('总游玩'), findsOneWidget);
    expect(find.text('活跃天数'), findsOneWidget);
    expect(find.text('最近游玩'), findsOneWidget);
    expect(find.text('待玩测试作'), findsWidgets);

    // R18 appears strictly before rating in Spotlight
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('9.4').first).dx;
    expect(r18Dx, lessThan(scoreDx));
  });

  testWidgets('HomePage Spotlight shows stop session button when running',
      (tester) async {
    final fakeHome = HomeData(
      week: AggStats(totalSeconds: 3600, sessionCount: 1, activeDays: 1),
      month: AggStats(totalSeconds: 3600, sessionCount: 1, activeDays: 1),
      all: AggStats(totalSeconds: 3600, sessionCount: 1, activeDays: 1),
      recentGames: [
        Game(
          id: 9,
          name: 'Running VN',
          nameCn: '运行中作品',
          playStatus: PlayStatus.playing,
          lastPlayedAt: DateTime(2026, 11, 15),
        ),
      ],
      activity: const [],
      gameCount: 1,
    );

    await tester.pumpWidget(
      _fluentHost(
        overrides: [
          homeDataProvider.overrideWith((ref) async => fakeHome),
          gamesProvider.overrideWith(() => _FakeGamesController(const [])),
          allTagsProvider.overrideWith((ref) async => const []),
          trackingGameProvider.overrideWith((ref) => 9),
        ],
        child: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('停止会话'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('探索百科'), findsOneWidget);
  });

  testWidgets('FluentGameCard shows title and status without Material errors',
      (tester) async {
    final g = Game(
      id: 2,
      name: 'TestVN',
      nameCn: '测试视觉小说',
      nsfw: true,
      userRating: 8.5,
      playStatus: PlayStatus.playing,
    );
    await tester.pumpWidget(
      _fluentHost(
        child: Center(
          child: SizedBox(
            width: 220,
            height: 320,
            child: FluentGameCard(game: g),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试视觉小说'), findsOneWidget);
    expect(find.text('在玩'), findsOneWidget);
    final r18Dx = tester.getTopLeft(find.text('R18')).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('8.5')).dx;
    expect(r18Dx, lessThan(scoreDx));
  });

  testWidgets('FluentGameCard hover strip and right-click MenuFlyout work',
      (tester) async {
    final g = Game(
      id: 3,
      name: 'MenuTest',
      nameCn: '右键菜单测试作',
      directory: 'C:/Games/MenuTest',
      isFavorite: false,
    );
    await tester.pumpWidget(
      _fluentHost(
        child: ScaffoldPage(
          content: Center(
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

    // Hover card to reveal Acrylic bottom action strip
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(FluentGameCard)));
    await tester.pumpAndSettle();

    expect(find.text('启动'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);

    // Secondary tap opens MenuFlyout
    await tester.tapAt(
      tester.getCenter(find.byType(FluentGameCard)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(MenuFlyout), findsOneWidget);
    expect(find.text('启动游戏'), findsOneWidget);
    expect(find.text('LE 转区启动'), findsNothing);
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('探索百科'), findsOneWidget);
    expect(find.text('存档备份'), findsOneWidget);
    expect(find.text('打开目录'), findsOneWidget);
    expect(find.text('移出库'), findsOneWidget);
  });

  testWidgets('FluentGameListTile renders R18 before score and opens MenuFlyout',
      (tester) async {
    final g = Game(
      id: 4,
      name: 'ListTileTest',
      nameCn: '列表条目测试',
      developer: 'Key',
      nsfw: true,
      userRating: 9.1,
      playStatus: PlayStatus.played,
      totalSeconds: 7200,
    );
    await tester.pumpWidget(
      _fluentHost(
        child: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 680,
              child: FluentGameListTile(game: g),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('列表条目测试'), findsOneWidget);
    final r18Dx = tester.getTopLeft(find.text('R18')).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('9.1')).dx;
    expect(r18Dx, lessThan(scoreDx));

    await tester.tapAt(
      tester.getCenter(find.byType(FluentGameListTile)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(MenuFlyout), findsOneWidget);
    expect(find.text('启动游戏'), findsOneWidget);
  });

  testWidgets('FilterRail updates libraryFilterProvider and clears filters',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        allTagsProvider.overrideWith(
            (ref) async => [TagItem(name: '纯爱'), TagItem(name: '悬疑')]),
        developersProvider.overrideWith((ref) async => ['Yuzusoft', 'Key']),
        usedSourcesProvider.overrideWith((ref) async => ['vndb', 'bgm']),
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
          home: const ScaffoldPage(
            content: SizedBox(
              height: 600,
              child: FilterRail(visible: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('在玩'), findsOneWidget);
    expect(find.text('纯爱'), findsOneWidget);

    await tester.tap(find.text('在玩'));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).status, PlayStatus.playing);

    await tester.tap(find.byType(ToggleSwitch));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).favoriteOnly, isTrue);

    await tester.ensureVisible(find.text('纯爱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯爱'));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).tag, '纯爱');

    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    final filter = container.read(libraryFilterProvider);
    expect(filter.status, isNull);
    expect(filter.favoriteOnly, isFalse);
    expect(filter.tag, isNull);
    expect(filter.hasActive, isFalse);
  });

  testWidgets(
      'LibraryPage renders DropTarget, CommandBar, layout toggle, FilterRail, no duplicate search bar, and unifies Add Game with Tabs.add',
      (tester) async {
    final sampleGames = [
      Game(
        id: 10,
        name: 'Clannad',
        nameCn: '团子大家族',
        developer: 'Key',
        playStatus: PlayStatus.played,
        userRating: 9.8,
      ),
      Game(
        id: 11,
        name: 'Sabbat',
        nameCn: '魔女的夜宴',
        developer: 'Yuzusoft',
        nsfw: true,
        playStatus: PlayStatus.playing,
        userRating: 8.9,
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        gamesProvider.overrideWith(() => _FakeGamesController(sampleGames)),
        platformRatingsProvider.overrideWith((ref) async => const {}),
        allTagsProvider.overrideWith((ref) async => [TagItem(name: '催泪')]),
        developersProvider.overrideWith((ref) async => ['Key', 'Yuzusoft']),
        usedSourcesProvider.overrideWith((ref) async => ['vndb']),
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
          home: const LibraryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropTarget), findsOneWidget);
    expect(find.byType(CommandBar), findsOneWidget);
    expect(find.byType(FluentGameCard), findsNWidgets(2));
    expect(find.byType(FluentGameListTile), findsNothing);
    // No duplicate search box inside LibraryPage itself (TitleBar search box handles it)
    expect(find.byType(TextBox), findsNothing);
    expect(find.text('添加游戏'), findsOneWidget);
    expect(find.text('刷新库'), findsOneWidget);

    // Toggle grid -> list layout
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(find.byType(FluentGameListTile), findsNWidgets(2));
    expect(find.byType(FluentGameCard), findsNothing);

    // Toggle FilterRail open
    expect(find.byType(FilterRail), findsOneWidget);
    await tester.tap(find.text('筛选栏'));
    await tester.pumpAndSettle();
    expect(find.text('清除筛选'), findsOneWidget);

    // Clicking "添加游戏" switches unified Add tab instead of pushing a separate route
    await tester.tap(find.text('添加游戏'));
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), Tabs.add);
  });
}

class _FakeGamesController extends GamesController {
  final List<Game> items;
  _FakeGamesController(this.items);

  @override
  Future<List<Game>> build() async => items;
}
