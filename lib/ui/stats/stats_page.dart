/// 统计页：信息 / 评分 / 总结 三个子 Tab。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../detail/game_detail_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'word_cloud.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  StatsPeriod _period = StatsPeriod.month;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('统计',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              SegmentedButton<StatsPeriod>(
                showSelectedIcon: false,
                segments: [
                  for (final p in StatsPeriod.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_period},
                onSelectionChanged: (s) =>
                    setState(() => _period = s.first),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: '信息'),
              Tab(text: '评分'),
              Tab(text: '总结'),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _InfoTab(period: _period),
                const _RatingsTab(),
                _SummaryTab(period: _period),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================= 信息页 =================

class _InfoTab extends ConsumerWidget {
  final StatsPeriod period;
  const _InfoTab({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider(period));
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (s) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          children: [
            Row(
              children: [
                _numCard(context, '总游玩时长', fmtDuration(s.totalSeconds),
                    Icons.schedule_rounded, KisakiColors.pink),
                _numCard(context, '活跃天数', '${s.activeDays} 天',
                    Icons.event_available_rounded, KisakiColors.lavender),
                _numCard(
                    context,
                    '日均时长',
                    s.activeDays == 0 ? '—' : fmtDuration(s.avgPerActiveDay),
                    Icons.today_rounded,
                    const Color(0xFF7EC8C3)),
                _numCard(context, '游玩次数', '${s.sessionCount} 次',
                    Icons.sports_esports_rounded, const Color(0xFFF0B95E)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('游玩时段分布',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 18),
                        SizedBox(
                            height: 190, child: _hourlyChart(context, s.byHour)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('星期分布',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 18),
                        SizedBox(
                            height: 190,
                            child: _weekdayChart(context, s.byWeekday)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('游戏时长 Top 10',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (s.topGames.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                          child: Text('暂无数据',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant))),
                    )
                  else
                    ...s.topGames.asMap().entries.map((e) =>
                        _topGameTile(context, ref, e.key + 1, e.value,
                            s.topGames.first.seconds)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numCard(BuildContext context, String label, String value,
      IconData icon, Color color) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink)),
          ],
        ),
      ),
    );
  }

  Widget _hourlyChart(BuildContext context, List<int> byHour) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final maxVal = byHour.reduce((a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal == 0 ? 10 : maxVal * 1.2,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 3,
              getTitlesWidget: (v, _) => Text(
                  v.toInt() % 3 == 0 ? '${v.toInt()}' : '',
                  style: TextStyle(
                      fontSize: 9.5,
                      color: dark
                          ? KisakiColors.nightInkSoft
                          : KisakiColors.inkSoft)),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var h = 0; h < 24; h++)
            BarChartGroupData(x: h, barRods: [
              BarChartRodData(
                toY: byHour[h].toDouble(),
                width: 9,
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      KisakiColors.pink.withValues(alpha: 0.55),
                      KisakiColors.lavender,
                    ]),
              ),
            ]),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${group.x}:00 · ${fmtDuration(rod.toY.toInt())}',
                TextStyle(
                    fontSize: 10.5,
                    color: dark ? Colors.white : Colors.black)),
          ),
        ),
      ),
    );
  }

  Widget _weekdayChart(BuildContext context, List<int> byWeekday) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    final maxVal = byWeekday.reduce((a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal == 0 ? 10 : maxVal * 1.2,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) => Text(days[v.toInt() % 7],
                  style: TextStyle(
                      fontSize: 10,
                      color: dark
                          ? KisakiColors.nightInkSoft
                          : KisakiColors.inkSoft)),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var d = 0; d < 7; d++)
            BarChartGroupData(x: d, barRods: [
              BarChartRodData(
                toY: byWeekday[d].toDouble(),
                width: 22,
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      KisakiColors.lavender.withValues(alpha: 0.5),
                      KisakiColors.pink,
                    ]),
              ),
            ]),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '周${days[group.x.toInt() % 7]} · ${fmtDuration(rod.toY.toInt())}',
                TextStyle(
                    fontSize: 10.5,
                    color: dark ? Colors.white : Colors.black)),
          ),
        ),
      ),
    );
  }

  Widget _topGameTile(BuildContext context, WidgetRef ref, int rank,
      TopGame g, int maxSeconds) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rankColor = rank <= 3
        ? [const Color(0xFFF0B95E), const Color(0xFFB9C0CB), const Color(0xFFCE9166)][rank - 1]
        : (dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft);
    return InkWell(
      onTap: g.gameId > 0
          ? () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GameDetailPage(gameId: g.gameId)))
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rank <= 3
                    ? rankColor.withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
              child: Text('$rank',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: rankColor)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxSeconds == 0 ? 0 : g.seconds / maxSeconds,
                      minHeight: 5,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      color: KisakiColors.pink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(fmtDuration(g.seconds),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ================= 评分页 =================

class _RatingsTab extends ConsumerWidget {
  const _RatingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(gamesProvider);
    return games.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        final rated = list.where((g) => g.userRating > 0).toList()
          ..sort((a, b) => b.userRating.compareTo(a.userRating));
        if (rated.isEmpty) {
          return const EmptyState(
              title: '还没有评分',
              subtitle: '到游戏详情页为喜欢的作品打分吧');
        }
        return GridView(
          padding: const EdgeInsets.only(bottom: 20, top: 4),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 380,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.6,
          ),
          children: [
            for (final g in rated) _RatingTile(game: g),
          ],
        );
      },
    );
  }
}

