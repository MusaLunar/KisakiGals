/// 探索页：Fluent 2 多源聚合榜单浏览与全网百科搜索（与游戏库共享统一工具栏、筛选栏与网格/列表视觉语言）。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import '../library/filter_rail.dart' show kFilterRailWidth;
import '../library/game_actions.dart';
import '../shell/tabs.dart';
import 'discover_filter_state.dart';
import 'discover_state.dart';
import 'game_explore_page.dart';

/// 探索页主视图（发现聚合榜单与全网多源关键词搜索）。
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final Set<String> _adding = {};
  bool _sidebarVisible = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    final services = tryAppServices();
    if (services != null) {
      services.settings
          .getBool(SettingsStore.kDiscoverSidebar, def: false)
          .then((v) {
        if (mounted) setState(() => _sidebarVisible = v);
      });
    }

    final pending = ref.read(resourceQueryProvider).trim();
    _searchCtrl.text =
        pending.isNotEmpty ? pending : ref.read(discoverFilterProvider).keyword;
    if (pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumePendingQuery(pending);
      });
    }
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed &&
        ref.read(tabIndexProvider) == Tabs.discover &&
        _searchFocus.canRequestFocus) {
      _searchFocus.requestFocus();
      if (_searchCtrl.text.isNotEmpty) {
        _searchCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchCtrl.text.length,
        );
      }
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarVisible = !_sidebarVisible);
    await tryAppServices()
        ?.settings
        .setBool(SettingsStore.kDiscoverSidebar, _sidebarVisible);
  }

  Future<void> _setLayout(String next) async {
    if (ref.read(discoverLayoutProvider) == next) return;
    ref.read(discoverLayoutProvider.notifier).state = next;
    await tryAppServices()
        ?.settings
        .setString(SettingsStore.kDiscoverLayout, next);
  }

  void _submitSearch() {
    final kw = _searchCtrl.text.trim();
    final filter = ref.read(discoverFilterProvider);
    if (kw != filter.keyword) {
      ref
          .read(discoverFeedProvider.notifier)
          .updateFilter(filter.withKeyword(kw));
    }
    setState(() {});
  }

  void _clearSearch() {
    _searchCtrl.clear();
    final filter = ref.read(discoverFilterProvider);
    if (filter.keyword.isNotEmpty) {
      ref.read(discoverFeedProvider.notifier).updateFilter(filter.browse());
    }
    setState(() {});
    _searchFocus.requestFocus();
  }

  void _consumePendingQuery(String kw) {
    if (_searchCtrl.text != kw) {
      _searchCtrl.value = TextEditingValue(
        text: kw,
        selection: TextSelection(baseOffset: 0, extentOffset: kw.length),
      );
    }
    ref.read(resourceQueryProvider.notifier).state = '';
    final filter = ref.read(discoverFilterProvider);
    if (filter.keyword != kw) {
      ref
          .read(discoverFeedProvider.notifier)
          .updateFilter(filter.withKeyword(kw));
    }
    if (mounted) setState(() {});
  }

  List<ScrapedGame> _filterLoaded(
    List<ScrapedGame> items,
    DiscoverFilter filter,
  ) {
    final typed = _searchCtrl.text.trim();
    if (typed.isEmpty || typed == filter.keyword) return items;
    final norm = normalizeForMatch(typed);
    return items.where((g) {
      for (final s in [g.displayName, g.name, g.nameCn, ...g.aliases]) {
        if (s.isNotEmpty && normalizeForMatch(s).contains(norm)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Future<void> _openDetail(ScrapedGame g) {
    return pushFluentPage(
      context,
      (_) => GameExplorePage(
        seedGame: g,
        onAdd: _addToLibrary,
      ),
    );
  }

  Future<void> _addToLibrary(ScrapedGame g) async {
    final services = tryAppServices();
    if (services == null) {
      showNotice('当前为离线预览模式，无法写入本地游戏库');
      return;
    }
    final key = discoverLibraryKey(g);
    if (_adding.contains(key)) return;
    setState(() => _adding.add(key));
    try {
      final repo = services.repo;
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
      await repo.insertGame(game);
      await ScrapeApplier(repo, services.fetcher).apply(game, [g]);
      if (!mounted) return;
      ref.read(libraryVersionProvider.notifier).state++;
      showNotice('已入库：${game.displayName}');
    } catch (e) {
      if (mounted) showNotice('入库失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _adding.remove(key));
    }
  }

  void _clearAllFilters(DiscoverFilter filter) {
    _searchCtrl.clear();
    ref
        .read(discoverFeedProvider.notifier)
        .updateFilter(filter.browse().cleared());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(resourceQueryProvider, (prev, next) {
      final kw = next.trim();
      if (kw.isNotEmpty) {
        Future.microtask(() {
          if (mounted) _consumePendingQuery(kw);
        });
      }
    });

    final filter = ref.watch(discoverFilterProvider);
    final layout = ref.watch(discoverLayoutProvider);
    final feedAsync = ref.watch(discoverFeedProvider);
    final libIndex = ref.watch(discoverLibraryIndexProvider).valueOrNull ??
        const <String, Game>{};

    return ensureFluentTheme(
      context,
      Builder(
        builder: (ctx) {
          final disableAnim = fluentAnimationsDisabled(ctx);
          final theme = FluentTheme.of(ctx);
          final accent = theme.accentInk;
          final filterCount = _activeFilterCount(filter);
          final isLoading = feedAsync.isLoading;
          final subtitle = '${filter.source.label} · ${filter.summary}';

          return ScaffoldPage(
            padding: EdgeInsets.zero,
            header: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('探索', style: theme.typography.title),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.typography.caption?.copyWith(
                              color: theme.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: CommandBar(
                                overflowBehavior:
                                    CommandBarOverflowBehavior.dynamicOverflow,
                                mainAxisAlignment: MainAxisAlignment.end,
                                isCompact: false,
                                primaryItems: [
                                  CommandBarButton(
                                    icon: const Icon(
                                      FluentIcons.arrow_clockwise_16_regular,
                                    ),
                                    label: Text(isLoading ? '加载中…' : '刷新'),
                                    onPressed: isLoading
                                        ? null
                                        : () => ref
                                            .read(discoverFeedProvider.notifier)
                                            .refresh(),
                                  ),
                                  CommandBarButton(
                                    icon: Icon(
                                      FluentIcons.filter_16_regular,
                                      color: (_sidebarVisible ||
                                              filterCount > 0)
                                          ? accent
                                          : null,
                                    ),
                                    label: Text(
                                      filterCount > 0
                                          ? '筛选栏 ($filterCount)'
                                          : '筛选栏',
                                    ),
                                    onPressed: _toggleSidebar,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FluentSegmentedControl<String>(
                              compact: true,
                              selected: layout == 'list' ? 'list' : 'grid',
                              onChanged: _setLayout,
                              items: const [
                                FluentSegmentItem<String>(
                                  value: 'grid',
                                  label: '网格视图',
                                  tooltip: '网格视图',
                                  icon: FluentIcons.grid_16_regular,
                                  showLabel: false,
                                ),
                                FluentSegmentItem<String>(
                                  value: 'list',
                                  label: '列表视图',
                                  tooltip: '列表视图',
                                  icon: FluentIcons.text_bullet_list_16_regular,
                                  showLabel: false,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildUnifiedControlRow(ctx, filter),
                  if (filter.searching || filter.hasActiveFilters) ...[
                    const SizedBox(height: 10),
                    _ActiveDiscoverFilterChipsRow(
                      filter: filter,
                      onClearKeyword: _clearSearch,
                      onUpdateFilter: (next) => ref
                          .read(discoverFeedProvider.notifier)
                          .updateFilter(next),
                      onClearAll: () => _clearAllFilters(filter),
                    ),
                  ],
                ],
              ),
            ),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildFeedBody(
                      ctx,
                      filter,
                      layout,
                      feedAsync,
                      libIndex,
                    ),
                  ),
                  AnimatedContainer(
                    duration:
                        disableAnim ? Duration.zero : FluentMotion.standard,
                    curve: FluentMotion.enterCurve,
                    width: _sidebarVisible ? 16 : 0,
                  ),
                  if (disableAnim)
                    (_sidebarVisible
                        ? SizedBox(
                            width: kFilterRailWidth,
                            child: _DiscoverFilterRail(
                              filter: filter,
                              onChanged: (next) => ref
                                  .read(discoverFeedProvider.notifier)
                                  .updateFilter(next),
                            ),
                          )
                        : const SizedBox.shrink())
                  else
                    AnimatedSize(
                      duration: FluentMotion.standard,
                      curve: FluentMotion.enterCurve,
                      alignment: Alignment.centerRight,
                      child: _sidebarVisible
                          ? SizedBox(
                              width: kFilterRailWidth,
                              child: _DiscoverFilterRail(
                                filter: filter,
                                onChanged: (next) => ref
                                    .read(discoverFeedProvider.notifier)
                                    .updateFilter(next),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUnifiedControlRow(
    BuildContext context,
    DiscoverFilter filter,
  ) {
    final theme = FluentTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final searchArea = Row(
          children: [
            Flexible(
              child: FluentSearchBox(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                maxWidth: 420,
                shortcutHint: 'Ctrl+F',
                placeholder: '搜索全网百科：作品名 / 原名（输入过滤，回车全网检索）',
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitSearch(),
                onCleared: _clearSearch,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _submitSearch,
              child: const Text('搜索'),
            ),
          ],
        );

        final combos = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '数据源',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 120,
              child: ComboBox<DiscoverSource>(
                isExpanded: true,
                value: filter.source,
                items: [
                  for (final s in DiscoverSource.values)
                    ComboBoxItem<DiscoverSource>(
                      value: s,
                      child: Text(s.label),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  ref
                      .read(discoverFeedProvider.notifier)
                      .updateFilter(filter.withSource(v));
                },
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '排序',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 142,
              child: ComboBox<DiscoverSort>(
                isExpanded: true,
                value: filter.sort,
                items: [
                  for (final s in DiscoverSort.values)
                    ComboBoxItem<DiscoverSort>(
                      value: s,
                      child: Text(s.label),
                    ),
                ],
                onChanged: filter.searching
                    ? null
                    : (v) {
                        if (v == null) return;
                        ref
                            .read(discoverFeedProvider.notifier)
                            .updateFilter(filter.copyWith(sort: v));
                      },
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchArea,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: combos),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: searchArea),
            const SizedBox(width: 12),
            combos,
          ],
        );
      },
    );
  }

  Widget _buildFeedBody(
    BuildContext context,
    DiscoverFilter filter,
    String layout,
    AsyncValue<DiscoverFeedState> feedAsync,
    Map<String, Game> libIndex,
  ) {
    if (feedAsync.isLoading && !feedAsync.hasValue) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ProgressRing(),
            const SizedBox(height: 12),
            Text(
              filter.searching
                  ? '正在搜索「${filter.keyword}」…'
                  : '正在拉取 ${filter.source.label} 榜单…',
            ),
          ],
        ),
      );
    }

    if (feedAsync.hasError && !feedAsync.hasValue) {
      return FluentEmptyState(
        icon: FluentIcons.cloud_off_24_regular,
        title: '探索列表加载失败',
        message: '${feedAsync.error}',
        action: FilledButton(
          onPressed: () =>
              ref.read(discoverFeedProvider.notifier).refresh(),
          child: const Text('重新加载'),
        ),
      );
    }

    final data = feedAsync.valueOrNull;
    if (data == null || (data.filterKey != filter.key && feedAsync.isLoading)) {
      return const Center(child: ProgressRing());
    }

    final visible = _filterLoaded(data.items, filter);
    final typed = _searchCtrl.text.trim();
    if (visible.isEmpty) {
      if (typed.isNotEmpty && typed != filter.keyword) {
        return FluentEmptyState(
          icon: FluentIcons.search_24_regular,
          title: '当前已加载条目中无「$typed」',
          message: '上方输入仅过滤当前已加载列表，点击下方可直接向 ${filter.source.label} 发起全网搜索。',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _submitSearch,
                child: Text('全网搜索「$typed」'),
              ),
              Button(
                onPressed: _clearSearch,
                child: const Text('清空搜索'),
              ),
            ],
          ),
        );
      }
      return FluentEmptyState(
        icon: FluentIcons.compass_northwest_16_regular,
        title: filter.searching ? '未搜索到相关作品' : '当前条件下暂无作品',
        message: filter.searching
            ? '尝试使用日文原名、简写或切换右侧「仅全年龄 / 含 R18」设置。'
            : '尝试放宽评分下限、年份范围或切换至 VNDB / Bangumi。',
        action: filter.searching
            ? FilledButton(
                onPressed: _clearSearch,
                child: const Text('返回榜单'),
              )
            : (filter.hasActiveFilters
                ? FilledButton(
                    onPressed: () => ref
                        .read(discoverFeedProvider.notifier)
                        .updateFilter(filter.cleared()),
                    child: const Text('清空筛选'),
                  )
                : null),
      );
    }

    final hasFooter = data.preloading || data.error != null || data.hasMore;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400 &&
            data.hasMore &&
            !data.preloading) {
          ref.read(discoverFeedProvider.notifier).loadMore();
        }
        return false;
      },
      child: layout == 'list'
          ? ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: visible.length + (hasFooter ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= visible.length) {
                  return _buildFooterTile(context, data);
                }
                final g = visible[index];
                final libKey = discoverLibraryKey(g);
                return _DiscoverGameListTile(
                  game: g,
                  inLibrary: libIndex.containsKey(libKey),
                  adding: _adding.contains(libKey),
                  onTap: () => _openDetail(g),
                  onAdd: () => _addToLibrary(g),
                );
              },
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(bottom: hasFooter ? 14 : 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: 344,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final g = visible[index];
                        final libKey = discoverLibraryKey(g);
                        return _DiscoverGameCard(
                          game: g,
                          inLibrary: libIndex.containsKey(libKey),
                          adding: _adding.contains(libKey),
                          onTap: () => _openDetail(g),
                          onAdd: () => _addToLibrary(g),
                        );
                      },
                      childCount: visible.length,
                    ),
                  ),
                ),
                if (hasFooter)
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 16),
                    sliver: SliverToBoxAdapter(
                      child: _buildFooterTile(context, data),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildFooterTile(BuildContext context, DiscoverFeedState data) {
    final theme = FluentTheme.of(context);
    if (data.preloading) {
      return const FluentSurfaceCard(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: ProgressRing(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('加载下一页…'),
          ],
        ),
      );
    }
    if (data.error != null) {
      return FluentSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => ref.read(discoverFeedProvider.notifier).loadMore(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.cloud_off_24_regular,
              size: 22,
              color: theme.dangerInk,
            ),
            const SizedBox(height: 6),
            Text('加载下一页失败', style: theme.typography.bodyStrong),
            const SizedBox(height: 4),
            Text(
              data.error!,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点击重试',
              style: theme.typography.caption?.copyWith(color: theme.accentInk),
            ),
          ],
        ),
      );
    }
    return FluentSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => ref.read(discoverFeedProvider.notifier).loadMore(),
      child: Center(
        child: Text(
          '继续加载更多',
          style: theme.typography.bodyStrong?.copyWith(color: theme.accentInk),
        ),
      ),
    );
  }

  static int _activeFilterCount(DiscoverFilter f) {
    var count = 0;
    if (f.minRating > 0) count++;
    if (f.yearFrom != null || f.yearTo != null) count++;
    if (f.onlySfw) count++;
    if (f.tagIds.isNotEmpty) count += f.tagIds.length;
    return count;
  }
}

