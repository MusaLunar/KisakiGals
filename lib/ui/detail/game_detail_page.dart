/// 游戏详情页：背景图（可换/可调模糊）、信息、统计、简介与趋势、来源、标签、启动。
///
/// 全屏路由页：保留 Scaffold + WindowDragBar；内容卡片统一走 kit 的
/// KCard / KStat / KRow / KChip，有背景图时卡片改用毛玻璃（glass: true）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/shell/title_bar.dart';
import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../services/game_launch_service.dart';
import '../../services/game_launcher.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/notifications.dart';
import '../widgets/save_backup_dialog.dart';
import '../widgets/scrape_search_sheet.dart';
import 'edit_sheet.dart';
import 'rate_dialog.dart';

class GameDetailPage extends ConsumerStatefulWidget {
  final int gameId;
  /// 调用方（游戏库/主页/搜索）已有的数据：传入后立即渲染，避免先闪一下加载态
  final Game? initial;
  const GameDetailPage({super.key, required this.gameId, this.initial});

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameProvider(widget.gameId));

    return gameAsync.when(
      skipLoadingOnRefresh: true,
      // 有 initial（列表里已加载过的数据）时不显示加载态，直接渲染已知数据
      skipLoadingOnReload: true,
      loading: () => widget.initial != null
          ? _buildDetail(context, widget.initial!, ref)
          : const Scaffold(body: KLoading()),
      error: (e, _) => widget.initial != null
          ? _buildDetail(context, widget.initial!, ref)
          : Scaffold(
              body: KEmpty(
                icon: Icons.error_outline_rounded,
                title: '加载失败',
                subtitle: '$e',
              ),
            ),
      data: (game) {
        if (game == null) {
          return const Scaffold(
            body: KEmpty(icon: Icons.search_off_rounded, title: '游戏不存在'),
          );
        }
        return _buildDetail(context, game, ref);
      },
    );
  }

  /// 实际页面内容（供 loading/error/data 三个分支复用，避免首帧闪加载态）。
  Widget _buildDetail(BuildContext context, Game game, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tracking = ref.watch(trackingGameProvider) == widget.gameId;
    final sources = ref.watch(gameSourcesProvider(widget.gameId)).valueOrNull ?? [];
    final tags = ref.watch(gameTagsProvider(widget.gameId)).valueOrNull ?? [];
    final bgBlur = ref.watch(detailBgBlurProvider);
    // 背景图同样可能存的是相对路径（换设备迁移后需解析）
    final bgPath = game.backgroundUrl.isEmpty
        ? ''
        : AppServices.I.paths.resolveStored(game.backgroundUrl);
    final bgFile = cachedFileExists(bgPath);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 底色：主题背景色（不再依赖 Mica 透明）
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          // 背景层：用户选择的截图
          if (bgFile)
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                  sigmaX: bgBlur, sigmaY: bgBlur, tileMode: TileMode.clamp),
              child: Image.file(
                File(bgPath),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          // 遮罩：上浅下深的渐变 —— 顶部保留作品主视觉，下方保证内容可读
          // （纯色遮罩要么压掉画面、要么让下方文字发灰，评审建议改渐变）
          if (bgFile)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? [
                          KisakiColors.nightBg.withValues(alpha: 0.62),
                          KisakiColors.nightBg.withValues(alpha: 0.88),
                          KisakiColors.nightBg.withValues(alpha: 0.94),
                        ]
                      : [
                          KisakiColors.cream.withValues(alpha: 0.52),
                          KisakiColors.cream.withValues(alpha: 0.86),
                          KisakiColors.cream.withValues(alpha: 0.94),
                        ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                // 顶部拖动条：横跨整宽，空白处即可拖动窗口
                const AppTitleBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _topBar(game, tracking),
                        const SizedBox(height: Gap.md),
                        _header(game, sources, tracking, bgFile),
                        // 以下区块与右侧信息列对齐（封面 220 + 间距 24），
                        // 避免页面出现两条不同的左基线（评审指出 24 与 269 并存）
                        Padding(
                          padding: const EdgeInsets.only(left: 244),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: Gap.xl),
                          _tags(tags),
                        ],
                        const SizedBox(height: Gap.xl),
                        // 左简介 / 右趋势 双栏
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: KCard(
                                glass: bgFile,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const KSectionTitle('简介'),
                                    Text(
                                      game.summary.isEmpty ? '暂无简介' : game.summary,
                                      style: game.summary.isEmpty
                                          ? Type.body.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)
                                          : Type.body.copyWith(height: 1.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: Gap.lg),
                            Expanded(
                              flex: 2,
                              child: _DailyTrendCard(
                                  gameId: widget.gameId, glass: bgFile),
                            ),
                          ],
                        ),
                        const SizedBox(height: Gap.xl),
                        _sourcesSection(game, sources, bgFile),
                            ],
                          ),
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
  }

  /// 顶栏：返回 / 收藏 / 编辑信息 / 更多（存档备份、删除游戏）。
  Widget _topBar(Game game, bool tracking) {
    return Row(
      children: [
        KIconAction(
          icon: Icons.arrow_back_rounded,
          tooltip: '返回',
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: Gap.sm),
        Text('游戏详情', style: Type.title),
        const Spacer(),
        if (tracking) ...[
          const _LiveSessionChip(),
          const SizedBox(width: Gap.sm),
        ],
        // 收藏（心形，直接切换）
        KIconAction(
          icon: game.isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          tooltip: game.isFavorite ? '取消收藏' : '加入收藏',
          active: game.isFavorite,
          onTap: () async {
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
        ),
        KIconAction(
          icon: Icons.edit_rounded,
          tooltip: '编辑信息',
          onTap: () => _openEditSheet(game),
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md)),
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (v) async {
            if (v == 'save') {
              await SaveBackupDialog.show(context, game);
            } else if (v == 'delete') {
              await _confirmDelete(game);
            } else if (v == 'rescan') {
              await _rescan(game);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'save', child: Text('存档备份')),
            PopupMenuItem(value: 'rescan', child: Text('重新刮削')),
            PopupMenuItem(
                value: 'delete',
                child: Text('删除游戏', style: TextStyle(color: Colors.red))),
          ],
        ),
      ],
    );
  }

  Widget _header(Game game, List<SourceRecord> sources, bool tracking,
      [bool glass = false]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面
        CoverImage(
          path: game.coverPath,
          nsfw: game.nsfw,
          width: 220,
          height: 310,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        const SizedBox(width: 24),
        // 信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.displayName, style: Type.display),
              // 显示中文名为主标题时，副标题补上原始名称（二者不同才显示）
              if (game.name.isNotEmpty && game.name != game.displayName)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.xs),
                  child: Text(
                    game.name,
                    style: Type.body.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: Gap.md),
              // 平台评分行（含 R18 标记与我的评分）
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                  if (game.nsfw)
                    const KBadge(
                        text: 'R18',
                        color: KisakiColors.danger,
                        icon: Icons.explicit_rounded),
                ],
              ),
              const SizedBox(height: Gap.lg),
              // 游玩记录：总时长 / 本次 / 平均单次（有背景图时毛玻璃）
              _PlaytimeCards(game: game, tracking: tracking, glass: glass),
              const SizedBox(height: Gap.lg),
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
                  icon: Icons.history_rounded,
                  label: '上次游玩',
                  value: game.lastPlayedAt == null
                      ? '尚未游玩'
                      : fmtDateTime(game.lastPlayedAt!)),
              _InfoRow(
                  icon: Icons.folder_rounded,
                  label: '目录',
                  value: game.directory.isEmpty ? '未指定' : game.directory),
              const SizedBox(height: Gap.lg),
              // 操作按钮
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  KPill(
                    label: tracking
                        ? '正在游戏中'
                        : (game.lastPlayedAt == null ? '启动游戏' : '继续游戏'),
                    icon: tracking
                        ? Icons.hourglass_top_rounded
                        : Icons.play_arrow_rounded,
                    onTap: tracking ? null : () => _launch(game),
                  ),
                  KPill(
                    label: '打开目录',
                    icon: Icons.folder_open_rounded,
                    filled: false,
                    onTap: game.directory.isEmpty
                        ? null
                        : () => GameLauncher.openDirectory(game.directory),
                  ),
                  KPill(
                    label: '评分 / 评价',
                    icon: Icons.rate_review_rounded,
                    filled: false,
                    onTap: () => _openRateDialog(game, sources),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 标签：点击回游戏库并按该标签筛选。
  Widget _tags(List<TagItem> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KSectionTitle('标签'),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final t in tags.take(18))
              KChip(
                label: t.name,
                color: KisakiColors.lavender,
                selected: true,
                onTap: () => _jumpLibrary(tag: t.name),
              ),
          ],
        ),
      ],
    );
  }

  /// 数据来源（各平台条目 id 与评分）+ 重新刮削入口。
  Widget _sourcesSection(
      Game game, List<SourceRecord> sources, bool glass) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KSectionTitle(
          '数据来源',
          trailing: TextButton.icon(
            onPressed: () => _rescan(game),
            icon: const Icon(Icons.travel_explore_rounded, size: 16),
            label: const Text('重新刮削'),
          ),
        ),
        KCard(
          glass: glass,
          padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg, vertical: Gap.xs),
          child: sources.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.sm),
                  child: KEmpty(
                    icon: Icons.dataset_outlined,
                    title: '暂无平台数据',
                    subtitle: '重新刮削后会自动登记各平台条目 id 与评分',
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < sources.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      KRow(
                        leading: SourceBadge(source: sources[i].source),
                        title: sources[i].sourceId.isEmpty
                            ? '未登记条目 id'
                            : sources[i].sourceId,
                        subtitle: sources[i].rating > 0
                            ? '${sources[i].rating.toStringAsFixed(1)} / 10 · ${sources[i].voteCount} 人评价'
                            : '无评分数据',
                      ),
                    ],
                  ],
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

  /// 重新刮削：搜索 → 选择 → 多源合并 → 应用（与添加页同一流程）。
  Future<void> _rescan(Game game) async {
    final all = await showScrapeSearchSheet(
      context,
      initialQuery: game.displayName,
    );
    if (all == null || !mounted) return;
    await ScrapeApplier(AppServices.I.repo, AppServices.I.fetcher)
        .apply(game, all);
    ref.read(libraryVersionProvider.notifier).state++;
    if (!mounted) return;
    showNotice('已重新刮削：${all.first.displayName}（${all.length} 个数据源）');
  }

  Future<void> _confirmDelete(Game game) async {
    final ok = await showKisakiDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除游戏'),
        content: Text('确定要从游戏库中删除「${game.displayName}」吗？\n游玩记录与统计将一并删除（游戏文件不受影响）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: KisakiColors.danger),
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

  Future<void> _openRateDialog(Game game, List<SourceRecord> sources) async {
    await Navigator.of(context).push(FadeThroughRoute.builder(
        builder: (_) => RateDialog(game: game, sources: sources)));
    // 延迟刷新，避免关闭动画期间整页闪烁
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(libraryVersionProvider.notifier).state++;
    });
  }

  Future<void> _openEditSheet(Game game) async {
    await Navigator.of(context).push(
        FadeThroughRoute.builder(builder: (_) => EditSheet(game: game)));
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(libraryVersionProvider.notifier).state++;
    });
  }
}

