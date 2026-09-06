/// 游戏详情页：信息、统计、启动、编辑、重刮、评分评价（可同步上传）。
library;

import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../services/game_launcher.dart';
import 'package:window_manager/window_manager.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'edit_sheet.dart';
import 'rate_dialog.dart';

class GameDetailPage extends ConsumerStatefulWidget {
  final int gameId;
  const GameDetailPage({super.key, required this.gameId});

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameProvider(widget.gameId));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tracking = ref.watch(trackingGameProvider) == widget.gameId;

    return gameAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (game) {
        if (game == null) {
          return const Scaffold(body: Center(child: Text('游戏不存在')));
        }
        final sources = ref.watch(gameSourcesProvider(widget.gameId)).valueOrNull ?? [];
        final tags = ref.watch(gameTagsProvider(widget.gameId)).valueOrNull ?? [];

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶栏
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    Text('游戏详情',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (tracking)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: KisakiColors.pink,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.play_arrow_rounded,
                                size: 16, color: Colors.white),
                            Text(' ${fmtDuration(AppServices.I.tracker.liveSeconds)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面
                    Stack(
                      children: [
                        CoverImage(
                          path: game.coverPath,
                          nsfw: game.nsfw,
                          width: 220,
                          height: 310,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        if (game.nsfw)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                              child: const Text('R18',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    // 信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(game.displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          if (game.nameCn.isNotEmpty && game.nameCn != game.displayName)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(game.name,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ),
                          const SizedBox(height: 12),
                          // 平台评分行
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in sources)
                                if (s.rating > 0)
                                  PlatformRatingChip(
                                    label: KisakiSources.labels[s.source] ?? s.source,
                                    rating: s.rating,
                                    votes: s.voteCount,
                                  ),
                              if (game.userRating > 0)
                                PlatformRatingChip(
                                    label: '我的', rating: game.userRating),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _InfoRow(
                              icon: Icons.business_rounded,
                              label: '开发商',
                              value: game.developer.isEmpty ? '未知' : game.developer),
                          _InfoRow(
                              icon: Icons.event_rounded,
                              label: '发售日期',
                              value:
                                  game.releaseDate.isEmpty ? '未知' : game.releaseDate),
                          _InfoRow(
                              icon: Icons.timer_outlined,
                              label: '总时长',
                              value: fmtDuration(game.totalSeconds)),
                          _InfoRow(
                              icon: Icons.history_rounded,
                              label: '上次游玩',
                              value: game.lastPlayedAt == null
                                  ? '尚未游玩'
                                  : fmtDateTime(game.lastPlayedAt!)),
                          _InfoRow(
                              icon: Icons.folder_rounded,
                              label: '目录',
                              value: game.directory.isEmpty ? '未指定' : game.directory,
                              ellipsis: true),
                          const SizedBox(height: 16),
                          // 操作按钮
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: tracking ? null : () => _launch(game),
                                icon: Icon(tracking
                                    ? Icons.hourglass_top_rounded
                                    : Icons.play_arrow_rounded),
                                label: Text(
                                    tracking ? '正在游戏中' : (game.lastPlayedAt == null ? '启动游戏' : '继续游戏')),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    game.directory.isEmpty ? null : () => GameLauncher.openDirectory(game.directory),
                                icon: const Icon(Icons.folder_open_rounded, size: 18),
                                label: const Text('打开目录'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openRateDialog(game, sources),
                                icon: const Icon(Icons.rate_review_rounded, size: 18),
                                label: const Text('评分 / 评价'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openEditSheet(game),
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                label: const Text('编辑信息'),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '更多',
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                icon: const Icon(Icons.more_horiz_rounded),
                                onSelected: (v) async {
                                  if (v == 'rescan') {
                                    await _rescan(game);
                                  } else if (v == 'favorite') {
                                    game.isFavorite = !game.isFavorite;
                                    await AppServices.I.repo.updateGame(game);
                                    ref.read(libraryVersionProvider.notifier).state++;
                                  } else if (v == 'delete') {
                                    await _confirmDelete(game);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'rescan',
                                      child: Text('重新刮削元数据')),
                                  PopupMenuItem(
                                      value: 'favorite',
                                      child: Text(game.isFavorite
                                          ? '取消收藏'
                                          : '加入收藏')),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除游戏',
                                          style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 标签
                if (tags.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tags.take(18))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: dark
                                ? KisakiColors.lavender.withValues(alpha: 0.16)
                                : KisakiColors.lavenderContainer,
                          ),
                          child: Text(
                            t.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: dark
                                  ? KisakiColors.lavenderSoft
                                  : KisakiColors.onLavenderContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                // 简介
                if (game.summary.isNotEmpty)
                  SoftCard(
                    child: Text(game.summary,
                        style: const TextStyle(height: 1.7, fontSize: 13.5)),
                  ),
                // 游玩趋势（近 30 天）
                const SizedBox(height: 20),
                _DailyTrendCard(gameId: widget.gameId),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- 动作 ----------

  Future<void> _launch(Game game) async {
    if (game.exePath.isEmpty || !File(game.exePath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到游戏可执行文件，请先在编辑中设置')));
      return;
    }
    final mode = await AppServices.I.settings.trackingMode();
    unawaited(GameLauncher.launch(game.exePath, game.directory));
    AppServices.I.tracker.startTracking(
      gameId: game.id!,
      exePath: game.exePath,
      directory: game.directory,
      mode: mode,
    );
    ref.read(trackingGameProvider.notifier).state = game.id!;
    // 记录 runtime 以便崩溃恢复
    await AppServices.I.settings.setString('runtime.last_game', '${game.id}');
    // 启动后动作
    final after = await AppServices.I.settings
        .getString(SettingsStore.kAfterLaunch, 'none');
    if (after == 'minimize') await WindowManager.instance.minimize();

    if (game.playStatus == PlayStatus.wish) {
      game.playStatus = PlayStatus.playing;
      await AppServices.I.repo.updateGame(game);
      ref.read(libraryVersionProvider.notifier).state++;
    }
    if (game.firstPlayedAt == null) {
      game.firstPlayedAt = DateTime.now();
      await AppServices.I.repo.updateGame(game);
    }
    if (mounted) setState(() {});
  }

  Future<void> _rescan(Game game) async {
    final kw = game.nameCn.isNotEmpty ? game.nameCn : game.name;
    final best = await AppServices.I.fetcher.fetchBest(kw);
    if (best == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未找到匹配的元数据')));
      return;
    }
    final repo = AppServices.I.repo;
    game.name = best.name.isNotEmpty ? best.name : game.name;
    if (best.nameCn.isNotEmpty) game.nameCn = best.nameCn;
    game.aliases = best.aliases;
    if (best.developer.isNotEmpty) game.developer = best.developer;
    if (best.releaseDate.isNotEmpty) game.releaseDate = best.releaseDate;
    if (best.summary.isNotEmpty) game.summary = best.summary;
    game.nsfw = best.nsfw;
    final cover = await AppServices.I.fetcher.downloadCover(best, game.id!);
    if (cover.isNotEmpty) game.coverPath = cover;
    await repo.updateGame(game);
    await repo.setTags(
        game.id!,
        best.tags
            .map((t) => TagItem(name: t.name, weight: t.weight, source: best.source))
            .toList());
    await repo.upsertSource(
        game.id!,
        SourceRecord(
          gameId: game.id!,
          source: best.source,
          sourceId: best.sourceId,
          rating: best.rating,
          voteCount: best.voteCount,
          raw: best.toJson(),
        ));
    ref.read(libraryVersionProvider.notifier).state++;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已重新刮削：${best.displayName}')));
  }

  Future<void> _confirmDelete(Game game) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除游戏'),
        content: Text('确定要从游戏库中删除「${game.displayName}」吗？\n游玩记录与统计将一并删除（游戏文件不受影响）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await AppServices.I.repo.deleteGame(game.id!);
      ref.read(libraryVersionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _openRateDialog(
      Game game, List<SourceRecord> sources) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RateDialog(game: game, sources: sources),
    );
    ref.read(libraryVersionProvider.notifier).state++;
  }

  Future<void> _openEditSheet(Game game) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditSheet(game: game),
    );
    ref.read(libraryVersionProvider.notifier).state++;
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool ellipsis;
  const _InfoRow(
      {required this.icon, required this.label, required this.value, this.ellipsis = false});

  @override
  Widget build(BuildContext context) {
    final soft = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: soft),
          const SizedBox(width: 8),
          Text('$label：',
              style: TextStyle(fontSize: 13, color: soft)),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.clip,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// 近 30 天游玩趋势。
class _DailyTrendCard extends ConsumerWidget {
  final int gameId;
  const _DailyTrendCard({required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('近 30 天游玩趋势',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: FutureBuilder<List<DailyPoint>>(
              future: _dailyPoints(),
              builder: (context, snap) {
                final points = snap.data ?? const <DailyPoint>[];
                final spots = <FlSpot>[];
                for (var i = 0; i < points.length; i++) {
                  spots.add(FlSpot(
                      i.toDouble(), points[i].seconds / 3600.0));
                }
                final color = Theme.of(context).colorScheme.primary;
                if (spots.isEmpty || spots.every((s) => s.y == 0)) {
                  return Center(
                    child: Text('这段时间还没有游玩记录',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12.5)),
                  );
                }
                return LineChart(
                  LineChartData(
                    gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                            color: (dark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.05),
                            strokeWidth: 1)),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.35,
                        color: color,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              color.withValues(alpha: 0.28),
                              color.withValues(alpha: 0.02),
                            ],
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots
                            .map((s) => LineTooltipItem(
                                '${points[s.x.toInt()].date}\n${fmtDuration(points[s.x.toInt()].seconds)}',
                                TextStyle(
                                    color: dark ? Colors.white : Colors.black,
                                    fontSize: 11)))
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<DailyPoint>> _dailyPoints() async {
    final game = await AppServices.I.repo.getGame(gameId);
    if (game == null) return [];
    final now = DateTime.now();
    final days = <DailyPoint>[];
    // 简化：从所有会话聚合近30天
    final sessions = <GameSession>[];
    final db = AppServices.I.db;
    final rows = await db.query('game_sessions',
        where: 'game_id = ? AND date >= ?',
        whereArgs: [gameId, _fmt(now.subtract(const Duration(days: 29)))]);
    for (final r in rows) {
      sessions.add(GameSession.fromRow(r));
    }
    final byDate = <String, int>{};
    for (final s in sessions) {
      byDate[s.date] = (byDate[s.date] ?? 0) + s.seconds;
    }
    for (var i = 29; i >= 0; i--) {
      final d = _fmt(now.subtract(Duration(days: i)));
      days.add(DailyPoint(d, byDate[d] ?? 0));
    }
    return days;
  }

  static String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
