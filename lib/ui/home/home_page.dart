/// 主页：问候与速览 / 最近游玩 Hero / 动态时间线 / 为你推荐。
///
/// 重构要点：
/// - 页面骨架交给 [KPage]（标题区 + 统一留白），整页滚动；
///   卡片内**不再嵌套滚动视图**：动态/推荐改为「限制条数 + 底部留白」，
///   修掉旧布局末条被裁成半截的问题（固定高度 + 卡内 ListView 的老毛病）；
///   被条数限制挡掉的旧动态在「全部动态」浮层里继续滚动查看。
/// - 全部卡片走 [KCard] / [KStat] / [KMediaRow]，间距圆角阴影动效取
///   design.dart 的 token，不再手写裸 Container + BoxDecoration。
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

/// 动态时间线展示上限（限制条数，避免整页被无限拉长）。
const int _kTimelineLimit = 6;

/// 推荐展示上限。
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

  // ================= 页面内容 =================

  Widget _content(HomeData data) {
    return KPage(
      // 超宽屏（>1440）下居中限宽，避免卡片与数据带被拉稀
      maxContentWidth: 1440,
      title: _greeting(),
      subtitle: '共 ${data.gameCount} 部作品 · 累计 ${fmtDuration(data.all.totalSeconds)}',
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
          StaggeredFadeIn(index: 0, child: _overviewSection(data)),
          const SizedBox(height: Gap.lg),
          StaggeredFadeIn(index: 1, child: _heroSection(data)),
          const SizedBox(height: Gap.lg),
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

  // ================= 1. 速览三卡 =================

  Widget _overviewSection(HomeData data) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KSectionTitle('速览'),
        Row(
          children: [
            Expanded(
              child: _statCard(
                title: '本周',
                icon: Icons.calendar_view_week_rounded,
                accent: scheme.primary,
                stats: data.week,
              ),
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: _statCard(
                title: '本月',
                icon: Icons.calendar_view_month_rounded,
                accent: scheme.secondary,
                stats: data.month,
              ),
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: _statCard(
                title: '总计',
                icon: Icons.all_inclusive_rounded,
                accent: scheme.tertiary,
                stats: data.all,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 速览卡：数值走 [KStat]（内部已用 AnimatedCount），点击进统计页。
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

  // ================= 2. 最近游玩（紧凑横排，同屏可见多部） =================

  Widget _heroSection(HomeData data) {
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
          // 横向滚动的一排小卡：一屏能看到 6-8 部（原先一个大 Hero 只显示一部）
          SizedBox(
            height: _kRecentTileHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: games.length,
              separatorBuilder: (_, __) => const SizedBox(width: Gap.md),
              itemBuilder: (context, i) => _RecentTile(
                game: games[i],
                primary: i == 0,
                onContinue: () => _continueGame(games[i]),
                onOpen: games[i].id == null
                    ? null
                    : () => _openGameDetail(games[i].id!,
                        initial: games[i]),
              ),
            ),
          ),
      ],
    );
  }

  /// 最近游玩卡片的整体高度（封面 84 + 标题/副标题两行 + 内边距）
  static const double _kRecentTileHeight = 84 / (2 / 3) + 62;

  // ================= 3. 动态 + 推荐 =================

  /// 动态与推荐并排，两列等高（IntrinsicHeight）；
  /// 两卡内部都只是 Column，没有嵌套滚动，因此不会出现半截条目。
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
    final scheme = Theme.of(context).colorScheme;
    final shown = activity.length > _kTimelineLimit
        ? _kTimelineLimit
        : activity.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KSectionTitle(
          '动态',
          trailing: _titleSlot(
            activity.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KBadge(
                        text: '最近 $shown 条',
                        icon: Icons.timeline_rounded,
                        color: scheme.secondary,
                      ),
                      // 超出卡片条数的旧记录：浮层里继续看
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
        Expanded(child: KCard(child: _timelineBody(activity))),
      ],
    );
  }

  /// 标题右侧固定 38 高的槽位：左右两列标题行等高，两张卡片顶边对齐。
  Widget _titleSlot(Widget? child) => SizedBox(height: 38, child: child);

  Widget _timelineBody(List<ActivityItem> activity) {
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
          if (i > 0) const SizedBox(height: Gap.xxs),
          _activityRow(items[i]),
        ],
        // 底部留白：最后一条不贴卡片下沿（评审指出的裁切问题）
        const SizedBox(height: Gap.xs),
      ],
    );
  }

  Widget _activityRow(ActivityItem a) {
    return _ActivityRow(item: a, onTap: () => _openGameDetail(a.gameId));
  }

  /// 「全部动态」浮层：卡片里只留最近几条，更早的记录在这里滚动查看
  /// （保留旧版时间线可滚动浏览全部动态的能力）。
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

  /// 刷新入口：加载中换成同尺寸的指示器，避免标题行高度跳动。
  Widget _recommendAction() {
    if (_loadingRecommendations) {
      return const Padding(
        padding: EdgeInsets.only(left: 6),
        child: SizedBox(width: 38, height: 38, child: KLoading(size: 18)),
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
                KBadge(text: '#${t.name}', color: scheme.secondary),
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
          // 首屏空态：骨架占位 + 卡内刷新按钮（旧版这里是大片死白）
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
            for (final g in recs.take(_kRecommendLimit)) _recommendRow(g),
          ],
        const SizedBox(height: Gap.xs),
      ],
    );
  }

  Widget _recommendRow(ScrapedGame g) {
    final scheme = Theme.of(context).colorScheme;
    final source = KisakiSources.labels[g.source] ?? g.source;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: InteractiveSurface(
        onTap: () => _openResourceSearch(g.displayName),
        borderRadius: BorderRadius.circular(Radii.md),
        color: Colors.transparent,
        outline: scheme.primary,
        // 行式条目：只保留 hover 描边与按压回弹，不做整行上浮
        borderOnIdle: false,
        elevated: false,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 6),
        child: Row(
          children: [
            CoverImage(
              path: '',
              networkUrl: g.coverUrl,
              nsfw: g.nsfw,
              width: 32,
              height: 48,
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
            const SizedBox(width: Gap.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body
                        .copyWith(fontWeight: FontWeight.w600, height: 1.3),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (g.rating > 0) ...[
                        const Icon(Icons.star_rounded,
                            size: 12, color: KisakiColors.star),
                        const SizedBox(width: 3),
                        Text(
                          g.rating.toStringAsFixed(1),
                          style: Type.micro.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: Gap.sm),
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

  /// 跳到探索页并**按该作品名发起一次关键词搜索**（榜单里找到它 → 点开详情
  /// 就能看到资源下载链接）。
  ///
  /// 只负责把关键词写进 [resourceQueryProvider]（语义 = 待预填的关键词）并切页：
  /// 探索页会消费它——填进搜索框并立刻发起搜索，消费完把 provider 清空，
  /// 这样对同一部作品再点一次仍然会真正触发（值从 '' 变化才触发监听）。
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

// ================= Hero 卡 =================

/// 最近游玩 Hero：封面 + 元信息 + 继续游戏；正在计时时右侧显示本局实时时长。
/// 最近游玩卡片：竖向小卡（封面 2:3 + 名称 + 上次游玩）。
///
/// 与旧版区别：旧版是一个大 Hero（一屏只显示一部，还要左右翻页），
/// 现在是一排可横向滚动的小卡，同屏可见 6-8 部，鼠标悬停即出现启动按钮。
class _RecentTile extends ConsumerStatefulWidget {
  final Game game;

  /// 最近一次游玩的那部：加主色描边并常驻启动按钮
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
                    ? scheme.primary.withValues(alpha: 0.45)
                    : (_hover
                        ? scheme.primary.withValues(alpha: 0.30)
                        : Elev.border(dark)),
              ),
              boxShadow:
                  _hover ? Elev.cardHover(dark, scheme.primary) : Elev.card(dark, scheme.primary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CoverImage(
                          path: game.coverPath,
                          nsfw: game.nsfw,
                          borderRadius: BorderRadius.circular(Radii.thumb),
                        ),
                      ),
                      // 悬停/最近游玩：在封面右下角浮出启动按钮
                      if (_hover || widget.primary || running)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: KOverlayIconButton(
                            icon: running
                                ? Icons.sports_esports_rounded
                                : Icons.play_arrow_rounded,
                            tooltip: running ? '游玩中' : '启动游戏',
                            color: running ? KisakiColors.pink : Colors.white,
                            onTap: running ? widget.onOpen : widget.onContinue,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  game.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: dark ? KisakiColors.nightInk : KisakiColors.ink),
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
                  style: Type.micro.copyWith(
                      color: running
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: running ? FontWeight.w700 : FontWeight.w400),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================= 动态条目 / 全部动态 =================

/// 动态条目：封面 + 游戏名 + 类型徽标 + 相对时间，点击进详情。
class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
  final VoidCallback onTap;

  const _ActivityRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (item.type) {
      'added' => (Icons.add_circle_rounded, scheme.secondary, '添加了游戏'),
      'rated' => (
          Icons.star_rounded,
          KisakiColors.star,
          item.detail.isEmpty ? '给出了评分' : '留下了评价'
        ),
      _ => (Icons.play_circle_rounded, scheme.primary, '开始游玩'),
    };
    return KMediaRow(
      coverPath: item.coverPath,
      coverWidth: 32,
      title: item.gameName,
      badges: [
        KBadge(text: text, icon: icon, color: color),
        Text(
          fmtRelative(item.at),
          style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
      onTap: onTap,
    );
  }
}

/// 「全部动态」浮层：卡片只展示最近几条，历史记录在这里滚动查看。
class _AllActivitySheet extends StatelessWidget {
  final List<ActivityItem> activities;
  final ValueChanged<int> onSelect;

  const _AllActivitySheet({required this.activities, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 行高固定（KMediaRow 约 70），按条数给高度并做上下限，避免空荡荡或超高
    final listHeight = (activities.length * 72.0).clamp(180.0, 440.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: KCard(
          borderRadius: Radii.sheet,
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
                    color: scheme.secondary,
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
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  children: [
                    for (final a in activities)
                      _ActivityRow(item: a, onTap: () => onSelect(a.gameId)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= 推荐骨架 =================

/// 推荐空态骨架：低对比占位块，避免大片死白。
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
                _Bone(color: scheme.surfaceContainerHighest, width: 32, height: 48),
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

/// 占位块：只用基础组件（圆角裁剪 + 纯色块），不写手搓 BoxDecoration。
class _Bone extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  const _Bone({required this.color, required this.width, required this.height});

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

// ================= 侧栏 Tab 索引 =================
//
// 索引已集中到 `lib/ui/shell/tabs.dart`（[Tabs]）：这里只保留这几个别名，
// 免得页面里再出现裸数字（新增页面时索引一变就会全线错位）。
// 探索页现在只有一种形态（没有「资源」模式了）：这里的入口会先把关键词写进
// `resourceQueryProvider`，探索页据此预填搜索框并**立刻发起一次关键词搜索**，
// 资源下载链接则由该作品的详情弹窗自动去查。
const int _kLibraryTab = Tabs.library;
const int _kSearchTab = Tabs.discover;
const int _kStatsTab = Tabs.stats;
