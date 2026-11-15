/// Fluent 2 游玩统计页：时段切换、KPI 概览、fl_chart 图表、月度热力、词云与评分墙。
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_surfaces.dart';
import '../library/game_actions.dart';
import 'word_cloud.dart';

const double _kChartHeight = 188;

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  final _scrollCtrl = ScrollController();
  StatsPeriod _period = StatsPeriod.month;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ensureFluentScope(
      context,
      Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final theme = FluentTheme.of(context);
    final statsAsync = ref.watch(statsProvider(_period));
    final cloudAsync = ref.watch(tagCloudProvider(_period));
    final ratedAsync = ref.watch(ratedGamesProvider);

    final subtitle = statsAsync.maybeWhen(
      skipLoadingOnReload: true,
      data: (s) =>
          '${_period.label} · ${fmtDuration(s.totalSeconds)} · ${s.sessionCount} 次游玩',
      orElse: () => '${_period.label}数据',
    );

    return ScaffoldPage(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('游玩统计', style: theme.typography.titleLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < StatsPeriod.values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  ToggleButton(
                    checked: _period == StatsPeriod.values[i],
                    onChanged: (_) =>
                        setState(() => _period = StatsPeriod.values[i]),
                    child: Text(StatsPeriod.values[i].label),
                  ),
                ],
                const SizedBox(width: 10),
                Button(
                  onPressed: () {
                    ref.invalidate(statsProvider(_period));
                    ref.invalidate(tagCloudProvider(_period));
                    ref.invalidate(ratedGamesProvider);
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.arrow_clockwise_16_regular, size: 15),
                      SizedBox(width: 6),
                      Text('刷新'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      content: statsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => FluentEmptyState(
          icon: FluentIcons.error_circle_24_regular,
          title: '统计加载失败',
          message: '$e',
          action: FilledButton(
            onPressed: () => ref.invalidate(statsProvider(_period)),
            child: const Text('重试'),
          ),
        ),
        data: (stats) => _buildContent(
          context,
          stats,
          cloudAsync,
          ratedAsync,
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AggStats stats,
    AsyncValue<List<TagItem>> cloudAsync,
    AsyncValue<List<Game>> ratedAsync,
  ) {
    final disableAnim = fluentAnimationsDisabled(context);
    final tags = cloudAsync.valueOrNull ?? const <TagItem>[];

    return SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KpiGrid(period: _period, stats: stats)
              .fluentEntrance(index: 0, disable: disableAnim),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final hourlyCard = _ChartCard(
                title: '游玩时段分布',
                subtitle: '按小时累计',
                child: _HourlyBarChart(byHour: stats.byHour),
              );
              final weekdayCard = _ChartCard(
                title: '星期分布',
                subtitle: '按星期一至日累计',
                child: _WeekdayBarChart(byWeekday: stats.byWeekday),
              );
              if (constraints.maxWidth >= 780) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: hourlyCard),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: weekdayCard),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hourlyCard,
                  const SizedBox(height: 14),
                  weekdayCard,
                ],
              );
            },
          ).fluentEntrance(index: 1, disable: disableAnim),
          const SizedBox(height: 16),
          _ChartCard(
            title: '每日游玩趋势',
            subtitle: '近期活跃天数走势',
            child: _DailyTrendChart(daily: stats.daily),
          ).fluentEntrance(index: 2, disable: disableAnim),
          const SizedBox(height: 16),
          _HeatmapCard(period: _period, daily: stats.daily, stats: stats)
              .fluentEntrance(index: 3, disable: disableAnim),
          const SizedBox(height: 16),
          _TagCloudSection(
            period: _period,
            cloudAsync: cloudAsync,
            onTagTap: (t) => jumpToLibraryFiltered(ref, tag: t.name),
          ).fluentEntrance(index: 4, disable: disableAnim),
          const SizedBox(height: 16),
          _PeriodSummaryCard(
            period: _period,
            stats: stats,
            tags: tags,
          ).fluentEntrance(index: 5, disable: disableAnim),
          const SizedBox(height: 16),
          _TopGamesCard(
            games: stats.topGames,
            onOpenGame: (id) => openGameDetail(context, id, ref: ref),
          ),
          const SizedBox(height: 16),
          _RatedGamesSection(
            ratedAsync: ratedAsync,
            onOpenGame: (g) => openGameDetail(
              context,
              g.id!,
              initial: g,
              ref: ref,
            ),
            onRetry: () => ref.invalidate(ratedGamesProvider),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final StatsPeriod period;
  final AggStats stats;

  const _KpiGrid({required this.period, required this.stats});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatsKpiCard(
        icon: FluentIcons.clock_20_regular,
        label: '总游玩时长',
        value: fmtDuration(stats.totalSeconds),
        hint: '${period.label}累计',
      ),
      _StatsKpiCard(
        icon: FluentIcons.games_24_regular,
        label: '游玩次数',
        value: '${stats.sessionCount} 次',
        hint: '平均每次 ${_avgPerSession(stats)}',
      ),
      _StatsKpiCard(
        icon: FluentIcons.calendar_20_regular,
        label: '活跃天数',
        value: '${stats.activeDays} 天',
        hint:
            '日均 ${stats.activeDays == 0 ? '—' : fmtDuration(stats.avgPerActiveDay)}',
      ),
      _StatsKpiCard(
        icon: FluentIcons.history_20_regular,
        label: '日均时长',
        value: stats.activeDays == 0
            ? '—'
            : fmtDuration(stats.avgPerActiveDay),
        hint: '按活跃天数折算',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
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

class _StatsKpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String hint;

  const _StatsKpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return FluentSurfaceCard(
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
                    color: theme.inactiveColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.typography.subtitle),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(height: _kChartHeight, child: child),
        ],
      ),
    );
  }
}

