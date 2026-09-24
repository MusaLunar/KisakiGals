/// 主页：问候与速览 / 最近游玩 Hero / 动态时间线 / 为你推荐 / 快捷操作。
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
import '../add/add_game_page.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../kit.dart';
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
  int _heroIndex = 0;
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
          const SizedBox(height: Gap.lg),
          StaggeredFadeIn(index: 3, child: _quickSection(data)),
          const SizedBox(height: Gap.sm),
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

  // ================= 2. 最近游玩 Hero =================

  Widget _heroSection(HomeData data) {
    final games = data.recentGames;
    final index = games.isEmpty ? 0 : _heroIndex.clamp(0, games.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KSectionTitle(
          '最近游玩',
          trailing: games.length > 1 ? _heroPager(games.length, index) : null,
        ),
        if (games.isEmpty)
          KCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.xl),
              child: KEmpty(
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
          _HeroCard(
            game: games[index],
            onContinue: _continueGame,
            onOpen: games[index].id == null
                ? null
                : () => _openGameDetail(games[index].id!,
                    initial: games[index]),
          ),
      ],
    );
  }

  Widget _heroPager(int total, int index) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KIconAction(
          icon: Icons.chevron_left_rounded,
          tooltip: '上一部',
          onTap: () => _switchHero((index - 1 + total) % total),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xxs),
          child: Text(
            '${index + 1} / $total',
            style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        KIconAction(
          icon: Icons.chevron_right_rounded,
          tooltip: '下一部',
          onTap: () => _switchHero((index + 1) % total),
        ),
      ],
    );
  }

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

  // ================= 4. 快捷操作 =================

  Widget _quickSection(HomeData data) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KSectionTitle('快捷操作'),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.play_circle_fill_rounded,
                label: '继续游戏',
                color: scheme.primary,
                onTap: () => _continueLatest(data),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _QuickAction(
                icon: Icons.add_circle_outline_rounded,
                label: '添加游戏',
                color: scheme.secondary,
                onTap: _openAddGame,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _QuickAction(
                icon: Icons.videogame_asset_rounded,
                label: '游戏库',
                color: scheme.tertiary,
                onTap: () => _switchTab(_kLibraryTab),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _QuickAction(
                icon: Icons.travel_explore_rounded,
                label: '资源搜索',
                color: scheme.primary,
                onTap: () => _openResourceSearch(''),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _QuickAction(
                icon: Icons.insights_rounded,
                label: '游玩统计',
                color: scheme.secondary,
                onTap: () => _switchTab(_kStatsTab),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ================= 交互 =================

  void _switchHero(int index) => setState(() => _heroIndex = index);

  void _switchTab(int index) =>
      ref.read(tabIndexProvider.notifier).state = index;

  /// 跳到资源搜索页（可带关键词预填）。
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

  Future<void> _openAddGame() async {
    await Navigator.of(context)
        .push(FadeThroughRoute.builder(builder: (_) => const AddGamePage()));
    if (!mounted) return;
    ref.read(libraryVersionProvider.notifier).state++;
  }

  Future<void> _continueGame(Game g) async {
    await GameLaunchService.launchAndTrack(g, ref);
    if (mounted) setState(() {});
  }

  /// 继续最近游玩的一部；没有记录时退回游戏库挑选。
  Future<void> _continueLatest(HomeData data) async {
    if (data.recentGames.isEmpty) {
      _switchTab(_kLibraryTab);
      return;
    }
    await _continueGame(data.recentGames.first);
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
class _HeroCard extends ConsumerWidget {
  final Game game;
  final ValueChanged<Game> onContinue;

  /// 打开详情（无 id 时为 null，按钮与整卡都不可点）。
  final VoidCallback? onOpen;

  const _HeroCard({
    required this.game,
    required this.onContinue,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = game.id != null && ref.watch(trackingGameProvider) == game.id;
    return KCard(
      padding: const EdgeInsets.all(18),
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(
            path: game.coverPath,
            nsfw: game.nsfw,
            width: 108,
            height: 162,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          const SizedBox(width: Gap.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Type.title.copyWith(fontSize: 19),
                ),
                const SizedBox(height: Gap.md),
                _HeroMeta(
                  '上次游玩',
                  game.lastPlayedAt == null
                      ? '—'
                      : fmtRelative(game.lastPlayedAt!),
                ),
                _HeroMeta('总时长', fmtDuration(game.totalSeconds)),
                if (game.developer.isNotEmpty)
                  _HeroMeta('开发商', game.developer),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    KPill(
                      label: game.lastPlayedAt == null ? '开始游戏' : '继续游戏',
                      icon: Icons.play_arrow_rounded,
                      onTap: () => onContinue(game),
                    ),
                    const SizedBox(width: Gap.md),
                    KPill(
                      label: '查看详情',
                      icon: Icons.menu_book_rounded,
                      filled: false,
                      onTap: onOpen,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (tracking && game.id != null) ...[
            const SizedBox(width: Gap.lg),
            _LiveSessionPanel(key: ValueKey(game.id)),
          ],
        ],
      ),
    );
  }
}

/// Hero 元信息行：左标签 + 右数值。
class _HeroMeta extends StatelessWidget {
  final String label;
  final String value;
  const _HeroMeta(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// 本局实时时长（每秒刷新；数字用等宽数字，避免逐秒跳动时宽度抖动）。
class _LiveSessionPanel extends StatefulWidget {
  const _LiveSessionPanel({super.key});

  @override
  State<_LiveSessionPanel> createState() => _LiveSessionPanelState();
}

class _LiveSessionPanelState extends State<_LiveSessionPanel> {
  Timer? _ticker;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _seconds = AppServices.I.tracker.liveSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds = AppServices.I.tracker.liveSeconds);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = _seconds ~/ 3600;
    final m = (_seconds % 3600) ~/ 60;
    final s = _seconds % 60;
    final text = h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_manual_record_rounded,
                  size: 9, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                '游玩中',
                style: Type.micro.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            text,
            style: Type.numeric.copyWith(fontSize: 22, color: scheme.primary),
          ),
          const SizedBox(height: Gap.xxs),
          Text(
            '本次时长',
            style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
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

// ================= 快捷操作 =================

/// 快捷操作卡：图标 + 文案，点击即跳转/执行。
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 14),
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: Gap.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.label,
            ),
          ),
        ],
      ),
    );
  }
}

// ================= 侧栏 Tab 索引（与 app_shell 导航表一致） =================

const int _kLibraryTab = 1;
const int _kSearchTab = 2;
const int _kStatsTab = 3;
