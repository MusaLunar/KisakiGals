/// 探索页：浏览元数据站点（VNDB / Bangumi）的榜单，筛选、无限滚动、一键入库。
///
/// 与「资源搜索」的区别：资源搜索是**有目标地找下载页**（关键词 → 聚合结果），
/// 探索页是**不知道玩什么时看榜单**（无关键词 → 按评分/年份/标签翻页浏览）。
/// 卡片上的作品还不在库里，所以点击卡片打开的是详情弹窗（封面/简介/标签 +
/// 入库按钮），而不是游戏库的详情页。
///
/// 视觉全部走 kit.dart / design.dart 的原语：KPage + KToolbar + KChip + KCard +
/// KOverlayTag / KOverlayIconButton + KSkeleton / KEmpty。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart' show CoverImage;
import '../widgets/notifications.dart';
import 'discover_filter_state.dart';
import 'discover_state.dart';

/// 距底部多少像素开始预取下一页。
/// 400 大约是「一行到一行半」的高度：滚动到底时下一页通常已经就位，
/// 不会出现「滚到底停住 → 等一秒 → 才出卡片」的顿挫。
const double _kPrefetchDistance = 400;

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  /// 本地搜索词（只过滤**已加载**的条目，不重新请求）
  String _query = '';

  /// 正在入库的条目（按 discoverLibraryKey），用于按钮进度态 + 防重复点击
  final _adding = <String>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels > _kPrefetchDistance) return;
    // 滚动回调也可能在**布局阶段**被触发（内容变长会重算 maxScrollExtent），
    // 那时直接改 provider 会撞上「布局中标记重绘」的断言，因此推到帧末再拉。
    // loadMore 自带「正在加载 / 没有下一页」短路，重复触发是安全的。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(discoverFeedProvider.notifier).loadMore();
    });
  }

  /// 内容撑不满视口时主动再拉一页。
  ///
  /// 没有滚动条就不会有滚动事件，「距底 400px」永远不成立——大窗口下
  /// 每页 30 条可能只占半屏，用户会以为「就这么多」。因此每次渲染后检查
  /// 一次 maxScrollExtent：仍然是 0 且还有下一页就继续加载，直到能滚动
  /// 或数据源没有更多为止。
  void _fillViewport() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent > 0) return;
    final feed = ref.read(discoverFeedProvider).valueOrNull;
    if (feed == null || feed.preloading || !feed.hasMore) return;
    ref.read(discoverFeedProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(discoverFilterProvider);
    final feed = ref.watch(discoverFeedProvider);
    final raw = feed.valueOrNull;
    // 只认「当前筛选条件下」拉到的数据：换源/换筛选/刷新期间一律当作还没数据
    // （riverpod 在重建时会保留上一次的值，直接用会先闪一排上一个源的卡片）。
    final data = (raw != null && raw.filterKey == filter.key) ? raw : null;
    final items = data?.items ?? const <ScrapedGame>[];
    final visible = _localFilter(items);
    // 已在库索引（key = `vndb:123` / `bgm:45678`）：一次查询供整屏卡片共用
    final library = ref.watch(discoverLibraryIndexProvider).valueOrNull ??
        const <String, Game>{};

    if (data != null && visible.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
    }

    return KPage(
      title: '探索',
      subtitle: '浏览元数据站点的作品，一键入库',
      actions: [
        KIconAction(
          icon: Icons.refresh_rounded,
          tooltip: '刷新榜单（跳过 24 小时缓存重新拉第一页）',
          onTap: () => ref.read(discoverFeedProvider.notifier).refresh(),
        ),
        KPill(
          label: '筛选',
          icon: Icons.tune_rounded,
          // 有筛选条件时用实心按钮：一眼能看出「当前看到的不是默认榜单」
          filled: filter.hasActiveFilters,
          onTap: _openFilterSheet,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toolbar(filter, items.length, visible.length, data),
          _summaryLine(filter),
          Expanded(child: _body(feed, data, items, visible, library)),
        ],
      ),
    );
  }

  // ==================== 工具栏 ====================

  Widget _toolbar(
      DiscoverFilter filter, int loaded, int shown, DiscoverFeedState? data) {
    return KToolbar(
      children: [
        // 来源切换
        for (final s in DiscoverSource.values) ...[
          KChip(
            label: s.label,
            selected: filter.source == s,
            onTap: () => ref
                .read(discoverFeedProvider.notifier)
                .updateFilter(filter.copyWith(source: s)),
          ),
          const SizedBox(width: Gap.sm),
        ],
        const SizedBox(width: Gap.sm),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: '在已加载的条目里搜索标题 / 标签 / 开发商',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: Gap.md),
        KBadge(
          icon: Icons.grid_view_rounded,
          // 数据源报告没有下一页时直接说清楚，省得用户一直往下滚
          text: data == null
              ? '尚未加载'
              : (shown != loaded
                  ? '$shown / $loaded 部'
                  : (data.hasMore ? '已加载 $loaded 部' : '已全部加载 $loaded 部')),
        ),
      ],
    );
  }

  /// 筛选摘要 + 数据源能力提示（避免「筛了但没生效」的困惑）。
  Widget _summaryLine(DiscoverFilter filter) {
    final scheme = Theme.of(context).colorScheme;
    final hints = <String>[
      if (filter.source == DiscoverSource.bgm && filter.tagIds.isNotEmpty)
        'Bangumi 不支持标签筛选，已忽略标签条件',
      if (filter.source == DiscoverSource.bgm &&
          filter.yearFrom != null &&
          filter.yearTo != null &&
          filter.yearFrom != filter.yearTo)
        'Bangumi 只能按单一年份浏览：已改用排名浏览并在本地筛选年份区间',
      if (!filter.onlySfw) '正在显示 R18 作品（按源站标记/标签判定，可能不完整）',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          KBadge(
            text: filter.summary,
            icon: Icons.filter_alt_rounded,
            color: filter.hasActiveFilters ? scheme.primary : scheme.secondary,
          ),
          for (final h in hints)
            Text(h, style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ==================== 内容区 ====================

  /// [data] 为 null 表示「当前筛选条件下还没有数据」（首次加载 / 刚换条件 /
  /// 刚刷新），此时用骨架占位；`feed.hasError` 则说明这个条件是拉失败了。
  Widget _body(
    AsyncValue<DiscoverFeedState> feed,
    DiscoverFeedState? data,
    List<ScrapedGame> items,
    List<ScrapedGame> visible,
    Map<String, Game> library,
  ) {
    if (data == null) {
      // 网络失败与「没有结果」是两回事：失败要把原因原样显示出来 + 给重试
      if (feed.hasError) return _errorState(feed.error);
      return _skeletonGrid();
    }
    // 没有任何结果（数据源确实没有匹配项）
    if (items.isEmpty) {
      // 注意区分两种「空」：数据源真的没有匹配（hasMore=false），
      // 与「本地补筛把开头几页都筛空了」（hasMore=true）——后者还能继续往后翻，
      // 直接说「没有作品」会把人堵死在空页上（Bangumi 的年份区间尤其容易这样）。
      final canContinue = data.hasMore;
      return KEmpty(
        icon: canContinue
            ? Icons.hourglass_empty_rounded
            : Icons.travel_explore_rounded,
        title: canContinue ? '开头几页没有符合条件的作品' : '这个条件下没有作品',
        subtitle: canContinue
            ? '有些条件（Bangumi 的年份区间、评分下限）是在本地补筛的，可以继续往后加载'
            : '试试放宽条件：降低评分下限、清空标签或去掉年份限制',
        actionLabel: canContinue ? '继续加载' : '重置筛选',
        actionIcon: canContinue
            ? Icons.expand_more_rounded
            : Icons.filter_alt_off_rounded,
        onAction: canContinue
            ? () => ref.read(discoverFeedProvider.notifier).loadMore()
            : () => ref
                .read(discoverFeedProvider.notifier)
                .updateFilter(DiscoverFilter(
                  source: ref.read(discoverFilterProvider).source,
                )),
      );
    }
    if (visible.isEmpty) {
      return KEmpty(
        icon: Icons.search_off_rounded,
        title: '已加载的条目里没有「$_query」',
        subtitle: '本地搜索只过滤已加载的条目，继续向下滚动可以加载更多',
        actionLabel: '清空搜索',
        actionIcon: Icons.close_rounded,
        onAction: () {
          _searchCtrl.clear();
          setState(() => _query = '');
        },
      );
    }

    // 页尾：加载骨架 +（失败时）一行重试卡
    final preloading = data.preloading;
    final tailError = data.error;
    final tail = (preloading ? 4 : 0) + (tailError == null ? 0 : 1);

    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: Gap.xl),
      // 参数按需求固定：最大列宽 220、间距 16/16、卡片 2:3
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2 / 3,
      ),
      itemCount: visible.length + tail,
      itemBuilder: (context, index) {
        if (index >= visible.length) {
          if (preloading && index < visible.length + 4) {
            return const _DiscoverSkeletonCard();
          }
          return _tailErrorCard(tailError ?? '');
        }
        final g = visible[index];
        return _tile(g, inLibrary: library.containsKey(discoverLibraryKey(g)));
      },
    );
  }

  /// 首屏骨架：整屏 8 个占位卡（与真实卡片同尺寸，避免加载完成时布局跳动）。
  Widget _skeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2 / 3,
      ),
      itemCount: 8,
      itemBuilder: (_, __) => const _DiscoverSkeletonCard(),
    );
  }

  /// 整页失败（首次加载 / 刷新失败）：把原因原样显示出来 + 重试。
  Widget _errorState(Object? error) {
    return KEmpty(
      icon: Icons.cloud_off_rounded,
      title: '榜单加载失败',
      subtitle: '$error',
      actionLabel: '重试',
      actionIcon: Icons.refresh_rounded,
      onAction: () => ref.read(discoverFeedProvider.notifier).refresh(),
    );
  }

  /// 下一页失败的页尾卡：内容还在，只提示这一页没拉到 + 重试按钮。
  Widget _tailErrorCard(String message) {
    final scheme = Theme.of(context).colorScheme;
    return KCard(
      padding: const EdgeInsets.all(Gap.md),
      onTap: () => ref.read(discoverFeedProvider.notifier).loadMore(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 22, color: KisakiColors.danger),
          const SizedBox(height: Gap.sm),
          Text('加载下一页失败',
              style: Type.label.copyWith(color: KisakiColors.danger)),
          const SizedBox(height: Gap.xs),
          Text(
            message,
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Gap.sm),
          Text('点击重试', style: Type.micro.copyWith(color: scheme.primary)),
        ],
      ),
    );
  }

  // ==================== 卡片 ====================

  Widget _tile(ScrapedGame g, {required bool inLibrary}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final key = discoverLibraryKey(g);
    final adding = _adding.contains(key);
    final year = _yearOf(g.releaseDate);
    return KCard(
      padding: const EdgeInsets.all(8),
      onTap: () => _openDetail(g),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 该作品还不在库里，只有网络封面（本地无文件）
                CoverImage(
                  path: '',
                  networkUrl: g.coverUrl,
                  nsfw: g.nsfw,
                  borderRadius: BorderRadius.circular(Radii.thumb),
                ),
                // 年份 / 评分压在封面底部左右两侧（浮层角标自带黑底，任何封面上都看得清）
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: KOverlayTag(
                    text: year == null ? '未定' : '$year',
                    icon: Icons.event_rounded,
                  ),
                ),
                if (g.rating > 0)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: KOverlayTag(
                      text: g.rating.toStringAsFixed(1),
                      icon: Icons.star_rounded,
                      color: KisakiColors.star,
                    ),
                  ),
                // 入库按钮放**右上角**：封面底部左右已经被年份/评分占用，
                // 三个浮层挤在一条底边上会互相重叠。
                Positioned(
                  right: 6,
                  top: 6,
                  child: adding
                      ? const SizedBox(
                          width: 26, height: 26, child: KLoading(size: 16))
                      : KOverlayIconButton(
                          icon: inLibrary
                              ? Icons.check_rounded
                              : Icons.library_add_rounded,
                          tooltip: inLibrary ? '已在游戏库' : '入库',
                          color:
                              inLibrary ? KisakiColors.pinkSoft : Colors.white,
                          // 已在库：只显示对勾且不可再点
                          onTap: inLibrary ? null : () => _addToLibrary(g),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            g.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: dark ? KisakiColors.nightInk : KisakiColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 本地搜索 ====================

  /// 只过滤已加载的条目（标题/中文名/别名/开发商/标签），不发请求。
  List<ScrapedGame> _localFilter(List<ScrapedGame> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((g) {
      bool hit(String s) => s.isNotEmpty && s.toLowerCase().contains(q);
      return hit(g.displayName) ||
          hit(g.name) ||
          hit(g.nameCn) ||
          hit(g.developer) ||
          g.aliases.any(hit) ||
          g.tags.any((t) => hit(t.name));
    }).toList();
  }

  // ==================== 筛选面板 ====================

  Future<void> _openFilterSheet() async {
    final current = ref.read(discoverFilterProvider);
    final next = await showKisakiDialog<DiscoverFilter>(
      context: context,
      builder: (_) => _FilterSheet(initial: current),
    );
    if (next == null || !mounted) return;
    ref.read(discoverFeedProvider.notifier).updateFilter(next);
  }

  // ==================== 详情弹窗 ====================

  /// 打开详情弹窗（不跳游戏库详情页：该作品还不在库里，
  /// GameDetailPage 需要一个已存在的 gameId）。
  Future<void> _openDetail(ScrapedGame g) {
    return showKisakiDialog<void>(
      context: context,
      builder: (_) => _DiscoverDetailDialog(game: g, onAdd: _addToLibrary),
    );
  }

  // ==================== 入库 ====================

  /// 入库：insertGame → ScrapeApplier.apply（下载封面 / 写标签 / 登记各源评分）。
  /// 与资源搜索页、添加页走的是同一条落库路径。
  Future<void> _addToLibrary(ScrapedGame g) async {
    final key = discoverLibraryKey(g);
    if (_adding.contains(key)) return;
    setState(() => _adding.add(key));
    try {
      final repo = AppServices.I.repo;
      // 按标题再兜一次重名：同一作品可能已经以**另一个源 id** 入库过
      // （卡片上的「已在库」是按 source id 判定的，判不到这种情况）
      final existing = await repo.findGameByTitle(g.displayName) ??
          (g.name.isEmpty || g.name == g.displayName
              ? null
              : await repo.findGameByTitle(g.name));
      if (existing != null) {
        if (!mounted) return;
        ref.read(libraryVersionProvider.notifier).state++;
        showNotice('「${existing.displayName}」已在库中');
        return;
      }
      final game = Game(
        name: g.name.isNotEmpty ? g.name : g.displayName,
        nameCn: g.nameCn,
        aliases: g.aliases,
        developer: g.developer,
        releaseDate: g.releaseDate,
        summary: g.summary,
        nsfw: g.nsfw,
        screenshots: g.screenshots,
      );
      // 探索页的条目还没有本地文件，不需要 relocator.stamp（那是给带 exe
      // 路径的条目登记设备指纹、换机后重定位用的）
      await repo.insertGame(game);
      await ScrapeApplier(repo, AppServices.I.fetcher).apply(game, [g]);
      if (!mounted) return;
      ref.read(libraryVersionProvider.notifier).state++;
      showNotice('已入库：${game.displayName}');
    } catch (e) {
      if (mounted) showNotice('入库失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _adding.remove(key));
    }
  }

  static int? _yearOf(String date) =>
      date.length < 4 ? null : int.tryParse(date.substring(0, 4));
}

// ==================== 骨架卡 ====================

/// 网格里的骨架卡：与真实卡片同尺寸（2:3 + 一行标题）。
class _DiscoverSkeletonCard extends StatelessWidget {
  const _DiscoverSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(
            child: KSkeleton(
                width: double.infinity,
                height: double.infinity,
                radius: Radii.sm),
          ),
          SizedBox(height: 8),
          KSkeleton(height: 10, width: 90),
        ],
      ),
    );
  }
}

