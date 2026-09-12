/// 主页：统计速览 / Hero 最近游玩 / 活动时间线 / 推荐。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../services/game_launch_service.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import '../add/add_game_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
    final dark = Theme.of(context).brightness == Brightness.dark;

    return home.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      // 固定布局：整页不滚动，一屏展示全部内容；动态/推荐卡片内部滚动
      data: (data) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _greeting(data),
            const SizedBox(height: 14),
            // 1. Stat Cards
            Row(
              children: [
                Expanded(child: _StatCard(
                  title: '本周',
                  icon: Icons.calendar_view_week_rounded,
                  color: KisakiColors.pink,
                  stats: data.week,
                )),
                const SizedBox(width: 14),
                Expanded(child: _StatCard(
                  title: '本月',
                  icon: Icons.calendar_view_month_rounded,
                  color: KisakiColors.lavender,
                  stats: data.month,
                )),
                const SizedBox(width: 14),
                Expanded(child: _StatCard(
                  title: '总计',
                  icon: Icons.all_inclusive_rounded,
                  color: const Color(0xFF7EC8C3),
                  stats: data.all,
                )),
              ],
            ),
            const SizedBox(height: 14),
            // 2/3/4. 最近游玩 + 动态 + 推荐（固定高度，内部滚动）
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeroCard(
                          games: data.recentGames,
                          index: _heroIndex,
                          onSwitch: (i) => setState(() => _heroIndex = i),
                          onContinue: (g) => _continueGame(g),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _TimelineCard(activity: data.activity),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: _RecommendCard(
                      recommendations: _recommendations,
                      loading: _loadingRecommendations,
                      onRefresh: _loadRecommendations,
                      libraryTopTags: () => _topTags(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 快捷入口
            Row(
              children: [
                _QuickAction(
                  icon: Icons.add_circle_outline_rounded,
                  label: '添加游戏',
                  color: KisakiColors.pink,
                  onTap: () async {
                    await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddGamePage()));
                    ref.read(libraryVersionProvider.notifier).state++;
                  },
                ),
                const SizedBox(width: 12),
                _QuickAction(
                  icon: Icons.videogame_asset_rounded,
                  label: '游戏库',
                  color: KisakiColors.lavender,
                  onTap: () =>
                      ref.read(tabIndexProvider.notifier).state = 1,
                ),
                const SizedBox(width: 12),
                _QuickAction(
                  icon: Icons.insights_rounded,
                  label: '游玩统计',
                  color: const Color(0xFF7EC8C3),
                  onTap: () =>
                      ref.read(tabIndexProvider.notifier).state = 2,
                ),
              ],
            ),
            if (dark) const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _greeting(HomeData data) {
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
    return Row(
      children: [
        Text('$hello，今天也想见见她们吗？',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('共 ${data.gameCount} 部作品',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13)),
      ],
    );
  }

  List<TagItem> _topTags() {
    final tags = ref.read(allTagsProvider).valueOrNull ?? [];
    return tags.take(6).toList();
  }

  Future<void> _continueGame(Game g) async {
    await GameLaunchService.launchAndTrack(g, ref);
    if (mounted) setState(() {});
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loadingRecommendations = true);
    try {
      final tags = _topTags();
      final tagNames =
          tags.map((t) => t.name).where((n) => n.isNotEmpty).take(3).toList();
      final results = <ScrapedGame>[];
      if (tagNames.isNotEmpty) {
        final bySource = await AppServices.I.fetcher
            .searchAll(tagNames.join(' '), only: [KisakiSources.vndb]);
        results.addAll(bySource[KisakiSources.vndb] ?? const []);
      }
      if (!mounted) return;
      setState(() {
        _recommendations = results.take(6).toList();
        _loadingRecommendations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecommendations = false);
    }
  }
}

// ================= Stat Card =================

