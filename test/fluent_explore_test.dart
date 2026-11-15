import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/scraping/scraped_game.dart';
import 'package:kisakigals/services/game_explore_service.dart';
import 'package:kisakigals/services/resource_search.dart';
import 'package:kisakigals/ui/discover/discover_page.dart';
import 'package:kisakigals/ui/discover/discover_state.dart';
import 'package:kisakigals/ui/discover/game_explore_page.dart';
import 'package:kisakigals/ui/discover/resource_links.dart';
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_surfaces.dart';

class _FakeDiscoverFeed extends DiscoverFeed {
  _FakeDiscoverFeed(this._items);
  final List<ScrapedGame> _items;

  @override
  Future<DiscoverFeedState> build() async {
    final filter = ref.watch(discoverFilterProvider);
    return DiscoverFeedState(
      items: _items,
      page: 1,
      hasMore: false,
      preloading: false,
      filterKey: filter.key,
    );
  }
}

void main() {
  tearDown(() {
    NoticeCenter.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
      'GameExplorePage renders R18 before score and hides add-to-library on Download tab',
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

    // Switch to 下载 tab & ensure no "入库" button sits on download cards
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.text('Steam 商店页'), findsOneWidget);
    expect(find.text('入库下载'), findsNothing);
    expect(find.text('入库'), findsNothing);
  });

  testWidgets(
      'GameExplorePage renders 10 sub-views, opens lightbox, and pushes related work',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sequelSeed = ScrapedGame(
      source: 'vndb',
      sourceId: 'v99',
      name: 'SequelWork',
      nameCn: '测试续作作品',
    );
    const sequelDetail = ExploreWorkDetail(
      cacheKey: 'vndb:v99',
      seedGame: sequelSeed,
      title: '测试续作作品',
      originalTitle: 'SequelWork',
      summary: '续作百科简介。',
    );

    const detail = ExploreWorkDetail(
      cacheKey: 'vndb:v17',
      seedGame: ScrapedGame(source: 'vndb', sourceId: 'v17', name: 'TestWork'),
      title: '测试百科主作',
      originalTitle: 'TestWork Original',
      aliases: ['TestAlias'],
      developers: ['测试社团'],
      releaseDate: '2024-06-28',
      summary: '这是一段测试百科作品简介。',
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
      releases: [
        ExploreReleaseItem(
          id: 'rel-1',
          title: '完全版',
          kind: 'digital',
          kindLabel: '数字发行',
          date: '2024-06-28',
          languages: ['简体中文'],
          platforms: ['Windows'],
        ),
      ],
      characters: [
        ExploreCharacter(
          id: 'ch-1',
          name: '雪村千秋',
          role: 'main',
          roleLabel: '主角',
          voiceActors: ['佐仓绫音'],
        ),
      ],
      credits: [
        ExploreCreditGroup(
          roleKey: 'scenario',
          roleLabel: '剧本',
          people: [
            ExploreStaffMember(id: 'st-1', name: '田中罗密欧'),
          ],
        ),
      ],
      relatedGames: [
        ExploreRelatedWork(
          id: 'v99',
          source: 'vndb',
          title: '测试续作作品',
          relationLabel: '续作',
          groupLabel: '续作与前传',
          seedGame: sequelSeed,
        ),
      ],
      screenshots: [
        ExploreScreenshot(
          url: '',
          caption: 'OP CG 截图',
        ),
      ],
      animeList: [
        ExploreCrossMediaItem(
          id: 'an-1',
          category: 'anime',
          title: '测试改编动画',
          relationLabel: '改编动画',
        ),
      ],
      musicList: [
        ExploreCrossMediaItem(
          id: 'mu-1',
          category: 'music',
          title: '测试原声集 OST',
          relationLabel: '原声集',
        ),
      ],
      mangaList: [
        ExploreCrossMediaItem(
          id: 'ma-1',
          category: 'manga',
          title: '测试漫画版',
          relationLabel: '改编漫画',
        ),
      ],
      novelList: [
        ExploreCrossMediaItem(
          id: 'no-1',
          category: 'novel',
          title: '测试轻小说',
          relationLabel: '外传小说',
        ),
      ],
    );

    var addCalled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exploreDetailLoaderProvider.overrideWithValue(
            (seed, known, {bool forceRefresh = false}) async => sequelDetail,
          ),
        ],
        child: FluentApp(
          home: GameExplorePage(
            seedGame: detail.seedGame,
            initialDetail: detail,
            onAdd: (_) async {
              addCalled = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Overview sub-views: 发行资料, 角色与声优, 制作人员, 相关游戏
    expect(find.text('发行资料'), findsWidgets);
    expect(find.text('完全版'), findsOneWidget);
    expect(find.text('角色与声优'), findsWidgets);
    expect(find.text('雪村千秋'), findsOneWidget);
    expect(find.text('制作人员'), findsWidgets);
    expect(find.text('田中罗密欧'), findsOneWidget);
    expect(find.text('相关游戏'), findsWidgets);
    expect(find.text('测试续作作品'), findsOneWidget);

    // Single Hero 一键入库 callback
    await tester.tap(find.text('一键入库'));
    await tester.pumpAndSettle();
    expect(addCalled, isTrue);

    // Switch across Media + Anime + Music + Manga + Novel tabs
    await tester.tap(find.text('媒体'));
    await tester.pumpAndSettle();
    expect(find.text('OP CG 截图'), findsOneWidget);

    await tester.tap(find.text('OP CG 截图'));
    await tester.pumpAndSettle();
    expect(find.text('图片预览'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('动画'));
    await tester.pumpAndSettle();
    expect(find.text('测试改编动画'), findsOneWidget);

    await tester.tap(find.text('音乐'));
    await tester.pumpAndSettle();
    expect(find.text('测试原声集 OST'), findsOneWidget);

    await tester.tap(find.text('漫画'));
    await tester.pumpAndSettle();
    expect(find.text('测试漫画版'), findsOneWidget);

    await tester.tap(find.text('轻小说'));
    await tester.pumpAndSettle();
    expect(find.text('测试轻小说'), findsOneWidget);

    // Back to 百科资料 & push Related Work page
    await tester.tap(find.text('百科资料'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('测试续作作品'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试续作作品'));
    await tester.pumpAndSettle();
    expect(find.text('续作百科简介。'), findsWidgets);
  });

  testWidgets(
      'DiscoverPage toggles modes, filters, layout, and streams Resource Search without add-to-library buttons',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sampleGames = [
      ScrapedGame(
        source: 'vndb',
        sourceId: 'v42',
        name: 'Sample VN',
        nameCn: '样例视觉小说',
        developer: '测试开发商',
        releaseDate: '2023-08-18',
        rating: 8.7,
        voteCount: 300,
        nsfw: true,
      ),
    ];

    final searchedKeywords = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discoverLibraryIndexProvider.overrideWith((ref) async => const {}),
          discoverFeedProvider.overrideWith(() => _FakeDiscoverFeed(sampleGames)),
          resourceSearchRunnerProvider.overrideWithValue((keyword) async* {
            searchedKeywords.add(keyword);
            yield ResourceSearchUpdate(
              completed: 1,
              total: 2,
              result: ResourceSourceResult(
                site: '鲲Galgame',
                tags: const [ResourceTag.noLogin],
                items: const [
                  ResourceItem(
                    site: '鲲Galgame',
                    title: '千恋万花 官方中文硬盘版',
                    url: 'https://example.com/resource/1',
                    tags: [ResourceTag.noLogin],
                  ),
                ],
              ),
            );
            yield const ResourceSearchUpdate(
              completed: 2,
              total: 2,
              done: true,
            );
          }),
        ],
        child: const FluentApp(
          home: ScaffoldPage(content: DiscoverPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现聚合'), findsOneWidget);
    expect(find.text('资源检索'), findsOneWidget);
    expect(find.text('样例视觉小说'), findsOneWidget);

    // R18 strictly left of Score badge on Discover card
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('8.7').first).dx;
    expect(r18Dx, lessThan(scoreDx));

    // Toggle layout grid -> list
    await tester.tap(find.byTooltip('切换视图'));
    await tester.pumpAndSettle();
    expect(find.text('样例视觉小说'), findsOneWidget);

    // Open filter rail & verify filter controls
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    expect(find.text('最低评分'), findsOneWidget);
    expect(find.text('仅全年龄'), findsOneWidget);

    // Switch to 资源检索 mode & run search
    await tester.tap(find.text('资源检索'));
    await tester.pumpAndSettle();

    final searchBox = find.byType(TextBox).first;
    await tester.enterText(searchBox, '千恋万花');
    await tester.tap(find.text('检索'));
    await tester.pumpAndSettle();

    expect(searchedKeywords, contains('千恋万花'));
    expect(find.text('千恋万花 官方中文硬盘版'), findsOneWidget);
    expect(find.byType(FluentSurfaceCard), findsWidgets);
    expect(find.text('入库'), findsNothing);
    expect(find.text('入库下载'), findsNothing);
    expect(find.text('一键入库'), findsNothing);
  });

  testWidgets('DiscoverPage consumes resourceQueryProvider one-shot',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        discoverLibraryIndexProvider.overrideWith((ref) async => const {}),
        discoverFeedProvider.overrideWith(
          () => _FakeDiscoverFeed(const []),
        ),
        resourceSearchRunnerProvider.overrideWithValue((keyword) async* {
          yield const ResourceSearchUpdate(completed: 1, total: 1, done: true);
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(resourceQueryProvider.notifier).state = '星之终途';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FluentApp(
          home: ScaffoldPage(content: DiscoverPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(resourceQueryProvider), isEmpty);
    expect(container.read(discoverFilterProvider).keyword, '星之终途');
  });
}
