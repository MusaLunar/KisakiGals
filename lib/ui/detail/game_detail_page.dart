/// 游戏详情页：誌面 (Shimen) 连贯双栏特辑纸页.
///
/// 设计架构：
/// 1. **顶部零冗余**：`AppTitleBar` 下方不再堆砌第二条工具栏或重复标题，
///    仅在左栏封面顶部放置克制的「← 返回书库」导览键，右栏直接以作品大标题开篇，彻底消除顶部臃肿感；
/// 2. **操作合一**：将「启动游戏、打开目录、评分评价、编辑信息、收藏、更多（存档备份/重新刮削/删除）」
///    全部收拢至标题下方的唯一动作行，避免按钮分散在页面上下两处；
/// 3. **连贯纸页（消除割裂）**：整页直接铺陈于 `KisakiColors.pageSurface` 连续纸面之上，
///    左栏（240px 封面图版 + 作品规格档案 + 数据来源）与右栏（主刊头 + 四格时长账本 + 故事简介 + 30 天趋势）
///    通过 1px 印刷裁切细线 (`Elev.border`) 自然分栏，不再切成多张孤立卡片。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../services/game_launch_service.dart';
import '../../services/game_launcher.dart';
import '../../ui/shell/title_bar.dart';
import '../design.dart';
import '../discover/game_explore_page.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/notifications.dart';
import '../widgets/save_backup_dialog.dart';
import '../widgets/scrape_search_sheet.dart';
import 'edit_sheet.dart';
import 'rate_dialog.dart';

// ============================ 版面常量 ============================

const double _kWideBreakpoint = 920;
const double _kContentMaxWidth = 1280;
const double _kLeftColWidthWide = 240;
const double _kCoverHeightWide = 360; // 240 * 1.5 (2:3)
const double _kCoverWidthNarrow = 156;
const double _kCoverHeightNarrow = 234;
const double _kTrendChartHeight = 140;
const int _kTagLimit = 20;
const String _kEmptyValue = '—';

