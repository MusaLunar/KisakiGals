/// Riverpod 状态：主题、Tab、游戏列表（筛选/排序/搜索）、统计。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_services.dart';
import 'core/constants.dart';
import 'data/models.dart';
import 'data/settings_store.dart';
import 'services/playtime_tracker.dart';
import 'ui/shell/tabs.dart';

// ---------- 应用配置 ----------

class ThemeController extends StateNotifier<ThemeModePref> {
  ThemeController() : super(ThemeModePref.system) {
    AppServices.I.settings.themeMode().then((m) => state = m);
  }

  Future<void> set(ThemeModePref pref) async {
    state = pref;
    await AppServices.I.settings.setString(SettingsStore.kThemeMode, pref.id);
  }
}

final themeProvider = StateNotifierProvider<ThemeController, ThemeModePref>(
    (ref) => ThemeController());

final tabIndexProvider = StateProvider<int>((ref) => Tabs.home);

/// 设置页分区索引（跨页跳转到「设置 → AI」等分区时设置）。
final settingsSectionProvider = StateProvider<int>((ref) => 0);

/// 跳转到设置页的指定分区（设置页内部的分区编号，AI=3）。
///
/// 注意：这里的 [section] 是**设置页内部**的分区索引，和侧栏页面索引
/// （[Tabs]）是两套编号，别混用；页面索引用 `Tabs.settings`。
/// 历史上这里曾写成裸数字 4，正好落到「AI 助手」页，表现为「点了没反应」。
void jumpToSettingsSection(WidgetRef ref, int section) {
  ref.read(settingsSectionProvider.notifier).state = section;
  ref.read(tabIndexProvider.notifier).state = Tabs.settings;
}

/// 库筛选栏展开信号：从详情页点开发商/标签跳转时置 true，
/// 游戏库页监听到后自动展开筛选栏（用户可见"跳过来就是为了筛选"）。
final librarySidebarProvider = StateProvider<bool>((ref) => false);

/// 刷新信号：任何库变更后自增，通知各页重新读取。
final libraryVersionProvider = StateProvider<int>((ref) => 0);

// ---------- NSFW 与外观（封面组件实时响应） ----------

/// NSFW 封面显示模式：blur / placeholder / show。
final nsfwModeProvider = StateProvider<String>((ref) => 'blur');

/// NSFW 模糊强度（0-20）。
final nsfwBlurProvider = StateProvider<double>((ref) => 12);

/// 详情页背景模糊度（0-20）。
final detailBgBlurProvider = StateProvider<double>((ref) => 14);

// ---------- 游戏库 ----------

class LibraryFilter {
  String query = '';
  PlayStatus? status;
  String? tag;
  String? developer;
  String? source;
  bool favoriteOnly = false;
  GameSort sort = GameSort.addedDesc;

  bool get hasActive =>
      query.isNotEmpty ||
      status != null ||
      tag != null ||
      developer != null ||
      source != null ||
      favoriteOnly;

  LibraryFilter clone() => LibraryFilter()
    ..query = query
    ..status = status
    ..tag = tag
    ..developer = developer
    ..source = source
    ..favoriteOnly = favoriteOnly
    ..sort = sort;
}

/// 游戏库排版：`grid` = 大封面网格；`list` = 紧凑列表（左封面右名称，一页看更多）
final libraryLayoutProvider = StateProvider<String>((ref) => 'grid');

/// 资源搜索页的查询词（供跨页跳转预填）
final resourceQueryProvider = StateProvider<String>((ref) => '');

final libraryFilterProvider =
    StateProvider<LibraryFilter>((ref) => LibraryFilter());

class GamesController extends AsyncNotifier<List<Game>> {
  @override
  Future<List<Game>> build() async {
    ref.watch(libraryVersionProvider);
    final filter = ref.watch(libraryFilterProvider);
    final games = await AppServices.I.repo.listGames(
      query: filter.query,
      status: filter.status,
      tag: filter.tag,
      developer: filter.developer,
      source: filter.source,
      favorite: filter.favoriteOnly ? true : null,
      sort: filter.sort,
    );
    if (filter.sort == GameSort.platformRatingDesc) {
      final best = await AppServices.I.repo.bestPlatformRatings();
      games.sort((a, b) =>
          (best[b.id] ?? 0).compareTo(best[a.id] ?? 0));
    }
    return games;
  }

