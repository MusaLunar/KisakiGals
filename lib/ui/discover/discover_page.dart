/// 探索页：聚合百科榜单浏览 / 多源关键词搜索 / 全网流式资源检索（Fluent 2）。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
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
import '../library/game_actions.dart';
import 'discover_filter_state.dart';
import 'discover_state.dart';
import 'game_explore_page.dart';
import 'resource_links.dart';

/// 探索页主视图（包含「发现聚合」与「资源检索」双模式切换）。
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
  String _resourceQuerySeed = '';

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Widget _wrapFluent(
    BuildContext context,
    Widget Function(BuildContext ctx) builder,
  ) {
    final hasTheme = FluentTheme.maybeOf(context) != null;
    final hasLoc = Localizations.of<FluentLocalizations>(
          context,
          FluentLocalizations,
        ) !=
        null;
    Widget wrapped = Builder(builder: builder);
    if (!hasLoc) {
      wrapped = Localizations.override(
        context: context,
        delegates: const [FluentLocalizations.delegate],
        child: wrapped,
      );
    }
    if (!hasTheme) {
      wrapped = ensureFluentTheme(context, wrapped);
    }
    return wrapped;
  }

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarVisible = !_sidebarVisible);
    await tryAppServices()
        ?.settings
        .setBool(SettingsStore.kDiscoverSidebar, _sidebarVisible);
  }

  Future<void> _toggleLayout() async {
    final next = ref.read(discoverLayoutProvider) == 'list' ? 'grid' : 'list';
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
    _resourceQuerySeed = kw;
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

    final mode = ref.watch(discoverModeProvider);
    final filter = ref.watch(discoverFilterProvider);
    final layout = ref.watch(discoverLayoutProvider);
    final feedAsync = ref.watch(discoverFeedProvider);
    final libIndex = ref.watch(discoverLibraryIndexProvider).valueOrNull ??
        const <String, Game>{};

    return _wrapFluent(
      context,
      (ctx) => ColoredBox(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(ctx, mode, filter),
            if (mode == DiscoverMode.aggregate) ...[
              _buildAggregateToolbar(ctx, filter, layout, feedAsync),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildFeedBody(ctx, filter, layout, feedAsync, libIndex),
                    ),
                    AnimatedSize(
                      duration: FluentMotion.standard,
                      curve: FluentMotion.enterCurve,
                      alignment: Alignment.centerRight,
                      child: _sidebarVisible
                          ? SizedBox(
                              width: 268,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: 24,
                                  bottom: 16,
                                ),
                                child: _DiscoverFilterRail(
                                  filter: filter,
                                  onChanged: (next) => ref
                                      .read(discoverFeedProvider.notifier)
                                      .updateFilter(next),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ] else
              Expanded(
                child: ResourceSearchPane(
                  initialKeyword: _resourceQuerySeed.isNotEmpty
                      ? _resourceQuerySeed
                      : filter.keyword,
                  onKeywordSubmitted: (kw) => _resourceQuerySeed = kw,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    DiscoverMode mode,
    DiscoverFilter filter,
  ) {
    final theme = FluentTheme.of(context);
    final subtitle = mode == DiscoverMode.aggregate
        ? '${filter.source.label} · ${filter.summary}'
        : mode.description;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('探索', style: theme.typography.title),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.typography.caption?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
              ),
            ],
          ),
          _ModeSegmentedSwitch(
            current: mode,
            onChanged: (next) {
              if (next == DiscoverMode.resource &&
                  _resourceQuerySeed.isEmpty &&
                  _searchCtrl.text.trim().isNotEmpty) {
                _resourceQuerySeed = _searchCtrl.text.trim();
              }
              ref.read(discoverModeProvider.notifier).state = next;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAggregateToolbar(
    BuildContext context,
    DiscoverFilter filter,
    String layout,
    AsyncValue<DiscoverFeedState> feedAsync,
  ) {
    final theme = FluentTheme.of(context);
    final isList = layout == 'list';
    final isLoading = feedAsync.isLoading;
    final typed = _searchCtrl.text.trim();
    final filterCount = _activeFilterCount(filter);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FluentSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            final searchBox = TextBox(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              placeholder: '搜索作品名 / 别名（输入即过滤，回车全网搜索）',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(FluentIcons.search_16_regular, size: 15),
              ),
              suffix: typed.isNotEmpty || filter.searching
                  ? IconButton(
                      icon: const Icon(FluentIcons.dismiss_16_regular, size: 13),
                      onPressed: _clearSearch,
                    )
                  : null,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitSearch(),
            );

            final sourceCombo = SizedBox(
              width: 122,
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
            );

            final sortCombo = SizedBox(
              width: 132,
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
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: _submitSearch,
                  child: const Text('搜索'),
                ),
                ToggleButton(
                  checked: _sidebarVisible,
                  onChanged: (_) => _toggleSidebar(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.filter_16_regular, size: 15),
                      const SizedBox(width: 6),
                      const Text('筛选'),
                      if (filterCount > 0) ...[
                        const SizedBox(width: 6),
                        FluentBadge(
                          text: '$filterCount',
                          foreground: theme.accentColor,
                          background: theme.accentColor.withValues(alpha: 0.14),
                        ),
                      ],
                    ],
                  ),
                ),
                Tooltip(
                  message: '切换视图',
                  child: IconButton(
                    icon: Icon(
                      isList
                          ? FluentIcons.grid_16_regular
                          : FluentIcons.text_bullet_list_16_regular,
                      size: 16,
                    ),
                    onPressed: _toggleLayout,
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: CommandBar(
                    isCompact: false,
                    overflowBehavior: CommandBarOverflowBehavior.clip,
                    primaryItems: [
                      CommandBarButton(
                        icon: const Icon(FluentIcons.arrow_clockwise_16_regular),
                        label: const Text('刷新'),
                        onPressed: isLoading
                            ? null
                            : () => ref
                                .read(discoverFeedProvider.notifier)
                                .refresh(),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: searchBox),
                      const SizedBox(width: 8),
                      sourceCombo,
                      const SizedBox(width: 8),
                      sortCombo,
                    ],
                  ),
                  const SizedBox(height: 8),
                  actions,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: searchBox),
                const SizedBox(width: 8),
                sourceCombo,
                const SizedBox(width: 8),
                sortCombo,
                const SizedBox(width: 10),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeedBody(
    BuildContext context,
    DiscoverFilter filter,
    String layout,
    AsyncValue<DiscoverFeedState> feedAsync,
    Map<String, Game> libIndex,
  ) {
    final padding = EdgeInsets.fromLTRB(24, 6, _sidebarVisible ? 12 : 24, 24);

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
      return Padding(
        padding: padding,
        child: FluentEmptyState(
          icon: FluentIcons.cloud_off_24_regular,
          title: '探索列表加载失败',
          message: '${feedAsync.error}',
          action: FilledButton(
            onPressed: () =>
                ref.read(discoverFeedProvider.notifier).refresh(),
            child: const Text('重新加载'),
          ),
        ),
      );
    }

    final data = feedAsync.valueOrNull;
    if (data == null || (data.filterKey != filter.key && feedAsync.isLoading)) {
      return const Center(child: ProgressRing());
    }

    final visible = _filterLoaded(data.items, filter);
    if (visible.isEmpty) {
      return Padding(
        padding: padding,
        child: FluentEmptyState(
          icon: FluentIcons.compass_northwest_16_regular,
          title: filter.searching ? '未搜索到相关作品' : '当前条件下暂无作品',
          message: filter.searching
              ? '尝试使用日文原名、简写或切换右侧「含 R18」设置。'
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
        ),
      );
    }

    final hasFooter = data.preloading || data.error != null || data.hasMore;
    final totalCount = visible.length + (hasFooter ? 1 : 0);

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
              padding: padding,
              itemCount: totalCount,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                ).fluentEntrance(index: index);
              },
            )
          : GridView.builder(
              padding: padding,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 215,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                mainAxisExtent: 356,
              ),
              itemCount: totalCount,
              itemBuilder: (context, index) {
                if (index >= visible.length) {
                  return _buildFooterTile(context, data);
                }
                final g = visible[index];
                final libKey = discoverLibraryKey(g);
                return _DiscoverGameCard(
                  game: g,
                  inLibrary: libIndex.containsKey(libKey),
                  adding: _adding.contains(libKey),
                  onTap: () => _openDetail(g),
                  onAdd: () => _addToLibrary(g),
                ).fluentEntrance(index: index);
              },
            ),
    );
  }

  Widget _buildFooterTile(BuildContext context, DiscoverFeedState data) {
    final theme = FluentTheme.of(context);
    if (data.preloading) {
      return FluentSurfaceCard(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              ProgressRing(),
              SizedBox(height: 8),
              Text('加载下一页…'),
            ],
          ),
        ),
      );
    }
    if (data.error != null) {
      return FluentSurfaceCard(
        onTap: () => ref.read(discoverFeedProvider.notifier).loadMore(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.cloud_off_24_regular,
              size: 22,
              color: Colors.red,
            ),
            const SizedBox(height: 8),
            Text('加载下一页失败', style: theme.typography.bodyStrong),
            const SizedBox(height: 4),
            Text(
              data.error!,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption,
            ),
            const SizedBox(height: 8),
            Text(
              '点击重试',
              style: theme.typography.caption?.copyWith(color: theme.accentColor),
            ),
          ],
        ),
      );
    }
    return FluentSurfaceCard(
      onTap: () => ref.read(discoverFeedProvider.notifier).loadMore(),
      child: Center(
        child: Text(
          '继续加载更多',
          style: theme.typography.bodyStrong?.copyWith(color: theme.accentColor),
        ),
      ),
    );
  }

  static int _activeFilterCount(DiscoverFilter f) {
    var count = 0;
    if (f.minRating > 0) count++;
    if (f.yearFrom != null || f.yearTo != null) count++;
    if (!f.onlySfw) count++;
    if (f.tagIds.isNotEmpty) count += f.tagIds.length;
    return count;
  }
}