/// 信息行：图标 + 标签 + 值（可点击的走筛选跳转）。
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KRow(
      leading: Icon(icon, size: 17, color: scheme.onSurfaceVariant),
      title: label,
      subtitle: value,
      onTap: onTap,
      trailing: onTap == null
          ? null
          : Icon(Icons.arrow_forward_rounded,
              size: 14, color: scheme.primary),
    );
  }
}

/// 近 30 天游玩趋势（右栏）。
class _DailyTrendCard extends ConsumerWidget {
  final int gameId;
  final bool glass;
  const _DailyTrendCard({required this.gameId, this.glass = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return KCard(
      glass: glass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KSectionTitle('近 30 天游玩趋势'),
          SizedBox(
            height: 140,
            child: FutureBuilder<List<DailyPoint>>(
              future: _dailyPoints(),
              builder: (context, snap) {
                final points = snap.data ?? const <DailyPoint>[];
                final spots = <FlSpot>[];
                for (var i = 0; i < points.length; i++) {
                  spots.add(
                      FlSpot(i.toDouble(), points[i].seconds / 3600.0));
                }
                final color = scheme.primary;
                if (spots.isEmpty || spots.every((s) => s.y == 0)) {
                  return Center(
                    child: Text('这段时间还没有游玩记录',
                        style:
                            Type.caption.copyWith(color: scheme.onSurfaceVariant)),
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

  /// 30 天趋势缓存：按 gameId 复用，避免每次重建都查库（页面切换卡顿的主要来源）
  static final Map<int, Future<List<DailyPoint>>> _trendCache = {};

  Future<List<DailyPoint>> _dailyPoints() =>
      _trendCache.putIfAbsent(gameId, () => _loadDailyPoints());

  Future<List<DailyPoint>> _loadDailyPoints() async {
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

/// 游玩数据变化后让详情页趋势缓存失效（会话结束/删除记录时调用）。
void invalidateDailyTrend(int gameId) => _DailyTrendCard._trendCache.remove(gameId);

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
    return KBadge(
      text: '本次 ${fmtDuration(_seconds)}',
      color: KisakiColors.pink,
      icon: Icons.play_arrow_rounded,
    );
  }
}

/// 详情页的游玩记录卡片（总时长 / 本次 / 平均单次）。
/// 「本次」在计时进行中每秒跳动；有背景图时整块用毛玻璃。
class _PlaytimeCards extends StatefulWidget {
  final Game game;
  final bool tracking;
  final bool glass;
  const _PlaytimeCards(
      {required this.game, required this.tracking, this.glass = false});

  @override
  State<_PlaytimeCards> createState() => _PlaytimeCardsState();
}

class _PlaytimeCardsState extends State<_PlaytimeCards> {
  Timer? _t;
  int _live = 0;

  @override
  void initState() {
    super.initState();
    _live = AppServices.I.tracker.liveSeconds;
    if (widget.tracking) _startTicker();
  }

  @override
  void didUpdateWidget(_PlaytimeCards old) {
    super.didUpdateWidget(old);
    if (widget.tracking && !old.tracking) {
      _startTicker();
    } else if (!widget.tracking && old.tracking) {
      _t?.cancel();
      _t = null;
      setState(() => _live = 0);
    }
  }

  void _startTicker() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _live = AppServices.I.tracker.liveSeconds);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final sessions = g.sessionCount;
    final avg = sessions > 0 ? g.totalSeconds ~/ sessions : 0;
    final cards = [
      (
        '总时长',
        Icons.timer_outlined,
        KisakiColors.pink,
        fmtDuration(g.totalSeconds),
        g.lastPlayedAt == null
            ? '尚未游玩'
            : '上次 ${fmtDate(g.lastPlayedAt!)}'
      ),
      (
        widget.tracking ? '本次游玩' : '本次',
        Icons.play_circle_outline_rounded,
        const Color(0xFF7EC8C3),
        widget.tracking
            ? fmtDuration(_live)
            : fmtDuration(AppServices.I.tracker.liveSeconds),
        widget.tracking ? '计时中…' : (sessions > 0 ? '共 $sessions 次' : '未开始')
      ),
      (
        '平均单次',
        Icons.insights_rounded,
        KisakiColors.lavender,
        avg > 0 ? fmtDuration(avg) : '—',
        sessions > 0 ? '$sessions 次游玩' : '暂无记录'
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: Gap.md),
          Expanded(
            child: KStat(
              glass: widget.glass,
              icon: cards[i].$2,
              accent: cards[i].$3,
              label: cards[i].$1,
              value: cards[i].$4,
              hint: cards[i].$5,
            ),
          ),
        ],
      ],
    );
  }
}