  void refresh() => ref.read(libraryVersionProvider.notifier).state++;
}

final gamesProvider =
    AsyncNotifierProvider<GamesController, List<Game>>(GamesController.new);

/// 库变更后调用：触发所有依赖页刷新。
void bumpLibrary(WidgetRef ref) =>
    ref.read(libraryVersionProvider.notifier).state++;

/// 筛选栏数据：全部标签/开发商/已用来源。
final allTagsProvider = FutureProvider<List<TagItem>>((ref) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.allTags();
});

/// 跳转到游戏库并应用筛选（详情页点开发商/标签时调用）。
void jumpToLibraryFiltered(
  WidgetRef ref, {
  String? developer,
  String? tag,
  String? source,
}) {
  final f = ref.read(libraryFilterProvider);
  f
    ..developer = (developer != null && developer.isNotEmpty) ? developer : null
    ..tag = tag
    ..source = source
    ..status = null
    ..favoriteOnly = false;
  ref.read(tabIndexProvider.notifier).state = Tabs.library;
  // 跳过来是为了按开发商/标签筛选 → 自动展开筛选栏
  if (developer != null || tag != null || source != null) {
    ref.read(librarySidebarProvider.notifier).state = true;
  }
  ref.read(libraryVersionProvider.notifier).state++;
}

final developersProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.developers();
});

final usedSourcesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.usedSources();
});

final gameCountProvider = FutureProvider<int>((ref) {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.gameCount();
});

/// 已评分游戏（**不受游戏库筛选影响**，统计页评分墙专用）。
final ratedGamesProvider = FutureProvider<List<Game>>((ref) async {
  ref.watch(libraryVersionProvider);
  final all = await AppServices.I.repo.listGames(
      sort: GameSort.userRatingDesc);
  return all.where((g) => g.userRating > 0).toList();
});

/// 各游戏的最佳平台评分（卡片角标用，一次查询供全网格共享）。
final platformRatingsProvider = FutureProvider<Map<int, double>>((ref) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.bestPlatformRatings();
});

// ---------- 单个游戏 ----------

final gameProvider =
    FutureProvider.family<Game?, int>((ref, id) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.getGame(id);
});

final gameSourcesProvider = FutureProvider.family<List<SourceRecord>,
    int>((ref, id) async => AppServices.I.repo.sourcesOf(id));

final gameTagsProvider = FutureProvider.family<List<TagItem>, int>(
    (ref, id) async => AppServices.I.repo.tagsOf(id));

// ---------- 主页 ----------

class HomeData {
  final AggStats week;
  final AggStats month;
  final AggStats all;
  final List<Game> recentGames;
  final List<ActivityItem> activity;
  final int gameCount;
  HomeData({
    required this.week,
    required this.month,
    required this.all,
    required this.recentGames,
    required this.activity,
    required this.gameCount,
  });
}

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(libraryVersionProvider);
  final repo = AppServices.I.repo;
  final results = await Future.wait([
    repo.stats(period: StatsPeriod.week),
    repo.stats(period: StatsPeriod.month),
    repo.stats(period: StatsPeriod.all),
    repo.recentActivity(limit: 40),
    repo.gameCount(),
  ]);
  final recent = (await repo.listGames(sort: GameSort.lastPlayedDesc))
      .where((g) => g.lastPlayedAt != null)
      .take(10)
      .toList();
  return HomeData(
    week: results[0] as AggStats,
    month: results[1] as AggStats,
    all: results[2] as AggStats,
    recentGames: recent,
    activity: results[3] as List<ActivityItem>,
    gameCount: results[4] as int,
  );
});

// ---------- 统计 ----------

final statsProvider = FutureProvider.family<AggStats, StatsPeriod>(
    (ref, period) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.stats(period: period);
});

final tagCloudProvider = FutureProvider.family<List<TagItem>, StatsPeriod>(
    (ref, period) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.tagCloud(period: period);
});

// ---------- 游玩监控 ----------

/// 当前正在跟踪的游戏（详情页/主页 Hero 显示"游戏中"）。
final trackingGameProvider = StateProvider<int?>((ref) => null);

final trackerEventsProvider = StreamProvider<PlaySessionEnd>(
    (ref) => AppServices.I.tracker.onSessionEnd);
