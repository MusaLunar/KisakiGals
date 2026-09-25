/// 游戏详情页：背景图（可换/可调模糊）、Hero、游玩记录、简介与趋势、标签、数据来源、启动。
///
/// 全屏路由页：保留 Scaffold + AppTitleBar；内容卡片统一走 kit 的
/// KCard / KStat / KRow / KChip，有背景图时卡片改用毛玻璃（glass: true）。
///
/// 本轮排版优化的四条主线：
/// 1. **单左基线**：顶栏、封面、各分区标题一律从内容左边界起排。旧实现把
///    简介/趋势/来源区块左缩进 244 去「对齐右侧信息列」，结果页面同时存在
///    24 与 268 两条左基线，封面列下方还空出一大片；现在 Hero 之后的分区
///    横向铺满内容宽度，左右边界统一。
/// 2. **分组节奏**：Hero 之外用 KSectionTitle 分四组（游玩记录 / 简介与趋势 /
///    标签 / 数据来源）；组内间距走 Gap.titleToContent（KSectionTitle 默认
///    bottom padding 12），组间走 Gap.sectionGap（28）。
/// 3. **断点**：窗口宽 < [_kWideBreakpoint] 时封面降为 160×240、简介与趋势
///    上下堆叠、统计卡按可用宽度减列（本页是全屏路由，页面宽即窗口宽）。
/// 4. **空值**：统一「—」占位（大数字位不塌陷、数值列仍对齐）+ 小号灰字
///    说明（KStat 的 hint / _MetaLine 的 placeholder）。
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

// ============================ 本页数值 ============================

/// 宽/窄布局断点（按**窗口宽度**判断；窗口最小尺寸 1080×680，见 main.dart）。
const double _kWideBreakpoint = 1100;

/// 内容最大宽度：超宽屏下居中，避免信息行被拉成一条长线（与 KPage 的
/// maxContentWidth 同一思路，取值贴合默认窗口 1280）。
const double _kContentMaxWidth = 1280;

/// Hero 封面尺寸：宽布局 220×310、窄布局 160×240（封面标准 2:3）。
const double _kCoverWidthWide = 220;
const double _kCoverHeightWide = 310;
const double _kCoverWidthNarrow = 160;
const double _kCoverHeightNarrow = 240;

/// 趋势图区固定高度；简介卡正文取同一最小值，使并排两卡等高。
const double _kTrendChartHeight = 140;

/// 统计卡最小可用宽度：不足时 3 列 → 2 列 → 1 列，避免标签/数值被挤压。
const double _kStatMinWidth = 230;

/// 标签最多展示数量（超出不展示，避免撑满整页）。
const int _kTagLimit = 18;

/// 作品信息行的标签列宽（四行数值左对齐成一列）。
const double _kMetaLabelWidth = 62;

/// 空数值占位：占住大数字位（数值列对齐），具体说明放 KStat 的 hint。
const String _kEmptyValue = '—';

/// 「本次」统计卡的强调色（青绿；与总时长粉、平均单次紫区分）。
const Color _kLiveAccent = Color(0xFF7EC8C3);

class GameDetailPage extends ConsumerStatefulWidget {
  final int gameId;