class _ModeSegmentedSwitch extends StatelessWidget {
  final DiscoverMode current;
  final ValueChanged<DiscoverMode> onChanged;

  const _ModeSegmentedSwitch({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in DiscoverMode.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: HoverButton(
                onPressed: () => onChanged(m),
                builder: (context, states) {
                  final selected = current == m;
                  return AnimatedContainer(
                    duration: FluentMotion.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.resources.cardBackgroundFillColorDefault
                          : states.isHovered
                              ? theme.resources.subtleFillColorSecondary
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: selected
                          ? Border.all(
                              color: theme.accentColor.withValues(alpha: 0.45),
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          m == DiscoverMode.aggregate
                              ? FluentIcons.compass_northwest_16_regular
                              : FluentIcons.search_16_regular,
                          size: 14,
                          color: selected
                              ? theme.accentColor
                              : theme.resources.textFillColorSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          m.label,
                          style: theme.typography.body?.copyWith(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? theme.accentColor
                                : theme.resources.textFillColorPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
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
                    color: theme.resources.textFillColorSecondary,
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
                    color: theme.resources.textFillColorSecondary,
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
      widget.filter.copyWith(yearFrom: from, yearTo: to),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final f = widget.filter;
    final tagQuery = _tagFilterCtrl.text.trim().toLowerCase();
    final filteredTags = DiscoverTags.presets.where((t) {
      if (tagQuery.isEmpty) return true;
      return t.label.toLowerCase().contains(tagQuery) ||
          t.id.toLowerCase().contains(tagQuery);
    }).toList();

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: ListView(
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.filter_16_regular,
                size: 16,
                color: theme.accentColor,
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
              color: theme.resources.textFillColorSecondary,
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
                  label: score == 0 ? '不限' : '${score.toStringAsFixed(score % 1 == 0 ? 0 : 1)}+',
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
            f.source == DiscoverSource.vndb
                ? '题材标签（VNDB）'
                : '题材标签（切换 VNDB 生效）',
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 8),
          TextBox(
            controller: _tagFilterCtrl,
            placeholder: '筛选标签…',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in filteredTags)
                _RailChoiceChip(
                  label: t.label,
                  selected: f.tagIds.contains(t.id),
                  onTap: f.source == DiscoverSource.vndb
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
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final disabled = onTap == null;
        final bg = selected
            ? theme.accentColor.withValues(alpha: 0.16)
            : states.isHovered && !disabled
                ? theme.resources.subtleFillColorSecondary
                : theme.resources.controlFillColorDefault;
        final border = selected
            ? theme.accentColor.withValues(alpha: 0.55)
            : theme.resources.cardStrokeColorDefault;
        return AnimatedContainer(
          duration: FluentMotion.fast,
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
                  ? theme.resources.textFillColorDisabled
                  : selected
                      ? theme.accentColor
                      : theme.resources.textFillColorPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        );
      },
    );
  }
}