class _ActiveDiscoverFilterChipsRow extends StatelessWidget {
  final DiscoverFilter filter;
  final VoidCallback onClearKeyword;
  final ValueChanged<DiscoverFilter> onUpdateFilter;
  final VoidCallback onClearAll;

  const _ActiveDiscoverFilterChipsRow({
    required this.filter,
    required this.onClearKeyword,
    required this.onUpdateFilter,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;

    Widget chip(String label, VoidCallback onRemove) => FluentBadge(
          text: '$label ×',
          foreground: accent,
          background: theme.accentTint,
          tooltip: '移除该筛选条件',
          onTap: onRemove,
        );

    final yearLabel = switch ((filter.yearFrom, filter.yearTo)) {
      (final int from, final int to) => from == to ? '$from 年' : '$from-$to 年',
      (final int from, null) => '$from 年以后',
      (null, final int to) => '$to 年以前',
      _ => null,
    };

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (filter.searching)
          chip('搜索: ${filter.keyword}', onClearKeyword),
        if (filter.onlySfw)
          chip('仅全年龄', () => onUpdateFilter(filter.copyWith(onlySfw: false))),
        if (filter.minRating > 0)
          chip(
            '评分 ≥ ${filter.minRating == filter.minRating.roundToDouble() ? filter.minRating.toStringAsFixed(0) : filter.minRating.toStringAsFixed(1)}',
            () => onUpdateFilter(filter.copyWith(minRating: 0)),
          ),
        if (yearLabel != null)
          chip(
            '年份: $yearLabel',
            () => onUpdateFilter(
              filter.copyWith(yearFrom: null, yearTo: null),
            ),
          ),
        for (final tagId in filter.tagIds)
          chip(
            '#${DiscoverTags.label(tagId)}',
            () => onUpdateFilter(filter.toggleTag(tagId)),
          ),
        FluentBadge(
          text: '清除全部',
          foreground: theme.textSecondary,
          onTap: onClearAll,
        ),
      ],
    );
  }
}

