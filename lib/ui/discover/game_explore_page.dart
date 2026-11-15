/// 游戏全维度百科探索页（Fluent 2）。
///
/// 聚合多源作品简介、发行资料、角色与声优、制作人员、相关游戏、
/// 媒体画廊与跨媒体衍生（动画 / 音乐 / 漫画 / 轻小说）以及站点发布页下载外链。
library;

import 'dart:ui' show ImageFilter;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../../services/game_explore_service.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../library/game_actions.dart';
import 'discover_state.dart';
import 'resource_links.dart';

/// 探索百科页顶部工作区 Tab。
enum ExplorePageTab {
  overview('百科资料', FluentIcons.info_16_regular),
  media('媒体', FluentIcons.image_16_regular),
  anime('动画', FluentIcons.play_circle_16_regular),
  music('音乐', FluentIcons.sparkle_16_regular),
  manga('漫画', FluentIcons.document_16_regular),
  novel('轻小说', FluentIcons.bookmark_16_regular),
  download('下载', FluentIcons.arrow_download_20_regular);

  final String label;
  final IconData icon;
  const ExplorePageTab(this.label, this.icon);
}

/// 作品百科详情加载函数签名（支持测试通过 Riverpod override 注入离线数据）。
typedef ExploreDetailLoader = Future<ExploreWorkDetail> Function(
  ScrapedGame seedGame,
  List<SourceRecord> knownSources, {
  bool forceRefresh,
});

/// 默认使用 [GameExploreService.instance.loadWorkDetail] 聚合多源百科数据。
final exploreDetailLoaderProvider = Provider<ExploreDetailLoader>((ref) {
  return (seedGame, knownSources, {bool forceRefresh = false}) =>
      GameExploreService.instance.loadWorkDetail(
        seedGame,
        knownSources: knownSources,
        forceRefresh: forceRefresh,
      );
});

/// 游戏百科探索页。
class GameExplorePage extends ConsumerStatefulWidget {
  final ScrapedGame seedGame;
  final List<SourceRecord> knownSources;
  final int? localGameId;
  final Future<void> Function(ScrapedGame)? onAdd;
  final ExplorePageTab initialTab;
  final ExploreWorkDetail? initialDetail;

  const GameExplorePage({
    super.key,
    required this.seedGame,
    this.knownSources = const [],
    this.localGameId,
    this.onAdd,
    this.initialTab = ExplorePageTab.overview,
    this.initialDetail,
  });

  /// 从本地入库游戏 (`GameDetailPage`) 构造百科探索页。
  factory GameExplorePage.fromLocalGame({
    Key? key,
    required Game game,
    required List<SourceRecord> sources,
    ExplorePageTab initialTab = ExplorePageTab.overview,
  }) {
    return GameExplorePage(
      key: key,
      seedGame: GameExploreService.seedFromLocalGame(game, sources),
      knownSources: sources,
      localGameId: game.id,
      initialTab: initialTab,
    );
  }

  @override
  ConsumerState<GameExplorePage> createState() => _GameExplorePageState();
}

class _GameExplorePageState extends ConsumerState<GameExplorePage> {
  final ScrollController _scroll = ScrollController();

  final GlobalKey _synopsisKey = GlobalKey();
  final GlobalKey _releasesKey = GlobalKey();
  final GlobalKey _charsKey = GlobalKey();
  final GlobalKey _staffKey = GlobalKey();
  final GlobalKey _relatedKey = GlobalKey();

