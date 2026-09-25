/// 统计页：信息 / 评分 / 总结三个子页 + 时段切换（本周/本月/今年/总计）。
///
/// 重构要点：
/// - 页面骨架走 [KPage]，子页切换用 [FadeThroughSwitcher]（不再用 TabBarView，
///   以便和 kit 的 chip 选择器统一观感）；
/// - 卡片全部走 [KCard]，数值走 [KStat]；图表高度固定，网格线/坐标轴颜色
///   取 `Theme.of(context).dividerColor` 与 colorScheme，不写死颜色。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart' show CoverImage, RatingBar;
import 'word_cloud.dart';

/// 图表区固定高度（切换时段时不跳动）。
const double _kChartHeight = 180;

/// 子页标识与图标。
const List<String> _kTabs = ['信息', '评分', '总结'];
const List<IconData> _kTabIcons = [
  Icons.insights_rounded,
  Icons.star_rounded,
  Icons.auto_stories_rounded,
];

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  int _tab = 0;
  StatsPeriod _period = StatsPeriod.month;

  @override
  Widget build(BuildContext context) {
    // 标题副文案随时段/数据实时变化（与子页共用同一个 provider 实例）
    final subtitle = ref.watch(statsProvider(_period)).maybeWhen(
          data: (s) =>
              '${_period.label} · ${fmtDuration(s.totalSeconds)} · ${s.sessionCount} 次游玩',
          orElse: () => _period.label,
        );

    return KPage(
      // 超宽屏下居中限宽，图表与卡片不被拉稀
      maxContentWidth: 1600,
      title: '统计',
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KToolbar(children: _toolbar()),
          Expanded(
            child: FadeThroughSwitcher(
              // 只按子页做转场：切换时段属于「同一页数据刷新」，
              // 保留滚动位置，数值由 AnimatedCount 平滑过渡。
              child: KeyedSubtree(
                key: ValueKey('tab-$_tab'),
                child: switch (_tab) {
                  0 => _InfoTab(period: _period),
                  1 => const _RatingsTab(),
                  _ => _SummaryTab(period: _period),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 工具栏：左侧子页切换，右侧时段切换（都用 KChip）。
  List<Widget> _toolbar() {
    return [
      for (var i = 0; i < _kTabs.length; i++) ...[
        if (i > 0) const SizedBox(width: Gap.xs + 2),
        KChip(
          label: _kTabs[i],
          icon: _kTabIcons[i],
          selected: _tab == i,
          onTap: () => setState(() => _tab = i),
        ),
      ],
      const Spacer(),
      for (var i = 0; i < StatsPeriod.values.length; i++) ...[
        if (i > 0) const SizedBox(width: Gap.xs + 2),
        KChip(
          label: StatsPeriod.values[i].label,
          selected: _period == StatsPeriod.values[i],
          onTap: () => setState(() => _period = StatsPeriod.values[i]),
        ),
      ],
    ];
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
      loading: () => const KLoading(),
      error: (e, _) => KEmpty(
        icon: Icons.error_outline_rounded,
        title: '统计加载失败',
        subtitle: '$e',
        actionLabel: '刷新',
        onAction: () => ref.invalidate(statsProvider(period)),
      ),
      data: (s) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 两张柱状图（等结构 = 等高，无需 IntrinsicHeight）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _ChartCard(
                    title: '游玩时段分布',
                    subtitle: '按小时累计',
                    child: _hourlyChart(context, s.byHour),
                  ),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  flex: 2,
                  child: _ChartCard(
                    title: '星期分布',
                    subtitle: '按星期累计',
                    child: _weekdayChart(context, s.byWeekday),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            _HeatmapCard(period: period, daily: s.daily, stats: s),
            const SizedBox(height: Gap.lg),
            _TopGamesCard(games: s.topGames),
          ],
        ),
      ),
    );
  }

  /// 时段分布：24 小时柱状，网格线取主题分隔色。
  Widget _hourlyChart(BuildContext context, List<int> byHour) {
    final scheme = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    final maxVal =
        byHour.isEmpty ? 0 : byHour.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 10.0 : maxVal * 1.2;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: divider, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 3,
              getTitlesWidget: (v, _) {
                final h = v.toInt();
                return Text(
                  h % 3 == 0 ? '$h' : '',
                  style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var h = 0; h < 24; h++)
            BarChartGroupData(x: h, barRods: [
              BarChartRodData(
                toY: (h < byHour.length ? byHour[h] : 0).toDouble(),
                width: 8,
                borderRadius: BorderRadius.circular(3),
                color: scheme.primary.withValues(alpha: 0.78),
              ),
            ]),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.surfaceContainerHigh,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '${group.x}:00 · ${fmtDuration(rod.toY.toInt())}',
              Type.micro.copyWith(color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  /// 星期分布：周一起（与仓储层口径一致）。
  Widget _weekdayChart(BuildContext context, List<int> byWeekday) {
    final scheme = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    final maxVal =
        byWeekday.isEmpty ? 0 : byWeekday.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 10.0 : maxVal * 1.2;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: divider, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (v, _) => Text(
                days[v.toInt() % 7],
                style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var d = 0; d < 7; d++)
            BarChartGroupData(x: d, barRods: [
              BarChartRodData(
                toY: (d < byWeekday.length ? byWeekday[d] : 0).toDouble(),
                width: 24,
                borderRadius: BorderRadius.circular(5),
                color: scheme.secondary.withValues(alpha: 0.82),
              ),
            ]),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.surfaceContainerHigh,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '周${days[group.x.toInt() % 7]} · ${fmtDuration(rod.toY.toInt())}',
              Type.micro.copyWith(color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// 图表卡：标题 + 说明 + 固定高度图表区。
class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _ChartCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KCard(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Type.section),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!,
                style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: Gap.md),
          SizedBox(height: _kChartHeight, child: child),
        ],
      ),
    );
  }
}

// ================= 月度热力 =================

/// 月度热力：按时段内每天的游玩时长着色（最多回看 26 周）。
class _HeatmapCard extends StatelessWidget {
  final StatsPeriod period;
  final List<DailyPoint> daily;
  final AggStats stats;

  const _HeatmapCard({
    required this.period,
    required this.daily,
    required this.stats,
  });

  /// 回看上限（周数），避免「总计」时段渲染上千个格子。
  static const int _maxWeeks = 26;

  /// 单元格尺寸与间距。
  static const double _cell = 13;
  static const double _gap = 3;

  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayMonday =
        DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: today.weekday - 1));
    final byDate = <String, int>{for (final d in daily) d.date: d.seconds};

    // 起点：时段起点对齐到周一，最多回看 _maxWeeks 周（列数按起点反推，
    // 保证最后一列一定是「本周」，今天不会被挤出图外）
    var first = _periodStart(period, today);
    first = first.subtract(Duration(days: first.weekday - 1));
    final earliest = todayMonday.subtract(const Duration(days: (_maxWeeks - 1) * 7));
    if (first.isBefore(earliest)) first = earliest;
    final weeks = todayMonday.difference(first).inDays ~/ 7 + 1;

    final maxSeconds =
        byDate.values.isEmpty ? 0 : byDate.values.reduce((a, b) => a > b ? a : b);

    // 最活跃的一天
    String bestDayText = '—';
    if (byDate.isNotEmpty) {
      final best = byDate.entries.reduce((a, b) => a.value >= b.value ? a : b);
      bestDayText = '${best.key.substring(5)} · ${fmtDuration(best.value)}';
    }
    // 到今天为止的连续记录天数
    var streak = 0;
    for (var i = 0; i < 400; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      if ((byDate[fmtDate(d)] ?? 0) > 0) {
        streak++;
      } else {
        break;
      }
    }

    return KCard(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KSectionTitle(
            '月度热力',
            padding: EdgeInsets.zero,
            trailing: KBadge(
              text: '${fmtDate(first)} ~ ${fmtDate(today)}',
              color: scheme.secondary,
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 星期标签列
                      Column(
                        children: [
                          for (var w = 0; w < 7; w++)
                            Padding(
                              padding: EdgeInsets.only(
                                  bottom: w == 6 ? 0 : _gap),
                              child: SizedBox(
                                height: _cell,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    _weekdays[w],
                                    style: Type.micro.copyWith(
                                        height: 1.0,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: Gap.sm),
                      for (var wk = 0; wk < weeks; wk++) ...[
                        if (wk > 0) const SizedBox(width: _gap),
                        Column(
                          children: [
                            for (var w = 0; w < 7; w++)
                              Padding(
                                padding: EdgeInsets.only(
                                    bottom: w == 6 ? 0 : _gap),
                                child: _cellBox(
                                  context: context,
                                  date: DateTime(first.year, first.month,
                                      first.day + wk * 7 + w),
                                  today: today,
                                  byDate: byDate,
                                  maxSeconds: maxSeconds,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  _legend(context),
                ],
              ),
              const SizedBox(width: Gap.xxl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fact(context, '最活跃的一天', bestDayText),
                    const SizedBox(height: Gap.md),
                    _fact(context, '单日峰值', fmtDuration(maxSeconds)),
                    const SizedBox(height: Gap.md),
                    _fact(context, '连续记录', streak == 0 ? '—' : '$streak 天'),
                    const SizedBox(height: Gap.md),
                    _fact(context, '本时段活跃', '${stats.activeDays} 天'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 单个热力格（今天之后的位置留空占位）。
  Widget _cellBox({
    required BuildContext context,
    required DateTime date,
    required DateTime today,
    required Map<String, int> byDate,
    required int maxSeconds,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (date.isAfter(DateTime(today.year, today.month, today.day))) {
      return const SizedBox(width: _cell, height: _cell);
    }
    final seconds = byDate[fmtDate(date)] ?? 0;
    final color = _levelColor(seconds, maxSeconds, scheme, dark);
    return Tooltip(
      message: '${fmtDate(date)} · ${seconds <= 0 ? '未游玩' : fmtDuration(seconds)}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: ColoredBox(
          color: color,
          child: const SizedBox(width: _cell, height: _cell),
        ),
      ),
    );
  }

  /// 四档热度色：无记录 = 底色，其余按占比取主色 alpha。
  Color _levelColor(
      int seconds, int maxSeconds, ColorScheme scheme, bool dark) {
    if (seconds <= 0 || maxSeconds <= 0) return scheme.surfaceContainerHighest;
    final level = (seconds / maxSeconds * 4).ceil().clamp(1, 4);
    final alpha = const [0.30, 0.50, 0.70, 0.95][level - 1];
    return scheme.primary.withValues(alpha: alpha);
  }

  Widget _legend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('少',
            style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(width: Gap.xs + 2),
        for (var i = 0; i <= 4; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: ColoredBox(
              color: _levelColor(i * 600, 2400, scheme, dark),
              child: const SizedBox(width: _cell, height: _cell),
            ),
          ),
        ],
        const SizedBox(width: Gap.xs + 2),
        Text('多',
            style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 3),
        AnimatedCount(text: value, style: Type.numeric.copyWith(fontSize: 15)),
      ],
    );
  }
}

// ================= Top 游戏 =================

/// 游戏时长 Top 10：名次 + 进度条 + 时长，点击进详情。
class _TopGamesCard extends StatelessWidget {
  final List<TopGame> games;
  const _TopGamesCard({required this.games});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KCard(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KSectionTitle(
            '游戏时长 Top 10',
            padding: EdgeInsets.zero,
            trailing: KBadge(
              text: '${games.length} 部',
              icon: Icons.sports_esports_rounded,
              color: scheme.secondary,
            ),
          ),
          const SizedBox(height: Gap.md),
          if (games.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.xl),
              child: KEmpty(
                icon: Icons.bar_chart_rounded,
                title: '暂无数据',
                subtitle: '这个时段还没有游玩记录',
              ),
            )
          else
            ...[
              for (var i = 0; i < games.length; i++)
                _TopGameRow(
                  rank: i + 1,
                  game: games[i],
                  maxSeconds: games.first.seconds,
                ),
              const SizedBox(height: Gap.xs),
            ],
        ],
      ),
    );
  }
}

class _TopGameRow extends StatelessWidget {
  final int rank;
  final TopGame game;
  final int maxSeconds;

  const _TopGameRow({
    required this.rank,
    required this.game,
    required this.maxSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rankColor = switch (rank) {
      1 => KisakiColors.star,
      2 => scheme.secondary,
      3 => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
    final openable = game.gameId > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: InteractiveSurface(
        onTap: openable
            ? () => Navigator.of(context).push(FadeThroughRoute.builder(
                builder: (_) => GameDetailPage(gameId: game.gameId)))
            : null,
        borderRadius: BorderRadius.circular(Radii.md),
        color: Colors.transparent,
        outline: scheme.primary,
        borderOnIdle: false,
        elevated: false,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: rank <= 3
                  ? rankColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              child: Text(
                '$rank',
                style: Type.micro
                    .copyWith(color: rankColor, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        Type.body.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                  ),
                  const SizedBox(height: Gap.xs + 1),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    child: LinearProgressIndicator(
                      value: maxSeconds == 0 ? 0 : game.seconds / maxSeconds,
                      minHeight: 5,
                      backgroundColor:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.md),
            AnimatedCount(
              text: fmtDuration(game.seconds),
              style: Type.label.copyWith(color: scheme.onSurfaceVariant),
            ),
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
    final scheme = Theme.of(context).colorScheme;
    final rated0 = ref.watch(ratedGamesProvider);
    return rated0.when(
      loading: () => const KLoading(),
      error: (e, _) => KEmpty(
        icon: Icons.error_outline_rounded,
        title: '评分加载失败',
        subtitle: '$e',
        actionLabel: '刷新',
        onAction: () => ref.invalidate(ratedGamesProvider),
      ),
      data: (list) {
        final rated = list.toList()
          ..sort((a, b) => b.userRating.compareTo(a.userRating));
        if (rated.isEmpty) {
          return KEmpty(
            icon: Icons.star_border_rounded,
            title: '还没有评分',
            subtitle: '到游戏详情页为喜欢的作品打分吧',
            actionLabel: '刷新',
            onAction: () => ref.invalidate(ratedGamesProvider),
          );
        }
        final avg = rated.map((g) => g.userRating).reduce((a, b) => a + b) /
            rated.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KSectionTitle(
              '评分墙',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KBadge(
                    text: '${rated.length} 部',
                    icon: Icons.star_rounded,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: Gap.sm),
                  KBadge(
                    text: '均分 ${avg.toStringAsFixed(1)}',
                    color: scheme.secondary,
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView(
                padding: const EdgeInsets.only(bottom: Gap.xl),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 380,
                  mainAxisSpacing: Gap.md,
                  crossAxisSpacing: Gap.md,
                  // 固定行高（而不是宽高比）：窗口变窄时行高不缩水，
                  // 52×72 封面 + 内边距始终装得下，不会撑破卡片
                  mainAxisExtent: 98,
                ),
                children: [
                  for (final g in rated) _RatingTile(game: g),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 评分卡：封面 + 名称 + 短评/星条 + 分数，点击进详情。
class _RatingTile extends StatelessWidget {
  final Game game;
  const _RatingTile({required this.game});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = game.id;
    return KCard(
      padding: const EdgeInsets.all(Gap.sm + 2),
      onTap: id == null
          ? null
          : () => Navigator.of(context).push(FadeThroughRoute.builder(
                builder: (_) => GameDetailPage(gameId: id, initial: game),
              )),
      child: Row(
        children: [
          CoverImage(
            path: game.coverPath,
            nsfw: game.nsfw,
            width: 52,
            height: 72,
            borderRadius: BorderRadius.circular(Radii.sm - 1),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  game.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Gap.xs),
                if (game.userReview.isNotEmpty)
                  Text(
                    game.userReview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                  )
                else
                  RatingBar(value: game.userRating, size: 15),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedCount(
                text: game.userRating.toStringAsFixed(0),
                style: Type.display.copyWith(fontSize: 22, color: scheme.primary),
              ),
              Text(
                '满分 10 · ${game.userRating ~/ 2}/5 星',
                style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
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
    final scheme = Theme.of(context).colorScheme;
    final cloud = ref.watch(tagCloudProvider(period));
    final stats = ref.watch(statsProvider(period));

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 四个关键数值（数值走 KStat → 内部 AnimatedCount）
          stats.when(
            loading: () => const SizedBox(height: 88, child: KLoading()),
            error: (e, _) => KEmpty(
              icon: Icons.error_outline_rounded,
              title: '统计加载失败',
              subtitle: '$e',
              actionLabel: '刷新',
              onAction: () => ref.invalidate(statsProvider(period)),
            ),
            data: (s) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: KStat(
                    icon: Icons.schedule_rounded,
                    label: '总游玩时长',
                    value: fmtDuration(s.totalSeconds),
                    hint: '${period.label}累计',
                    accent: scheme.primary,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: KStat(
                    icon: Icons.sports_esports_rounded,
                    label: '游玩次数',
                    value: '${s.sessionCount} 次',
                    hint: '平均每次 ${_avgPerSession(s)}',
                    accent: scheme.secondary,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: KStat(
                    icon: Icons.event_available_rounded,
                    label: '活跃天数',
                    value: '${s.activeDays} 天',
                    hint: '日均 ${s.activeDays == 0 ? '—' : fmtDuration(s.avgPerActiveDay)}',
                    accent: scheme.tertiary,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: KStat(
                    icon: Icons.today_rounded,
                    label: '日均时长',
                    value:
                        s.activeDays == 0 ? '—' : fmtDuration(s.avgPerActiveDay),
                    hint: '按活跃天数折算',
                    accent: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          // 标签词云
          KCard(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KSectionTitle(
                  '标签词云',
                  padding: EdgeInsets.zero,
                  trailing: KBadge(text: period.label, color: scheme.secondary),
                ),
                const SizedBox(height: Gap.md),
                cloud.when(
                  loading: () =>
                      const SizedBox(height: 200, child: KLoading()),
                  error: (e, _) => SizedBox(
                    height: 160,
                    child: KEmpty(
                      icon: Icons.cloud_off_rounded,
                      title: '词云加载失败',
                      subtitle: '$e',
                    ),
                  ),
                  data: (tags) => tags.isEmpty
                      ? const SizedBox(
                          height: 160,
                          child: KEmpty(
                            icon: Icons.cloud_off_rounded,
                            title: '还没有足够的数据',
                            subtitle: '先去玩一会儿游戏，再来生成词云吧',
                          ),
                        )
                      : WordCloud(tags: tags),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          // 文字总结
          KCard(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KSectionTitle(
                  '${period.label}总结',
                  padding: EdgeInsets.zero,
                  trailing:
                      KBadge(text: period.label, icon: Icons.auto_stories_rounded),
                ),
                const SizedBox(height: Gap.md),
                stats.when(
                  loading: () => Text('…', style: Type.body),
                  error: (e, _) => Text('$e', style: Type.body),
                  data: (s) => AnimatedCount(
                    // 词云标签直接复用 provider 结果，避免重复查询与闪烁
                    text: _buildSummary(
                      period,
                      s,
                      cloud.valueOrNull ?? const <TagItem>[],
                    ),
                    style: Type.body.copyWith(height: 1.8),
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

/// 平均每次时长（无会话时给「—」）。
String _avgPerSession(AggStats s) => s.sessionCount == 0
    ? '—'
    : fmtDuration(s.totalSeconds ~/ s.sessionCount);

/// 时段起点（与仓储层 stats() 的口径一致：本周从周一起算）。
DateTime _periodStart(StatsPeriod period, DateTime now) => switch (period) {
      StatsPeriod.week => now.subtract(Duration(days: now.weekday - 1)),
      StatsPeriod.month => DateTime(now.year, now.month, 1),
      StatsPeriod.year => DateTime(now.year, 1, 1),
      StatsPeriod.all => DateTime(2000),
    };

/// 总结文案（措辞与旧版逐字一致，仅把词云查询换成 provider 已取到的标签）。
String _buildSummary(StatsPeriod period, AggStats s, List<TagItem> tags) {
  if (s.totalSeconds == 0) {
    return '这个${period.label}还没有游玩记录，打开一部作品开始新的故事吧。';
  }
  final topTags = tags.take(4).map((t) => t.name).toList();
  final topGame = s.topGames.isEmpty ? '' : s.topGames.first.name;
  final durText = fmtDuration(s.totalSeconds);
  final avg = fmtDuration(
      s.avgPerActiveDay ~/ (s.sessionCount == 0 ? 1 : s.sessionCount));
  final tagText = topTags.isEmpty ? '' : '，最吸引你的关键词是「${topTags.join('」「')}」';
  final gameText = topGame.isEmpty ? '' : '，投入最多的作品是《$topGame》';
  return '这个${period.label}你游玩了 $durText，分布在 ${s.activeDays} 天、共 ${s.sessionCount} 次，'
      '平均每次 $avg'
      '$gameText$tagText。'
      '${s.activeDays >= 5 ? '保持这样细腻的节奏，故事会一直陪着你。' : '偶尔也要记得休息，故事不会跑。'}';
}