class _DiscoverGameCard extends StatelessWidget {
  final ScrapedGame game;
  final bool inLibrary;
  final bool adding;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _DiscoverGameCard({
    required this.game,
    required this.inLibrary,
    required this.adding,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final year = game.releaseDate.length >= 4
        ? game.releaseDate.substring(0, 4)
        : '';
    final scoreText =
        game.rating > 0 ? game.rating.toStringAsFixed(1) : null;
    final voteText = game.voteCount > 0 ? '(${game.voteCount})' : null;

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                FluentCoverImage(
                  pathOrUrl: game.coverUrl,
                  nsfw: game.nsfw,
                  fit: BoxFit.cover,
                  radius: 6,
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: FluentBadge(
                    text: game.source.toUpperCase(),
                    foreground: Colors.white,
                    background: Colors.black.withValues(alpha: 0.62),
                  ),
                ),
                if (year.isNotEmpty)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: FluentBadge(
                      text: year,
                      foreground: Colors.white,
                      background: Colors.black.withValues(alpha: 0.62),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Text(
              game.displayName,
              style: theme.typography.bodyStrong?.copyWith(
                fontSize: 13,
                height: 1.32,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: FluentR18ScoreRow(
                nsfw: game.nsfw,
                scoreText: scoreText,
                voteText: voteText,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  game.developer.isNotEmpty ? game.developer : '开发商未知',
                  style: theme.typography.caption?.copyWith(
                    color: theme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (inLibrary)
                const FluentBadge(
                  text: '已在库',
                  icon: FluentIcons.checkmark_circle_16_filled,
                )
              else
                Button(
                  onPressed: adding ? null : onAdd,
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
                  child: adding
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Text('入库'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscoverGameListTile extends StatelessWidget {
  final ScrapedGame game;
  final bool inLibrary;
  final bool adding;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _DiscoverGameListTile({
    required this.game,
    required this.inLibrary,
    required this.adding,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final scoreText =
        game.rating > 0 ? game.rating.toStringAsFixed(1) : null;
    final voteText = game.voteCount > 0 ? '(${game.voteCount})' : null;
    final subParts = <String>[
      if (game.developer.isNotEmpty) game.developer,
      if (game.releaseDate.isNotEmpty) game.releaseDate,
    ];

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          FluentCoverImage(
            pathOrUrl: game.coverUrl,
            nsfw: game.nsfw,
            width: 56,
            height: 80,
            radius: 6,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.displayName,
                  style: theme.typography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (game.name.isNotEmpty && game.name != game.displayName) ...[
                  const SizedBox(height: 2),
                  Text(
                    game.name,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  subParts.isEmpty ? game.source.toUpperCase() : subParts.join(' · '),
                  style: theme.typography.caption?.copyWith(
                    color: theme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                FluentR18ScoreRow(
                  nsfw: game.nsfw,
                  scoreText: scoreText,
                  voteText: voteText,
                  trailing: [
                    FluentBadge(text: game.source.toUpperCase()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (inLibrary)
            const FluentBadge(
              text: '已在库',
              icon: FluentIcons.checkmark_circle_16_filled,
            )
          else
            FilledButton(
              onPressed: adding ? null : onAdd,
              child: adding
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Text('入库'),
            ),
        ],
      ),
    );
  }
}

class _DiscoverFilterRail extends StatefulWidget {
  final DiscoverFilter filter;
  final ValueChanged<DiscoverFilter> onChanged;

  const _DiscoverFilterRail({
    required this.filter,
    required this.onChanged,
  });

  @override
  State<_DiscoverFilterRail> createState() => _DiscoverFilterRailState();
}

class _DiscoverFilterRailState extends State<_DiscoverFilterRail> {
  final TextEditingController _yearFromCtrl = TextEditingController();
  final TextEditingController _yearToCtrl = TextEditingController();
  final TextEditingController _tagFilterCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncYearFields();
  }

  @override
  void didUpdateWidget(covariant _DiscoverFilterRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter.yearFrom != widget.filter.yearFrom ||
        oldWidget.filter.yearTo != widget.filter.yearTo) {
      _syncYearFields();
    }
  }

  void _syncYearFields() {
    _yearFromCtrl.text = widget.filter.yearFrom?.toString() ?? '';
    _yearToCtrl.text = widget.filter.yearTo?.toString() ?? '';
  }

  @override
  void dispose() {
    _yearFromCtrl.dispose();
    _yearToCtrl.dispose();
    _tagFilterCtrl.dispose();
    super.dispose();
  }

  void _applyYears() {
    final from = int.tryParse(_yearFromCtrl.text.trim());
    final to = int.tryParse(_yearToCtrl.text.trim());
    widget.onChanged(
      widget.filter.copyWith(yearFrom: from, yearTo: to).normalized(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final f = widget.filter;
    final vndbTagsEnabled = f.source == DiscoverSource.vndb;
    final tagQuery = _tagFilterCtrl.text.trim().toLowerCase();
    final filteredTags = DiscoverTags.presets.where((t) {
      if (tagQuery.isEmpty) return true;
      return t.label.toLowerCase().contains(tagQuery) ||
          t.id.toLowerCase().contains(tagQuery);
    }).toList();

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: ListView(
        padding: const EdgeInsetsDirectional.only(end: 10),
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.filter_16_regular,
                size: 16,
                color: theme.accentInk,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('筛选条件', style: theme.typography.bodyStrong),
              ),
              if (f.hasActiveFilters)
                Button(
                  onPressed: () => widget.onChanged(f.cleared()),
                  child: const Text('重置'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            f.source.hint,
            style: theme.typography.caption?.copyWith(
              color: theme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Text('内容分级', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RailChoiceChip(
                label: '仅全年龄',
                selected: f.onlySfw,
                onTap: () => widget.onChanged(f.copyWith(onlySfw: true)),
              ),
              _RailChoiceChip(
                label: '含 R18',
                selected: !f.onlySfw,
                onTap: () => widget.onChanged(f.copyWith(onlySfw: false)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('最低评分', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final score in const [0.0, 6.0, 7.0, 8.0, 8.5])
                _RailChoiceChip(
                  label: score == 0
                      ? '不限'
                      : '${score.toStringAsFixed(score % 1 == 0 ? 0 : 1)}+',
                  selected: f.minRating == score,
                  onTap: () => widget.onChanged(f.copyWith(minRating: score)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('发售年份', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _yearFromCtrl,
                  placeholder: '起始年',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onSubmitted: (_) => _applyYears(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('-'),
              ),
              Expanded(
                child: TextBox(
                  controller: _yearToCtrl,
                  placeholder: '结束年',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onSubmitted: (_) => _applyYears(),
                ),
              ),
              const SizedBox(width: 6),
              Button(
                onPressed: _applyYears,
                child: const Text('应用'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _RailChoiceChip(
                label: '全部年份',
                selected: f.yearFrom == null && f.yearTo == null,
                onTap: () =>
                    widget.onChanged(f.copyWith(yearFrom: null, yearTo: null)),
              ),
              _RailChoiceChip(
                label: '2020+',
                selected: f.yearFrom == 2020 && f.yearTo == null,
                onTap: () =>
                    widget.onChanged(f.copyWith(yearFrom: 2020, yearTo: null)),
              ),
              _RailChoiceChip(
                label: '2015-2019',
                selected: f.yearFrom == 2015 && f.yearTo == 2019,
                onTap: () =>
                    widget.onChanged(f.copyWith(yearFrom: 2015, yearTo: 2019)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            vndbTagsEnabled ? '题材标签（VNDB）' : '题材标签（切换 VNDB 生效）',
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 8),
          FluentSearchBox(
            controller: _tagFilterCtrl,
            compact: true,
            enabled: vndbTagsEnabled,
            placeholder: vndbTagsEnabled ? '筛选标签…' : '需切换至 VNDB',
            onChanged: (_) => setState(() {}),
            onCleared: () {
              _tagFilterCtrl.clear();
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          if (filteredTags.isEmpty)
            Text(
              '没有匹配的预设标签',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in filteredTags)
                  _RailChoiceChip(
                    label: t.label,
                    selected: f.tagIds.contains(t.id),
                    onTap: vndbTagsEnabled
                        ? () => widget.onChanged(f.toggleTag(t.id))
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RailChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _RailChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final disabled = onTap == null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: label,
      child: HoverButton(
        onPressed: onTap,
        builder: (context, states) {
          final bg = selected
              ? theme.accentTint
              : states.isHovered && !disabled
                  ? theme.subtleHover
                  : theme.surfaceCardSecondary;
          final border = selected
              ? theme.accentInk.withValues(alpha: 0.55)
              : theme.surfaceStroke;
          return FocusBorder(
            focused: states.isFocused,
            child: AnimatedContainer(
              duration: fluentAnimationsDisabled(context)
                  ? Duration.zero
                  : FluentMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Text(
                label,
                style: theme.typography.caption?.copyWith(
                  color: disabled
                      ? theme.textDisabled
                      : selected
                          ? theme.accentInk
                          : theme.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
