/// 探索页状态：筛选条件 + 榜单信息流（分页 / 去重 / 已在库判定）。
///
/// 与 pages 的分工：这里只做「数据怎么来、什么时候再来」，不碰 BuildContext；
/// 页面只负责渲染和把用户操作翻译成 [DiscoverFeed] 上的方法调用。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import 'discover_filter_state.dart';

/// 每页条数。
///
/// 两个源都用 30：
/// - VNDB 的 `results` 上限是 100，但榜单请求带着简介/截图/全量标签，
///   本机实测 50 条约 400KB 且往返 ~3s（逼近 VNDB「单请求 3 秒执行上限」），
///   30 条更稳；
/// - Bangumi 有 1 req/s 的限流（见 MetadataFetcher 的 RateLimiters），
///   页越大越不该频繁翻页，但也没有必要超过 50。
const int kDiscoverPageSize = 30;

/// 空页自动续拉的页数上限（原因见 [DiscoverFeed._load]）。
const int _kMaxAutoPages = 3;

/// Bangumi **搜索**接口的每页条数（实测上限）。
///
/// `POST /v0/search/subjects` 硬性每页最多 20 条：无论 `limit` 传 20/30/50，
/// 都只回 20 条（浏览接口 `GET /v0/subjects` 没这个限制，传 30 就回 30）。
/// 而 `offset` 是按**我们请求的 limit** 步进的，所以搜索时必须真的按 20 去要，
/// 否则「请求 30 → 拿到 20 → 下一页从 offset=30 开始」，每翻一页都会漏掉
/// 中间 10 条。20 同时也让 `MetadataFetcher` 冷启动时的「整页 ⇒ 还有下一页」
/// 推断（`_pageLooksFull`）继续成立。
const int kBangumiSearchPageSize = 20;

/// 探索页筛选条件（页面顶部的「筛选」面板写它，信息流 watch 它）。
final discoverFilterProvider =
    StateProvider<DiscoverFilter>((ref) => const DiscoverFilter());

/// 「已在库」判定用的平台索引，key 形如 `vndb:123` / `bgm:45678`。
///
/// 为什么用 source id 而不是 `repo.findGameByTitle`：
/// 1) 精确——同名不同作品、同一作品多个译名都不会误判；
/// 2) 一次查询拿到全库索引，而网格里几十张卡各自去 findGameByTitle 会退化
///    成 O(卡片数 × 库大小) 的全表扫描。
/// 入库时仍会用 findGameByTitle 兜一次重名（同一作品挂在不同源 id 下时）。
final discoverLibraryIndexProvider =
    FutureProvider<Map<String, Game>>((ref) async {
  ref.watch(libraryVersionProvider);
  return AppServices.I.repo.sourceIndex();
});

/// 刮削条目 → [GameRepository.sourceIndex] 的 key。
/// 索引里 VNDB 的 `v` 前缀已被归一掉（`vndb:v123` → `vndb:123`），
/// 这里保持同一规则，否则刚入库的条目不会被认成「已在库」。
String discoverLibraryKey(ScrapedGame g) {
  var id = g.sourceId.trim();
  if (g.source == KisakiSources.vndb && id.startsWith('v')) {
    id = id.substring(1);
  }
  return '${g.source}:$id';
}

/// 榜单信息流的快照。
class DiscoverFeedState {
  /// 已加载的条目（跨页去重后，按数据源给出的顺序）。
  final List<ScrapedGame> items;

  /// 已请求过的最大页码（下一页 = page + 1）。
  final int page;

  /// 数据源是否报告还有下一页。
  final bool hasMore;

  /// 正在追加下一页（页尾显示骨架）。
  final bool preloading;

  /// 拉这批数据时用的筛选条件标识（[DiscoverFilter.key]）。
  /// 页面据此判断「手上的数据是不是当前条件下的」——换源/换筛选后，
  /// 旧条目不能再当新结果展示（否则会先闪一下上一个源的卡片）。
  final String filterKey;

  /// 最近一次失败的原因（成功后清空）。首次加载的失败不在这里，
  /// 而是以 AsyncValue.error 抛给页面，两者分别对应「整页失败」与
  /// 「已有内容、只是下一页没拉到」。
  final String? error;