class GameDetailPage extends ConsumerStatefulWidget {
  final int gameId;
  final Game? initial;
  final bool scrollToPlayPath;
  const GameDetailPage({
    super.key,
    required this.gameId,
    this.initial,
    this.scrollToPlayPath = false,
  });

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _playPathKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToPlayPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 220), () {
          if (mounted) _scrollToPlayPath();
        });
      });
    }
  }

  void _scrollToPlayPath() {
    final ctx = _playPathKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: Motion.normal,
      curve: Motion.enter,
      alignment: 0.08,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameProvider(widget.gameId));

    return gameAsync.when(
      skipLoadingOnRefresh: true,
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

  Widget _buildDetail(BuildContext context, Game game, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tracking = ref.watch(trackingGameProvider) == widget.gameId;
    final sources =
        ref.watch(gameSourcesProvider(widget.gameId)).valueOrNull ?? [];
    final tags = ref.watch(gameTagsProvider(widget.gameId)).valueOrNull ?? [];
    final bgBlur = ref.watch(detailBgBlurProvider);
    final bgPath = game.backgroundUrl.isEmpty
        ? ''
        : AppServices.I.paths.resolveStored(game.backgroundUrl);
    final hasBgImage = cachedFileExists(bgPath);
    final pageBg = KisakiColors.pageSurface(dark);

    return Scaffold(
      backgroundColor: pageBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: pageBg),
          if (hasBgImage)
            RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: bgBlur,
                  sigmaY: bgBlur,
                  tileMode: TileMode.clamp,
                ),
                child: Image.file(
                  File(bgPath),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  cacheWidth: 480,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                ),
              ),
            ),
          if (hasBgImage)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? [
                          pageBg.withValues(alpha: 0.76),
                          pageBg.withValues(alpha: 0.93),
                          pageBg.withValues(alpha: 0.98),
                        ]
                      : [
                          pageBg.withValues(alpha: 0.74),
                          pageBg.withValues(alpha: 0.92),
                          pageBg.withValues(alpha: 0.98),
                        ],
                  stops: const [0.0, 0.38, 1.0],
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                const AppTitleBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, pageC) {
                      final wide = pageC.maxWidth >= _kWideBreakpoint;
                      return Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(
                              36, 24, 36, Gap.huge),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: _kContentMaxWidth),
                              child: StaggeredFadeIn(
                                key: const ValueKey('spread-canvas'),
                                index: 0,
                                child: _buildSpreadCanvas(
                                  game: game,
                                  sources: sources,
                                  tags: tags,
                                  tracking: tracking,
                                  wide: wide,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================ 连贯双栏杂志版心 ============================

  Widget _buildSpreadCanvas({
    required Game game,
    required List<SourceRecord> sources,
    required List<TagItem> tags,
    required bool tracking,
    required bool wide,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = Elev.border(dark);

    if (wide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左栏：返回书库 + 2:3 封面图版 + 作品规格档案 + 数据来源
            SizedBox(
              width: _kLeftColWidthWide,
              child: _buildLeftColumn(
                game: game,
                sources: sources,
              ),
            ),
            const SizedBox(width: 28),
            Container(width: 1, color: borderColor),
            const SizedBox(width: 32),
            // 右栏：主标题刊头 + 统一动作栏 + 四格时长账本 + 简介与 30 天趋势
            Expanded(
              child: _buildRightColumn(
                game: game,
                sources: sources,
                tags: tags,
                tracking: tracking,
              ),
            ),
          ],
        ),
      );
    }

    // 窄窗口自适应单栏
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _BackToLibraryButton(
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFramedCover(
              game: game,
              width: _kCoverWidthNarrow,
              height: _kCoverHeightNarrow,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildMastheadAndActions(
                game: game,
                sources: sources,
                tags: tags,
                tracking: tracking,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Divider(height: 1, thickness: 1, color: borderColor),
        const SizedBox(height: 18),
        _PlaytimeLedgerStrip(game: game, tracking: tracking),
        const SizedBox(height: 18),
        Divider(height: 1, thickness: 1, color: borderColor),
        const SizedBox(height: 22),
        _buildSynopsisAndTrend(game: game, tracking: tracking),
        const SizedBox(height: 24),
        Divider(height: 1, thickness: 1, color: borderColor),
        const SizedBox(height: 20),
        _buildSpecLedger(game: game, sources: sources),
      ],
    );
  }

  // ============================ 左栏：返回键 + 封面 + 档案表 ============================

  Widget _buildLeftColumn({
    required Game game,
    required List<SourceRecord> sources,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _BackToLibraryButton(
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(height: 14),
        _buildFramedCover(
          game: game,
          width: _kLeftColWidthWide,
          height: _kCoverHeightWide,
        ),
        const SizedBox(height: 22),
        _buildSpecLedger(game: game, sources: sources),
      ],
    );
  }

  Widget _buildFramedCover({
    required Game game,
    required double width,
    required double height,
  }) {
    return _InteractiveCoverPlate(
      game: game,
      width: width,
      height: height,
    );
  }

  Widget _buildSpecLedger({
    required Game game,
    required List<SourceRecord> sources,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = Elev.border(dark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KSectionTitle(
          '作品档案',
          padding: EdgeInsets.only(bottom: 8),
        ),
        _SpecRow(
          label: '开发商',
          value: game.developer.isEmpty ? '未知' : game.developer,
          placeholder: game.developer.isEmpty,
          onTap: game.developer.isEmpty
              ? null
              : () => _jumpLibrary(developer: game.developer),
        ),
        Divider(height: 1, thickness: 1, color: borderColor),
        _SpecRow(
          label: '发售日',
          value: game.releaseDate.isEmpty ? '未知' : game.releaseDate,
          placeholder: game.releaseDate.isEmpty,
          tabular: true,
        ),
        Divider(height: 1, thickness: 1, color: borderColor),
        _SpecRow(
          label: '状态',
          value: game.playStatus.label,
        ),
        Divider(height: 1, thickness: 1, color: borderColor),
        _SpecRow(
          label: '目录',
          value: game.directory.isEmpty ? '未指定' : game.directory,
          placeholder: game.directory.isEmpty,
          onTap: game.directory.isEmpty
              ? null
              : () => GameLauncher.openDirectory(game.directory),
        ),
        const SizedBox(height: 20),
        KSectionTitle(
          '数据来源',
          padding: const EdgeInsets.only(bottom: 8),
          trailing: FluidPressable(
            onTap: () => _rescan(game),
            child: Text(
              '重新刮削',
              style: Type.micro.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (sources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '暂无外部源记录，可点击「重新刮削」关联',
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (var i = 0; i < sources.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SourceBadge(source: sources[i].source),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sources[i].sourceId.isEmpty ? '—' : sources[i].sourceId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.mono.copyWith(
                        fontSize: 11,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (sources[i].rating > 0)
                    Text(
                      sources[i].rating.toStringAsFixed(1),
                      style: Type.mono.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: KisakiColors.ratingInk(dark),
                      ),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  // ============================ 右栏：主刊头、时长账本与正文 ============================

  Widget _buildRightColumn({
    required Game game,
    required List<SourceRecord> sources,
    required List<TagItem> tags,
    required bool tracking,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = Elev.border(dark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMastheadAndActions(
          game: game,
          sources: sources,
          tags: tags,
          tracking: tracking,
        ),
        const SizedBox(height: 22),
        Divider(height: 1, thickness: 1, color: borderColor),
        const SizedBox(height: 18),
        _PlaytimeLedgerStrip(game: game, tracking: tracking),
        const SizedBox(height: 18),
        Divider(height: 1, thickness: 1, color: borderColor),
        const SizedBox(height: 24),
        _buildSynopsisAndTrend(game: game, tracking: tracking),
      ],
    );
  }

  Widget _buildMastheadAndActions({
    required Game game,
    required List<SourceRecord> sources,
    required List<TagItem> tags,
    required bool tracking,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);

    final chips = <Widget>[
      KBadge(
        text: tracking ? '正在运行' : game.playStatus.label,
        color: tracking ? cyanInk : scheme.primary,
        icon: tracking ? Icons.bolt_rounded : Icons.bookmark_rounded,
      ),
      if (game.nsfw)
        const KBadge(
          text: 'R18',
          color: KisakiColors.danger,
          icon: Icons.explicit_rounded,
        ),
      for (final s in sources)
        if (s.rating > 0)
          PlatformRatingChip(
            label: KisakiSources.labels[s.source] ?? s.source,
            rating: s.rating,
            votes: s.voteCount,
          ),
      if (game.userRating > 0)
        PlatformRatingChip(label: '我的', rating: game.userRating),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 状态与平台评分角标行（与左栏返回键处于同一视觉水平线）
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: chips,
        ),
        const SizedBox(height: 12),
        // 作品主标题（宽幅排印，最多两行）
        Text(
          game.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Type.display.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.18,
          ),
        ),
        if (game.name.isNotEmpty && game.name != game.displayName) ...[
          const SizedBox(height: 4),
          Text(
            game.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.body.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 18),
        // 唯一核心动作栏：所有操作集中于此，不再与顶部争抢空间
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
                  ? Icons.sports_esports_rounded
                  : Icons.play_arrow_rounded,
              color: tracking ? cyanInk : scheme.primary,
              onTap: tracking ? null : () => _launch(game),
            ),
            KPill(
              label: '探索百科',
              icon: Icons.travel_explore_rounded,
              filled: false,
              onTap: () => _openExplorePage(game, sources),
            ),
            KPill(
              label: '游玩路径',
              icon: Icons.route_rounded,
              filled: false,
              onTap: _scrollToPlayPath,
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
              icon: Icons.rate_review_outlined,
              filled: false,
              onTap: () => _openRateDialog(game, sources),
            ),
            KPill(
              label: '编辑信息',
              icon: Icons.edit_outlined,
              filled: false,
              onTap: () => _openEditSheet(game),
            ),
            KIconAction(
              icon: game.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              tooltip: game.isFavorite ? '取消收藏' : '加入收藏',
              active: game.isFavorite,
              onTap: () async {
                game.isFavorite = !game.isFavorite;
                await AppServices.I.repo.updateGame(game);
                Future.delayed(const Duration(milliseconds: 450), () {
                  if (mounted) {
                    ref.read(libraryVersionProvider.notifier).state++;
                  }
                });
                if (mounted) setState(() {});
              },
            ),
            _MoreActionsMenu(
              onSaveBackup: () => SaveBackupDialog.show(context, game),
              onRescan: () => _rescan(game),
              onDelete: () => _confirmDelete(game),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in tags.take(_kTagLimit))
                KChip(
                  label: '#${t.name}',
                  color: cyanInk,
                  onTap: () => _jumpLibrary(tag: t.name),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSynopsisAndTrend({
    required Game game,
    required bool tracking,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KSectionTitle('作品简介'),
        if (game.summary.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '暂无故事简介，可点击上方「编辑信息」补充或通过「更多 → 重新刮削」自动获取。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          Text(
            game.summary,
            style: Type.body.copyWith(
              height: 1.74,
              color: dark ? KisakiColors.nightInk : KisakiColors.ink,
            ),
          ),
        if (game.userReview.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: dark
                  ? KisakiColors.nightContainer
                  : KisakiColors.paperContainer,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border(
                left: BorderSide(
                  color: KisakiColors.ratingInk(dark),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的评价',
                  style: Type.micro.copyWith(
                    color: KisakiColors.ratingInk(dark),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  game.userReview.trim(),
                  style: Type.body.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        KSectionTitle(
          '近 30 天游玩轨迹',
          accentColor: cyanInk,
        ),
        _DailyTrendChart(gameId: widget.gameId),
        const SizedBox(height: 30),
        KeyedSubtree(
          key: _playPathKey,
          child: _PlayPathSection(game: game, tracking: tracking),
        ),
      ],
    );
  }

  void _jumpLibrary({String? developer, String? tag}) {
    jumpToLibraryFiltered(ref, developer: developer, tag: tag);
    Navigator.of(context).pop();
  }

  Future<void> _launch(Game game) async {
    await GameLaunchService.launchAndTrack(game, ref);
    if (!mounted) return;
    setState(() {});
  }

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
        content: Text(
            '确定要从游戏库中删除「${game.displayName}」吗？\n游玩记录与统计将一并删除（游戏文件不受影响）。'),
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

  void _openExplorePage(Game game, List<SourceRecord> sources) {
    Navigator.of(context).push(
      FadeThroughRoute.builder(
        builder: (_) => GameExplorePage.fromLocalGame(
          game: game,
          sources: sources,
        ),
      ),
    );
  }

  Future<void> _openRateDialog(Game game, List<SourceRecord> sources) async {
    await Navigator.of(context).push(FadeThroughRoute.builder(
        builder: (_) => RateDialog(game: game, sources: sources)));
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(libraryVersionProvider.notifier).state++;
    });
  }

  Future<void> _openEditSheet(Game game) async {
    await Navigator.of(context)
        .push(FadeThroughRoute.builder(builder: (_) => EditSheet(game: game)));
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(libraryVersionProvider.notifier).state++;
    });
  }
}

// ============================ 左栏顶部轻巧返回键 ============================

class _BackToLibraryButton extends StatefulWidget {
  final VoidCallback onTap;
  const _BackToLibraryButton({required this.onTap});

  @override
  State<_BackToLibraryButton> createState() => _BackToLibraryButtonState();
}

class _BackToLibraryButtonState extends State<_BackToLibraryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final hoverFill = dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: FluidPressable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hover
                ? hoverFill
                : (dark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.72)),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: Elev.controlBorder(dark),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                size: 14,
                color: _hover ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '返回书库',
                style: Type.caption.copyWith(
                  color: _hover ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ 低频更多操作菜单 ============================

class _MoreActionsMenu extends StatelessWidget {
  final VoidCallback onSaveBackup;
  final VoidCallback onRescan;
  final VoidCallback onDelete;

  const _MoreActionsMenu({
    required this.onSaveBackup,
    required this.onRescan,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 36,
      height: 36,
      child: PopupMenuButton<String>(
        tooltip: '更多操作',
        padding: EdgeInsets.zero,
        iconSize: 18,
        position: PopupMenuPosition.under,
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: Elev.border(dark), width: 1),
          ),
          child: Icon(
            Icons.more_horiz_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: Elev.border(dark), width: 1),
        ),
        onSelected: (v) {
          switch (v) {
            case 'save':
              onSaveBackup();
            case 'rescan':
              onRescan();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'save',
            child: Row(
              children: [
                Icon(Icons.folder_zip_outlined, size: 17),
                SizedBox(width: 10),
                Text('存档备份与恢复'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'rescan',
            child: Row(
              children: [
                Icon(Icons.travel_explore_rounded, size: 17),
                SizedBox(width: 10),
                Text('重新刮削元数据'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline_rounded,
                    size: 17, color: KisakiColors.danger),
                const SizedBox(width: 10),
                Text(
                  '删除游戏',
                  style: Type.body.copyWith(color: KisakiColors.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ 左栏规格档案行 ============================

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final bool placeholder;
  final bool tabular;
  final VoidCallback? onTap;

  const _SpecRow({
    required this.label,
    required this.value,
    this.placeholder = false,
    this.tabular = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7.5),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: Type.caption.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: value,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: (tabular ? Type.mono : Type.label).copyWith(
                  color: placeholder
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.65)
                      : (onTap != null ? scheme.primary : scheme.onSurface),
                  fontWeight: placeholder ? FontWeight.w400 : FontWeight.w700,
                ),
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.north_east_rounded,
              size: 12,
              color: scheme.primary,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return FluidPressable(onTap: onTap, child: row);
  }
}

// ============================ 四格等宽游玩时长账本条 ============================

class _PlaytimeLedgerStrip extends StatefulWidget {
  final Game game;
  final bool tracking;

  const _PlaytimeLedgerStrip({
    required this.game,
    required this.tracking,
  });

  @override
  State<_PlaytimeLedgerStrip> createState() => _PlaytimeLedgerStripState();
}

class _PlaytimeLedgerStripState extends State<_PlaytimeLedgerStrip> {
  Timer? _t;
  int _live = 0;

  @override
  void initState() {
    super.initState();
    _live = AppServices.I.tracker.liveSeconds;
    if (widget.tracking) _startTicker();
  }

  @override
  void didUpdateWidget(_PlaytimeLedgerStrip old) {
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);
    final borderColor = Elev.border(dark);

    final g = widget.game;
    final sessions = g.sessionCount;
    final avg = sessions > 0 ? g.totalSeconds ~/ sessions : 0;
    final live = widget.tracking ? _live : AppServices.I.tracker.liveSeconds;

    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _LedgerCell(
              label: '累计总时长',
              value: g.totalSeconds > 0
                  ? fmtDuration(g.totalSeconds)
                  : _kEmptyValue,
              sub: sessions > 0 ? '共 $sessions 次会话' : '尚未开始',
              valueColor: scheme.primary,
            ),
          ),
          Container(width: 1, color: borderColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _LedgerCell(
                label: widget.tracking ? '本次运行中' : '本次时长',
                value: live > 0 ? fmtDuration(live) : _kEmptyValue,
                sub: widget.tracking ? '实时计时中' : '当前未运行',
                valueColor: cyanInk,
              ),
            ),
          ),
          Container(width: 1, color: borderColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _LedgerCell(
                label: '平均单次',
                value: avg > 0 ? fmtDuration(avg) : _kEmptyValue,
                sub: sessions > 0 ? '单次均值' : '暂无记录',
                valueColor: cyanInk,
              ),
            ),
          ),
          Container(width: 1, color: borderColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _LedgerCell(
                label: '上次游玩',
                value: g.lastPlayedAt == null
                    ? _kEmptyValue
                    : fmtDate(g.lastPlayedAt!),
                sub: g.firstPlayedAt == null
                    ? '尚无初见记录'
                    : '初见 ${fmtDate(g.firstPlayedAt!)}',
                valueColor: dark ? KisakiColors.nightInk : KisakiColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerCell extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color valueColor;

  const _LedgerCell({
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.caption.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedCount(
            text: value,
            style: Type.numeric.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ============================ 近 30 天趋势图 ============================

class _DailyTrendChart extends ConsumerWidget {
  final int gameId;
  const _DailyTrendChart({required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final color = KisakiColors.temporalInk(dark);

    return Container(
      height: _kTrendChartHeight,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: dark ? KisakiColors.nightCard : Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Elev.border(dark), width: 1),
      ),
      child: FutureBuilder<List<DailyPoint>>(
        future: _dailyPoints(),
        builder: (context, snap) {
          final points = snap.data ?? const <DailyPoint>[];
          final spots = <FlSpot>[];
          for (var i = 0; i < points.length; i++) {
            spots.add(FlSpot(i.toDouble(), points[i].seconds / 3600.0));
          }
          if (spots.isEmpty || spots.every((s) => s.y == 0)) {
            return Center(
              child: Text(
                '近 30 天暂无游玩记录',
                style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            );
          }
          return LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: Elev.border(dark),
                  strokeWidth: 1,
                ),
              ),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.32,
                  color: color,
                  barWidth: 2.2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.14),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                            '${points[s.x.toInt()].date}\n${fmtDuration(points[s.x.toInt()].seconds)}',
                            Type.mono.copyWith(
                              color: dark ? Colors.white : Colors.black,
                              fontSize: 11,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

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
void invalidateDailyTrend(int gameId) =>
    _DailyTrendChart._trendCache.remove(gameId);

/// 详情页杂志封面图版：悬停时纸面微抬升 + 封面微距放大。
class _InteractiveCoverPlate extends StatefulWidget {
  final Game game;
  final double width;
  final double height;

  const _InteractiveCoverPlate({
    required this.game,
    required this.width,
    required this.height,
  });

  @override
  State<_InteractiveCoverPlate> createState() => _InteractiveCoverPlateState();
}

class _InteractiveCoverPlateState extends State<_InteractiveCoverPlate> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = _hover
        ? scheme.primary.withValues(alpha: dark ? 0.55 : 0.42)
        : Elev.border(dark);
    final shadows = _hover
        ? Elev.cardHover(dark, scheme.primary)
        : Elev.card(dark, scheme.primary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.enter,
        width: widget.width,
        height: widget.height,
        transform: Matrix4.translationValues(0, _hover ? -2.0 : 0.0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: shadows,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md - 1),
          child: AnimatedScale(
            scale: _hover ? 1.022 : 1.0,
            duration: Motion.normal,
            curve: Motion.enter,
            child: CoverImage(
              path: widget.game.coverPath,
              nsfw: widget.game.nsfw,
              width: widget.width,
              height: widget.height,
              borderRadius: BorderRadius.circular(Radii.md - 1),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================ 游玩路径（截图时间线 & 笔记） ============================

class _PlayPathSection extends ConsumerStatefulWidget {
  final Game game;
  final bool tracking;

  const _PlayPathSection({required this.game, required this.tracking});

  @override
  ConsumerState<_PlayPathSection> createState() => _PlayPathSectionState();
}

class _PlayPathSectionState extends ConsumerState<_PlayPathSection> {
  String _hotkey = 'F12';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadHotkey();
  }

  Future<void> _loadHotkey() async {
    try {
      final key = await AppServices.I.settings.getString(
        SettingsStore.kScreenshotHotkey,
        'F12',
      );
      if (mounted) {
        setState(() => _hotkey = key);
      }
    } catch (_) {}
  }

  String _hotkeyLabel() {
    return switch (_hotkey) {
      'disabled' => '已关闭快捷键（可点右侧按钮手动截取或写笔记）',
      'PrintScreen' => 'PrtSc',
      _ => _hotkey,
    };
  }

  Future<void> _captureNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppServices.I.tracker.captureCurrentGameWindow(
        expectedGameId: widget.game.id,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTextNote() async {
    final result = await _showNoteDialog(context);
    if (result == null) return;
    await AppServices.I.repo.addPlayPathNode(
      gameId: widget.game.id!,
      imagePath: result.imagePath,
      note: result.note,
    );
    if (!mounted) return;
    ref.read(playPathVersionProvider.notifier).state++;
    showNotice('已添加游玩路径笔记');
  }

  Future<void> _importImageNote() async {
    final pickedPath = await _pickAndCopyImage(widget.game.id!);
    if (pickedPath == null || !mounted) return;
    final result = await _showNoteDialog(
      context,
      initialImagePath: pickedPath,
      allowEmptyNoteWithImage: true,
    );
    if (result == null) {
      // 用户取消创建，清理刚刚拷贝进去的临时图
      try {
        final f = File(pickedPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return;
    }
    await AppServices.I.repo.addPlayPathNode(
      gameId: widget.game.id!,
      imagePath: result.imagePath,
      note: result.note,
    );
    if (!mounted) return;
    ref.read(playPathVersionProvider.notifier).state++;
    showNotice('已保存游玩路径图文记录');
  }

  Future<void> _editNode(PlayPathNode node) async {
    final result = await _showNoteDialog(
      context,
      initialNote: node.note,
      initialImagePath: node.resolvedImagePath,
      allowEmptyNoteWithImage: node.imagePath.isNotEmpty,
    );
    if (result == null) return;
    node.note = result.note;
    if (result.imagePath.isNotEmpty) {
      node.imagePath = AppServices.I.paths.toStored(result.imagePath);
    }
    await AppServices.I.repo.updatePlayPathNode(node);
    if (!mounted) return;
    ref.read(playPathVersionProvider.notifier).state++;
    showNotice('已更新游玩路径笔记');
  }

  Future<void> _deleteNode(PlayPathNode node) async {
    final ok = await showKisakiDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除游玩路径节点'),
        content: const Text('确定删除这条记录吗？关联截图也会一并移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: KisakiColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || node.id == null) return;
    await AppServices.I.repo.deletePlayPathNode(node.id!);
    if (!mounted) return;
    ref.read(playPathVersionProvider.notifier).state++;
    showNotice('已删除游玩路径节点');
  }

  Future<String?> _pickAndCopyImage(int gameId) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: '选择游戏截图或 CG 图片',
    );
    final src = res?.files.single.path;
    if (src == null || src.isEmpty) return null;
    final ext = p.extension(src).toLowerCase();
    final safeExt = ext.isEmpty ? '.png' : ext;
    final destDir = Directory(p.join(AppServices.I.paths.playPath, '$gameId'));
    destDir.createSync(recursive: true);
    final dest = p.join(
      destDir.path,
      '${DateTime.now().millisecondsSinceEpoch}$safeExt',
    );
    await File(src).copy(dest);
    return dest;
  }

  Future<({String note, String imagePath})?> _showNoteDialog(
    BuildContext context, {
    String initialNote = '',
    String initialImagePath = '',
    bool allowEmptyNoteWithImage = false,
  }) {
    return showKisakiDialog<({String note, String imagePath})>(
      context: context,
      builder: (_) => _PlayPathNoteDialog(
        initialNote: initialNote,
        initialImagePath: initialImagePath,
        allowEmptyNoteWithImage: allowEmptyNoteWithImage,
        onPickImage: () => _pickAndCopyImage(widget.game.id!),
      ),
    );
  }

  Future<void> _previewImage(BuildContext context, String path, String note) {
    return showKisakiDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 780),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.photo_library_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.label,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.file(File(path), fit: BoxFit.contain),
                    ),
                  ),
                ),
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    note.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final asyncNodes = ref.watch(playPathProvider(widget.game.id!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KSectionTitle(
          '游玩路径',
          accentColor: KisakiColors.m3Peach,
          trailing: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (widget.tracking)
                KPill(
                  label: _busy ? '截图中…' : '截取当前画面',
                  icon: Icons.camera_alt_outlined,
                  color: KisakiColors.m3Rose,
                  onTap: _busy ? null : _captureNow,
                ),
              KPill(
                label: '添加图文',
                icon: Icons.add_photo_alternate_outlined,
                filled: false,
                onTap: _importImageNote,
              ),
              KPill(
                label: '写笔记',
                icon: Icons.edit_note_rounded,
                filled: false,
                onTap: _addTextNote,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              KBadge(
                text: '快捷键 ${_hotkeyLabel()}',
                color: KisakiColors.m3Lavender,
                icon: Icons.keyboard_rounded,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '游玩时按下截图键自动采集游戏窗口并保存至本地，支持随时补充图文心得',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        asyncNodes.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: KLoading(),
          ),
          error: (e, _) => Text('加载游玩路径失败：$e', style: Type.caption),
          data: (nodes) {
            if (nodes.isEmpty) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                decoration: BoxDecoration(
                  color: dark
                      ? KisakiColors.nightContainer
                      : const Color(0xFFFAF4F7),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(color: Elev.border(dark)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            KisakiColors.m3Rose.withValues(alpha: 0.25),
                            KisakiColors.m3Peach.withValues(alpha: 0.25),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                      child: Icon(
                        Icons.route_rounded,
                        size: 20,
                        color: KisakiColors.roseInk(dark),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '还没有任何游玩足迹。游玩时按下 ${_hotkeyLabel()} 可快速抓取精彩瞬间，也可以点右上角手动写笔记或添加图片。',
                        style: Type.body.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < nodes.length; i++)
                  _PlayPathTimelineTile(
                    node: nodes[i],
                    isLast: i == nodes.length - 1,
                    dark: dark,
                    onPreviewImage: (path) =>
                        _previewImage(context, path, nodes[i].note),
                    onEdit: () => _editNode(nodes[i]),
                    onDelete: () => _deleteNode(nodes[i]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PlayPathTimelineTile extends StatelessWidget {
  final PlayPathNode node;
  final bool isLast;
  final bool dark;
  final ValueChanged<String> onPreviewImage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlayPathTimelineTile({
    required this.node,
    required this.isLast,
    required this.dark,
    required this.onPreviewImage,
    required this.onEdit,
    required this.onDelete,
  });

  String _formatDateTime(DateTime dt) {
    final l = dt.toLocal();
    final y = l.year;
    final mo = l.month.toString().padLeft(2, '0');
    final d = l.day.toString().padLeft(2, '0');
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    final s = l.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imgPath = node.resolvedImagePath;
    final hasImage = imgPath.isNotEmpty && cachedFileExists(imgPath);
    final dotColor = hasImage ? KisakiColors.m3Rose : KisakiColors.m3Peach;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间轴轨线
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    border: Border.all(
                      color: dotColor.withValues(alpha: 0.35),
                      width: 2.5,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            KisakiColors.m3Rose.withValues(alpha: 0.45),
                            KisakiColors.m3Lavender.withValues(alpha: 0.35),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 4 : 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark
                    ? KisakiColors.nightContainer
                    : KisakiColors.paperElevated,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: Elev.border(dark)),
                boxShadow: Elev.card(dark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      KBadge(
                        text: hasImage ? '截图时刻' : '文字笔记',
                        color: hasImage
                            ? KisakiColors.m3Lavender
                            : KisakiColors.m3Peach,
                        icon: hasImage
                            ? Icons.photo_camera_outlined
                            : Icons.notes_rounded,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDateTime(node.createdAt),
                        style: Type.mono.copyWith(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: '编辑笔记',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.full),
                          onTap: onEdit,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: '删除节点',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.full),
                          onTap: onDelete,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: KisakiColors.danger.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hasImage) ...[
                    const SizedBox(height: 10),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => onPreviewImage(imgPath),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.md),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 240,
                              minWidth: 160,
                            ),
                            child: Image.file(
                              File(imgPath),
                              fit: BoxFit.cover,
                              cacheWidth: 960,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (node.note.trim().isNotEmpty)
                    Text(
                      node.note.trim(),
                      style: Type.body.copyWith(
                        height: 1.62,
                        color: scheme.onSurface,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: onEdit,
                      child: Text(
                        '点击此处或右上角「编辑笔记」，写下此刻的剧情感受或分支备注…',
                        style: Type.caption.copyWith(
                          color: dark
                              ? KisakiColors.nightInkSoft
                              : KisakiColors.inkSoft,
                          fontStyle: FontStyle.italic,
                        ),
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
}

class _PlayPathNoteDialog extends StatefulWidget {
  final String initialNote;
  final String initialImagePath;
  final bool allowEmptyNoteWithImage;
  final Future<String?> Function() onPickImage;

  const _PlayPathNoteDialog({
    required this.initialNote,
    required this.initialImagePath,
    required this.allowEmptyNoteWithImage,
    required this.onPickImage,
  });

  @override
  State<_PlayPathNoteDialog> createState() => _PlayPathNoteDialogState();
}

class _PlayPathNoteDialogState extends State<_PlayPathNoteDialog> {
  late final TextEditingController _ctrl;
  late String _imgPath;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNote);
    _imgPath = widget.initialImagePath;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasImg = _imgPath.isNotEmpty && File(_imgPath).existsSync();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Text(widget.initialNote.isEmpty ? '新建游玩路径节点' : '编辑游玩路径笔记'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImg) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: Image.file(
                      File(_imgPath),
                      fit: BoxFit.contain,
                      cacheWidth: 960,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  KPill(
                    label: hasImg ? '更换图片' : '附带截图…',
                    icon: Icons.image_outlined,
                    filled: false,
                    onTap: () async {
                      final copied = await widget.onPickImage();
                      if (copied != null && mounted) {
                        setState(() => _imgPath = copied);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasImg ? p.basename(_imgPath) : '可留空作为纯文字节点',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.caption.copyWith(
                        color: dark
                            ? KisakiColors.nightInkSoft
                            : KisakiColors.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                minLines: 4,
                maxLines: 9,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '游玩笔记 / 剧情备忘',
                  hintText: '记录当前路线选择、伏笔线索或心情感受…',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final text = _ctrl.text.trim();
            if (text.isEmpty &&
                !widget.allowEmptyNoteWithImage &&
                _imgPath.isEmpty) {
              return;
            }
            Navigator.pop(context, (note: text, imagePath: _imgPath));
          },
          child: const Text('保存节点'),
        ),
      ],
    );
  }
}