class _HourlyBarChart extends StatelessWidget {
  final List<int> byHour;

  const _HourlyBarChart({required this.byHour});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final gridColor = theme.resources.cardStrokeColorDefault;
    final captionStyle = (theme.typography.caption ?? const TextStyle())
        .copyWith(color: theme.inactiveColor);
    final tooltipTextStyle = (theme.typography.caption ?? const TextStyle())
        .copyWith(
      color: theme.typography.bodyStrong?.color ?? theme.inactiveColor,
      fontWeight: FontWeight.w600,
    );

    final maxVal =
        byHour.isEmpty ? 0 : byHour.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 60.0 : maxVal * 1.2;
    final interval = math.max(1.0, maxY / 3);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 0.8),
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
              reservedSize: 22,
              interval: 3,
              getTitlesWidget: (v, _) {
                final h = v.toInt();
                return Text(h % 3 == 0 ? '$h' : '', style: captionStyle);
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var h = 0; h < 24; h++)
            BarChartGroupData(
              x: h,
              barRods: [
                BarChartRodData(
                  toY: (h < byHour.length ? byHour[h] : 0).toDouble(),
                  width: 8,
                  borderRadius: BorderRadius.circular(3),
                  color: accent.withValues(alpha: 0.82),
                ),
              ],
            ),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 6,
            tooltipBorder: BorderSide(color: gridColor),
            getTooltipColor: (_) => theme.cardColor,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '${group.x}:00 · ${fmtDuration(rod.toY.round())}',
              tooltipTextStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayBarChart extends StatelessWidget {
  final List<int> byWeekday;

  const _WeekdayBarChart({required this.byWeekday});

  static const _days = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barColor =
        isDark ? theme.accentColor.light : theme.accentColor.dark;
    final gridColor = theme.resources.cardStrokeColorDefault;
    final captionStyle = (theme.typography.caption ?? const TextStyle())
        .copyWith(color: theme.inactiveColor);
    final tooltipTextStyle = (theme.typography.caption ?? const TextStyle())
        .copyWith(
      color: theme.typography.bodyStrong?.color ?? theme.inactiveColor,
      fontWeight: FontWeight.w600,
    );

    final maxVal =
        byWeekday.isEmpty ? 0 : byWeekday.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 60.0 : maxVal * 1.2;
    final interval = math.max(1.0, maxY / 3);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 0.8),
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
              reservedSize: 22,
              getTitlesWidget: (v, _) =>
                  Text(_days[v.toInt() % 7], style: captionStyle),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var d = 0; d < 7; d++)
            BarChartGroupData(
              x: d,
              barRods: [
                BarChartRodData(
                  toY: (d < byWeekday.length ? byWeekday[d] : 0).toDouble(),
                  width: 22,
                  borderRadius: BorderRadius.circular(5),
                  color: barColor.withValues(alpha: 0.85),
                ),
              ],
            ),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 6,
            tooltipBorder: BorderSide(color: gridColor),
            getTooltipColor: (_) => theme.cardColor,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '周${_days[group.x.toInt() % 7]} · ${fmtDuration(rod.toY.round())}',
              tooltipTextStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyTrendChart extends StatelessWidget {
  final List<DailyPoint> daily;

  const _DailyTrendChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final gridColor = theme.resources.cardStrokeColorDefault;
    final captionStyle = (theme.typography.caption ?? const TextStyle())
        .copyWith(color: theme.inactiveColor);
    final tooltipTextStyle = (theme.typography.caption ?? const TextStyle())
        .copyWith(
      color: theme.typography.bodyStrong?.color ?? theme.inactiveColor,
      fontWeight: FontWeight.w600,
    );

    final ordered = [...daily]..sort((a, b) => a.date.compareTo(b.date));
    final recent = ordered.length > 30
        ? ordered.sublist(ordered.length - 30)
        : ordered;

    if (recent.isEmpty) {
      return Center(
        child: Text(
          '当前时段暂无趋势数据',
          style: captionStyle,
        ),
      );
    }

    final spots = [
      for (var i = 0; i < recent.length; i++)
        FlSpot(i.toDouble(), recent[i].seconds / 60.0),
    ];
    final maxMinutes = recent
        .map((p) => p.seconds / 60.0)
        .fold<double>(0.0, (a, b) => a > b ? a : b);
    final maxY = maxMinutes <= 0 ? 60.0 : maxMinutes * 1.25;
    final maxX = recent.length <= 1 ? 1.0 : (recent.length - 1).toDouble();
    final yInterval = math.max(1.0, maxY / 3);
    final xStep = math.max(1, (recent.length / 6).ceil());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(show: false),
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
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= recent.length || idx % xStep != 0) {
                  return const SizedBox.shrink();
                }
                final label = recent[idx].date.length >= 10
                    ? recent[idx].date.substring(5)
                    : recent[idx].date;
                return Text(label, style: captionStyle);
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 6,
            tooltipBorder: BorderSide(color: gridColor),
            getTooltipColor: (_) => theme.cardColor,
            getTooltipItems: (touched) {
              return touched.map((spot) {
                final idx = spot.x.round().clamp(0, recent.length - 1);
                final pt = recent[idx];
                return LineTooltipItem(
                  '${pt.date}\n${fmtDuration(pt.seconds)}',
                  tooltipTextStyle,
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: recent.length > 2,
            preventCurveOverShooting: true,
            color: accent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: recent.length <= 12),
            belowBarData: BarAreaData(
              show: true,
              color: accent.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  final StatsPeriod period;
  final List<DailyPoint> daily;
  final AggStats stats;

  const _HeatmapCard({
    required this.period,
    required this.daily,
    required this.stats,
  });

  static const int _maxWeeks = 26;
  static const double _cell = 13;
  static const double _gap = 3;
  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final emptyCellColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final todayMonday =
        todayDay.subtract(Duration(days: today.weekday - 1));
    final byDate = <String, int>{for (final d in daily) d.date: d.seconds};

    var first = _periodStart(period, today);
    first = first.subtract(Duration(days: first.weekday - 1));
    final earliest =
        todayMonday.subtract(const Duration(days: (_maxWeeks - 1) * 7));
    if (first.isBefore(earliest)) first = earliest;
    final weeks = todayMonday.difference(first).inDays ~/ 7 + 1;

    final maxSeconds = byDate.values.isEmpty
        ? 0
        : byDate.values.reduce((a, b) => a > b ? a : b);

    var bestDayText = '—';
    if (byDate.isNotEmpty) {
      final best =
          byDate.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final shortDate =
          best.key.length >= 6 ? best.key.substring(5) : best.key;
      bestDayText = '$shortDate · ${fmtDuration(best.value)}';
    }

    var streak = 0;
    for (var i = 0; i < 400; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      if ((byDate[fmtDate(d)] ?? 0) > 0) {
        streak++;
      } else {
        break;
      }
    }

    Color levelColor(int seconds) {
      if (seconds <= 0 || maxSeconds <= 0) return emptyCellColor;
      final level = (seconds / maxSeconds * 4).ceil().clamp(1, 4);
      final alpha = const [0.30, 0.50, 0.72, 0.95][level - 1];
      return accent.withValues(alpha: alpha);
    }

    final grid = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (var w = 0; w < 7; w++)
                    Padding(
                      padding: EdgeInsets.only(bottom: w == 6 ? 0 : _gap),
                      child: SizedBox(
                        height: _cell,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _weekdays[w],
                            style: theme.typography.caption?.copyWith(
                              fontSize: 11,
                              height: 1.0,
                              color: theme.inactiveColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              for (var wk = 0; wk < weeks; wk++) ...[
                if (wk > 0) const SizedBox(width: _gap),
                Column(
                  children: [
                    for (var w = 0; w < 7; w++)
                      Padding(
                        padding: EdgeInsets.only(bottom: w == 6 ? 0 : _gap),
                        child: _buildCell(
                          date: DateTime(
                              first.year, first.month, first.day + wk * 7 + w),
                          todayDay: todayDay,
                          byDate: byDate,
                          colorFor: levelColor,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '少',
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
              const SizedBox(width: 6),
              for (var i = 0; i <= 4; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: ColoredBox(
                    color: i == 0
                        ? emptyCellColor
                        : accent.withValues(
                            alpha: const [0.30, 0.50, 0.72, 0.95][i - 1],
                          ),
                    child: const SizedBox(width: _cell, height: _cell),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Text(
                '多',
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final facts = Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _FactItem(label: '最活跃的一天', value: bestDayText),
        _FactItem(label: '单日峰值', value: fmtDuration(maxSeconds)),
        _FactItem(label: '连续记录', value: streak == 0 ? '—' : '$streak 天'),
        _FactItem(label: '本时段活跃', value: '${stats.activeDays} 天'),
      ],
    );

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            icon: FluentIcons.calendar_week_numbers_20_regular,
            title: '月度热力',
            trailing: FluentBadge(
              text: '${fmtDate(first)} ~ ${fmtDate(today)}',
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(flex: 3, child: grid),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: facts),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  grid,
                  const SizedBox(height: 14),
                  facts,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCell({
    required DateTime date,
    required DateTime todayDay,
    required Map<String, int> byDate,
    required Color Function(int seconds) colorFor,
  }) {
    if (date.isAfter(todayDay)) {
      return const SizedBox(width: _cell, height: _cell);
    }
    final seconds = byDate[fmtDate(date)] ?? 0;
    return Tooltip(
      message:
          '${fmtDate(date)} · ${seconds <= 0 ? '未游玩' : fmtDuration(seconds)}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: ColoredBox(
          color: colorFor(seconds),
          child: const SizedBox(width: _cell, height: _cell),
        ),
      ),
    );
  }
}

class _FactItem extends StatelessWidget {
  final String label;
  final String value;

  const _FactItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.typography.bodyStrong),
      ],
    );
  }
}

class _TagCloudSection extends StatelessWidget {
  final StatsPeriod period;
  final AsyncValue<List<TagItem>> cloudAsync;
  final ValueChanged<TagItem> onTagTap;

  const _TagCloudSection({
    required this.period,
    required this.cloudAsync,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            icon: FluentIcons.tag_16_regular,
            title: '标签词云',
            subtitle: '点击任意标签快速筛选游戏库',
            trailing: FluentBadge(text: period.label),
          ),
          const SizedBox(height: 14),
          cloudAsync.when(
            skipLoadingOnReload: true,
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: ProgressRing()),
            ),
            error: (e, _) => FluentEmptyState(
              icon: FluentIcons.cloud_off_24_regular,
              title: '词云加载失败',
              message: '$e',
            ),
            data: (tags) => tags.isEmpty
                ? const FluentEmptyState(
                    icon: FluentIcons.tag_16_regular,
                    title: '还没有足够的数据',
                    message: '先去玩一会儿作品，再来生成标签词云吧',
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FluentTagWordCloud(
                      tags: tags,
                      onTagTap: onTagTap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSummaryCard extends StatelessWidget {
  final StatsPeriod period;
  final AggStats stats;
  final List<TagItem> tags;

  const _PeriodSummaryCard({
    required this.period,
    required this.stats,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            icon: FluentIcons.sparkle_20_regular,
            title: '${period.label}总结',
            trailing: FluentBadge(text: period.label),
          ),
          const SizedBox(height: 10),
          Text(
            _buildSummary(period, stats, tags),
            style: theme.typography.body?.copyWith(height: 1.75),
          ),
        ],
      ),
    );
  }
}

class _TopGamesCard extends StatelessWidget {
  final List<TopGame> games;
  final ValueChanged<int> onOpenGame;

  const _TopGamesCard({
    required this.games,
    required this.onOpenGame,
  });

  @override
  Widget build(BuildContext context) {
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            icon: FluentIcons.timeline_20_regular,
            title: '游戏时长 Top 10',
            trailing: FluentBadge(text: '${games.length} 部'),
          ),
          const SizedBox(height: 12),
          if (games.isEmpty)
            const FluentEmptyState(
              icon: FluentIcons.games_24_regular,
              title: '暂无游玩记录',
              message: '这个时段还没有游玩记录',
            )
          else
            Column(
              children: [
                for (var i = 0; i < games.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _TopGameRow(
                    rank: i + 1,
                    game: games[i],
                    maxSeconds: games.first.seconds,
                    onTap: games[i].gameId > 0
                        ? () => onOpenGame(games[i].gameId)
                        : null,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TopGameRow extends StatelessWidget {
  final int rank;
  final TopGame game;
  final int maxSeconds;
  final VoidCallback? onTap;

  const _TopGameRow({
    required this.rank,
    required this.game,
    required this.maxSeconds,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final ratio = maxSeconds <= 0
        ? 0.0
        : (game.seconds / maxSeconds * 100).clamp(0.0, 100.0);

    return FluentSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rank <= 3
                  ? accent.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
            child: Text(
              '$rank',
              style: theme.typography.caption?.copyWith(
                fontWeight: FontWeight.w700,
                color: rank <= 3 ? accent : theme.inactiveColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.bodyStrong,
                ),
                const SizedBox(height: 6),
                ProgressBar(value: ratio),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            fmtDuration(game.seconds),
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatedGamesSection extends StatelessWidget {
  final AsyncValue<List<Game>> ratedAsync;
  final ValueChanged<Game> onOpenGame;
  final VoidCallback onRetry;

  const _RatedGamesSection({
    required this.ratedAsync,
    required this.onOpenGame,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ratedAsync.when(
      skipLoadingOnReload: true,
      loading: () => const FluentSurfaceCard(
        padding: EdgeInsets.all(24),
        child: Center(child: ProgressRing()),
      ),
      error: (e, _) => FluentSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: FluentEmptyState(
          icon: FluentIcons.error_circle_24_regular,
          title: '评分墙加载失败',
          message: '$e',
          action: FilledButton(
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ),
      ),
      data: (list) {
        final rated = [...list]
          ..sort((a, b) => b.userRating.compareTo(a.userRating));
        final avg = rated.isEmpty
            ? 0.0
            : rated.map((g) => g.userRating).reduce((a, b) => a + b) /
                rated.length;

        return FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FluentSectionHeader(
                icon: FluentIcons.star_20_regular,
                title: '评分墙',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FluentBadge(text: '${rated.length} 部'),
                    if (rated.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      FluentBadge(text: '均分 ${avg.toStringAsFixed(1)}'),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (rated.isEmpty)
                const FluentEmptyState(
                  icon: FluentIcons.star_16_regular,
                  title: '还没有评分作品',
                  message: '前往游戏详情页为喜欢的作品打分吧',
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 122,
                  ),
                  itemCount: rated.length,
                  itemBuilder: (context, index) => _RatedGameTile(
                    game: rated[index],
                    onTap: rated[index].id != null
                        ? () => onOpenGame(rated[index])
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RatedGameTile extends StatelessWidget {
  final Game game;
  final VoidCallback? onTap;

  const _RatedGameTile({required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          FluentCoverImage(
            pathOrUrl: game.coverPath,
            nsfw: game.nsfw,
            width: 56,
            height: 82,
            radius: 5,
            allowRevealOnHover: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  game.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.bodyStrong,
                ),
                const SizedBox(height: 4),
                FluentR18ScoreRow(
                  nsfw: game.nsfw,
                  scoreText: game.userRating.toStringAsFixed(1),
                  voteText: '${game.userRating ~/ 2}/5 星',
                ),
                if (game.userReview.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    game.userReview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _avgPerSession(AggStats s) => s.sessionCount == 0
    ? '—'
    : fmtDuration(s.totalSeconds ~/ s.sessionCount);

DateTime _periodStart(StatsPeriod period, DateTime now) => switch (period) {
      StatsPeriod.week => now.subtract(Duration(days: now.weekday - 1)),
      StatsPeriod.month => DateTime(now.year, now.month, 1),
      StatsPeriod.year => DateTime(now.year, 1, 1),
      StatsPeriod.all => DateTime(2000),
    };

String _buildSummary(StatsPeriod period, AggStats s, List<TagItem> tags) {
  if (s.totalSeconds == 0) {
    return '这个${period.label}还没有游玩记录，打开一部作品开始新的故事吧。';
  }
  final topTags = tags.take(4).map((t) => t.name).toList();
  final topGame = s.topGames.isEmpty ? '' : s.topGames.first.name;
  final durText = fmtDuration(s.totalSeconds);
  final avg = fmtDuration(
      s.avgPerActiveDay ~/ (s.sessionCount == 0 ? 1 : s.sessionCount));
  final tagText =
      topTags.isEmpty ? '' : '，最吸引你的关键词是「${topTags.join('」「')}」';
  final gameText = topGame.isEmpty ? '' : '，投入最多的作品是《$topGame》';
  return '这个${period.label}你游玩了 $durText，分布在 ${s.activeDays} 天、共 ${s.sessionCount} 次，'
      '平均每次 $avg'
      '$gameText$tagText。'
      '${s.activeDays >= 5 ? '保持这样细腻的节奏，故事会一直陪着你。' : '偶尔也要记得休息，故事不会跑。'}';
}
