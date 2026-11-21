/// Fluent 2 主页：Spotlight 聚光灯横幅 + 4 列 KPI 统计 + 最近游玩 / 待玩水平货架 + 库中动态。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import '../../services/game_launch_service.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import '../library/game_actions.dart';
import '../shell/tabs.dart';

const int _kTimelineLimit = 6;
const int _kRecommendLimit = 5;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<ScrapedGame>? _recommendations;
  bool _loadingRecommendations = false;
  String? _recommendError;
  int _recommendBatch = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.f5 &&
        mounted &&
        ref.read(tabIndexProvider) == Tabs.home) {
      _refreshHome();
      return true;
    }
    return false;
  }

  void _refreshHome() {
    ref.invalidate(homeDataProvider);
    ref.invalidate(allTagsProvider);
    bumpLibrary(ref);
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeDataProvider);

    return ensureFluentTheme(
      context,
      Builder(
        builder: (ctx) {
          final theme = FluentTheme.of(ctx);
          final refreshing = home.isRefreshing;

          return ScaffoldPage(
            padding: EdgeInsets.zero,
            header: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(), style: theme.typography.title),
                        const SizedBox(height: 2),
                        home.when(
                          skipLoadingOnReload: true,
                          data: (d) => Text(
                            '共 ${d.gameCount} 部作品 · 累计 ${fmtDuration(d.all.totalSeconds)}',
                            style: theme.typography.caption?.copyWith(
                              color: theme.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          loading: () => Text(
                            '正在读取你的游玩记录…',
                            style: theme.typography.caption?.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                          error: (_, __) => Text(
                            '主页数据加载失败',
                            style: theme.typography.caption?.copyWith(
                              color: theme.dangerInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: '刷新主页数据 (F5)',
                    child: Button(
                      onPressed: refreshing ? null : _refreshHome,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (refreshing)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          else
                            const Icon(
                              FluentIcons.arrow_clockwise_16_regular,
                              size: 16,
                            ),
                          const SizedBox(width: 6),
                          Text(refreshing ? '刷新中…' : '刷新'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            content: home.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => _buildLoadingSkeleton(),
              error: (err, _) => FluentEmptyState(
                icon: FluentIcons.cloud_off_24_regular,
                title: '主页数据加载失败',
                message: '无法读取本地游玩统计：$err',
                action: FilledButton(
                  onPressed: () => ref.invalidate(homeDataProvider),
                  child: const Text('重试'),
                ),
              ),
              data: (data) => _buildContent(ctx, data),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: const [
        FluentCardSkeleton(height: 248, radius: 12),
        SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: FluentCardSkeleton(height: 92)),
            SizedBox(width: 12),
            Expanded(child: FluentCardSkeleton(height: 92)),
            SizedBox(width: 12),
            Expanded(child: FluentCardSkeleton(height: 92)),
            SizedBox(width: 12),
            Expanded(child: FluentCardSkeleton(height: 92)),
          ],
        ),
        SizedBox(height: 22),
        FluentCardSkeleton(height: 240),
      ],
    );
  }

  Widget _buildContent(BuildContext context, HomeData data) {
    final disableAnim = fluentAnimationsDisabled(context);
    final allGamesAsync = ref.watch(allGamesProvider);
    final allGames = allGamesAsync.valueOrNull ??
        (allGamesAsync.hasValue
            ? const <Game>[]
            : ref.watch(gamesProvider).valueOrNull) ??
        const <Game>[];
    final platformRatings =
        ref.watch(platformRatingsProvider).valueOrNull ?? const <int, double>{};

    final wishGames = allGames
        .where((g) => g.playStatus == PlayStatus.wish)
        .take(12)
        .toList();
    final playingCount =
        allGames.where((g) => g.playStatus == PlayStatus.playing).length;
    final playedCount =
        allGames.where((g) => g.playStatus == PlayStatus.played).length;

    final leadGame =
        data.recentGames.isNotEmpty ? data.recentGames.first : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SpotlightHeroBanner(
            game: leadGame,
            bestPlatformRating:
                leadGame?.id != null ? platformRatings[leadGame!.id!] : null,
            onOpenLibrary: () => _switchTab(Tabs.library),
            onOpenAdd: () => _switchTab(Tabs.add),
          ).fluentEntrance(index: 0, disable: disableAnim),
          const SizedBox(height: 18),
          _KpiMatrixRow(
            data: data,
            playingCount: playingCount,
            playedCount: playedCount,
            onOpenLibrary: () => _switchTab(Tabs.library),
            onOpenStats: () => _switchTab(Tabs.stats),
          ).fluentEntrance(index: 1, disable: disableAnim),
          const SizedBox(height: 22),
          _HorizontalShelfSection(
            title: '最近游玩',
            subtitle: data.recentGames.isEmpty
                ? '暂无近期会话'
                : '最近 ${data.recentGames.length} 部游玩作品',
            icon: FluentIcons.clock_20_regular,
            actionLabel: '全部作品',
            onAction: () => _switchTab(Tabs.library),
            games: data.recentGames,
            platformRatings: platformRatings,
            emptyTitle: '还没有游玩记录',
            emptyMessage: '从游戏库挑一部开始新的故事吧',
          ).fluentEntrance(index: 2, disable: disableAnim),
          const SizedBox(height: 22),
          _HorizontalShelfSection(
            title: '待玩清单',
            subtitle: wishGames.isEmpty
                ? '待玩队列为空'
                : '${wishGames.length} 部待开启的作品',
            icon: FluentIcons.bookmark_16_regular,
            actionLabel: '浏览游戏库',
            onAction: _openWishListInLibrary,
            games: wishGames,
            platformRatings: platformRatings,
            emptyTitle: '暂无待玩作品',
            emptyMessage: '可在游戏库中将作品状态标记为「想玩」',
          ).fluentEntrance(index: 3, disable: disableAnim),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final activityCard = _ActivityFeedCard(
                activity: data.activity,
                onShowAll: () => _openAllActivityDialog(context, data.activity),
              );
              final recCard = _RecommendCard(
                tags: _topTags(),
                recommendations: _recommendations,
                loading: _loadingRecommendations,
                error: _recommendError,
                onRefresh: _loadRecommendations,
                onPickQuery: _openResourceSearch,
              );
              if (constraints.maxWidth >= 780) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: activityCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: recCard),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  activityCard,
                  const SizedBox(height: 16),
                  recCard,
                ],
              );
            },
          ).fluentEntrance(index: 4, disable: disableAnim),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    final hello = hour < 5
        ? '夜深了'
        : hour < 11
            ? '早上好'
            : hour < 14
                ? '中午好'
                : hour < 18
                    ? '下午好'
                    : '晚上好';
    return '$hello，今天也想见见她们吗？';
  }

  void _switchTab(int index) =>
      ref.read(tabIndexProvider.notifier).state = index;

  void _openWishListInLibrary() {
    ref.read(libraryFilterProvider)
      ..status = PlayStatus.wish
      ..favoriteOnly = false
      ..tag = null
      ..developer = null
      ..source = null
      ..query = '';
    ref.read(librarySidebarProvider.notifier).state = true;
    ref.read(libraryVersionProvider.notifier).state++;
    _switchTab(Tabs.library);
  }

  void _openResourceSearch(String query) {
    if (query.isNotEmpty) {
      ref.read(resourceQueryProvider.notifier).state = query;
    }
    _switchTab(Tabs.discover);
  }

  List<TagItem> _topTags() {
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <TagItem>[];
    return tags.take(6).toList();
  }

  Future<void> _loadRecommendations() async {
    if (_loadingRecommendations) return;
    final services = tryAppServices();
    if (services == null) return;
    setState(() {
      _loadingRecommendations = true;
      _recommendError = null;
    });
    try {
      final allTagNames = _topTags()
          .map((t) => t.name)
          .where((n) => n.isNotEmpty)
          .toList();
      final results = <ScrapedGame>[];
      if (allTagNames.isNotEmpty) {
        final offset = _recommendBatch % allTagNames.length;
        final rotated = [
          ...allTagNames.skip(offset),
          ...allTagNames.take(offset),
        ].take(3).toList();
        final bySource = await services.fetcher
            .searchAll(rotated.join(' '), only: [KisakiSources.vndb]);
        results.addAll(bySource[KisakiSources.vndb] ?? const []);
      }
      if (!mounted) return;
      _recommendBatch++;
      final offsetSlice =
          results.length > _kRecommendLimit ? _recommendBatch % (results.length - _kRecommendLimit + 1) : 0;
      setState(() {
        _recommendations =
            results.skip(offsetSlice).take(_kRecommendLimit).toList();
        _loadingRecommendations = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRecommendations = false;
        _recommendError = '检索推荐失败，请检查网络连接或代理设置';
      });
      showNotice('推荐获取失败：$e', error: true);
    }
  }

  void _openAllActivityDialog(
    BuildContext context,
    List<ActivityItem> activities,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 540),
        title: Row(
          children: [
            const Icon(FluentIcons.timeline_20_regular, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('全部动态 (${activities.length})')),
            Tooltip(
              message: '关闭 (Esc)',
              child: IconButton(
                icon: const Icon(FluentIcons.dismiss_20_regular, size: 16),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
        content: ListView.separated(
          itemCount: activities.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, i) => _ActivityRow(
            item: activities[i],
            onTap: () {
              Navigator.pop(ctx);
              openGameDetail(context, activities[i].gameId, ref: ref);
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _SpotlightHeroBanner extends ConsumerStatefulWidget {
  final Game? game;
  final double? bestPlatformRating;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenAdd;

  const _SpotlightHeroBanner({
    required this.game,
    required this.onOpenLibrary,
    required this.onOpenAdd,
    this.bestPlatformRating,
  });

  @override
  ConsumerState<_SpotlightHeroBanner> createState() =>
      _SpotlightHeroBannerState();
}

class _SpotlightHeroBannerState extends ConsumerState<_SpotlightHeroBanner> {
  final FlyoutController _flyoutCtrl = FlyoutController();
  final GlobalKey _moreKey = GlobalKey();

  @override
  void dispose() {
    _flyoutCtrl.dispose();
    super.dispose();
  }

  Offset? _moreAnchorPos() {
    final box = _moreKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final accent = theme.accentInk;
    final game = widget.game;

    if (game == null) {
      return FluentSurfaceCard(
        radius: 12,
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('欢迎回到 KisakiGals', style: theme.typography.title),
                  const SizedBox(height: 6),
                  Text(
                    '添加或拖拽第一部视觉小说，开启你的游玩轨迹与存档守护之旅。',
                    style: theme.typography.body?.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: widget.onOpenAdd,
                        child: const Text('添加作品'),
                      ),
                      Button(
                        onPressed: widget.onOpenLibrary,
                        child: const Text('前往游戏库'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isRunning = ref.watch(
      trackingGameProvider.select((id) => game.id != null && id == game.id),
    );
    final hasExe = game.exePath.trim().isNotEmpty;
    final nsfwMode = ref.watch(nsfwModeProvider);
    final showBackdropCover =
        game.coverPath.isNotEmpty && (!game.nsfw || nsfwMode == 'show');
    final displayScore = game.userRating > 0
        ? game.userRating
        : ((widget.bestPlatformRating != null &&
                widget.bestPlatformRating! > 0)
            ? widget.bestPlatformRating
            : null);

    final metaParts = <String>[
      if (game.developer.isNotEmpty) game.developer,
      if (game.totalSeconds > 0) '累计 ${fmtDuration(game.totalSeconds)}',
      if (game.lastPlayedAt != null) '上次 ${fmtRelativeShort(game.lastPlayedAt!)}',
    ];

    void openMenu([Offset? pos]) => showGameMenuFlyout(
          context,
          ref,
          controller: _flyoutCtrl,
          game: game,
          position: pos,
        );

    return FlyoutTarget(
      controller: _flyoutCtrl,
      child: GestureDetector(
        onSecondaryTapUp: (d) => openMenu(d.globalPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.surfaceStroke),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.surfaceCard,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: isDark ? 0.20 : 0.12),
                          theme.surfaceCard,
                        ],
                      ),
                    ),
                  ),
                ),
                if (showBackdropCover)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: isDark ? 0.24 : 0.18,
                        child: FluentCoverImage(
                          pathOrUrl: game.coverPath,
                          nsfw: false,
                          radius: 0,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
                // 单层定向可读性遮罩，替代二重模糊开销并保证高对比度文本可读
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            theme.surfaceCard.withValues(
                              alpha: isDark ? 0.55 : 0.65,
                            ),
                            theme.surfaceCard.withValues(
                              alpha: isDark ? 0.92 : 0.94,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cover = Tooltip(
                        message: '查看「${game.displayName}」详情',
                        child: Semantics(
                          button: true,
                          label: '查看「${game.displayName}」详情',
                          child: HoverButton(
                            cursor: game.id == null
                                ? MouseCursor.defer
                                : SystemMouseCursors.click,
                            onPressed: game.id == null
                                ? null
                                : () => openGameDetail(
                                      context,
                                      game.id!,
                                      initial: game,
                                      ref: ref,
                                    ),
                            builder: (context, states) => FocusBorder(
                              focused: states.isFocused,
                              renderOutside: false,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: states.isHovered
                                        ? accent.withValues(alpha: 0.7)
                                        : theme.surfaceStroke,
                                  ),
                                ),
                                child: FluentCoverImage(
                                  pathOrUrl: game.coverPath,
                                  nsfw: game.nsfw,
                                  width: 152,
                                  height: 214,
                                  radius: 7,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );

                      final details = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FluentR18ScoreRow(
                            nsfw: game.nsfw,
                            scoreText: displayScore?.toStringAsFixed(1),
                            trailing: [
                              if (isRunning)
                                FluentBadge(
                                  icon: FluentIcons.play_16_filled,
                                  text: '正在运行',
                                  foreground: theme.onAccentInk,
                                  background: accent,
                                )
                              else
                                FluentStatusPill(status: game.playStatus),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            game.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.titleLarge,
                          ),
                          if (metaParts.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              metaParts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.body?.copyWith(
                                color: theme.textSecondary,
                              ),
                            ),
                          ],
                          if (game.summary.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              game.summary.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.caption?.copyWith(
                                color: theme.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              isRunning
                                  ? Button(
                                      style: ButtonStyle(
                                        backgroundColor:
                                            WidgetStatePropertyAll(
                                          theme.dangerFill,
                                        ),
                                        foregroundColor:
                                            const WidgetStatePropertyAll(
                                          Colors.white,
                                        ),
                                      ),
                                      onPressed: () =>
                                          stopActiveGameSession(ref),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            FluentIcons.stop_16_filled,
                                            size: 15,
                                          ),
                                          SizedBox(width: 6),
                                          Text('停止会话'),
                                        ],
                                      ),
                                    )
                                  : FilledButton(
                                      onPressed: () {
                                        GameLaunchService.launchAndTrack(
                                          game,
                                          ref,
                                        );
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            FluentIcons.play_16_filled,
                                            size: 15,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(hasExe ? '立即启动' : '配置后启动'),
                                        ],
                                      ),
                                    ),
                              Button(
                                onPressed: game.id == null
                                    ? null
                                    : () => openGameDetail(
                                          context,
                                          game.id!,
                                          initial: game,
                                          ref: ref,
                                        ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(FluentIcons.open_16_regular, size: 15),
                                    SizedBox(width: 6),
                                    Text('查看详情'),
                                  ],
                                ),
                              ),
                              Button(
                                onPressed: () =>
                                    openGameExploreForGame(context, game),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      FluentIcons.compass_northwest_16_regular,
                                      size: 15,
                                    ),
                                    SizedBox(width: 6),
                                    Text('探索百科'),
                                  ],
                                ),
                              ),
                              Tooltip(
                                message: '更多操作 (右键横幅)',
                                child: IconButton(
                                  key: _moreKey,
                                  icon: const Icon(
                                    FluentIcons.more_horizontal_16_regular,
                                    size: 16,
                                  ),
                                  onPressed: () => openMenu(_moreAnchorPos()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );

                      if (constraints.maxWidth < 540) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(child: cover),
                            const SizedBox(height: 16),
                            details,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          cover,
                          const SizedBox(width: 22),
                          Expanded(child: details),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiMatrixRow extends StatelessWidget {
  final HomeData data;
  final int playingCount;
  final int playedCount;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenStats;

  const _KpiMatrixRow({
    required this.data,
    required this.playingCount,
    required this.playedCount,
    required this.onOpenLibrary,
    required this.onOpenStats,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiCard(
        icon: FluentIcons.library_20_regular,
        label: '总入库',
        value: '${data.gameCount} 部',
        hint: '在玩 $playingCount · 已通关 $playedCount',
        onTap: onOpenLibrary,
      ),
      _KpiCard(
        icon: FluentIcons.calendar_week_numbers_20_regular,
        label: '本周游玩',
        value: fmtDuration(data.week.totalSeconds),
        hint: '${data.week.sessionCount} 次 · 活跃 ${data.week.activeDays} 天',
        onTap: onOpenStats,
      ),
      _KpiCard(
        icon: FluentIcons.clock_20_regular,
        label: '总游玩',
        value: fmtDuration(data.all.totalSeconds),
        hint: '${data.all.sessionCount} 次游玩会话',
        onTap: onOpenStats,
      ),
      _KpiCard(
        icon: FluentIcons.calendar_20_regular,
        label: '活跃天数',
        value: '${data.all.activeDays} 天',
        hint: '本月活跃 ${data.month.activeDays} 天',
        onTap: onOpenStats,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final VoidCallback onTap;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    return FluentSurfaceCard(
      onTap: onTap,
      semanticLabel: '$label $value，$hint',
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.caption?.copyWith(
                    color: theme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                FluentIcons.chevron_right_16_regular,
                size: 13,
                color: theme.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.subtitle?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.caption?.copyWith(
              color: theme.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalShelfSection extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;
  final List<Game> games;
  final Map<int, double> platformRatings;
  final String emptyTitle;
  final String emptyMessage;

  const _HorizontalShelfSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.games,
    required this.platformRatings,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  @override
  State<_HorizontalShelfSection> createState() =>
      _HorizontalShelfSectionState();
}

class _HorizontalShelfSectionState extends State<_HorizontalShelfSection> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _hoveringShelf = false;
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_syncScrollExtents);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollExtents());
  }

  @override
  void didUpdateWidget(covariant _HorizontalShelfSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.games.length != widget.games.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollExtents());
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_syncScrollExtents);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _syncScrollExtents() {
    if (!mounted || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final left = pos.pixels > 2;
    final right = pos.pixels < pos.maxScrollExtent - 2;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollCtrl.hasClients) return;
    final disableAnim = fluentAnimationsDisabled(context);
    final target = (_scrollCtrl.offset + delta)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(
      target,
      duration: disableAnim ? Duration.zero : FluentMotion.standard,
      curve: FluentMotion.enterCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluentSectionHeader(
          title: widget.title,
          subtitle: widget.subtitle,
          icon: widget.icon,
          trailing: Button(
            onPressed: widget.onAction,
            child: Text(widget.actionLabel),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.games.isEmpty)
          FluentSurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: FluentEmptyState(
              icon: FluentIcons.games_24_regular,
              title: widget.emptyTitle,
              message: widget.emptyMessage,
            ),
          )
        else
          MouseRegion(
            onEnter: (_) {
              _syncScrollExtents();
              setState(() => _hoveringShelf = true);
            },
            onExit: (_) => setState(() => _hoveringShelf = false),
            child: SizedBox(
              height: 292,
              child: Stack(
                children: [
                  NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) {
                      _syncScrollExtents();
                      return false;
                    },
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      itemCount: widget.games.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final g = widget.games[i];
                        return _HomeShelfCard(
                          game: g,
                          bestPlatformRating:
                              g.id != null ? widget.platformRatings[g.id!] : null,
                        );
                      },
                    ),
                  ),
                  if ((_hoveringShelf || _canLeft) && _canLeft)
                    Positioned(
                      left: 6,
                      top: 76,
                      child: AnimatedOpacity(
                        opacity: _hoveringShelf ? 1.0 : 0.72,
                        duration: FluentMotion.fast,
                        child: _ShelfArrowButton(
                          icon: FluentIcons.chevron_left_16_regular,
                          tooltip: '向左滚动',
                          onTap: () => _scrollBy(-320),
                        ),
                      ),
                    ),
                  if ((_hoveringShelf || _canRight) && _canRight)
                    Positioned(
                      right: 6,
                      top: 76,
                      child: AnimatedOpacity(
                        opacity: _hoveringShelf ? 1.0 : 0.72,
                        duration: FluentMotion.fast,
                        child: _ShelfArrowButton(
                          icon: FluentIcons.chevron_right_16_regular,
                          tooltip: '向右滚动',
                          onTap: () => _scrollBy(320),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ShelfArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ShelfArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FluentAcrylicPanel(
        radius: 18,
        padding: const EdgeInsets.all(2),
        child: SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            icon: Icon(icon, size: 16),
            onPressed: onTap,
          ),
        ),
      ),
    );
  }
}

class _HomeShelfCard extends ConsumerStatefulWidget {
  final Game game;
  final double? bestPlatformRating;

  const _HomeShelfCard({
    required this.game,
    this.bestPlatformRating,
  });

  @override
  ConsumerState<_HomeShelfCard> createState() => _HomeShelfCardState();
}

class _HomeShelfCardState extends ConsumerState<_HomeShelfCard> {
  final FlyoutController _flyoutCtrl = FlyoutController();

  @override
  void dispose() {
    _flyoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final isRunning = ref.watch(
      trackingGameProvider.select((id) => game.id != null && id == game.id),
    );
    final rating = game.userRating > 0
        ? game.userRating
        : ((widget.bestPlatformRating != null && widget.bestPlatformRating! > 0)
            ? widget.bestPlatformRating
            : null);

    return FlyoutTarget(
      controller: _flyoutCtrl,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => showGameMenuFlyout(
          context,
          ref,
          controller: _flyoutCtrl,
          game: game,
          position: d.globalPosition,
        ),
        child: SizedBox(
          width: 148,
          child: FluentSurfaceCard(
            padding: const EdgeInsets.all(8),
            selected: isRunning,
            semanticLabel: game.displayName,
            onTap: game.id == null
                ? null
                : () => openGameDetail(
                      context,
                      game.id!,
                      initial: game,
                      ref: ref,
                    ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 固定封面高度，保证同一水平货架上所有卡片封面底边严格对齐
                SizedBox(
                  height: 158,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FluentCoverImage(
                        pathOrUrl: game.coverPath,
                        nsfw: game.nsfw,
                        radius: 6,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                      if (isRunning)
                        Positioned(
                          left: 5,
                          top: 5,
                          child: FluentBadge(
                            icon: FluentIcons.play_16_filled,
                            text: '正在运行',
                            foreground: theme.onAccentInk,
                            background: accent,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  game.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.bodyStrong,
                ),
                const SizedBox(height: 3),
                Text(
                  isRunning
                      ? '正在运行'
                      : (game.lastPlayedAt != null
                          ? fmtRelativeShort(game.lastPlayedAt!)
                          : game.playStatus.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.caption?.copyWith(
                    color: isRunning ? accent : theme.textSecondary,
                    fontWeight: isRunning ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                FluentR18ScoreRow(
                  nsfw: game.nsfw,
                  scoreText: rating?.toStringAsFixed(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityFeedCard extends ConsumerWidget {
  final List<ActivityItem> activity;
  final VoidCallback onShowAll;

  const _ActivityFeedCard({
    required this.activity,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = activity.take(_kTimelineLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluentSectionHeader(
          title: '库中动态',
          icon: FluentIcons.timeline_20_regular,
          trailing: activity.length > _kTimelineLimit
              ? Button(
                  onPressed: onShowAll,
                  child: Text('全部 (${activity.length})'),
                )
              : null,
        ),
        const SizedBox(height: 12),
        FluentSurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: items.isEmpty
              ? const FluentEmptyState(
                  icon: FluentIcons.timeline_20_regular,
                  title: '暂无动态',
                  message: '游玩、添加或评分后这里会记录你的轨迹',
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(),
                      _ActivityRow(
                        item: items[i],
                        onTap: () => openGameDetail(
                          context,
                          items[i].gameId,
                          ref: ref,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
  final VoidCallback onTap;

  const _ActivityRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final (icon, label) = switch (item.type) {
      'added' => (FluentIcons.add_16_regular, '收录入库'),
      'finished' => (FluentIcons.checkmark_circle_16_regular, '标记通关'),
      'rated' => (
          FluentIcons.star_16_filled,
          item.detail.isEmpty ? '给出评分' : '留下评价',
        ),
      _ => (FluentIcons.play_16_regular, '开始游玩'),
    };
    final detail = item.detail.trim();

    return Semantics(
      button: true,
      label: '${item.gameName}，$label',
      child: HoverButton(
        cursor: SystemMouseCursors.click,
        onPressed: onTap,
        builder: (context, states) => FocusBorder(
          focused: states.isFocused,
          renderOutside: false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: states.isPressed
                  ? theme.subtlePressed
                  : states.isHovered
                      ? theme.subtleHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 68,
                  child: Text(
                    fmtRelativeShort(item.at),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption?.copyWith(
                      color: theme.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                FluentCoverImage(
                  pathOrUrl: item.coverPath,
                  nsfw: item.nsfw,
                  width: 30,
                  height: 44,
                  radius: 4,
                  allowRevealOnHover: false,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.gameName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.bodyStrong,
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.caption?.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FluentBadge(icon: icon, text: label),
                const SizedBox(width: 4),
                Icon(
                  FluentIcons.chevron_right_16_regular,
                  size: 13,
                  color: theme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendCard extends StatelessWidget {
  final List<TagItem> tags;
  final List<ScrapedGame>? recommendations;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<String> onPickQuery;

  const _RecommendCard({
    required this.tags,
    required this.recommendations,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onPickQuery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final recs = recommendations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluentSectionHeader(
          title: '为你推荐',
          icon: FluentIcons.sparkle_20_regular,
          trailing: recs != null
              ? Button(
                  onPressed: loading ? null : onRefresh,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.arrow_clockwise_16_regular, size: 14),
                      SizedBox(width: 4),
                      Text('换一批'),
                    ],
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        FluentSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in tags)
                      FluentBadge(
                        text: '#${t.name}',
                        tooltip: '在探索页检索「${t.name}」',
                        onTap: () => onPickQuery(t.name),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: ProgressRing()),
                )
              else if (error != null)
                FluentEmptyState(
                  icon: FluentIcons.error_circle_24_regular,
                  title: '检索推荐出错',
                  message: error!,
                  action: FilledButton(
                    onPressed: onRefresh,
                    child: const Text('重试'),
                  ),
                )
              else if (recs == null)
                FluentEmptyState(
                  icon: FluentIcons.sparkle_24_regular,
                  title: '按库内标签发现新作',
                  message: '点击下方按钮从 VNDB 检索匹配作品',
                  action: FilledButton(
                    onPressed: onRefresh,
                    child: const Text('获取推荐'),
                  ),
                )
              else if (recs.isEmpty)
                FluentEmptyState(
                  icon: FluentIcons.sparkle_24_regular,
                  title: '暂无推荐',
                  message: '网络不可用或库内标签太少，稍后再试',
                  action: Button(
                    onPressed: onRefresh,
                    child: const Text('重新获取'),
                  ),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < recs.length; i++) ...[
                      if (i > 0) const Divider(),
                      Semantics(
                        button: true,
                        label: '在探索中查看 ${recs[i].displayName}',
                        child: HoverButton(
                          cursor: SystemMouseCursors.click,
                          onPressed: () => onPickQuery(recs[i].displayName),
                          builder: (context, states) => FocusBorder(
                            focused: states.isFocused,
                            renderOutside: false,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 6,
                              ),
                              decoration: BoxDecoration(
                                color: states.isPressed
                                    ? theme.subtlePressed
                                    : states.isHovered
                                        ? theme.subtleHover
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  FluentCoverImage(
                                    pathOrUrl: recs[i].coverUrl,
                                    nsfw: recs[i].nsfw,
                                    width: 34,
                                    height: 50,
                                    radius: 4,
                                    allowRevealOnHover: false,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          recs[i].displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.typography.bodyStrong,
                                        ),
                                        const SizedBox(height: 4),
                                        FluentR18ScoreRow(
                                          nsfw: recs[i].nsfw,
                                          scoreText: recs[i].rating > 0
                                              ? recs[i]
                                                  .rating
                                                  .toStringAsFixed(1)
                                              : null,
                                          trailing: [
                                            FluentBadge(
                                              text: KisakiSources.labels[
                                                      recs[i].source] ??
                                                  recs[i].source,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    FluentIcons.chevron_right_16_regular,
                                    size: 13,
                                    color: theme.textTertiary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
