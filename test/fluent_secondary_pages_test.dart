import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
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
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_surfaces.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';
import 'package:kisakigals/ui/shell/tabs.dart';
import 'package:kisakigals/ui/stats/stats_page.dart';
import 'package:kisakigals/ui/stats/word_cloud.dart';

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
  final app = FluentApp(theme: theme, home: child);
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return ProviderScope(overrides: overrides, child: app);
}

void main() {
  tearDown(() {
    NoticeCenter.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('StatsPage renders fl_chart and KPIs inside FluentApp',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        statsProvider(StatsPeriod.month).overrideWith(
          (ref) async => AggStats(
            totalSeconds: 14400,
            sessionCount: 6,
            activeDays: 4,
            byHour: List<int>.generate(24, (i) => i == 21 ? 7200 : 300),
            byWeekday: const [1200, 0, 3600, 0, 2400, 3600, 3600],
            daily: [
              DailyPoint('2026-11-14', 3600),
              DailyPoint('2026-11-15', 7200),
            ],
            topGames: [TopGame(1, '千恋万花', 10800)],
          ),
        ),
        tagCloudProvider(StatsPeriod.month).overrideWith(
          (ref) async => [
            TagItem(name: '纯爱', weight: 12),
            TagItem(name: '催泪', weight: 6),
          ],
        ),
        ratedGamesProvider.overrideWith(
          (ref) async => [
            Game(
              id: 1,
              name: 'Senren',
              nameCn: '千恋万花',
              nsfw: true,
              userRating: 9.2,
              userReview: '节奏轻快甜度满分',
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _fluentHost(container: container, child: const StatsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('游玩统计'), findsOneWidget);
    expect(find.text('纯爱'), findsOneWidget);
    expect(find.byType(FluentTagWordCloud), findsOneWidget);
    expect(find.byType(BarChart), findsWidgets);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('总游玩时长'), findsOneWidget);
    expect(find.text('游玩次数'), findsOneWidget);
    expect(find.text('活跃天数'), findsOneWidget);
    expect(find.text('日均时长'), findsOneWidget);
    expect(find.text('千恋万花'), findsWidgets);

    // R18 badge appears strictly before score on rated game card
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('9.2').first).dx;
    expect(r18Dx, lessThan(scoreDx));

    // Clicking a tag jumps to Library filtered by that tag
    await tester.ensureVisible(find.text('纯爱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯爱'));
    await tester.pumpAndSettle();

    expect(container.read(libraryFilterProvider).tag, '纯爱');
    expect(container.read(tabIndexProvider), Tabs.library);
  });

  testWidgets('StatsPage switches period and updates stats queries',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _fluentHost(
        overrides: [
          statsProvider(StatsPeriod.month).overrideWith(
            (ref) async => AggStats(totalSeconds: 3600, sessionCount: 2),
          ),
          statsProvider(StatsPeriod.week).overrideWith(
            (ref) async => AggStats(
              totalSeconds: 18000,
              sessionCount: 9,
              activeDays: 5,
            ),
          ),
          tagCloudProvider(StatsPeriod.month).overrideWith((ref) async => const []),
          tagCloudProvider(StatsPeriod.week).overrideWith(
            (ref) async => [TagItem(name: '校园', weight: 8)],
          ),
          ratedGamesProvider.overrideWith((ref) async => const []),
        ],
        child: const StatsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 次'), findsOneWidget);

    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();

    expect(find.text('9 次'), findsOneWidget);
    expect(find.text('校园'), findsOneWidget);
  });

  testWidgets('AiPage shows unconfigured InfoBar linking to SettingsSections.ai',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        aiStateProvider.overrideWith(
          (ref) => _FakeAiController(
            ref,
            const AiState(summaryError: kAiNotConfiguredMsg),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _fluentHost(container: container, child: const AiPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InfoBar), findsOneWidget);
    expect(find.textContaining('前往设置'), findsOneWidget);

    await tester.tap(find.textContaining('前往设置').first);
    await tester.pumpAndSettle();

    expect(container.read(settingsSectionProvider), SettingsSections.ai);
    expect(container.read(tabIndexProvider), Tabs.settings);
  });

  testWidgets('AiPage renders shimmer while loading and recommendation states',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late _FakeAiController controller;
    await tester.pumpWidget(
      _fluentHost(
        overrides: [
          aiStateProvider.overrideWith((ref) {
            controller = _FakeAiController(
              ref,
              const AiState(
                summarizing: true,
                loadingRecommendations: true,
              ),
            );
            return controller;
          }),
        ],
        child: const AiPage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(ProgressRing), findsWidgets);
    expect(find.text('正在结合游玩数据生成总结…'), findsOneWidget);

    controller.setTestState(
      AiState(
        summary: '你偏好纯爱与日常向作品，平均每次游玩约两小时。',
        recommendations: [
          AiRecommendation(
            title: 'ATRI',
            reason: '短小精悍的末日治愈系佳作',
            tags: const ['科幻', '治愈'],
          ),
          AiRecommendation(
            title: 'Clannad',
            reason: '感人至深的家族物语',
            tags: const ['催泪'],
          ),
          AiRecommendation(
            title: 'Sabbat',
            reason: '轻松甜美的奇幻日常',
            tags: const ['奇幻'],
          ),
          AiRecommendation(
            title: 'Summer Pockets',
            reason: '夏日海岛的青春回忆',
            tags: const ['夏日'],
          ),
        ],
        addStates: const {
          'ATRI': RecAddState.added,
          'Clannad': RecAddState.exists,
          'Sabbat': RecAddState.failed,
          'Summer Pockets': RecAddState.idle,
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('你偏好纯爱与日常向作品'), findsOneWidget);
    expect(find.text('已入库'), findsOneWidget);
    expect(find.text('已在库'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget);

    await tester.ensureVisible(find.text('加入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(controller.addedTitles, contains('Summer Pockets'));
  });

  testWidgets('AddGamePage shows local drop and online scrape cards',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tempDir = Directory.systemTemp.createTempSync('kisaki_add_page_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final fakeExe = File('${tempDir.path}/SenrenBanka.exe')
      ..writeAsStringSync('stub');

    final searchedKeywords = <String>[];
    List<ScrapedGame>? addedGames;
    String? addedExe;

    final hit = ScrapedGame(
      source: KisakiSources.vndb,
      sourceId: 'v19073',
      name: '千恋＊万花',
      nameCn: '千恋万花',
      developer: 'ゆずソフト',
      releaseDate: '2016-07-29',
      summary: '在穗织邂逅巫女与刀剑的故事。',
      rating: 8.6,
      voteCount: 3200,
      nsfw: true,
      tags: const [ScrapedTag('纯爱', weight: 3.0)],
    );
    final group = ScrapeHitGroup(hit, [hit], 95);

    await tester.pumpWidget(
      _fluentHost(
        child: AddGamePage(
          initialDropPath: fakeExe.path,
          onSearch: (kw, sources) async {
            searchedKeywords.add(kw);
            return [group];
          },
          onMergeGroup: (g) async => [g.merged],
          onAddScraped: (all, {exePath = '', directory = ''}) async {
            addedGames = all;
            addedExe = exePath;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropTarget), findsOneWidget);
    expect(find.text('本地游戏导入'), findsOneWidget);
    expect(find.text('在线元信息刮削'), findsOneWidget);
    expect(find.byType(FluentSurfaceCard), findsWidgets);

    // Search query auto-populated from initialDropPath executable name
    await tester.enterText(find.byType(TextBox).last, '千恋万花');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    expect(searchedKeywords, contains('千恋万花'));
    expect(find.byType(Expander), findsOneWidget);

    // R18 badge strictly before score
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('8.6').first).dx;
    expect(r18Dx, lessThan(scoreDx));

    // One-click add via Expander button
    await tester.ensureVisible(find.text('一键入库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一键入库'));
    await tester.pumpAndSettle();

    expect(addedGames, isNotNull);
    expect(addedGames!.first.sourceId, 'v19073');
    expect(addedExe, fakeExe.path);

    NoticeCenter.instance.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('AddGamePage respects initialQuery from Library search jump',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _fluentHost(
        child: const AddGamePage(initialQuery: 'ATRI -My Dear Moments-'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ATRI -My Dear Moments-'), findsOneWidget);
  });
}

class _FakeAiController extends AiController {
  _FakeAiController(super.ref, AiState initial) {
    state = initial;
  }

  final List<String> addedTitles = [];

  void setTestState(AiState next) {
    state = next;
  }

  @override
  Future<void> addRecommendation(AiRecommendation rec) async {
    addedTitles.add(rec.title);
  }
}
