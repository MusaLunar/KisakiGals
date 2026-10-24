/// 主页：誌面 (Shimen) 卷首特辑 Bento 矩阵 / 最近游玩图版列 / 发售表式动态与推荐.
///
/// 核心版式升级：
/// - 卷首特辑 Bento 区：左侧为主打作品特辑卡（支持一键启动与封面微缩放物理），
///   右侧咬合本周/本月/总计三格专色青蓝 (Process Cyan) 等宽数字统计矩阵；
/// - 消除「卡中套卡」(Card-inside-Card) 冗余描边：动态时间线采用杂志日程表式
///   悬挂时间列 + 1px 裁切细线分隔，严守单一海拔原则。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import '../../services/game_launch_service.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../kit.dart';
import '../shell/tabs.dart';
import '../theme.dart';
import '../widgets/common.dart' show CoverImage;

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

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeDataProvider);

    return home.when(
      loading: () => const KPage(
        title: '主页',
        subtitle: '正在读取你的游玩记录',
        child: KLoading(),
      ),
      error: (e, _) => KPage(
        title: '主页',
        child: KEmpty(
          icon: Icons.cloud_off_rounded,
          title: '主页数据加载失败',
          subtitle: '$e',
          actionLabel: '刷新',
          onAction: () => ref.invalidate(homeDataProvider),
        ),
      ),
      data: _content,
    );
  }

  Widget _content(HomeData data) {
    return KPage(
      maxContentWidth: 1440,
      title: _greeting(),
      subtitle:
          '共 ${data.gameCount} 部作品 · 累计 ${fmtDuration(data.all.totalSeconds)}',
      actions: [
        KIconAction(
          icon: Icons.refresh_rounded,
          tooltip: '刷新主页数据',
          onTap: () {
            ref.invalidate(homeDataProvider);
            ref.invalidate(allTagsProvider);
          },
        ),
      ],
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggeredFadeIn(index: 0, child: _leadBentoSection(data)),
          const SizedBox(height: Gap.xl),
          StaggeredFadeIn(index: 1, child: _recentShelfSection(data)),
          const SizedBox(height: Gap.xl),
          StaggeredFadeIn(index: 2, child: _feedRow(data)),
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

  // ================= 1. 卷首特辑 + 专色青蓝数据 Bento =================

  Widget _leadBentoSection(HomeData data) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cyanInk = KisakiColors.temporalInk(dark);
    final leadGame =
        data.recentGames.isNotEmpty ? data.recentGames.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KSectionTitle('速览'),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final statsGrid = Row(
              children: [
                Expanded(
                  child: _statCard(
                    title: '本周',
                    icon: Icons.calendar_view_week_rounded,
                    accent: cyanInk,
                    stats: data.week,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: _statCard(
                    title: '本月',
                    icon: Icons.calendar_view_month_rounded,
                    accent: cyanInk,
                    stats: data.month,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: _statCard(
                    title: '总计',
                    icon: Icons.all_inclusive_rounded,
                    accent: Theme.of(context).colorScheme.primary,
                    stats: data.all,
                  ),
                ),
              ],
            );

            if (leadGame == null) {
              return statsGrid;
            }

            final featureCard = _LeadFeatureCard(
              game: leadGame,
              onContinue: () => _continueGame(leadGame),
              onOpen: leadGame.id == null
                  ? null
                  : () => _openGameDetail(leadGame.id!, initial: leadGame),
            );

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  featureCard,
                  const SizedBox(height: Gap.md),
                  statsGrid,
                ],
              );
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 6, child: featureCard),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _statCard(
                                  title: '本周',
                                  icon: Icons.calendar_view_week_rounded,
                                  accent: cyanInk,
                                  stats: data.week,
                                ),
                              ),
                              const SizedBox(width: Gap.md),
                              Expanded(
                                child: _statCard(
                                  title: '本月',
                                  icon: Icons.calendar_view_month_rounded,
                                  accent: cyanInk,
                                  stats: data.month,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Gap.md),
                        Expanded(
                          child: _statCard(
                            title: '总计',
                            icon: Icons.all_inclusive_rounded,
                            accent: Theme.of(context).colorScheme.primary,
                            stats: data.all,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _statCard({
    required String title,
    required IconData icon,
    required Color accent,
    required AggStats stats,
  }) {
    return KStat(
      icon: icon,
      label: title,
      accent: accent,
      value: fmtDuration(stats.totalSeconds),
      hint: '${stats.sessionCount} 次游玩 · 活跃 ${stats.activeDays} 天',
      onTap: () => _switchTab(_kStatsTab),
    );
  }

  // ================= 2. 最近游玩图版横排 =================

  Widget _recentShelfSection(HomeData data) {
    final games = data.recentGames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KSectionTitle(
          '最近游玩',
          reserveSlot: true,
          trailing: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _switchTab(_kLibraryTab),
              child: const Text('全部作品'),
            ),
          ),
        ),
        if (games.isEmpty)
          KCard(
            dense: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.lg),
              child: KEmpty(
                compact: true,
                icon: Icons.videogame_asset_off_rounded,
                title: '还没有游玩记录',
                subtitle: '从游戏库挑一部开始新的故事吧',
                actionLabel: '去游戏库',
                actionIcon: Icons.videogame_asset_rounded,
                onAction: () => _switchTab(_kLibraryTab),
              ),
            ),
          )
        else
          SizedBox(
            height: _kRecentTileHeight + 8,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              itemCount: games.length,
              separatorBuilder: (_, __) => const SizedBox(width: Gap.md),
              itemBuilder: (context, i) => RepaintBoundary(
                child: _RecentTile(
                  game: games[i],
                  primary: i == 0,
                  onContinue: () => _continueGame(games[i]),
                  onOpen: games[i].id == null
                      ? null
                      : () => _openGameDetail(games[i].id!, initial: games[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static const double _kRecentTileHeight = 84 / (2 / 3) + 62;

  // ================= 3. 发售表式动态列 + 为你推荐 =================

  Widget _feedRow(HomeData data) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: _timelineColumn(data.activity)),
          const SizedBox(width: Gap.lg),
          Expanded(flex: 2, child: _recommendColumn()),
        ],
      ),
    );
  }

  Widget _timelineColumn(List<ActivityItem> activity) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cyanInk = KisakiColors.temporalInk(dark);
    final shown =
        activity.length > _kTimelineLimit ? _kTimelineLimit : activity.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KSectionTitle(
          '动态',
          accentColor: cyanInk,
          trailing: _titleSlot(
            activity.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KBadge(
                        text: '最近 $shown 条',
                        icon: Icons.timeline_rounded,
                        color: cyanInk,
                      ),
                      if (activity.length > _kTimelineLimit)
                        KIconAction(
                          icon: Icons.list_alt_rounded,
                          tooltip: '全部动态（${activity.length} 条）',
                          onTap: () => _openAllActivity(activity),
                        ),
                    ],
                  ),
          ),
        ),
        Expanded(
          child: KCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: _timelineBody(activity),
          ),
        ),
      ],
    );
  }

  Widget _titleSlot(Widget? child) => SizedBox(height: 36, child: child);

  Widget _timelineBody(List<ActivityItem> activity) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (activity.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Gap.xl),
        child: KEmpty(
          icon: Icons.timeline_rounded,
          title: '暂无动态',
          subtitle: '游玩、添加或评分后这里会有记录',
        ),
      );
    }
    final items = activity.take(_kTimelineLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: Elev.border(dark),
            ),
          _ActivityRow(
            item: items[i],
            onTap: () => _openGameDetail(items[i].gameId),
          ),
        ],
      ],
    );
  }

  void _openAllActivity(List<ActivityItem> activities) {
    showKisakiDialog<void>(
      context: context,
      builder: (_) => _AllActivitySheet(
        activities: activities,
        onSelect: (gameId) {
          Navigator.of(context).pop();
          _openGameDetail(gameId);
        },
      ),
    );
  }

  Widget _recommendColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KSectionTitle('为你推荐', trailing: _titleSlot(_recommendAction())),
        Expanded(child: KCard(child: _recommendBody())),
      ],
    );
  }

  Widget _recommendAction() {
    if (_loadingRecommendations) {
      return const Padding(
        padding: EdgeInsets.only(left: 6),
        child: SizedBox(width: 36, height: 36, child: KLoading(size: 18)),
      );
    }
    return KIconAction(
      icon: Icons.refresh_rounded,
      tooltip: '换一批推荐',
      onTap: _loadRecommendations,
    );
  }

  Widget _recommendBody() {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tags = _topTags();
    final recs = _recommendations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: Gap.xs + 2,
            runSpacing: Gap.xs,
            children: [
              for (final t in tags)
                KBadge(
                  text: '#${t.name}',
                  color: KisakiColors.temporalInk(dark),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
        ],
        if (_loadingRecommendations)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Gap.xxl),
            child: KLoading(),
          )
        else if (recs == null)
          ...[
            const _RecommendSkeleton(rows: 4),
            const SizedBox(height: Gap.md),
            Center(
              child: KPill(
                label: '刷新推荐',
                icon: Icons.refresh_rounded,
                filled: false,
                onTap: _loadRecommendations,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Center(
              child: Text(
                '按库内标签推荐新作品',
                style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ]
        else if (recs.isEmpty)
          KEmpty(
            icon: Icons.auto_awesome_rounded,
            title: '暂无推荐',
            subtitle: '网络不可用或库内标签太少，稍后再试',
            actionLabel: '重新获取',
            actionIcon: Icons.refresh_rounded,
            onAction: _loadRecommendations,
          )
        else
          ...[
            for (var i = 0; i < recs.take(_kRecommendLimit).length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: Elev.border(dark)),
              _recommendRow(recs[i]),
            ],
          ],
        const SizedBox(height: Gap.xs),
      ],
    );
  }

  Widget _recommendRow(ScrapedGame g) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ratingColor = KisakiColors.ratingInk(dark);
    final source = KisakiSources.labels[g.source] ?? g.source;

    return FluidPressable(
      onTap: () => _openResourceSearch(g.displayName),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            CoverImage(
              path: '',
              networkUrl: g.coverUrl,
              nsfw: g.nsfw,
              width: 34,
              height: 51,
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.28,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (g.rating > 0) ...[
                        Icon(Icons.star_rounded, size: 12, color: ratingColor),
                        const SizedBox(width: 3),
                        Text(
                          g.rating.toStringAsFixed(1),
                          style: Type.mono.copyWith(
                            fontSize: 11,
                            color: ratingColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.micro
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.xs),
            Icon(Icons.north_east_rounded,
                size: 13, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _switchTab(int index) =>
      ref.read(tabIndexProvider.notifier).state = index;

  void _openResourceSearch(String query) {
    if (query.isNotEmpty) {
      ref.read(resourceQueryProvider.notifier).state = query;
    }
    _switchTab(_kSearchTab);
  }

  void _openGameDetail(int gameId, {Game? initial}) {
    Navigator.of(context).push(FadeThroughRoute.builder(
      builder: (_) => GameDetailPage(gameId: gameId, initial: initial),
    ));
  }

  Future<void> _continueGame(Game g) async {
    await GameLaunchService.launchAndTrack(g, ref);
    if (mounted) setState(() {});
  }

  List<TagItem> _topTags() {
    final tags = ref.read(allTagsProvider).valueOrNull ?? [];
    return tags.take(6).toList();
  }

  Future<void> _loadRecommendations() async {
    if (_loadingRecommendations) return;
    setState(() => _loadingRecommendations = true);
    try {
      final tagNames = _topTags()
          .map((t) => t.name)
          .where((n) => n.isNotEmpty)
          .take(3)
          .toList();
      final results = <ScrapedGame>[];
      if (tagNames.isNotEmpty) {
        final bySource = await AppServices.I.fetcher
            .searchAll(tagNames.join(' '), only: [KisakiSources.vndb]);
        results.addAll(bySource[KisakiSources.vndb] ?? const []);
      }
      if (!mounted) return;
      setState(() {
        _recommendations = results.take(_kRecommendLimit).toList();
        _loadingRecommendations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecommendations = false);
    }
  }
}

// ================= 卷首主打特辑卡 (Lead Feature Card) =================

class _LeadFeatureCard extends ConsumerStatefulWidget {
  final Game game;
  final VoidCallback onContinue;
  final VoidCallback? onOpen;

  const _LeadFeatureCard({
    required this.game,
    required this.onContinue,
    this.onOpen,
  });

  @override
  ConsumerState<_LeadFeatureCard> createState() => _LeadFeatureCardState();
}

class _LeadFeatureCardState extends ConsumerState<_LeadFeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final game = widget.game;
    final running = ref.watch(trackingGameProvider) == game.id;
    final cyanInk = KisakiColors.temporalInk(dark);
    final ratingColor = KisakiColors.ratingInk(dark);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: KCard(
        onTap: widget.onOpen,
        padding: const EdgeInsets.all(14),
        borderColor: running
            ? cyanInk.withValues(alpha: 0.55)
            : scheme.primary.withValues(alpha: dark ? 0.32 : 0.22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 2:3 杂志封面图版（悬停时内部微缩放 1.035x）
            SizedBox(
              width: 96,
              height: 144,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: AnimatedScale(
                  scale: _hover ? Motion.coverHoverScale : 1.0,
                  duration: Motion.normal,
                  curve: Motion.enter,
                  child: CoverImage(
                    path: game.coverPath,
                    nsfw: game.nsfw,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      KBadge(
                        text: running ? '正在运行' : game.playStatus.label,
                        color: running ? cyanInk : scheme.primary,
                        icon: running
                            ? Icons.bolt_rounded
                            : Icons.bookmark_rounded,
                      ),
                      if (game.userRating > 0) ...[
                        const SizedBox(width: 6),
                        KBadge(
                          text: game.userRating.toStringAsFixed(1),
                          color: ratingColor,
                          icon: Icons.star_rounded,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    game.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.title.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (game.developer.isNotEmpty) game.developer,
                      if (game.totalSeconds > 0)
                        '累计 ${fmtDuration(game.totalSeconds)}',
                      if (game.lastPlayedAt != null)
                        '上次 ${fmtRelativeShort(game.lastPlayedAt!)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      KPill(
                        label: running ? '正在游玩' : '立即启动',
                        icon: running
                            ? Icons.sports_esports_rounded
                            : Icons.play_arrow_rounded,
                        color: running ? cyanInk : scheme.primary,
                        onTap: running ? widget.onOpen : widget.onContinue,
                      ),
                      const SizedBox(width: 8),
                      KPill(
                        label: '作品详情',
                        filled: false,
                        onTap: widget.onOpen,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 最近游玩小图版 =================

class _RecentTile extends ConsumerStatefulWidget {
  final Game game;
  final bool primary;
  final VoidCallback onContinue;
  final VoidCallback? onOpen;

  const _RecentTile({
    required this.game,
    required this.onContinue,
    this.onOpen,
    this.primary = false,
  });

  @override
  ConsumerState<_RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends ConsumerState<_RecentTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final game = widget.game;
    final running = ref.watch(trackingGameProvider) == game.id;
    final cyanInk = KisakiColors.temporalInk(dark);

    return SizedBox(
      width: 124,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            transform: Matrix4.identity()
              ..translateByDouble(0, _hover ? -2.0 : 0.0, 0, 1),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: dark ? KisakiColors.nightCard : Colors.white,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: running || widget.primary
                    ? scheme.primary.withValues(alpha: 0.55)
                    : (_hover
                        ? scheme.primary.withValues(alpha: 0.36)
                        : Elev.border(dark)),
                width: 1,
              ),
              boxShadow: _hover
                  ? Elev.cardHover(dark, scheme.primary)
                  : Elev.card(dark, scheme.primary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: AnimatedScale(
                              scale: _hover ? Motion.coverHoverScale : 1.0,
                              duration: Motion.fast,
                              curve: Motion.enter,
                              child: CoverImage(
                                path: game.coverPath,
                                nsfw: game.nsfw,
                                borderRadius: BorderRadius.circular(Radii.xs),
                              ),
                            ),
                          ),
                        ),
                        if (_hover || widget.primary || running)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: KOverlayIconButton(
                              icon: running
                                  ? Icons.sports_esports_rounded
                                  : Icons.play_arrow_rounded,
                              tooltip: running ? '游玩中' : '启动游戏',
                              color: running ? cyanInk : Colors.white,
                              onTap:
                                  running ? widget.onOpen : widget.onContinue,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  game.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  running
                      ? '游玩中'
                      : (game.lastPlayedAt == null
                          ? game.playStatus.label
                          : fmtRelativeShort(game.lastPlayedAt!)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.mono.copyWith(
                    fontSize: 10.5,
                    color: running ? cyanInk : scheme.onSurfaceVariant,
                    fontWeight: running ? FontWeight.w700 : FontWeight.w500,
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

// ================= 发售表式动态行 / 全部动态 =================

/// 发售表式动态行：左侧等宽悬挂时间列 + 2:3 缩略图版 + 标题 + 右侧 CMYK 专色动作徽标（无嵌套内卡边框）
class _ActivityRow extends StatefulWidget {
  final ActivityItem item;
  final VoidCallback onTap;

  const _ActivityRow({required this.item, required this.onTap});

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);
    final ratingColor = KisakiColors.ratingInk(dark);
    final item = widget.item;

    final (icon, color, text) = switch (item.type) {
      'added' => (Icons.add_circle_rounded, cyanInk, '收录入库'),
      'rated' => (
          Icons.star_rounded,
          ratingColor,
          item.detail.isEmpty ? '给出评分' : '留下评价'
        ),
      _ => (Icons.play_circle_rounded, scheme.primary, '开始游玩'),
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: FluidPressable(
        onTap: widget.onTap,
        scaleFactor: 0.985,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? (dark ? Colors.white : const Color(0xFF16151A))
                    .withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              // 悬挂等宽时间索引列
              SizedBox(
                width: 68,
                child: Text(
                  fmtRelativeShort(item.at),
                  style: Type.mono.copyWith(
                    fontSize: 11,
                    color: cyanInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                height: 45,
                child: CoverImage(
                  path: item.coverPath,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.gameName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              KBadge(text: text, icon: icon, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllActivitySheet extends StatelessWidget {
  final List<ActivityItem> activities;
  final ValueChanged<int> onSelect;

  const _AllActivitySheet({required this.activities, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cyanInk = KisakiColors.temporalInk(dark);
    final listHeight = (activities.length * 64.0).clamp(180.0, 440.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: KCard(
          borderRadius: Radii.sheet,
          overlayShadow: true,
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('全部动态', style: Type.title),
                  const SizedBox(width: Gap.sm),
                  KBadge(
                    text: '${activities.length} 条',
                    icon: Icons.timeline_rounded,
                    color: cyanInk,
                  ),
                  const Spacer(),
                  KIconAction(
                    icon: Icons.close_rounded,
                    tooltip: '关闭',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              SizedBox(
                height: listHeight,
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  itemCount: activities.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: Elev.border(dark),
                  ),
                  itemBuilder: (_, i) => _ActivityRow(
                    item: activities[i],
                    onTap: () => onSelect(activities[i].gameId),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendSkeleton extends StatelessWidget {
  final int rows;
  const _RecommendSkeleton({this.rows = 3});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Row(
              children: [
                _Bone(
                    color: scheme.surfaceContainerHighest,
                    width: 32,
                    height: 48),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bone(
                          color: scheme.surfaceContainerHighest,
                          width: double.infinity,
                          height: 11),
                      const SizedBox(height: Gap.sm),
                      FractionallySizedBox(
                        widthFactor: 0.55,
                        child: _Bone(
                            color: scheme.surfaceContainerHighest,
                            width: double.infinity,
                            height: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bone extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  const _Bone(
      {required this.color, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.xs),
      child: ColoredBox(
        color: color,
        child: SizedBox(width: width, height: height),
      ),
    );
  }
}

const int _kLibraryTab = Tabs.library;
const int _kSearchTab = Tabs.discover;
const int _kStatsTab = Tabs.stats;