  /// 调用方（游戏库/主页/搜索）已有的数据：传入后立即渲染，避免先闪一下加载态
  final Game? initial;
  const GameDetailPage({super.key, required this.gameId, this.initial});

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  /// 滚动控制器：Scrollbar 常驻显示需要显式控制器（不依赖 Primary）。
  final ScrollController _scroll = ScrollController();

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
  ///
  /// 结构：背景层 → 顶栏 → Hero（封面 + 信息列）→ 四个分区。
  Widget _buildDetail(BuildContext context, Game game, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tracking = ref.watch(trackingGameProvider) == widget.gameId;
    final sources =
        ref.watch(gameSourcesProvider(widget.gameId)).valueOrNull ?? [];
    final tags = ref.watch(gameTagsProvider(widget.gameId)).valueOrNull ?? [];
    final bgBlur = ref.watch(detailBgBlurProvider);
    // 背景图同样可能存的是相对路径（换设备迁移后需解析）
    final bgPath = game.backgroundUrl.isEmpty
        ? ''
        : AppServices.I.paths.resolveStored(game.backgroundUrl);
    // 有背景图时卡片全部改用毛玻璃，保证与背景的对比度
    final glass = cachedFileExists(bgPath);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 底色：主题背景色（不再依赖 Mica 透明）
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          // 背景层：用户选择的截图
          if (glass)
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
          if (glass)
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
            child: LayoutBuilder(
              builder: (context, pageC) {
                // 本页是全屏路由：页面宽即窗口宽，断点直接按页宽判定
                final wide = pageC.maxWidth >= _kWideBreakpoint;
                // 错落进场序号（可按分区顺序递增，最多 12 项）
                var stagger = 0;
                return Column(
                  children: [
                    // 顶部拖动条：横跨整宽，空白处即可拖动窗口
                    const AppTitleBar(),
                    Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        // 常驻滚动条：避免「内容被裁但看不出还能滚」
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(
                              Gap.pageH, 0, Gap.pageH, Gap.huge),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: _kContentMaxWidth),
                              child: Column(
                                // stretch：让每个分区横向铺满内容宽度，
                                // 顶栏 / 封面 / 分区标题共用同一条左基线
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _topBar(game, tracking),
                                  const SizedBox(height: Gap.sm),
                                  // ---- Hero：封面 + 信息列 ----
                                  StaggeredFadeIn(
                                    // key：标签是异步加载的，插入新区块时
                                    // 避免元素按位置复用导致重复/漏播进场
                                    key: const ValueKey('hero'),
                                    index: stagger++,
                                    child: _hero(game, sources, tracking, wide, tags,
                                        glass),
                                  ),
                                  const SizedBox(height: Gap.sectionGap),
                                  // ---- 分区：游玩记录 ----
                                  StaggeredFadeIn(
                                    key: const ValueKey('playtime'),
                                    index: stagger++,
                                    child: _Section(
                                      title: '游玩记录',
                                      child: _PlaytimeStats(
                                        game: game,
                                        tracking: tracking,
                                        glass: glass,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: Gap.sectionGap),
                                  // ---- 分区：简介与趋势 ----
                                  StaggeredFadeIn(
                                    key: const ValueKey('summary'),
                                    index: stagger++,
                                    child: _summaryTrendSection(
                                        game, wide, glass),
                                  ),
                                  // 标签已并入 Hero 信息列（信息行下方、操作按钮上方），
                                  // 不再单独占一个分区
                                  const SizedBox(height: Gap.sectionGap),
                                  // ---- 分区：数据来源 ----
                                  StaggeredFadeIn(
                                    key: const ValueKey('sources'),
                                    index: stagger++,
                                    child: _sourcesSection(game, sources, glass),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================ Hero ============================

  /// 顶栏：返回 / 收藏 / 编辑信息 / 更多（存档备份、重新刮削、删除游戏）。
  Widget _topBar(Game game, bool tracking) {
    final scheme = Theme.of(context).colorScheme;
    return KToolbar(
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
        // 更多菜单：外框固定 38×38、内边距清零，与 KIconAction 同尺寸
        //（IconButton 默认 48 的热区会让 ⋯ 比右侧卡片边界再往外探 16px，
        // 顶栏右边界与下方卡片对不齐）；左侧 6 对齐 KIconAction 的 margin
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: SizedBox(
            width: 38,
            height: 38,
            child: PopupMenuButton<String>(
              tooltip: '更多',
              padding: EdgeInsets.zero,
              iconSize: 19,
              position: PopupMenuPosition.under,
              icon: Icon(Icons.more_horiz_rounded,
                  color: scheme.onSurfaceVariant),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.md)),
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
                    child:
                        Text('删除游戏', style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Hero：封面（220×310 / 窄窗口 160×240）+ 右侧信息列
  /// （游戏名、原名副标题、评分与徽标行、作品信息行、操作按钮）。
  ///
  /// 两列都顶对齐；间距 Gap.xl 让封面与信息列成组，而不是松散并排。
  Widget _hero(Game game, List<SourceRecord> sources, bool tracking, bool wide,
      List<TagItem> tags,
      bool glass) {
    final scheme = Theme.of(context).colorScheme;
    final coverW = wide ? _kCoverWidthWide : _kCoverWidthNarrow;
    final coverH = wide ? _kCoverHeightWide : _kCoverHeightNarrow;

    // 平台评分 chip + 我的评分 + 状态徽标（收藏 / R18）；空行不占位
    final chips = <Widget>[
      for (final s in sources)
        if (s.rating > 0)
          PlatformRatingChip(
            label: KisakiSources.labels[s.source] ?? s.source,
            rating: s.rating,
            votes: s.voteCount,
          ),
      if (game.userRating > 0)
        PlatformRatingChip(label: '我的', rating: game.userRating),
      if (game.isFavorite)
        const KBadge(
            text: '收藏',
            color: KisakiColors.pink,
            icon: Icons.favorite_rounded),
      if (game.nsfw)
        const KBadge(
            text: 'R18',
            color: KisakiColors.danger,
            icon: Icons.explicit_rounded),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverImage(
          path: game.coverPath,
          nsfw: game.nsfw,
          width: coverW,
          height: coverH,
          borderRadius: BorderRadius.circular(wide ? Radii.lg : Radii.md),
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
                style: Type.display,
              ),
              // 显示中文名为主标题时，副标题补上原始名称（二者不同才显示）
              if (game.name.isNotEmpty && game.name != game.displayName)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.xs),
                  child: Text(
                    game.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: chips,
                ),
              ],
              const SizedBox(height: Gap.lg),
              // 作品信息：紧凑单行，标签列固定宽度使四行数值左对齐
              _MetaLine(
                icon: Icons.business_rounded,
                label: '开发商',
                value: game.developer.isEmpty ? '未知' : game.developer,
                placeholder: game.developer.isEmpty,
                onTap: game.developer.isEmpty
                    ? null
                    : () => _jumpLibrary(developer: game.developer),
              ),
              _MetaLine(
                icon: Icons.event_rounded,
                label: '发售日期',
                value: game.releaseDate.isEmpty ? '未知' : game.releaseDate,
                placeholder: game.releaseDate.isEmpty,
              ),
              _MetaLine(
                icon: Icons.history_rounded,
                label: '上次游玩',
                value: game.lastPlayedAt == null
                    ? '尚未游玩'
                    : fmtDateTime(game.lastPlayedAt!),
                placeholder: game.lastPlayedAt == null,
              ),
              _MetaLine(
                icon: Icons.folder_rounded,
                label: '目录',
                value: game.directory.isEmpty ? '未指定' : game.directory,
                placeholder: game.directory.isEmpty,
              ),
              // 标签并入信息列（原先单独占一个整宽分区，离作品信息太远）
              if (tags.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                _tagChips(tags),
              ],
              const SizedBox(height: Gap.lg),
              // 操作按钮：启动/继续（计时中禁用）、打开目录、评分评价
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

  // ============================ 分区 ============================

  /// 简介与趋势：宽窗口左右并排（简介 3 : 趋势 2），窄窗口上下堆叠。
  ///
  /// 两张卡都用 KCard（有背景图时 glass）；卡内标题用 [_CardHeader]，
  /// 比分区标题轻一档，形成「分区标题 → 卡内标题 → 正文」的层级。
  Widget _summaryTrendSection(Game game, bool wide, bool glass) {
    final summaryCard = KCard(
      glass: glass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡内标题沿用原先的措辞（'简介' / '近 30 天游玩趋势'），
          // 只降一档字重与颜色，让分区标题承担分组信息
          const _CardHeader(icon: Icons.menu_book_rounded, text: '简介'),
          const SizedBox(height: Gap.md),
          // 正文区取与趋势图相同的最小高度：并排时两卡等高，
          // 简介为空/很短也不会塌成一条
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _kTrendChartHeight),
            child: game.summary.isEmpty
                ? const KEmpty(
                    compact: true,
                    icon: Icons.notes_rounded,
                    title: '暂无简介',
                    subtitle: '可在「编辑信息」里补充，或重新刮削获取',
                  )
                : Text(
                    game.summary,
                    style: Type.body.copyWith(height: 1.7),
                  ),
          ),
        ],
      ),
    );
    final trendCard = _DailyTrendCard(gameId: widget.gameId, glass: glass);

    return _Section(
      title: '简介与趋势',
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: summaryCard),
                const SizedBox(width: Gap.lg),
                Expanded(flex: 2, child: trendCard),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summaryCard,
                const SizedBox(height: Gap.md),
                trendCard,
              ],
            ),
    );
  }

  /// 标签：点击回游戏库并按该标签筛选。
  /// 标签 chip 行（放在信息列内；原先是整宽分区）
  Widget _tagChips(List<TagItem> tags) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('标签',
            style: Type.micro.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        const SizedBox(height: Gap.xs + 2),
        Wrap(
          spacing: Gap.xs + 2,
          runSpacing: Gap.xs + 2,
          children: [
            for (final t in tags.take(_kTagLimit))
              KChip(
                label: t.name,
                icon: Icons.local_offer_outlined,
                color: KisakiColors.lavender,
                onTap: () => _jumpLibrary(tag: t.name),
              ),
          ],
        ),
      ],
    );
  }

  /// 数据来源（各平台条目 id 与评分）+ 重新刮削入口。
  Widget _sourcesSection(Game game, List<SourceRecord> sources, bool glass) {
    return _Section(
      title: '数据来源',
      trailing: TextButton.icon(
        onPressed: () => _rescan(game),
        icon: const Icon(Icons.travel_explore_rounded, size: 16),
        label: const Text('重新刮削'),
      ),
      child: KCard(
        glass: glass,
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
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

// ============================ 页面内小原语 ============================

/// 分区：标题 + 内容。
///
/// 组内间距由 KSectionTitle 的默认 bottom padding（Gap.titleToContent）承担；
/// 无右侧动作时用 `reserveSlot` 把标题行撑到 38 高 —— 否则带 TextButton 的
/// 分区标题行更高，各分区「标题 → 内容」的距离会不一致。
class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _Section({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KSectionTitle(title, trailing: trailing, reserveSlot: trailing == null),
        child,
      ],
    );
  }
}

/// 卡内小标题：图标 + 小号次要色文字。
/// 比 KSectionTitle（13.5 / w700 / 主文字色）轻一档，用于卡片内部再分组。
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CardHeader({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: Gap.sm),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.label.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// 作品信息行：图标 + 标签（固定列宽）+ 值（单行省略，悬停显示全文）。
///
/// 比 KRow 更紧凑：一行一项、四行连排；标签列固定宽度使数值左对齐成列。
/// 空值（未指定/未知/尚未游玩）用小号灰字，与真值拉开层级。
class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// 值的占位态（空值）：用小号灰字，避免与真值同级
  final bool placeholder;
  final VoidCallback? onTap;

  const _MetaLine({
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InteractiveSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      color: Colors.transparent,
      outline: scheme.primary,
      // 行式条目：只保留 hover 描边与按压回弹（与主页推荐行一致），不投影
      borderOnIdle: false,
      elevated: false,
      lift: 0,
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: Gap.sm),
          SizedBox(
            width: _kMetaLabelWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            // 单行省略：全文放 tooltip，长目录/长开发商名不丢信息
            child: Tooltip(
              message: value,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: placeholder
                    ? Type.caption.copyWith(color: scheme.onSurfaceVariant)
                    : Type.label,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: Gap.xs),
            Icon(Icons.arrow_forward_rounded, size: 13, color: scheme.primary),
          ],
        ],
      ),
    );
  }
}

// ============================ 游玩记录 ============================

/// 游玩记录：总时长 / 本次 / 平均单次。
///
/// - 三卡按可用宽度自动 3 → 2 → 1 列（窄窗口不再把标签与数值挤成一团）；
/// - 「本次」在计时中每秒跳动：计时器只重建这一块，不带动整页；
/// - 空值统一「—」占位 + 小号灰字说明，数值列保持对齐。
class _PlaytimeStats extends StatefulWidget {
  final Game game;
  final bool tracking;
  final bool glass;
  const _PlaytimeStats(
      {required this.game, required this.tracking, this.glass = false});

