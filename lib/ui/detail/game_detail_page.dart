/// 游戏详情页：背景图（可换/可调模糊）、信息、左简介右趋势、评分评价上传。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../services/game_launch_service.dart';
import '../../services/game_launcher.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/save_backup_dialog.dart';
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
        final bgBlur = ref.watch(detailBgBlurProvider);
        final bgFile = game.backgroundUrl.isNotEmpty &&
            File(game.backgroundUrl).existsSync();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 底色：主题背景色（不再依赖 Mica 透明）
              ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor),
              // 背景层：用户选择的截图
              if (bgFile)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                      sigmaX: bgBlur, sigmaY: bgBlur, tileMode: TileMode.clamp),
                  child: Image.file(
                    File(game.backgroundUrl),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              // 压暗/提亮遮罩（纯色，不用渐变），保证前景可读
              if (bgFile)
                Container(
                    color: dark
                        ? KisakiColors.nightBg.withValues(alpha: 0.68)
                        : KisakiColors.cream.withValues(alpha: 0.72)),
              SafeArea(
                child: Column(
                  children: [
                    // 顶部拖动条：横跨整宽，空白处即可拖动窗口
                    const WindowDragBar(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _topBar(game, tracking),
                            const SizedBox(height: 14),
                            _header(game, sources, tracking),
                            const SizedBox(height: 20),
                            if (tags.isNotEmpty) ...[
                              _tags(tags, dark),
                              const SizedBox(height: 20),
                            ],
                            // 左简介 / 右趋势 双栏
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: game.summary.isEmpty
                                      ? SoftCard(
                                          child: Text('暂无简介',
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)))
                                      : SoftCard(
                                          child: Text(game.summary,
                                              style: const TextStyle(
                                                  height: 1.7,
                                                  fontSize: 13.5))),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: _DailyTrendCard(gameId: widget.gameId),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _topBar(Game game, bool tracking) {
    return Row(
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
          const _LiveSessionChip(),
        const SizedBox(width: 8),
        // 收藏（心形，直接切换）
        IconButton(
          tooltip: game.isFavorite ? '取消收藏' : '加入收藏',
          onPressed: () async {
            game.isFavorite = !game.isFavorite;
            await AppServices.I.repo.updateGame(game);
            // 延迟刷新，避免返回游戏库时整页闪烁
            Future.delayed(const Duration(milliseconds: 450), () {
              if (mounted) {
                ref.read(libraryVersionProvider.notifier).state++;
              }
            });
            if (mounted) setState(() {});
          },
          icon: Icon(
            game.isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: game.isFavorite ? KisakiColors.pink : null,
          ),
        ),
      ],
    );
  }

  Widget _header(Game game, List<SourceRecord> sources, bool tracking) {
    return Row(
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
                  value: game.developer.isEmpty ? '未知' : game.developer,
                  onTap: game.developer.isEmpty
                      ? null
                      : () => _jumpLibrary(developer: game.developer)),
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
                      if (v == 'save') {
                        await SaveBackupDialog.show(context, game);
                      } else if (v == 'delete') {
                        await _confirmDelete(game);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'save', child: Text('存档备份')),
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
    );
  }

  Widget _tags(List<TagItem> tags, bool dark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tags.take(18))
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _jumpLibrary(tag: t.name),
            child: Container(
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
          ),
      ],
    );
  }

  /// 点开发商/标签 → 回游戏库并应用对应筛选。
  void _jumpLibrary({String? developer, String? tag}) {
    jumpToLibraryFiltered(ref, developer: developer, tag: tag);
    Navigator.of(context).pop();
  }

  // ---------- 动作 ----------

  Future<void> _launch(Game game) async {
    // 统一走 GameLaunchService（含转区启动判定、启动失败提示、计时与会话落库）
    await GameLaunchService.launchAndTrack(game, ref);
    if (!mounted) return;
    setState(() {});
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
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RateDialog(game: game, sources: sources)));
    // 延迟刷新，避免关闭动画期间整页闪烁
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(libraryVersionProvider.notifier).state++;
    });
  }

  Future<void> _openEditSheet(Game game) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditSheet(game: game)));
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(libraryVersionProvider.notifier).state++;
    });
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool ellipsis;
  final VoidCallback? onTap;
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.ellipsis = false,
      this.onTap});

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
            child: onTap != null
                ? InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: onTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(value,
                              maxLines: 1,
                              overflow: ellipsis
                                  ? TextOverflow.ellipsis
                                  : TextOverflow.clip,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: KisakiColors.pink)),
                        ),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 13, color: KisakiColors.pink),
                      ],
                    ),
                  )
                : Text(
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

/// 近 30 天游玩趋势（右栏）。
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
                          color: color.withValues(alpha: 0.12),
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
    final rows = await AppServices.I.db.query('game_sessions',
        where: 'game_id = ? AND date >= ?',
        whereArgs: [gameId, _fmt(now.subtract(const Duration(days: 29)))]);
    final byDate = <String, int>{};
    for (final r in rows) {
      final s = GameSession.fromRow(r);
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

/// 本次游玩实时时长（每秒自刷新）。
class _LiveSessionChip extends StatefulWidget {
  const _LiveSessionChip();

  @override
  State<_LiveSessionChip> createState() => _LiveSessionChipState();
}

class _LiveSessionChipState extends State<_LiveSessionChip> {
  Timer? _t;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _seconds = AppServices.I.tracker.liveSeconds;
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds = AppServices.I.tracker.liveSeconds);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: KisakiColors.pink,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text('本次 ${fmtDuration(_seconds)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}