// ==================== 详情弹窗 ====================

/// 条目详情：封面 + 元信息 + 简介 + 标签 + 入库。
///
/// 自己 watch 已在库索引（而不是从页面传一个 bool 进来）：入库成功后
/// libraryVersionProvider 自增会刷新索引，弹窗里的按钮立刻变成「已在库」。
class _DiscoverDetailDialog extends ConsumerStatefulWidget {
  final ScrapedGame game;
  final Future<void> Function(ScrapedGame) onAdd;

  const _DiscoverDetailDialog({required this.game, required this.onAdd});

  @override
  ConsumerState<_DiscoverDetailDialog> createState() =>
      _DiscoverDetailDialogState();
}

class _DiscoverDetailDialogState extends ConsumerState<_DiscoverDetailDialog> {
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    await widget.onAdd(widget.game);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final scheme = Theme.of(context).colorScheme;
    final library = ref.watch(discoverLibraryIndexProvider).valueOrNull ??
        const <String, Game>{};
    final inLibrary = library.containsKey(discoverLibraryKey(g));
    final source = KisakiSources.labels[g.source] ?? g.source;
    final year =
        g.releaseDate.length < 4 ? null : g.releaseDate.substring(0, 4);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: KCard(
          borderRadius: Radii.sheet,
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    height: 225, // 2:3
                    child: CoverImage(
                      path: '',
                      networkUrl: g.coverUrl,
                      nsfw: g.nsfw,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                  ),
                  const SizedBox(width: Gap.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Type.title),
                        if (g.name.isNotEmpty && g.name != g.displayName) ...[
                          const SizedBox(height: 2),
                          Text(g.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.caption
                                  .copyWith(color: scheme.onSurfaceVariant)),
                        ],
                        const SizedBox(height: Gap.md),
                        Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            KBadge(text: source, icon: Icons.public_rounded),
                            if (g.rating > 0)
                              KBadge(
                                text: '评分 ${g.rating.toStringAsFixed(1)}',
                                icon: Icons.star_rounded,
                                color: KisakiColors.star,
                              ),
                            if (g.voteCount > 0)
                              KBadge(text: '${g.voteCount} 票'),
                            if (year != null) KBadge(text: '$year 年'),
                            if (g.nsfw)
                              const KBadge(
                                  text: 'R18',
                                  icon: Icons.block_rounded,
                                  color: KisakiColors.danger),
                            if (inLibrary)
                              const KBadge(
                                  text: '已在库',
                                  icon: Icons.check_rounded,
                                  color: KisakiColors.success),
                          ],
                        ),
                        if (g.developer.isNotEmpty) ...[
                          const SizedBox(height: Gap.md),
                          Text('开发商：${g.developer}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.caption
                                  .copyWith(color: scheme.onSurfaceVariant)),
                        ],
                        if (g.tags.isNotEmpty) ...[
                          const SizedBox(height: Gap.md),
                          Wrap(
                            spacing: Gap.xs + 2,
                            runSpacing: Gap.xs,
                            children: [
                              for (final t in g.tags.take(8))
                                KBadge(text: t.name, color: scheme.secondary),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              const KSectionTitle('简介', padding: EdgeInsets.only(bottom: 6)),
              // 长简介自己滚动，不把弹窗撑爆
              Expanded(
                child: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      g.summary.isEmpty ? '（该数据源没有提供简介）' : g.summary,
                      style: Type.body,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  if (g.aliases.isNotEmpty)
                    Expanded(
                      child: Text(
                        '别名：${g.aliases.take(3).join(" / ")}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Type.micro.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    const Spacer(),
                  KPill(
                    label: '关闭',
                    filled: false,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: Gap.sm),
                  if (_busy)
                    const SizedBox(
                        width: 96, height: 36, child: KLoading(size: 18))
                  else
                    KPill(
                      label: inLibrary ? '已在库' : '入库',
                      icon: inLibrary
                          ? Icons.check_rounded
                          : Icons.library_add_rounded,
                      onTap: inLibrary ? null : _add,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 筛选面板 ====================

/// 筛选面板：来源 / 排序 / 评分下限 / 年份区间 / 标签 / R18。
/// 返回值是新的 [DiscoverFilter]（取消则为 null）。
class _FilterSheet extends StatefulWidget {
  final DiscoverFilter initial;

  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DiscoverFilter _draft = widget.initial;

  late final TextEditingController _fromCtrl =
      TextEditingController(text: widget.initial.yearFrom?.toString() ?? '');
  late final TextEditingController _toCtrl =
      TextEditingController(text: widget.initial.yearTo?.toString() ?? '');

  /// 评分下限预设（0 = 不限）
  static const _ratings = <double>[0, 7, 7.5, 8, 8.5, 9];

  /// 年份区间预设（常见档位，避免用户手打；也可以直接填起止年）
  static const _ranges = <({String label, int? from, int? to})>[
    (label: '不限', from: null, to: null),
    (label: '2020 以后', from: 2020, to: null),
    (label: '2015-2019', from: 2015, to: 2019),
    (label: '2010-2014', from: 2010, to: 2014),
    (label: '2005-2009', from: 2005, to: 2009),
    (label: '2000-2004', from: 2000, to: 2004),
  ];

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  bool _isRangeSelected(({String label, int? from, int? to}) r) =>
      _draft.yearFrom == r.from && _draft.yearTo == r.to;

  void _applyRange(({String label, int? from, int? to}) r) {
    _fromCtrl.text = r.from?.toString() ?? '';
    _toCtrl.text = r.to?.toString() ?? '';
    setState(() => _draft = _draft.copyWith(yearFrom: r.from, yearTo: r.to));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: KCard(
          borderRadius: Radii.sheet,
          padding: const EdgeInsets.all(Gap.xl),
          // 透明 Material：TextField 与 Switch 必须有 Material 祖先，而
          // showKisakiDialog 的浮层挂在 Navigator 上、不在 Scaffold 的
          // Material 之下（没有它会在真机上直接抛 "No Material widget found"）。
          // 与 kit 里 KRow 用透明 Material 承载水波纹是同一做法。
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('筛选', style: Type.title),
                    const SizedBox(width: Gap.sm),
                    KBadge(
                        text: _draft.summary, icon: Icons.filter_alt_rounded),
                    const Spacer(),
                    KIconAction(
                      icon: Icons.close_rounded,
                      tooltip: '关闭',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                // 条件区自己滚动，底部按钮常驻：条件项较多时（年份 + 标签）
                // 也不会把「应用」挤到看不见的地方。
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section('来源', _sourceChips()),
                        _section('排序', _sortChips()),
                        _section(
                            '最低评分（${_draft.minRating > 0 ? _trim(_draft.minRating) : "不限"}）',
                            _ratingChips()),
                        _section('年份', _yearSection()),
                        _section(
                          _draft.source == DiscoverSource.bgm
                              ? '标签（Bangumi 不支持，仅 VNDB 生效）'
                              : '标签（多选为「同时满足」）',
                          _tagChips(),
                        ),
                        const SizedBox(height: Gap.sm),
                        Row(
                          children: [
                            Text('显示 R18 作品', style: Type.formLabel),
                            const SizedBox(width: Gap.sm),
                            Text(
                              _draft.onlySfw ? '已隐藏（默认）' : '已显示',
                              style: Type.caption.copyWith(
                                  color: _draft.onlySfw
                                      ? scheme.onSurfaceVariant
                                      : KisakiColors.warning),
                            ),
                            const Spacer(),
                            Switch(
                              value: !_draft.onlySfw,
                              onChanged: (v) => setState(
                                  () => _draft = _draft.copyWith(onlySfw: !v)),
                            ),
                          ],
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          _draft.source.hint,
                          style: Type.micro
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: Gap.sm),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    KPill(
                      label: '重置',
                      icon: Icons.filter_alt_off_rounded,
                      filled: false,
                      onTap: () {
                        _fromCtrl.clear();
                        _toCtrl.clear();
                        setState(() => _draft = _draft.cleared());
                      },
                    ),
                    const Spacer(),
                    KPill(
                      label: '取消',
                      filled: false,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: Gap.sm),
                    KPill(
                      label: '应用',
                      icon: Icons.check_rounded,
                      onTap: () =>
                          Navigator.of(context).pop(_draft.normalized()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Type.formLabel),
            const SizedBox(height: Gap.sm),
            child,
          ],
        ),
      );

  Widget _sourceChips() => Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        children: [
          for (final s in DiscoverSource.values)
            KChip(
              label: s.label,
              selected: _draft.source == s,
              onTap: () => setState(() => _draft = _draft.copyWith(source: s)),
            ),
        ],
      );

  Widget _sortChips() => Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        children: [
          for (final s in DiscoverSort.values)
            KChip(
              label: s.label,
              selected: _draft.sort == s,
              onTap: () => setState(() => _draft = _draft.copyWith(sort: s)),
            ),
        ],
      );

  Widget _ratingChips() => Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        children: [
          for (final r in _ratings)
            KChip(
              label: r == 0 ? '不限' : '≥ ${_trim(r)}',
              selected: _draft.minRating == r,
              onTap: () =>
                  setState(() => _draft = _draft.copyWith(minRating: r)),
            ),
        ],
      );

  Widget _yearSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final r in _ranges)
                KChip(
                  label: r.label,
                  selected: _isRangeSelected(r),
                  onTap: () => _applyRange(r),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _fromCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: '起始年', isDense: true),
                  onChanged: (v) => setState(() =>
                      _draft = _draft.copyWith(yearFrom: int.tryParse(v))),
                ),
              ),
              const SizedBox(width: Gap.md),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _toCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: '结束年', isDense: true),
                  onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(yearTo: int.tryParse(v))),
                ),
              ),
              const SizedBox(width: Gap.md),
              Text('留空表示不限',
                  style: Type.micro.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      );

  Widget _tagChips() => Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        children: [
          for (final t in DiscoverTags.presets)
            KChip(
              label: t.label,
              icon: Icons.tag_rounded,
              selected: _draft.tagIds.contains(t.id),
              onTap: () => setState(() => _draft = _draft.toggleTag(t.id)),
            ),
        ],
      );

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