  ExploreWorkDetail? _detail;
  bool _loading = true;
  Object? _error;
  bool _adding = false;
  bool _showSpoilers = false;
  String _characterRoleFilter = 'all';
  late ExplorePageTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    if (widget.initialDetail != null) {
      _detail = widget.initialDetail;
      _loading = false;
    } else {
      Future.microtask(() {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
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

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = ref.read(exploreDetailLoaderProvider);
      final detail = await loader(
        widget.seedGame,
        widget.knownSources,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _handleAdd(ExploreWorkDetail detail) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      if (widget.onAdd != null) {
        await widget.onAdd!(detail.seedGame);
      } else {
        final services = tryAppServices();
        if (services == null) {
          showNotice('当前为离线预览模式，无法写入本地游戏库');
          return;
        }
        final repo = services.repo;
        final seed = detail.seedGame;
        final existing = await repo.findGameByTitle(seed.displayName) ??
            (seed.name.isEmpty || seed.name == seed.displayName
                ? null
                : await repo.findGameByTitle(seed.name));
        if (existing != null) {
          if (!mounted) return;
          ref.read(libraryVersionProvider.notifier).state++;
          showNotice('「${existing.displayName}」已在库中');
          return;
        }
        final game = Game(
          name: seed.name.isNotEmpty ? seed.name : seed.displayName,
          nameCn: seed.nameCn,
          aliases: seed.aliases,
          developer: seed.developer,
          releaseDate: seed.releaseDate,
          summary: seed.summary,
          nsfw: seed.nsfw,
          screenshots: seed.screenshots,
        );
        await repo.insertGame(game);
        await ScrapeApplier(repo, services.fetcher).apply(game, [seed]);
        if (!mounted) return;
        ref.read(libraryVersionProvider.notifier).state++;
        showNotice('已入库：${game.displayName}');
      }
    } catch (e) {
      if (mounted) showNotice('入库失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openRelated(ExploreRelatedWork rel) {
    return pushFluentPage(
      context,
      (_) => GameExplorePage(
        seedGame: rel.seedGame,
        onAdd: widget.onAdd,
      ),
    );
  }

  void _scrollToSection(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: FluentMotion.standard,
      curve: FluentMotion.enterCurve,
      alignment: 0.05,
    );
  }

  int _tabCount(ExploreWorkDetail detail, ExplorePageTab tab) => switch (tab) {
        ExplorePageTab.overview => 0,
        ExplorePageTab.media =>
          detail.screenshots.length +
              detail.mediaLinks.where((l) => l.isVideo).length,
        ExplorePageTab.anime => detail.animeList.length,
        ExplorePageTab.music => detail.musicList.length,
        ExplorePageTab.manga => detail.mangaList.length,
        ExplorePageTab.novel => detail.novelList.length,
        ExplorePageTab.download =>
          detail.mediaLinks.where((l) => !l.isVideo).length,
      };

  @override
  Widget build(BuildContext context) {
    final libIndex = ref.watch(discoverLibraryIndexProvider).valueOrNull ??
        const <String, Game>{};

    return _wrapFluent(
      context,
      (ctx) => ScaffoldPage(
        padding: EdgeInsets.zero,
        header: _buildTopHeader(ctx),
        content: _buildBody(ctx, libIndex),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final theme = FluentTheme.of(context);
    final detail = _detail;
    final title = detail?.title ?? widget.seedGame.displayName;
    final canPop = Navigator.of(context).canPop();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: theme.micaBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          if (canPop) ...[
            Tooltip(
              message: '返回上一页',
              child: IconButton(
                icon: const Icon(FluentIcons.chevron_left_16_regular, size: 16),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: BreadcrumbBar<String>(
              items: [
                const BreadcrumbItem<String>(
                  label: Text('探索'),
                  value: 'explore',
                ),
                BreadcrumbItem<String>(
                  label: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: 'current',
                ),
              ],
              onItemPressed: (item) {
                if (item.value == 'explore' && canPop) {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Wrap(
              spacing: 6,
              children: [
                if (detail.nextmoeId.isNotEmpty)
                  FluentBadge(text: 'NextMoe ${detail.nextmoeId}'),
                if (detail.bangumiId.isNotEmpty)
                  FluentBadge(text: 'BGM ${detail.bangumiId}'),
                if (detail.vndbId.isNotEmpty)
                  FluentBadge(text: 'VNDB ${detail.vndbId}'),
              ],
            ),
          ],
          const SizedBox(width: 8),
          if (widget.localGameId != null) ...[
            Button(
              onPressed: () => openGameDetail(context, widget.localGameId!),
              child: const Text('库内详情'),
            ),
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: '刷新百科数据',
            child: IconButton(
              icon: const Icon(FluentIcons.arrow_clockwise_16_regular, size: 16),
              onPressed: _loading ? null : () => _load(forceRefresh: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, Game> libIndex) {
    if (_loading && _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ProgressRing(),
            const SizedBox(height: 12),
            Text('正在聚合「${widget.seedGame.displayName}」多源百科资料…'),
          ],
        ),
      );
    }

    if (_error != null && _detail == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: FluentEmptyState(
          icon: FluentIcons.error_circle_24_regular,
          title: '百科资料加载失败',
          message: '$_error',
          action: FilledButton(
            onPressed: () => _load(forceRefresh: true),
            child: const Text('重试加载'),
          ),
        ),
      );
    }

    final detail = _detail!;
    final matchedLocal = libIndex[discoverLibraryKey(detail.seedGame)];
    final localId = widget.localGameId ?? matchedLocal?.id;
    final inLibrary = localId != null;

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        _buildHeroStage(context, detail, inLibrary: inLibrary, localId: localId)
            .fluentEntrance(index: 0),
        const SizedBox(height: 16),
        _buildTabStrip(context, detail),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: FluentMotion.standard,
          switchInCurve: FluentMotion.enterCurve,
          child: KeyedSubtree(
            key: ValueKey<ExplorePageTab>(_activeTab),
            child: _buildActiveTabContent(context, detail),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroStage(
    BuildContext context,
    ExploreWorkDetail detail, {
    required bool inLibrary,
    required int? localId,
  }) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgMedia = detail.bannerUrl.isNotEmpty
        ? detail.bannerUrl
        : (detail.coverUrl.isNotEmpty ? detail.coverUrl : detail.seedGame.coverUrl);
    final coverMedia =
        detail.coverUrl.isNotEmpty ? detail.coverUrl : detail.seedGame.coverUrl;

    final primaryRating =
        detail.ratings.isNotEmpty ? detail.ratings.first : null;
    final scoreText = primaryRating != null
        ? '${primaryRating.label} ${primaryRating.displayScore}'
        : (detail.seedGame.rating > 0
            ? detail.seedGame.rating.toStringAsFixed(1)
            : null);
    final voteText = primaryRating != null && primaryRating.voteCount > 0
        ? '(${primaryRating.voteCount})'
        : (detail.seedGame.voteCount > 0
            ? '(${detail.seedGame.voteCount})'
            : null);
    final secondaryRatings = detail.ratings.length > 1
        ? detail.ratings.sublist(1)
        : const <ExploreSourceRating>[];

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
                    theme.resources.cardBackgroundFillColorDefault,
                  ],
                ),
              ),
              child: bgMedia.isNotEmpty
                  ? Opacity(
                      opacity: isDark ? 0.25 : 0.16,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: FluentCoverImage(
                          pathOrUrl: bgMedia,
                          nsfw: false,
                          allowRevealOnHover: false,
                          radius: 0,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          FluentAcrylicPanel(
            padding: const EdgeInsets.all(20),
            radius: 10,
            luminosityAlpha: isDark ? 0.78 : 0.84,
            tintAlpha: isDark ? 0.72 : 0.80,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final coverWidget = GestureDetector(
                  onTap: () => showFluentLightboxDialog(
                    context,
                    pathOrUrl: coverMedia,
                    title: '图片预览',
                    caption: detail.title,
                  ),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FluentCoverImage(
                      pathOrUrl: coverMedia,
                      nsfw: detail.nsfw,
                      width: wide ? 160 : 120,
                      height: wide ? 236 : 178,
                      radius: 8,
                    ),
                  ),
                );

                final infoColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.title,
                      style: theme.typography.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail.originalTitle.isNotEmpty &&
                        detail.originalTitle != detail.title) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail.originalTitle,
                        style: theme.typography.subtitle?.copyWith(
                          fontSize: 14,
                          color: theme.resources.textFillColorSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (detail.aliases.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '别名：${detail.aliases.take(4).join(' / ')}',
                        style: theme.typography.caption?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    FluentR18ScoreRow(
                      nsfw: detail.nsfw,
                      scoreText: scoreText,
                      voteText: voteText,
                      trailing: [
                        for (final r in secondaryRatings)
                          FluentBadge(
                            text: r.voteCount > 0
                                ? '${r.label} ${r.displayScore} (${r.voteCount})'
                                : '${r.label} ${r.displayScore}',
                            icon: FluentIcons.star_16_regular,
                            onTap: r.url.isNotEmpty
                                ? () => openExternalExploreUrl(r.url)
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (detail.developers.isNotEmpty)
                          FluentBadge(
                            text: detail.developers.join(' / '),
                            icon: FluentIcons.building_16_regular,
                          ),
                        if (detail.releaseDate.isNotEmpty)
                          FluentBadge(
                            text: detail.releaseDate,
                            icon: FluentIcons.calendar_16_regular,
                          ),
                        for (final eng in detail.engines.take(2))
                          FluentBadge(text: eng),
                        for (final s in detail.series.take(2))
                          FluentBadge(text: '系列：$s'),
                      ],
                    ),
                    if (detail.summary.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        detail.summary,
                        style: theme.typography.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (localId != null)
                          FilledButton(
                            onPressed: () => openGameDetail(context, localId),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  FluentIcons.checkmark_circle_16_filled,
                                  size: 15,
                                ),
                                SizedBox(width: 6),
                                Text('在库中查看'),
                              ],
                            ),
                          )
                        else
                          FilledButton(
                            onPressed:
                                _adding ? null : () => _handleAdd(detail),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_adding)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: ProgressRing(strokeWidth: 2),
                                  )
                                else
                                  const Icon(FluentIcons.add_16_regular,
                                      size: 15),
                                const SizedBox(width: 6),
                                const Text('一键入库'),
                              ],
                            ),
                          ),
                        if (detail.screenshots.isNotEmpty ||
                            coverMedia.isNotEmpty)
                          Button(
                            onPressed: () {
                              if (detail.screenshots.isNotEmpty) {
                                setState(
                                    () => _activeTab = ExplorePageTab.media);
                              } else {
                                showFluentLightboxDialog(
                                  context,
                                  pathOrUrl: coverMedia,
                                  title: '图片预览',
                                  caption: detail.title,
                                );
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(FluentIcons.image_16_regular, size: 15),
                                SizedBox(width: 6),
                                Text('画廊大图'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                );

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      coverWidget,
                      const SizedBox(width: 20),
                      Expanded(child: infoColumn),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: coverWidget),
                    const SizedBox(height: 14),
                    infoColumn,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip(BuildContext context, ExploreWorkDetail detail) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in ExplorePageTab.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: HoverButton(
                  onPressed: () => setState(() => _activeTab = tab),
                  builder: (context, states) {
                    final selected = _activeTab == tab;
                    final count = _tabCount(detail, tab);
                    return AnimatedContainer(
                      duration: FluentMotion.fast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.accentColor.withValues(alpha: 0.14)
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
                            tab.icon,
                            size: 15,
                            color: selected
                                ? theme.accentColor
                                : theme.resources.textFillColorSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tab.label,
                            style: theme.typography.body?.copyWith(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected
                                  ? theme.accentColor
                                  : theme.resources.textFillColorPrimary,
                            ),
                          ),
                          if (tab != ExplorePageTab.overview && count > 0) ...[
                            const SizedBox(width: 6),
                            FluentBadge(
                              text: '$count',
                              foreground: selected ? theme.accentColor : null,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(
    BuildContext context,
    ExploreWorkDetail detail,
  ) {
    return switch (_activeTab) {
      ExplorePageTab.overview => _buildOverviewTab(context, detail),
      ExplorePageTab.media => _buildMediaTab(context, detail),
      ExplorePageTab.anime => _buildCrossMediaTab(
          context,
          title: '动画',
          subtitle: '来自 Bangumi 的相关动画、OVA 与影视衍生条目',
          items: detail.animeList,
          emptyTitle: '暂无关联动画记录',
        ),
      ExplorePageTab.music => _buildCrossMediaTab(
          context,
          title: '音乐',
          subtitle: '原声集 OST、片头/片尾单曲、角色歌与广播剧',
          items: detail.musicList,
          emptyTitle: '暂无关联音乐记录',
        ),
      ExplorePageTab.manga => _buildCrossMediaTab(
          context,
          title: '漫画',
          subtitle: '改编漫画、四格与官方短篇合集',
          items: detail.mangaList,
          emptyTitle: '暂无关联漫画记录',
        ),
      ExplorePageTab.novel => _buildCrossMediaTab(
          context,
          title: '轻小说',
          subtitle: '外传小说、文库本与官方视觉设定书',
          items: detail.novelList,
          emptyTitle: '暂无关联轻小说记录',
        ),
      ExplorePageTab.download => _buildDownloadTab(context, detail),
    };
  }

  // ==================== Tab 1: 百科资料（含 5 个干净子区块） ====================

  Widget _buildOverviewTab(BuildContext context, ExploreWorkDetail detail) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 锚点快速跳转条
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AnchorChip(
              label: '简介与标签',
              onTap: () => _scrollToSection(_synopsisKey),
            ),
            _AnchorChip(
              label: '发行资料 (${detail.releases.length})',
              onTap: () => _scrollToSection(_releasesKey),
            ),
            _AnchorChip(
              label: '角色与声优 (${detail.characters.length})',
              onTap: () => _scrollToSection(_charsKey),
            ),
            _AnchorChip(
              label: '制作人员 (${detail.credits.length})',
              onTap: () => _scrollToSection(_staffKey),
            ),
            _AnchorChip(
              label: '相关游戏 (${detail.relatedGames.length})',
              onTap: () => _scrollToSection(_relatedKey),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 1. 简介与标签
        KeyedSubtree(
          key: _synopsisKey,
          child: FluentSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FluentSectionHeader(
                  title: '简介与标签',
                  icon: FluentIcons.info_16_regular,
                ),
                const SizedBox(height: 10),
                Text(
                  detail.summary.isNotEmpty
                      ? detail.summary
                      : '暂无作品简介，可点击顶部刷新或参考各外部百科站点。',
                  style: theme.typography.body?.copyWith(height: 1.6),
                ),
                if (detail.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in detail.tags.take(24))
                        FluentBadge(
                          text: t,
                          icon: FluentIcons.tag_16_regular,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. 发行资料
        KeyedSubtree(
          key: _releasesKey,
          child: _buildReleasesSection(context, detail),
        ),
        const SizedBox(height: 16),

        // 3. 角色与声优
        KeyedSubtree(
          key: _charsKey,
          child: _buildCharactersSection(context, detail),
        ),
        const SizedBox(height: 16),

        // 4. 制作人员
        KeyedSubtree(
          key: _staffKey,
          child: _buildCreditsSection(context, detail),
        ),
        const SizedBox(height: 16),

        // 5. 相关游戏
        KeyedSubtree(
          key: _relatedKey,
          child: _buildRelatedSection(context, detail),
        ),
      ],
    );
  }

  Widget _buildReleasesSection(BuildContext context, ExploreWorkDetail detail) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            title: '发行资料',
            subtitle: '收录数字版、实体版、体验版与平台版本信息',
            icon: FluentIcons.calendar_16_regular,
            trailing: FluentBadge(text: '${detail.releases.length} 条'),
          ),
          const SizedBox(height: 12),
          if (detail.releases.isEmpty)
            const FluentEmptyState(
              icon: FluentIcons.calendar_20_regular,
              title: '暂无详细发行版本',
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < detail.releases.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _ReleaseRowCard(
                    item: detail.releases[i],
                    onOpenLink: openExternalExploreUrl,
                    theme: theme,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCharactersSection(
    BuildContext context,
    ExploreWorkDetail detail,
  ) {
    final theme = FluentTheme.of(context);
    final filtered = detail.characters.where((c) {
      if (!_showSpoilers && c.spoiler) return false;
      if (_characterRoleFilter != 'all' && c.role != _characterRoleFilter) {
        return false;
      }
      return true;
    }).toList();

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            title: '角色与声优',
            icon: FluentIcons.heart_16_regular,
            trailing: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final r in const [
                  (id: 'all', label: '全部'),
                  (id: 'main', label: '主角'),
                  (id: 'secondary', label: '配角'),
                  (id: 'appears', label: '客串'),
                ])
                  _AnchorChip(
                    label: r.label,
                    selected: _characterRoleFilter == r.id,
                    onTap: () =>
                        setState(() => _characterRoleFilter = r.id),
                  ),
                Checkbox(
                  checked: _showSpoilers,
                  onChanged: (v) => setState(() => _showSpoilers = v ?? false),
                  content: const Text('含剧透角色'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const FluentEmptyState(
              icon: FluentIcons.heart_16_regular,
              title: '暂无符合条件的角色条目',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 900
                    ? 3
                    : (constraints.maxWidth >= 560 ? 2 : 1);
                final itemW =
                    (constraints.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in filtered)
                      SizedBox(
                        width: itemW,
                        child: FluentSurfaceCard(
                          padding: const EdgeInsets.all(10),
                          backgroundColor:
                              theme.resources.subtleFillColorSecondary,
                          child: Row(
                            children: [
                              FluentCoverImage(
                                pathOrUrl: c.imageUrl,
                                nsfw: c.nsfw,
                                width: 48,
                                height: 64,
                                radius: 6,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.name,
                                            style: theme.typography.bodyStrong,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        FluentBadge(text: c.roleLabel),
                                      ],
                                    ),
                                    if (c.originalName.isNotEmpty &&
                                        c.originalName != c.name) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        c.originalName,
                                        style: theme.typography.caption
                                            ?.copyWith(
                                          color: theme
                                              .resources.textFillColorSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      c.voiceActorLine,
                                      style: theme.typography.caption,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCreditsSection(BuildContext context, ExploreWorkDetail detail) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            title: '制作人员',
            icon: FluentIcons.edit_16_regular,
            trailing: FluentBadge(text: '${detail.credits.length} 组'),
          ),
          const SizedBox(height: 12),
          if (detail.credits.isEmpty)
            const FluentEmptyState(
              icon: FluentIcons.edit_16_regular,
              title: '暂无制作人员分工信息',
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < detail.credits.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          detail.credits[i].roleLabel,
                          style: theme.typography.bodyStrong?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final p in detail.credits[i].people)
                              FluentBadge(
                                text: p.note.isNotEmpty
                                    ? '${p.name} (${p.note})'
                                    : p.name,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRelatedSection(BuildContext context, ExploreWorkDetail detail) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            title: '相关游戏',
            subtitle: '点击条目直接在百科页中深入查看续作 / 前传 / FanDisc',
            icon: FluentIcons.games_24_regular,
            trailing: FluentBadge(text: '${detail.relatedGames.length} 部'),
          ),
          const SizedBox(height: 12),
          if (detail.relatedGames.isEmpty)
            const FluentEmptyState(
              icon: FluentIcons.games_24_regular,
              title: '暂无关联系列或衍生游戏',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 820 ? 2 : 1;
                final itemW =
                    (constraints.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final rel in detail.relatedGames)
                      SizedBox(
                        width: itemW,
                        child: FluentSurfaceCard(
                          padding: const EdgeInsets.all(10),
                          backgroundColor:
                              theme.resources.subtleFillColorSecondary,
                          onTap: () => _openRelated(rel),
                          child: Row(
                            children: [
                              FluentCoverImage(
                                pathOrUrl: rel.coverUrl,
                                nsfw: rel.nsfw,
                                width: 52,
                                height: 72,
                                radius: 6,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      rel.title,
                                      style: theme.typography.bodyStrong,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (rel.originalTitle.isNotEmpty &&
                                        rel.originalTitle != rel.title) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        rel.originalTitle,
                                        style: theme.typography.caption
                                            ?.copyWith(
                                          color: theme
                                              .resources.textFillColorSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        FluentBadge(
                                          text: rel.relationLabel,
                                          foreground: theme.accentColor,
                                          background: theme.accentColor
                                              .withValues(alpha: 0.14),
                                        ),
                                        if (rel.releaseDate.isNotEmpty)
                                          FluentBadge(text: rel.releaseDate),
                                        if (rel.nsfw)
                                          const FluentBadge(
                                            text: 'R18',
                                            foreground: Color(0xFFD13438),
                                            background: Color(0x24D13438),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                FluentIcons.chevron_right_16_regular,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // ==================== Tab 2: 媒体 ====================

  Widget _buildMediaTab(BuildContext context, ExploreWorkDetail detail) {
    final videos = detail.mediaLinks.where((l) => l.isVideo).toList();
    final shots = detail.screenshots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (videos.isNotEmpty) ...[
          FluentSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FluentSectionHeader(
                  title: '宣传影片 / PV',
                  icon: FluentIcons.play_circle_16_regular,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in videos)
                      Button(
                        onPressed: () => openExternalExploreUrl(v.url),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.open_16_regular, size: 14),
                            const SizedBox(width: 6),
                            Text(v.label),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FluentSectionHeader(
                title: '截图与 CG 画廊',
                subtitle: '点击任意缩略图打开高清大图预览窗口',
                icon: FluentIcons.image_16_regular,
                trailing: FluentBadge(text: '${shots.length} 张'),
              ),
              const SizedBox(height: 12),
              if (shots.isEmpty)
                const FluentEmptyState(
                  icon: FluentIcons.image_24_regular,
                  title: '暂无画廊截图与预览 CG',
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 900
                        ? 3
                        : (constraints.maxWidth >= 520 ? 2 : 1);
                    final itemW =
                        (constraints.maxWidth - (cols - 1) * 12) / cols;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (var i = 0; i < shots.length; i++)
                          SizedBox(
                            width: itemW,
                            child: _ScreenshotCard(
                              shot: shots[i],
                              onTap: () => showFluentLightboxDialog(
                                context,
                                pathOrUrl: shots[i].url,
                                title: '图片预览',
                                caption: shots[i].caption.isNotEmpty
                                    ? shots[i].caption
                                    : detail.title,
                              ),
                            ).fluentEntrance(index: i),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== Tab 3-6: 跨媒体（动画 / 音乐 / 漫画 / 轻小说） ====================

  Widget _buildCrossMediaTab(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<ExploreCrossMediaItem> items,
    required String emptyTitle,
  }) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: FluentBadge(text: '${items.length} 条'),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            FluentEmptyState(
              icon: FluentIcons.sparkle_24_regular,
              title: emptyTitle,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _CrossMediaCard(
                    item: items[i],
                    onOpenLink: openExternalExploreUrl,
                    theme: theme,
                  ).fluentEntrance(index: i),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // ==================== Tab 7: 下载（严禁放置任何入库按钮） ====================

  Widget _buildDownloadTab(BuildContext context, ExploreWorkDetail detail) {
    final storeAndSiteLinks =
        detail.mediaLinks.where((l) => !l.isVideo).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (storeAndSiteLinks.isNotEmpty) ...[
          FluentSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FluentSectionHeader(
                  title: '官方商城与外部站点',
                  subtitle: '正版数字商店、官网与数据库链接（仅作外部跳转）',
                  icon: FluentIcons.globe_16_regular,
                  trailing: FluentBadge(text: '${storeAndSiteLinks.length} 个'),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < storeAndSiteLinks.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _ExternalLinkCard(
                    link: storeAndSiteLinks[i],
                    onOpen: () => openExternalExploreUrl(storeAndSiteLinks[i].url),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        ResourceLinkSection(
          game: detail.enrichedScrapedGame,
          shrinkWrap: true,
        ),
      ],
    );
  }
}

class _AnchorChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AnchorChip({
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final bg = selected
            ? theme.accentColor.withValues(alpha: 0.16)
            : states.isHovered
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
              color: selected
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

class _ReleaseRowCard extends StatelessWidget {
  final ExploreReleaseItem item;
  final Future<void> Function(String url) onOpenLink;
  final FluentThemeData theme;

  const _ReleaseRowCard({
    required this.item,
    required this.onOpenLink,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(12),
      backgroundColor: theme.resources.subtleFillColorSecondary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.typography.bodyStrong),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FluentBadge(
                      text: item.kindLabel,
                      foreground: theme.accentColor,
                      background: theme.accentColor.withValues(alpha: 0.14),
                    ),
                    if (item.date.isNotEmpty) FluentBadge(text: item.date),
                    for (final lang in item.languages) FluentBadge(text: lang),
                    for (final plat in item.platforms) FluentBadge(text: plat),
                    if (item.engine.isNotEmpty) FluentBadge(text: item.engine),
                  ],
                ),
              ],
            ),
          ),
          if (item.links.isNotEmpty) ...[
            const SizedBox(width: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final link in item.links)
                  Button(
                    onPressed: () => onOpenLink(link.url),
                    child: Text(link.label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScreenshotCard extends StatelessWidget {
  final ExploreScreenshot shot;
  final VoidCallback onTap;

  const _ScreenshotCard({
    required this.shot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(8),
      backgroundColor: theme.resources.subtleFillColorSecondary,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: FluentCoverImage(
              pathOrUrl: shot.url,
              nsfw: shot.nsfw,
              fit: BoxFit.cover,
              radius: 6,
            ),
          ),
          if (shot.caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              shot.caption,
              style: theme.typography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _CrossMediaCard extends StatelessWidget {
  final ExploreCrossMediaItem item;
  final Future<void> Function(String url) onOpenLink;
  final FluentThemeData theme;

  const _CrossMediaCard({
    required this.item,
    required this.onOpenLink,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(12),
      backgroundColor: theme.resources.subtleFillColorSecondary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentCoverImage(
            pathOrUrl: item.coverUrl,
            width: 58,
            height: 82,
            radius: 6,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.typography.bodyStrong),
                if (item.originalTitle.isNotEmpty &&
                    item.originalTitle != item.title) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.originalTitle,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FluentBadge(
                      text: item.relationLabel,
                      foreground: theme.accentColor,
                      background: theme.accentColor.withValues(alpha: 0.14),
                    ),
                    if (item.date.isNotEmpty) FluentBadge(text: item.date),
                    if (item.score > 0)
                      FluentBadge(
                        text: item.voteCount > 0
                            ? '${item.score.toStringAsFixed(1)} (${item.voteCount})'
                            : item.score.toStringAsFixed(1),
                        icon: FluentIcons.star_16_filled,
                      ),
                    for (final e in item.facts.entries)
                      FluentBadge(text: '${e.key}：${e.value}'),
                  ],
                ),
                if (item.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.summary,
                    style: theme.typography.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (item.links.isNotEmpty) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final link in item.links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Button(
                      onPressed: () => onOpenLink(link.url),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.open_16_regular, size: 13),
                          const SizedBox(width: 4),
                          Text(link.label),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ExternalLinkCard extends StatelessWidget {
  final ExploreExternalLink link;
  final VoidCallback onOpen;

  const _ExternalLinkCard({
    required this.link,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final host = Uri.tryParse(link.url)?.host ?? link.url;
    return FluentSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      backgroundColor: theme.resources.subtleFillColorSecondary,
      onTap: onOpen,
      child: Row(
        children: [
          Icon(
            FluentIcons.globe_16_regular,
            size: 16,
            color: theme.accentColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(link.label, style: theme.typography.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  link.subtitle.isNotEmpty ? '${link.subtitle} · $host' : host,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (link.isStore)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: FluentBadge(text: '官方/商店'),
            ),
          Button(
            onPressed: onOpen,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(FluentIcons.open_16_regular, size: 14),
                SizedBox(width: 6),
                Text('打开链接'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
