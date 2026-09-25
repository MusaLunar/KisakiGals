/// 探索页：「探索」（元数据榜单）与「资源」（资源站搜索）两种模式合一。
///
/// **信息架构**：侧栏原先有「探索」与「资源搜索」两项，但两者本质都是
/// 「找游戏」——前者是不知道玩什么时看榜单（无关键词，按评分/年份/标签翻页），
/// 后者是有目标地找下载页（关键词 → 聚合发布页）。因此合并成一页，用页内的
/// 模式切换（[DiscoverMode]）区分，侧栏只剩「探索」一项：
///
/// - **探索**：VNDB / Bangumi 榜单浏览。来源 / 排序 / 最低评分 / 年份 /
///   标签 / R18 全部收进右侧筛选栏（[FilterSidebar]，与游戏库同一个组件）；
///   卡片网格、无限滚动、一键入库、详情弹窗。
/// - **资源**：资源站发布页的关键词搜索（流式结果、相关度排序、打开下载页 /
///   入库）。结果区是 [ResourceSearchPane]，每源错误独立提示。
///
/// 两种模式共享页面外壳：KPage 标题区 + 一个 KToolbar（模式切换、各模式一个
/// 同宽搜索框、各模式的操作）+ FadeThroughSwitcher 做模式切换动效。
///
/// **跨页约定**：主页的「找资源」入口（`home_page.dart` 的 `_openResourceSearch`）
/// 会先把关键词写进 [resourceQueryProvider] 再切到本页；因此本页在挂载时若发现
/// 该 provider 非空，就直接落在「资源」模式并把关键词预填进搜索框（见
/// [_DiscoverPageState.initState] 与 build 里的 ref.listen）。这条链路是主页
/// 推荐位 → 找资源的主要入口，改动本页模式默认值时必须一起考虑。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../design.dart';
import '../kit.dart';
import '../search/resource_search_page.dart'
    show ResourceSearchPane, ResourceSearchState, resourceSearchSessionProvider;
import '../theme.dart';
import '../widgets/common.dart' show CoverImage;
import '../widgets/filter_sidebar.dart';
import '../widgets/notifications.dart';
import 'discover_filter_state.dart';
import 'discover_state.dart';

/// 距底部多少像素开始预取下一页。
/// 400 大约是「一行到一行半」的高度：滚动到底时下一页通常已经就位，
/// 不会出现「滚到底停住 → 等一秒 → 才出卡片」的顿挫。
const double _kPrefetchDistance = 400;

/// 搜索结果网格排版：最大列宽 220、间距 16/16、卡片 2:3。
///
/// 骨架卡与真实卡片共用同一份 delegate：加载完成时不会出现布局跳动。
const SliverGridDelegate _kGridDelegate =
    SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 220,
  mainAxisSpacing: 16,
  crossAxisSpacing: 16,
  childAspectRatio: 2 / 3,
);

/// 工具条搜索框宽度（与游戏库的搜索框同宽，两个页面的工具条节奏一致）。
const double _kSearchWidth = 300;

/// 页内模式。
enum DiscoverMode {
  explore('探索', Icons.travel_explore_rounded),
  resource('资源', Icons.cloud_download_outlined);

  final String label;
  final IconData icon;
  const DiscoverMode(this.label, this.icon);
}