class _StatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final AggStats stats;
  const _StatCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: color.withValues(alpha: dark ? 0.22 : 0.14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 3),
                Text(fmtDuration(stats.totalSeconds),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: dark ? KisakiColors.nightInk : KisakiColors.ink)),
                const SizedBox(height: 2),
                Text(
                  '${stats.sessionCount} 次游玩 · 活跃 ${stats.activeDays} 天',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================= Hero Card =================

class _HeroCard extends StatelessWidget {
  final List<Game> games;
  final int index;
  final ValueChanged<int> onSwitch;
  final ValueChanged<Game> onContinue;

  const _HeroCard({
    required this.games,
    required this.index,
    required this.onSwitch,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (games.isEmpty) {
      return SoftCard(
        child: SizedBox(
          height: 180,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videogame_asset_off_rounded,
                    size: 40,
                    color: dark
                        ? KisakiColors.nightInkSoft
                        : KisakiColors.inkSoft),
                const SizedBox(height: 10),
                const Text('还没有游玩记录，从游戏库开始第一款吧'),
              ],
            ),
          ),
        ),
      );
    }
    final i = index.clamp(0, games.length - 1);
    final game = games[i];

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded,
                  color: KisakiColors.pink, size: 20),
              const SizedBox(width: 6),
              Text('最近游玩',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5)),
              const Spacer(),
              if (games.length > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => onSwitch(
                          (index - 1 + games.length) % games.length),
                    ),
                    Text('${i + 1} / ${games.length}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => onSwitch((index + 1) % games.length),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CoverImage(
                path: game.coverPath,
                nsfw: game.nsfw,
                width: 108,
                height: 162,
                borderRadius: BorderRadius.circular(14),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.25)),
                    const SizedBox(height: 8),
                    _heroMeta(context, '上次游玩',
                        game.lastPlayedAt == null ? '—' : fmtRelative(game.lastPlayedAt!)),
                    _heroMeta(context, '总时长', fmtDuration(game.totalSeconds)),
                    if (game.developer.isNotEmpty)
                      _heroMeta(context, '开发商', game.developer),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => onContinue(game),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(game.lastPlayedAt == null ? '开始游戏' : '继续游戏'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMeta(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ================= Timeline Card =================

class _TimelineCard extends StatelessWidget {
  final List<ActivityItem> activity;
  const _TimelineCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, color: KisakiColors.lavender, size: 20),
              const SizedBox(width: 6),
              Text('动态',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            ],
          ),
          const SizedBox(height: 14),
          if (activity.isEmpty)
            Expanded(
              child: Center(
                child: Text('暂无动态',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12.5)),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final a in activity.take(20))
                    _activityTile(context, a),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _activityTile(BuildContext context, ActivityItem a) {
    final (icon, color, text) = switch (a.type) {
      'added' => (
          Icons.add_circle_rounded,
          KisakiColors.lavender,
          '添加了游戏'
        ),
      'rated' => (
          Icons.star_rounded,
          const Color(0xFFF0B95E),
          a.detail.isEmpty ? '给出了评分' : '留下了评价'
        ),
      _ => (Icons.play_circle_rounded, KisakiColors.pink, '开始游玩'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CoverImage(
            path: a.coverPath,
            width: 34,
            height: 46,
            borderRadius: BorderRadius.circular(7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      WidgetSpan(
                        child: Icon(icon, size: 13, color: color),
                        alignment: PlaceholderAlignment.middle,
                      ),
                      TextSpan(text: ' $text '),
                      TextSpan(
                          text: a.gameName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Text(fmtRelative(a.at),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================= Recommendation Card =================

class _RecommendCard extends StatelessWidget {
  final List<ScrapedGame>? recommendations;
  final bool loading;
  final VoidCallback onRefresh;
  final List<TagItem> Function() libraryTopTags;

  const _RecommendCard({
    required this.recommendations,
    required this.loading,
    required this.onRefresh,
    required this.libraryTopTags,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tags = libraryTopTags();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: const Color(0xFF7EC8C3), size: 20),
              const SizedBox(width: 6),
              Text('为你推荐',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 20),
                onPressed: loading ? null : onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: dark
                          ? Colors.white.withValues(alpha: 0.06)
                          : KisakiColors.pinkContainer,
                    ),
                    child: Text('#${t.name}',
                        style: TextStyle(
                            fontSize: 11,
                            color: dark
                                ? KisakiColors.pinkSoft
                                : KisakiColors.pink,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          if (loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (recommendations == null)
            Expanded(
              child: Center(
                child: Text('根据库内标签推荐新游戏\n点击右上角刷新试试',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            )
          else if (recommendations!.isEmpty)
            Expanded(
              child: Center(
                child: Text('暂无推荐（网络不可用或标签太少）',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final g in recommendations!.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          CoverImage(
                            path: '',
                            networkUrl: g.coverUrl,
                            nsfw: g.nsfw,
                            width: 32,
                            height: 48,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                if (g.rating > 0)
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          size: 12, color: Color(0xFFF0B95E)),
                                      Text(
                                          ' ${g.rating.toStringAsFixed(1)} · ${KisakiSources.labels[g.source] ?? g.source}',
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ================= Quick Action =================

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: dark ? KisakiColors.nightCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: dark ? KisakiColors.nightInk : KisakiColors.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