  const DiscoverFeedState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.preloading = false,
    this.filterKey = '',
    this.error,
  });

  DiscoverFeedState copyWith({
    List<ScrapedGame>? items,
    int? page,
    bool? hasMore,
    bool? preloading,
    String? filterKey,
    String? error,
    bool clearError = false,
  }) =>
      DiscoverFeedState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        preloading: preloading ?? this.preloading,
        filterKey: filterKey ?? this.filterKey,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 探索页信息流。
///
/// 不做 autoDispose：切到别的页再切回来时已加载的榜单还在，
/// 不会每次都从第一页重新拉（榜单本身变化很慢，24h 缓存也印证了这点）。
class DiscoverFeed extends AsyncNotifier<DiscoverFeedState> {
  /// 代际计数：每次 build（首次 / 换筛选 / 刷新）自增。
  /// 迟到的分页响应据此丢弃——否则「换筛选 → 旧的第 3 页结果返回」会把
  /// 新筛选的第一页盖掉（riverpod 2.6 的 Ref 还没有 mounted 可用）。
  int _gen = 0;

  @override
  Future<DiscoverFeedState> build() async {
    _gen++;
    final filter = ref.watch(discoverFilterProvider);
    return _load(filter, startPage: 1);
  }

  /// 更新筛选条件。条件真的变了才会重新拉榜单（build 里 watch 了它，
  /// 相同条件直接返回，避免用户重复点同一项又白跑一次网络）。
  void updateFilter(DiscoverFilter filter) {
    final next = filter.normalized();
    if (next == ref.read(discoverFilterProvider)) return;
    ref.read(discoverFilterProvider.notifier).state = next;
  }

  /// 手动刷新：回到第一页重新拉（页面上「刷新」按钮）。
  /// 期间状态置为 loading，网格显示骨架（而不是留着旧数据不声不响）。
  Future<void> refresh() async {
    final gen = _gen;
    final filter = ref.read(discoverFilterProvider);
    state = const AsyncValue.loading();
    try {
      final next = await _load(filter, startPage: 1);
      if (gen != _gen) return;
      state = AsyncValue.data(next);
    } catch (e, st) {
      if (gen != _gen) return;
      state = AsyncValue.error(e, st);
    }
  }