/// 只过滤**已加载**的条目（标题/中文名/别名/开发商/标签），不发请求。
///
/// 工具条的计数与网格共用这一份实现：两处数字不会打架。
List<ScrapedGame> _filterLoaded(List<ScrapedGame> items, String query) {
  final q = query.trim().toLowerCase();
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

/// 8.0 → "8"，8.5 → "8.5"（评分摘要不要出现无意义的小数位）。
String _trimRating(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  /// 当前模式（默认「探索」；带关键词从主页跳进来时直接进「资源」，见类注释）
  late DiscoverMode _mode;

  /// 探索模式的筛选栏是否展开（工具条上的筛选图标切换，持久化到设置）
  bool _sidebarVisible = true;

  /// 探索模式的本地搜索词（只过滤已加载的条目，不重新请求）
  final _localCtrl = TextEditingController();
  String _localQuery = '';

  /// 资源模式的关键词输入框（真正的搜索请求由 [ResourceSearchSession] 发起）
  late final TextEditingController _resourceCtrl;

  @override
  void initState() {
    super.initState();
    // 主页「找资源」入口的握手：关键词已就位 → 直接进「资源」模式
    _mode = ref.read(resourceQueryProvider).isEmpty
        ? DiscoverMode.explore
        : DiscoverMode.resource;
    _resourceCtrl =
        TextEditingController(text: ref.read(resourceQueryProvider));
    AppServices.I.settings
        .getBool(SettingsStore.kDiscoverSidebar, def: true)
        .then((v) {
      if (mounted) setState(() => _sidebarVisible = v);
    });
  }

  @override
  void dispose() {
    _localCtrl.dispose();
    _resourceCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarVisible = !_sidebarVisible);
    await AppServices.I.settings
        .setBool(SettingsStore.kDiscoverSidebar, _sidebarVisible);
  }

  void _setMode(DiscoverMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  void _clearLocalQuery() {
    _localCtrl.clear();
    setState(() => _localQuery = '');
  }

  /// 发起资源搜索：关键词同时写回 [resourceQueryProvider]，
  /// 让「主页 → 找资源」与「本页搜索」共用同一份状态（切走再回来还能预填）。
  void _startResourceSearch() {
    final keyword = _resourceCtrl.text.trim();
    ref.read(resourceQueryProvider.notifier).state = keyword;
    ref.read(resourceSearchSessionProvider.notifier).start(keyword);
  }

  /// 结果区「再搜一次」的回程：先把关键词同步进工具栏输入框，再走同一条
  /// 搜索路径——否则会出现「输入框显示 A、结果却是 B」。
  void _rerunResourceSearch(String keyword) {
    if (_resourceCtrl.text != keyword) _resourceCtrl.text = keyword;
    _startResourceSearch();
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(discoverFilterProvider);
    final feed = ref.watch(discoverFeedProvider);
    final session = ref.watch(resourceSearchSessionProvider);

    // 主页「找资源」入口在页面已挂载时（例如本次会话里已停在探索页）也要生效：
    // 同步输入框并按需切到「资源」模式。相同值（本页自己发起的搜索）直接跳过。
    ref.listen<String>(resourceQueryProvider, (prev, next) {
      if (next.isEmpty || next == prev) return;
      if (_resourceCtrl.text != next) _resourceCtrl.text = next;
      if (_mode != DiscoverMode.resource) {
        setState(() => _mode = DiscoverMode.resource);
      }
    });

    // 只认「当前筛选条件下」拉到的数据：换源/换筛选/刷新期间一律当作还没数据
    // （riverpod 在重建时会保留上一次的值，直接用会先闪一排上一个源的卡片）。
    final raw = feed.valueOrNull;
    final data = (raw != null && raw.filterKey == filter.key) ? raw : null;
    final items = data?.items ?? const <ScrapedGame>[];
    final shown = _filterLoaded(items, _localQuery).length;

    return KPage(
      title: '探索',
      subtitle: _subtitle(session),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toolbar(data, items.length, shown, session),
          Expanded(
            child: FadeThroughSwitcher(
              child: KeyedSubtree(
                key: ValueKey(_mode),
                child: _mode == DiscoverMode.resource
                    ? ResourceSearchPane(onRerun: _rerunResourceSearch)
                    : _exploreBody(feed, data, items),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(ResourceSearchState session) => switch (_mode) {
        DiscoverMode.explore => '浏览 VNDB / Bangumi 榜单，筛选后一键入库',
        DiscoverMode.resource => session.started
            ? '共 ${session.items.length} 条 · 按相关度排序'
            : '聚合资源站发布页 · 只提供链接，不托管资源',
      };

  // ==================== 工具条（两种模式共享） ====================

  Widget _toolbar(
    DiscoverFeedState? data,
    int loaded,
    int shown,
    ResourceSearchState session,
  ) {
    return KToolbar(
      children: [
        // 模式切换：看榜单（探索）/ 找下载页（资源）
        for (final m in DiscoverMode.values) ...[
          KChip(
            label: m.label,
            icon: m.icon,
            selected: _mode == m,
            onTap: () => _setMode(m),
          ),
          const SizedBox(width: Gap.sm),
        ],
        const SizedBox(width: Gap.sm),
        // 搜索框：两种模式同宽同位（探索=过滤已加载条目，资源=关键词搜索）。
        // 宽度与游戏库工具条的搜索框一致（300）。
        SizedBox(
          width: _kSearchWidth,
          child: FadeThroughSwitcher(
            child: KeyedSubtree(
              key: ValueKey(_mode),
              child: _mode == DiscoverMode.explore
                  ? _localSearchField()
                  : _resourceSearchField(),
            ),
          ),
        ),
        const SizedBox(width: Gap.md),
        // 探索：视图操作一律右对齐（与游戏库的工具条同一个布局节奏）；
        // 资源：「搜索」是主操作，紧贴输入框，进度徽标放右端。
        if (_mode == DiscoverMode.explore) ...[
          const Spacer(),
          ..._exploreActions(data, loaded, shown),
        ] else ...[
          _resourcePill(session),
          if (session.started) ...[
            const Spacer(),
            _resourceBadge(session),
          ],
        ],
      ],
    );
  }

  Widget _localSearchField() => TextField(
        controller: _localCtrl,
        onChanged: (v) => setState(() => _localQuery = v),
        decoration: InputDecoration(
          hintText: '搜索已加载的条目',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _localQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空搜索',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: _clearLocalQuery,
                ),
          isDense: true,
        ),
      );

  Widget _resourceSearchField() => TextField(
        controller: _resourceCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _startResourceSearch(),
        decoration: const InputDecoration(
          hintText: '搜索游戏名（中文名效果最好）',
          prefixIcon: Icon(Icons.search_rounded, size: 20),
          isDense: true,
        ),
      );

  List<Widget> _exploreActions(
      DiscoverFeedState? data, int loaded, int shown) {
    return [
      KBadge(
        icon: Icons.grid_view_rounded,
        // 数据源报告没有下一页时直接说清楚，省得用户一直往下滚
        text: data == null
            ? '尚未加载'
            : (shown != loaded
                ? '$shown / $loaded 部'
                : (data.hasMore ? '已加载 $loaded 部' : '已全部加载 $loaded 部')),
      ),
      KIconAction(
        icon: _sidebarVisible
            ? Icons.filter_alt_rounded
            : Icons.filter_alt_off_rounded,
        tooltip: _sidebarVisible ? '隐藏筛选栏' : '显示筛选栏',
        active: _sidebarVisible,
        onTap: _toggleSidebar,
      ),
      KIconAction(
        icon: Icons.refresh_rounded,
        tooltip: '刷新榜单（跳过 24 小时缓存重新拉第一页）',
        onTap: () => ref.read(discoverFeedProvider.notifier).refresh(),
      ),
    ];
  }

  /// 资源模式的进度/计数徽标（搜索中显示 n / N，完成后显示结果条数）。
  Widget _resourceBadge(ResourceSearchState s) {
    final scheme = Theme.of(context).colorScheme;
    return KBadge(
      icon: s.busy
          ? Icons.cloud_download_outlined
          : Icons.check_circle_outline_rounded,
      text: s.busy ? '${s.completed} / ${s.total}' : '共 ${s.items.length} 条',
      color: s.busy ? scheme.primary : scheme.onSurfaceVariant,
    );
  }

  /// 资源模式的主操作：实心药丸（与游戏库的「添加游戏」同一套原语）。
  Widget _resourcePill(ResourceSearchState s) => KPill(
        label: s.busy ? '搜索中…' : '搜索',
        icon: s.busy ? null : Icons.search_rounded,
        onTap: s.busy ? null : _startResourceSearch,
      );

  // ==================== 探索模式的内容区 ====================

  /// 网格 + 筛选栏（筛选栏与游戏库共用 [FilterSidebar]，布局也一致）。
  Widget _exploreBody(
    AsyncValue<DiscoverFeedState> feed,
    DiscoverFeedState? data,
    List<ScrapedGame> items,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ExplorePane(
            feed: feed,
            data: data,
            items: items,
            query: _localQuery,
            onClearQuery: _clearLocalQuery,
          ),
        ),
        if (_sidebarVisible) ...[
          const SizedBox(width: Gap.lg),
          const _DiscoverFilterSidebar(),
        ],
      ],
    );
  }
}

// ==================== 探索模式：榜单网格 ====================

/// 榜单网格：骨架 / 空态 / 失败态 / 无限滚动 / 入库 / 详情弹窗。
class _ExplorePane extends ConsumerStatefulWidget {
  final AsyncValue<DiscoverFeedState> feed;

  /// 当前筛选条件下的数据（null = 还没拉到 / 刚换条件 / 刚刷新）
  final DiscoverFeedState? data;
  final List<ScrapedGame> items;

  /// 本地搜索词（由页面工具条维护）
  final String query;
  final VoidCallback onClearQuery;

  const _ExplorePane({
    required this.feed,
    required this.data,
    required this.items,
    required this.query,
    required this.onClearQuery,
  });

  @override
  ConsumerState<_ExplorePane> createState() => _ExplorePaneState();
}

class _ExplorePaneState extends ConsumerState<_ExplorePane> {
  final _scroll = ScrollController();

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
    final data = widget.data;
    final items = widget.items;
    final visible = _filterLoaded(items, widget.query);
    // 已在库索引（key = `vndb:123` / `bgm:45678`）：一次查询供整屏卡片共用
    final library = ref.watch(discoverLibraryIndexProvider).valueOrNull ??
        const <String, Game>{};

    if (data != null && visible.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryLine(),
        Expanded(child: _body(data, items, visible, library)),
      ],
    );
  }

  /// 筛选摘要 + 数据源能力提示（避免「筛了但没生效」的困惑）。
  Widget _summaryLine() {
    final filter = ref.watch(discoverFilterProvider);
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

  /// [data] 为 null 表示「当前筛选条件下还没有数据」（首次加载 / 刚换条件 /
  /// 刚刷新），此时用骨架占位；`widget.feed.hasError` 则说明这个条件是拉失败了。
  Widget _body(
    DiscoverFeedState? data,
    List<ScrapedGame> items,
    List<ScrapedGame> visible,
    Map<String, Game> library,
  ) {
    if (data == null) {
      // 网络失败与「没有结果」是两回事：失败要把原因原样显示出来 + 给重试
      if (widget.feed.hasError) return _errorState(widget.feed.error);
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
        title: '已加载的条目里没有「${widget.query}」',
        subtitle: '本地搜索只过滤已加载的条目，继续向下滚动可以加载更多',
        actionLabel: '清空搜索',
        actionIcon: Icons.close_rounded,
        onAction: widget.onClearQuery,
      );
    }

    // 页尾：加载骨架 +（失败时）一行重试卡
    final preloading = data.preloading;
    final tailError = data.error;
    final tail = (preloading ? 4 : 0) + (tailError == null ? 0 : 1);

    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: Gap.xl),
      gridDelegate: _kGridDelegate,
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
      gridDelegate: _kGridDelegate,
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
  /// 与资源搜索、添加页走的是同一条落库路径。
  Future<void> _addToLibrary(ScrapedGame g) async {
    final key = discoverLibraryKey(g);
    if (_adding.contains(key)) return;
    setState(() => _adding.add(key));
    try {
      final repo = AppServices.I.repo;
      // 按标题再兜一次重名：同一作品可能已经以**另一个源 id**入库过
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

// ==================== 筛选边栏 ====================

/// 探索模式的筛选边栏：来源 / 排序 / 最低评分 / 年份 / 显示内容 / 标签。
///
/// 原先这些条件在一个筛选弹窗里（改完点「应用」才生效），现在搬进与游戏库
/// 同一个 [FilterSidebar]：点一下即生效、条件始终可见、有生效条件时置顶
/// 「清除全部筛选」。改动只落在 [discoverFeedProvider.updateFilter] 一处，
/// 因此「相同条件不重复拉取」「年份区间自动摆正」等既有保护都还在。
class _DiscoverFilterSidebar extends ConsumerStatefulWidget {
  const _DiscoverFilterSidebar();

  @override
  ConsumerState<_DiscoverFilterSidebar> createState() =>
      _DiscoverFilterSidebarState();
}

class _DiscoverFilterSidebarState
    extends ConsumerState<_DiscoverFilterSidebar> {
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

  /// 折叠前显示的标签数（VNDB 标签很多，铺满整屏反而挑不出来）
  static const _kTagsCollapsed = 8;

  /// 年份可选范围：只认四位年份。
  /// `browse` 会把 yearFrom/yearTo 原样下发给数据源，把「20」（用户还在输
  /// 入的那半截）或「abcd」当成条件发出去，轻则筛出莫名其妙的结果、
  /// 重则数据源直接报错把整页变成失败态，所以这里要卡住。
  static const _kMinYear = 1900;
  static const _kMaxYear = 2100;

  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  /// 年份输入框的焦点：失焦即视为「填完了」并提交
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  /// 上一帧的聚焦状态：焦点在两格之间转移（起 → 止）时也要提交，
  /// 不能只在「两格都没焦点」时提交，否则用户清空的那格会被写回旧值。
  bool _fromHadFocus = false;
  bool _toHadFocus = false;

  bool _tagsExpanded = false;

  @override
  void initState() {
    super.initState();
    // 年份区间不能停在半截数字上：回车或点到别处就提交。
    // 不在 onChanged 里逐字符提交——`updateFilter` 会把颠倒的区间摆正，
    // 逐字符提交会在用户还没填完时把两格文字互换，很难理解。
    _fromFocus.addListener(_onFromFocus);
    _toFocus.addListener(_onToFocus);
  }

  void _onFromFocus() {
    final has = _fromFocus.hasFocus;
    if (_fromHadFocus && !has) _scheduleCommit();
    _fromHadFocus = has;
  }

  void _onToFocus() {
    final has = _toFocus.hasFocus;
    if (_toHadFocus && !has) _scheduleCommit();
    _toHadFocus = has;
  }

  /// 失焦也会在「切模式 / 关页面」时被动发生（元素被移出树）。推到帧末再提交：
  /// 那时已卸载就直接放弃（那时再读 provider 没有意义，也不该触发网络请求）。
  void _scheduleCommit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commitYears();
    });
  }

  @override
  void dispose() {
    _fromFocus.dispose();
    _toFocus.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  /// 解析一格年份：只有合法四位年份才算数，其余（半截数字 / 乱填）返回 null。
  static int? _parseYear(String text) {
    final v = int.tryParse(text.trim());
    if (v == null || v < _kMinYear || v > _kMaxYear) return null;
    return v;
  }

  /// 提交年份输入（回车 / 失焦）：两格一起校验后应用，摆正由
  /// [DiscoverFeed.updateFilter] 负责，随后 [_syncYearFields] 会把结果写回两格。
  ///
  /// [notify] 为 true（回车提交，用户明确表示填完了）时，非法输入会给提示；
  /// 失焦提交默认静默回滚——点到另一格时用户往往只是还在输入。
  void _commitYears({bool notify = false}) {
    if (!mounted) return;
    final f = ref.read(discoverFilterProvider);
    final fromText = _fromCtrl.text.trim();
    final toText = _toCtrl.text.trim();
    final from = _parseYear(fromText);
    final to = _parseYear(toText);
    final badFrom = fromText.isNotEmpty && from == null;
    final badTo = toText.isNotEmpty && to == null;
    if (badFrom || badTo) {
      // 非法输入不提交：把出问题的那格恢复成当前条件值（不留「显示与条件不一致」）
      if (badFrom) _setText(_fromCtrl, f.yearFrom?.toString() ?? '');
      if (badTo) _setText(_toCtrl, f.yearTo?.toString() ?? '');
      if (notify) {
        showNotice('年份请填四位数字（$_kMinYear-$_kMaxYear），留空表示不限',
            error: true);
      }
      return;
    }
    if (from == f.yearFrom && to == f.yearTo) return;
    _apply(f.copyWith(yearFrom: from, yearTo: to));
  }

  /// 应用新条件：统一走 [DiscoverFeed.updateFilter]（内部会 normalized +
  /// 相同条件短路），避免各处直接写 provider 造成重复的网络请求。
  void _apply(DiscoverFilter next) =>
      ref.read(discoverFeedProvider.notifier).updateFilter(next);

  /// 年份输入框与当前条件对账。
  ///
  /// - **正在输入的那一格不动**：年份条件只在回车/失焦时才更新，输入过程中
  ///   文字本来就和条件不一致，在这里回写会把用户刚敲进去的字符吃掉；
  /// - 其余情况（点区间 chip、点「清除全部筛选」、条件被外部改动）一律按条件值
  ///   回写，包含「框里留着半截/非法文字」的情况，避免显示与条件长期不一致。
  void _syncYearFields(DiscoverFilter f) {
    if (!_fromFocus.hasFocus && _yearTextDiffers(_fromCtrl.text, f.yearFrom)) {
      _setText(_fromCtrl, f.yearFrom?.toString() ?? '');
    }
    if (!_toFocus.hasFocus && _yearTextDiffers(_toCtrl.text, f.yearTo)) {
      _setText(_toCtrl, f.yearTo?.toString() ?? '');
    }
  }

  /// 输入文字与条件值是否不一致（含「非空但解析不出合法年份」）。
  static bool _yearTextDiffers(String text, int? value) {
    final t = text.trim();
    if (t.isEmpty) return value != null;
    final parsed = _parseYear(t);
    return parsed == null || parsed != value;
  }

  static void _setText(TextEditingController c, String text) {
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(discoverFilterProvider);
    final scheme = Theme.of(context).colorScheme;
    _syncYearFields(filter);

    return FilterSidebar(
      // 「清除全部筛选」置顶，仅在筛选生效时显示（保留来源与排序）
      leading: filter.hasActiveFilters
          ? FilterClearButton(
              onTap: () {
                _setText(_fromCtrl, '');
                _setText(_toCtrl, '');
                _apply(filter.cleared());
              },
            )
          : null,
      sections: [
        FilterSection(
          title: '来源',
          // 数据源能力说明：避免用户以为「筛了却没生效」
          hint: filter.source.hint,
          children: [
            for (final s in DiscoverSource.values)
              KChip(
                label: s.label,
                selected: filter.source == s,
                onTap: () => _apply(filter.copyWith(source: s)),
              ),
          ],
        ),
        FilterSection(
          title: '排序',
          children: [
            for (final s in DiscoverSort.values)
              KChip(
                label: s.label,
                selected: filter.sort == s,
                onTap: () => _apply(filter.copyWith(sort: s)),
              ),
          ],
        ),
        FilterSection(
          title: '最低评分',
          children: [
            for (final r in _ratings)
              KChip(
                label: r == 0 ? '不限' : '≥ ${_trimRating(r)}',
                selected: filter.minRating == r,
                onTap: () => _apply(filter.copyWith(minRating: r)),
              ),
          ],
        ),
        FilterSection(
          title: '年份',
          children: [
            for (final r in _ranges)
              KChip(
                label: r.label,
                selected: filter.yearFrom == r.from && filter.yearTo == r.to,
                onTap: () {
                  _setText(_fromCtrl, r.from?.toString() ?? '');
                  _setText(_toCtrl, r.to?.toString() ?? '');
                  _apply(filter.copyWith(yearFrom: r.from, yearTo: r.to));
                },
              ),
          ],
          // 自定义区间：两格窄输入（侧栏只有 210 宽，留空表示不限，回车提交）
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _fromCtrl,
                      focusNode: _fromFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commitYears(notify: true),
                      decoration:
                          const InputDecoration(hintText: '起', isDense: true),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Text('—',
                      style: Type.caption
                          .copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(width: Gap.sm),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _toCtrl,
                      focusNode: _toFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commitYears(notify: true),
                      decoration:
                          const InputDecoration(hintText: '止', isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text('填完按回车生效，留空表示不限',
                  style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        FilterSection(
          title: '显示内容',
          children: [
            KChip(
              label: '仅全年龄',
              selected: filter.onlySfw,
              onTap: () => _apply(filter.copyWith(onlySfw: true)),
            ),
            KChip(
              label: '含 R18',
              // 与设置页/R18 提示同一套强调色：这是「结果会变脏」的开关
              color: KisakiColors.warning,
              selected: !filter.onlySfw,
              onTap: () => _apply(filter.copyWith(onlySfw: false)),
            ),
          ],
        ),
        FilterSection(
          title: '标签',
          hint: filter.source == DiscoverSource.bgm
              ? 'Bangumi 不支持标签筛选，此条件不生效'
              : '多选为「同时满足」',
          trailing: _tagToggle(),
          // 标签搜索框：数量多时先过滤再选
          above: TextField(
            controller: _tagCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '过滤标签',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
          ),
          children: _tagChips(filter),
        ),
      ],
    );
  }

  /// 标签列表：默认折叠显示前 N 个（热门），点「更多」展开；
  /// 输入过滤词时直接显示全部命中项。
  List<Widget> _tagChips(DiscoverFilter filter) {
    final q = _tagCtrl.text.trim().toLowerCase();
    final all = DiscoverTags.presets;
    final List<({String id, String label})> shown;
    if (q.isEmpty) {
      shown = _tagsExpanded
          ? [...all]
          : all.take(_kTagsCollapsed).toList(growable: true);
      // 已选中的标签一定显示（否则会出现「选了却看不见、也取消不掉」）
      for (final t in all) {
        if (filter.tagIds.contains(t.id) && !shown.contains(t)) shown.add(t);
      }
    } else {
      shown = all
          .where((t) =>
              t.label.toLowerCase().contains(q) || t.id.contains(q))
          .toList();
    }
    return [
      for (final t in shown)
        KChip(
          label: t.label,
          icon: Icons.tag_rounded,
          selected: filter.tagIds.contains(t.id),
          onTap: () => _apply(filter.toggleTag(t.id)),
        ),
    ];
  }

  /// 「更多 / 收起」：只在折叠确实藏了东西时出现（正在过滤时不出现）。
  Widget? _tagToggle() {
    if (DiscoverTags.presets.length <= _kTagsCollapsed) return null;
    if (_tagCtrl.text.trim().isNotEmpty) return null;
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => setState(() => _tagsExpanded = !_tagsExpanded),
      child: Text(
        _tagsExpanded ? '收起' : '更多',
        style: Type.caption.copyWith(color: scheme.primary),
      ),
    );
  }
}