class _RatingTile extends StatelessWidget {
  final Game game;
  const _RatingTile({required this.game});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GameDetailPage(gameId: game.id!))),
      child: Row(
        children: [
          CoverImage(
            path: game.coverPath,
            nsfw: game.nsfw,
            width: 52,
            height: 72,
            borderRadius: BorderRadius.circular(9),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(game.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                if (game.userReview.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(game.userReview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ] else ...[
                  const SizedBox(height: 4),
                  RatingBar(value: game.userRating, size: 16),
                ],
              ],
            ),
          ),
          Text(game.userRating.toStringAsFixed(0),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

// ================= 总结页 =================

class _SummaryTab extends ConsumerWidget {
  final StatsPeriod period;
  const _SummaryTab({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloud = ref.watch(tagCloudProvider(period));
    final stats = ref.watch(statsProvider(period));
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_rounded,
                        size: 20, color: KisakiColors.lavender),
                    const SizedBox(width: 6),
                    Text('标签词云 · ${period.label}',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 14),
                cloud.when(
                  loading: () => const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('$e'),
                  data: (tags) => tags.isEmpty
                      ? SizedBox(
                          height: 160,
                          child: Center(
                              child: Text('先去玩一会儿游戏再来生成词云吧',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant))),
                        )
                      : WordCloud(tags: tags),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          stats.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (s) => SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_stories_rounded,
                          size: 20, color: KisakiColors.pink),
                      const SizedBox(width: 6),
                      Text('${period.label}总结',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<String>(
                    future: _buildSummary(s),
                    builder: (context, snap) => Text(
                      snap.data ?? '…',
                      style: const TextStyle(height: 1.8, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _buildSummary(AggStats s) async {
    if (s.totalSeconds == 0) return '这个${period.label == '本周' ? '周' : '时段'}还没有游玩记录，打开一部作品开始新的故事吧。';
    final tags = await AppServices.I.repo.tagCloud(period: period);
    final topTags = tags.take(4).map((t) => t.name).toList();
    final topGame = s.topGames.isEmpty ? '' : s.topGames.first.name;
    final hours = (s.totalSeconds / 3600).toStringAsFixed(1);
    final tagText =
        topTags.isEmpty ? '' : '，最吸引你的关键词是「${topTags.join('」「')}」';
    final gameText =
        topGame.isEmpty ? '' : '，投入最多的作品是《$topGame》';
    return '这个$hours 小时的${period.label}里，你在 ${s.activeDays} 天里游玩了 ${s.sessionCount} 次，'
        '平均每次 ${fmtDuration(s.avgPerActiveDay ~/ (s.sessionCount == 0 ? 1 : s.sessionCount))}'
        '$gameText$tagText。'
        '${s.activeDays >= 5 ? '保持这样细腻的节奏，故事会一直陪着你。' : '偶尔也要记得休息，故事不会跑。'}';
  }
}