  /// 加载下一页（滚动到距底 400px 时由页面触发）。
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.preloading || !current.hasMore) return;
    if (state.isLoading) return; // 首次加载 / 刷新中，等它自己完成
    final gen = _gen;
    final filter = ref.read(discoverFilterProvider);
    // 手上的条目必须是当前条件拉到的：换条件后重建失败时（AsyncError 仍保留
    // 旧值、isLoading 又是 false）继续追加会把两个条件的条目混在一起。
    if (current.filterKey != filter.key) return;
    state =
        AsyncValue.data(current.copyWith(preloading: true, clearError: true));
    try {
      final next =
          await _load(filter, startPage: current.page + 1, previous: current);
      if (gen != _gen) return;
      state = AsyncValue.data(next);
    } catch (e) {
      if (gen != _gen) return;
      // 已有内容 + 下一页失败：保留内容，把原因挂在 error 上（页尾提示 + 重试）
      state = AsyncValue.data(
          current.copyWith(preloading: false, error: _message(e)));
    }
  }

  /// 拉取从 [startPage] 开始的一页（必要时自动续拉，见下），并入 [previous]。
  Future<DiscoverFeedState> _load(
    DiscoverFilter filter, {
    required int startPage,
    DiscoverFeedState? previous,
  }) async {
    // ---- 关键词搜索：并行查询所有来源并合并 ----
    //
    // 别名/简称往往只被某一个来源收录：实测「金恋」在 VNDB 命中
    // v21852（VNDB 收录了 zh-Hans 别名「金恋」），而 Bangumi 的搜索返回空。
    // 原先只查「当前选中的来源」，于是用户在 Bangumi 下搜别名就永远搜不到。
    // 这里改成：关键词搜索时把每个来源都查一遍（并发、各自遵守限流与缓存），
    // 合并去重后返回；分页只对浏览（榜单）模式有意义。
    if (filter.searching && startPage <= 1 && previous == null) {
      final merged = <ScrapedGame>[];
      final seenIds = <String>{};
      final seenTitles = <String>{};
      final results = await Future.wait(DiscoverSource.values.map((src) async {
        try {
          final params = _paramsFor(filter.withSource(src), 1);
          return await AppServices.I.fetcher.browse(src.id, params);
        } catch (_) {
          // 单个来源失败不影响其它来源（KunGal 这类要求登录的源会抛异常）
          return const <ScrapedGame>[];
        }
      }));
      for (final list in results) {
        for (final g in list) {
          if (!_passes(filter, g)) continue;
          if (!seenIds.add(_dedupKey(g))) continue;
          // 跨源去重：同一部作品在不同源里 sourceId 不同，用规范化标题兜一层
          final tk = normalizeForMatch(g.displayName);
          if (tk.isNotEmpty && !seenTitles.add(tk)) continue;
          merged.add(g);
        }
      }
      // 排序：规范化后标题完全等于关键词的最优先，其次包含关键词，再按评分/票数
      final q = normalizeForMatch(filter.keyword);
      int rank(ScrapedGame g) {
        final t = normalizeForMatch(g.displayName);
        if (t == q) return 0;
        if (t.contains(q)) return 1;
        final ja = normalizeForMatch(g.name);
        if (ja == q) return 0;
        if (ja.contains(q)) return 1;
        for (final a in g.aliases) {
          final na = normalizeForMatch(a);
          if (na == q) return 0;
          if (na.contains(q)) return 1;
        }
        return 2;
      }

      merged.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return b.rating.compareTo(a.rating);
      });
      return DiscoverFeedState(
        items: merged,
        page: 1,
        hasMore: false, // 关键词搜索一把查完，不做分页
        preloading: false,
        filterKey: filter.key,
      );
    }

    final items = <ScrapedGame>[...?previous?.items];
    final seen = <String>{for (final g in items) _dedupKey(g)};
    var page = startPage;
    var hasMore = false;

    // 空页自动续拉：本地补筛（R18 / Bangumi 的年份区间与评分下限）有可能把
    // 一整页全筛掉，此时界面既没有新卡片、滚动位置也没变（不会再触发
    // loadMore），页面会「卡住不动」。所以最多连续续拉 [_kMaxAutoPages] 页；
    // 设上限是为了不给 Bangumi（1 req/s）造成压力。
    for (var attempt = 0; attempt < _kMaxAutoPages; attempt++) {
      final params = _paramsFor(filter, page);
      final raw = await AppServices.I.fetcher.browse(filter.source.id, params);
      hasMore = AppServices.I.fetcher.browseHasMore(filter.source.id, params);
      var added = 0;
      for (final g in raw) {
        if (!_passes(filter, g)) continue;
        if (!seen.add(_dedupKey(g))) continue;
        items.add(g);
        added++;
      }
      page++; // 这一页已经请求过（无论被筛掉多少条），下一页从 page+1 开始
      if (added > 0 || !hasMore) break;
    }
    return DiscoverFeedState(
      items: items,
      page: page - 1,
      hasMore: hasMore,
      preloading: false,
      filterKey: filter.key,
    );
  }

  /// 把筛选条件翻译成「该数据源真正支持的请求参数」。
  ///
  /// VNDB 能把评分下限 / 年份区间 / 标签全部下发到服务端（rating、released、
  /// tag 过滤器）；Bangumi 的浏览接口只有 `sort`(rank|date) + `year`（单一
  /// 年份）+ 分页，所以：
  /// - 排序：rating / votecount / title → `rank`（BGM 的浏览列表本身就是按
  ///   评分权重排的），released → `date`；
  /// - 年份：只有「起止同年」才下发 `year`；跨年区间下 `date` 排序会从最新
  ///   年份倒着翻，翻到区间内要几百页，因此跨年区间强制用 `rank` 浏览，
  ///   年份条件交给本地补筛（summary 里会如实显示区间）；
  /// - 评分下限、标签：BGM 不支持，本地补筛 / 不生效（页面会提示）。
  ///
  /// `keyword` 非空时两源都进入关键词搜索（各自在适配器里换接口/换排序），
  /// 此时**只下发关键词**：评分下限/年份区间/标签一概不带。它们都是"逛榜单"
  /// 时的收窄条件，用在一部已经明确知道名字的作品上只会把用户要找的那条筛掉
  /// （VNDB 服务端 rating ≥ 8 会把评分 6.5 的本命作品滤掉），而且能避免
  /// "VNDB 生效、Bangumi 不生效"的口径差异（页面摘要里会如实提示）。
  static Map<String, dynamic> _paramsFor(DiscoverFilter f, int page) {
    if (f.searching) {
      // 每页条数按各源搜索接口的真实上限要（BGM 是 20，见
      // [kBangumiSearchPageSize]；VNDB 沿用榜单的 30）
      if (f.source == DiscoverSource.vndb) {
        return {
          'page': page,
          'keyword': f.keyword,
          'results': kDiscoverPageSize,
        };
      }
      return {
        'page': page,
        'keyword': f.keyword,
        'limit': kBangumiSearchPageSize,
      };
    }
    if (f.source == DiscoverSource.vndb) {
      return {
        'sort': f.sort.value,
        'reverse': f.sort.reverse,
        'page': page,
        'results': kDiscoverPageSize,
        if (f.minRating > 0) 'minRating': f.minRating,
        if (f.yearFrom != null) 'yearFrom': f.yearFrom,
        if (f.yearTo != null) 'yearTo': f.yearTo,
        if (f.tagIds.isNotEmpty) 'tagIds': [...f.tagIds],
      };
    }
    final sameYear = f.yearFrom != null && f.yearFrom == f.yearTo;
    final ranged = f.yearFrom != null && f.yearTo != null && !sameYear;
    return {
      'sort': (ranged || f.sort != DiscoverSort.released) ? 'rank' : 'date',
      'page': page,
      'limit': kDiscoverPageSize,
      if (sameYear) 'year': f.yearFrom,
    };
  }

  /// 本地补筛。
  ///
  /// - **关键词搜索**：只保留 R18 这一项。评分下限 / 年份区间是「逛榜单」时
  ///   用来收窄范围的，对「我已经知道要找哪一部」的关键词搜索没有意义，而且
  ///   会把用户明确要找的那条筛掉（Bangumi 里新条目的 score 常为 0，一勾
  ///   「评分 ≥ 7」搜索结果就直接空了）。数据源本身也已经按关键词过滤过，
  ///   再做名称级补筛只会把「中文名命中、列表里显示日文名」的条目藏起来。
  /// - `onlySfw`：两个源都没有服务端 R18 开关（VNDB 连 R18 标记字段都没有，
  ///   判定见 `VndbAdapter._looksNsfw`；Bangumi 的列表里带 `nsfw`），一律本地过滤；
  /// - Bangumi：评分下限与年份区间是它的浏览接口不支持的参数，本地过滤
  ///   （BGM 里评分 0 = 还没人评分，属于「不满足评分 ≥ N」，一样筛掉；
  ///   实测 2015 年的榜单里排前面的多为 score=0 的新条目）；
  /// - VNDB：评分下限与年份已下发成 filters，这里不再重复判断，
  ///   免得服务端口径（10-100 的整型 Bayesian 分）与本地四舍五入后的
  ///   小数点口径出现细微差异、把服务端放行的条目又筛掉。
  static bool _passes(DiscoverFilter f, ScrapedGame g) {
    if (f.onlySfw && g.nsfw) return false;
    if (f.searching) return true;
    if (f.source != DiscoverSource.bgm) return true;
    if (f.minRating > 0 && g.rating < f.minRating) return false;
    final year = _yearOf(g.releaseDate);
    if (year == null) return true; // 没有发售日的条目不该被年份条件误杀
    if (f.yearFrom != null && year < f.yearFrom!) return false;
    if (f.yearTo != null && year > f.yearTo!) return false;
    return true;
  }

  static int? _yearOf(String date) =>
      date.length < 4 ? null : int.tryParse(date.substring(0, 4));

  /// 去重键：同一源内 sourceId 唯一；id 缺失时退回标题。
  /// 不同源的同一作品会各出现一次——那是刻意的，跨源合并交给入库时的
  /// `MetadataFetcher.mergeAcrossSources`。
  static String _dedupKey(ScrapedGame g) => g.sourceId.isNotEmpty
      ? '${g.source}:${g.sourceId}'
      : '${g.source}:${g.displayName}';

  /// 异常文案去掉 `Exception: ` 前缀（直接显示给用户看）。
  static String _message(Object e) {
    final s = '$e';
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }
}

final discoverFeedProvider =
    AsyncNotifierProvider<DiscoverFeed, DiscoverFeedState>(DiscoverFeed.new);
