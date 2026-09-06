/// Riverpod 状态：主题、Tab、游戏列表（筛选/排序/搜索）、统计。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_services.dart';
import 'core/constants.dart';
import 'data/models.dart';
import 'data/settings_store.dart';
import 'services/playtime_tracker.dart';

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

final tabIndexProvider = StateProvider<int>((ref) => 0);

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
final allTagsProvider = FutureProvider<List<TagItem>>(
    (ref) async => ref.watch(libraryVersionProvider) >= 0
        ? AppServices.I.repo.allTags()
        : []);

final developersProvider = FutureProvider<List<String>>(
    (ref) async => AppServices.I.repo.developers());

final usedSourcesProvider = FutureProvider<List<String>>(
    (ref) async => AppServices.I.repo.usedSources());

final gameCountProvider =
    FutureProvider<int>((ref) => AppServices.I.repo.gameCount());

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