  @override
  State<_PlaytimeStats> createState() => _PlaytimeStatsState();
}

class _PlaytimeStatsState extends State<_PlaytimeStats> {
  Timer? _t;
  int _live = 0;

  @override
  void initState() {
    super.initState();
    _live = AppServices.I.tracker.liveSeconds;
    if (widget.tracking) _startTicker();
  }

  @override
  void didUpdateWidget(_PlaytimeStats old) {
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
    // 计时中取本块实时秒数，否则取计时器残留值（会话结束后为 0）
    final live = widget.tracking ? _live : AppServices.I.tracker.liveSeconds;

    final cards = <Widget>[
      KStat(
        glass: widget.glass,
        icon: Icons.timer_outlined,
        accent: KisakiColors.pink,
        label: '总时长',
        value: g.totalSeconds > 0 ? fmtDuration(g.totalSeconds) : _kEmptyValue,
        hint: g.lastPlayedAt == null
            ? '暂无记录'
            : '上次 ${fmtDate(g.lastPlayedAt!)}',
      ),
      KStat(
        glass: widget.glass,
        icon: Icons.play_circle_outline_rounded,
        accent: _kLiveAccent,
        label: widget.tracking ? '本次游玩' : '本次',
        value: live > 0 ? fmtDuration(live) : _kEmptyValue,
        hint: widget.tracking
            ? '计时中…'
            : (sessions > 0 ? '共 $sessions 次' : '暂无记录'),
      ),
      KStat(
        glass: widget.glass,
        icon: Icons.insights_rounded,
        accent: KisakiColors.lavender,
        label: '平均单次',
        value: avg > 0 ? fmtDuration(avg) : _kEmptyValue,
        hint: sessions > 0 ? '共 $sessions 次游玩' : '暂无记录',
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        // 单卡低于 _kStatMinWidth 就先减列（3 → 2 → 1）
        final columns = c.maxWidth >= _kStatMinWidth * 3 + Gap.md * 2
            ? 3
            : (c.maxWidth >= _kStatMinWidth * 2 + Gap.md ? 2 : 1);
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += columns) ...[
              if (i > 0) const SizedBox(height: Gap.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: Gap.md),
                    // 末行不足时补等宽空位：卡片宽度始终一致
                    Expanded(
                      child: i + j < cards.length
                          ? cards[i + j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

// ============================ 趋势图 ============================

/// 近 30 天游玩趋势（宽窗口在简介右侧，窄窗口堆叠到简介下方）。
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
          const _CardHeader(
              icon: Icons.show_chart_rounded, text: '近 30 天游玩趋势'),
          const SizedBox(height: Gap.md),
          SizedBox(
            height: _kTrendChartHeight,
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

// ============================ 运行态 ============================

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
