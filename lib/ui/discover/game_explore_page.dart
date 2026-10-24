/// 游戏探索百科页（参考 `Ph-Rank/The-Order` 的现代化全景百科架构）.
///
/// 排版重构要点（解决拥挤感，形成呼吸感与层次感）：
/// 1. **全景横幅与沉浸舞台 (`_HeroStage`)**：
///    - 顶部全景 CG 宽幅横幅，底部渐变融合于 `KisakiColors.pageSurface` 连续纸面；
///    - 封面悬浮图版（2:3 比例、160×240、利落裁切与深度微投影）；
///    - 状态行中 **R18 标记置于评分前面**（WCAG 高对比危险专色）；
///    - 多站点评分胶囊（鲲Gal / VNDB / Bangumi / 批评空间 / DLsite）独立成组，点击直达对应原站；
///    - 核心规格（开发商、发行商、发售日、引擎、系列）以杂志规格表排印，清晰开阔。
/// 2. **顶层多维工作台 Tab 栏 (Top-Level Segmented Workspace)**：
///    - 将「百科资料」「媒体画廊」「动画」「音乐」「漫画」「轻小说」「资源下载」提升为顶层平级 Tab；
///    - 彻底消除旧版在纵向长页面中间嵌套子 Tab 导致的拥挤与割裂；
///    - 每个 Tab 附带实时计数角标，带流畅切换过渡。
/// 3. **百科资料长页右侧小悬浮定位窗 (`FloatingAnchorNav`)**：
///    - 在百科资料页右侧浮动定位胶囊，可随时点击跳转「故事简介」「角色与声优」「发行资料」「制作人员」「相关游戏」；
///    - 滚动时自动高亮当前所在章节，可一键平滑回到顶部。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../../services/game_explore_service.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../kit.dart';
import '../shell/title_bar.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/floating_anchor_nav.dart';
import '../widgets/notifications.dart';
import 'discover_state.dart';
import 'resource_links.dart';

/// 探索百科主工作区 Tab 枚举
enum ExplorePageTab {
  overview('百科资料', Icons.library_books_rounded),
  media('媒体画廊', Icons.collections_rounded),
  anime('动画', Icons.movie_filter_rounded),
  music('音乐', Icons.album_rounded),
  manga('漫画', Icons.menu_book_rounded),
  novel('轻小说', Icons.auto_stories_rounded),
  download('资源下载', Icons.cloud_download_rounded);

  final String label;
  final IconData icon;
  const ExplorePageTab(this.label, this.icon);
}

Color _surfaceLevel(int level, bool dark) {
  if (level <= 1) {
    return dark ? KisakiColors.nightCard : KisakiColors.creamCard;
  }
  return dark ? KisakiColors.nightContainer : KisakiColors.paperContainer;
}

Color _borderStrong(bool dark) => dark
    ? Colors.white.withValues(alpha: 0.16)
    : const Color(0xFF16151A).withValues(alpha: 0.16);

List<BoxShadow> _boxShadow(int level, bool dark) => level >= 3
    ? Elev.overlay(dark)
    : Elev.card(dark, KisakiColors.outline(dark));

class GameExplorePage extends ConsumerStatefulWidget {
  final ScrapedGame seedGame;
  final List<SourceRecord> knownSources;
  final int? localGameId;
  final Future<void> Function(ScrapedGame)? onAdd;
  final ExplorePageTab initialTab;

  const GameExplorePage({
    super.key,
    required this.seedGame,
    this.knownSources = const [],
    this.localGameId,
    this.onAdd,
    this.initialTab = ExplorePageTab.overview,
  });

  /// 从本地入库游戏 (`GameDetailPage`) 打开游戏探索百科页
  factory GameExplorePage.fromLocalGame({
    Key? key,
    required Game game,
    required List<SourceRecord> sources,
    ExplorePageTab initialTab = ExplorePageTab.overview,
  }) {
    return GameExplorePage(
      key: key,
      seedGame: GameExploreService.seedFromLocalGame(game, sources),
      knownSources: sources,
      localGameId: game.id,
      initialTab: initialTab,
    );
  }

  @override
  ConsumerState<GameExplorePage> createState() => _GameExplorePageState();
}

class _GameExplorePageState extends ConsumerState<GameExplorePage> {
  final ScrollController _scroll = ScrollController();

  // 章节锚点定位 Key（用于悬浮定位窗）
  final GlobalKey _synopsisKey = GlobalKey();
  final GlobalKey _charsKey = GlobalKey();
  final GlobalKey _releasesKey = GlobalKey();
  final GlobalKey _staffKey = GlobalKey();
  final GlobalKey _relatedKey = GlobalKey();

  ExploreWorkDetail? _detail;
  bool _loading = true;
  String? _error;
  late ExplorePageTab _activeTab;
  bool _adding = false;

  // 局部开关与筛选
  bool _showAliases = false;
  bool _expandSynopsis = false;
  bool _showSpoilers = false;
  String _charRoleFilter = 'all'; // 'all' | 'main' | 'secondary'
  String _releaseLangFilter = 'all'; // 'all' | 'zh' | 'ja' | 'en'

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    final cached = GameExploreService.instance.getCached(
      widget.seedGame,
      knownSources: widget.knownSources,
    );
    if (cached != null) {
      _detail = cached;
      _loading = false;
    } else {
      _load(forceRefresh: false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool forceRefresh}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await GameExploreService.instance.loadWorkDetail(
        widget.seedGame,
        knownSources: widget.knownSources,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _detail = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final clean = rawUrl.trim();
    if (clean.isEmpty) return;
    final uri = Uri.tryParse(clean);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showNotice('无法打开链接：$clean', error: true);
      }
    } catch (e) {
      if (mounted) showNotice('打开链接失败：$e', error: true);
    }
  }

  Game? _findInLibrary(Map<String, Game> index) {
    final d = _detail;
    if (d != null) {
      if (d.nextmoeId.isNotEmpty) {
        final hit = index['${KisakiSources.kun}:${d.nextmoeId}'];
        if (hit != null) return hit;
      }
      if (d.bangumiId.isNotEmpty) {
        final hit = index['${KisakiSources.bangumi}:${d.bangumiId}'];
        if (hit != null) return hit;
      }
      if (d.vndbId.isNotEmpty) {
        final hit = index['${KisakiSources.vndb}:${d.vndbId}'];
        if (hit != null) return hit;
      }
    }
    return index[discoverLibraryKey(widget.seedGame)];
  }

  Future<void> _handleAddToLibrary() async {
    if (_adding) return;
    final target = _detail?.enrichedScrapedGame ?? widget.seedGame;
    if (widget.onAdd != null) {
      setState(() => _adding = true);
      try {
        await widget.onAdd!(target);
      } finally {
        if (mounted) setState(() => _adding = false);
      }
      return;
    }

    setState(() => _adding = true);
    try {
      final repo = AppServices.I.repo;
      final existing = await repo.findGameByTitle(target.displayName) ??
          (target.name.isEmpty || target.name == target.displayName
              ? null
              : await repo.findGameByTitle(target.name));
      if (existing != null) {
        if (!mounted) return;
        ref.read(libraryVersionProvider.notifier).state++;
        showNotice('「${existing.displayName}」已在库中');
        return;
      }
      final game = Game(
        name: target.name.isNotEmpty ? target.name : target.displayName,
        nameCn: target.nameCn,
        aliases: target.aliases,
        developer: target.developer,
        releaseDate: target.releaseDate,
        summary: target.summary,
        nsfw: target.nsfw,
        screenshots: target.screenshots,
      );
      await repo.insertGame(game);
      await ScrapeApplier(repo, AppServices.I.fetcher).apply(game, [target]);
      if (!mounted) return;
      ref.read(libraryVersionProvider.notifier).state++;
      showNotice('已入库：${game.displayName}');
    } catch (e) {
      if (mounted) showNotice('入库失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _openRelatedWork(ExploreRelatedWork rel) {
    Navigator.of(context).push(
      FadeThroughRoute.builder(
        builder: (_) => GameExplorePage(
          seedGame: rel.seedGame,
          onAdd: widget.onAdd,
        ),
      ),
    );
  }

  int _tabCount(ExploreWorkDetail detail, ExplorePageTab tab) {
    return switch (tab) {
      ExplorePageTab.overview => 0,
      ExplorePageTab.media =>
        detail.screenshots.length + detail.mediaLinks.length,
      ExplorePageTab.anime => detail.animeList.length,
      ExplorePageTab.music => detail.musicList.length,
      ExplorePageTab.manga => detail.mangaList.length,
      ExplorePageTab.novel => detail.novelList.length,
      ExplorePageTab.download => 5,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = KisakiColors.pageSurface(dark);
    final libraryIndex =
        ref.watch(discoverLibraryIndexProvider).valueOrNull ??
            const <String, Game>{};
    final inLibGame = _findInLibrary(libraryIndex);
    final effectiveLocalGameId = widget.localGameId ?? inLibGame?.id;
    final detail = _detail ?? _buildFallbackDetail(widget.seedGame);

    return Scaffold(
      backgroundColor: pageBg,
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(
            child: Stack(
              children: [
                Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. 全景沉浸横幅与信息展台 (Hero Stage)
                        _buildHeroStage(
                          context,
                          detail: detail,
                          effectiveLocalGameId: effectiveLocalGameId,
                        ),

                        // 2. 顶层主工作区 Segmented Tab 切换栏
                        _buildWorkspaceTabBar(context, detail: detail),

                        // 3. Tab 主内容区
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1280),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 24,
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 240),
                                switchInCurve: Motion.enter,
                                switchOutCurve: Motion.exit,
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.0, 0.02),
                                      end: Offset.zero,
                                    ).animate(anim),
                                    child: child,
                                  ),
                                ),
                                child: KeyedSubtree(
                                  key: ValueKey<ExplorePageTab>(_activeTab),
                                  child: _buildActiveTabContent(
                                    context,
                                    detail: detail,
                                    inLibrary: effectiveLocalGameId != null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. 百科资料 Tab 激活时的右侧小悬浮定位窗
                if (_activeTab == ExplorePageTab.overview)
                  Positioned(
                    right: 28,
                    top: 24,
                    child: FloatingAnchorNav(
                      scrollController: _scroll,
                      items: [
                        AnchorSectionItem(
                          id: 'synopsis',
                          label: '简介与标签',
                          icon: Icons.notes_rounded,
                          key: _synopsisKey,
                        ),
                        AnchorSectionItem(
                          id: 'characters',
                          label: '角色与声优',
                          icon: Icons.people_alt_rounded,
                          key: _charsKey,
                        ),
                        AnchorSectionItem(
                          id: 'releases',
                          label: '发行资料',
                          icon: Icons.inventory_2_outlined,
                          key: _releasesKey,
                        ),
                        AnchorSectionItem(
                          id: 'staff',
                          label: '制作人员',
                          icon: Icons.badge_outlined,
                          key: _staffKey,
                        ),
                        AnchorSectionItem(
                          id: 'related',
                          label: '相关游戏',
                          icon: Icons.hub_outlined,
                          key: _relatedKey,
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

  ExploreWorkDetail _buildFallbackDetail(ScrapedGame seed) {
    final cleanTitle = GameExploreService.extractLocalizedText(
      seed.nameCn.isNotEmpty ? seed.nameCn : seed.displayName,
    );
    final cleanOrig = GameExploreService.extractLocalizedText(
      seed.name,
      langPriority: const ['ja', 'en', 'zh-Hans'],
    );
    return ExploreWorkDetail(
      cacheKey: 'seed',
      seedGame: seed,
      nextmoeId: seed.source == KisakiSources.kun ? seed.sourceId : '',
      bangumiId: seed.source == KisakiSources.bangumi ? seed.sourceId : '',
      vndbId: seed.source == KisakiSources.vndb ? seed.sourceId : '',
      title: cleanTitle.isNotEmpty ? cleanTitle : seed.displayName,
      originalTitle: cleanOrig != cleanTitle ? cleanOrig : '',
      aliases: seed.aliases
          .map(GameExploreService.extractLocalizedText)
          .where((a) => a.isNotEmpty && a != cleanTitle && a != cleanOrig)
          .toList(),
      coverUrl: seed.coverUrl,
      bannerUrl: seed.screenshots.isNotEmpty
          ? seed.screenshots.first
          : seed.coverUrl,
      nsfw: seed.nsfw,
      developers: seed.developer.isEmpty
          ? const []
          : [GameExploreService.extractLocalizedText(seed.developer)],
      releaseDate: seed.releaseDate,
      summary: GameExploreService.extractLocalizedText(seed.summary),
      ratings: seed.rating > 0
          ? [
              ExploreSourceRating(
                source: seed.source,
                label: KisakiSources.labels[seed.source] ?? seed.source,
                score: seed.rating,
                displayScore: seed.rating.toStringAsFixed(1),
                voteCount: seed.voteCount,
              ),
            ]
          : const [],
      tags: seed.tags.map((t) => t.name).toList(),
      screenshots: seed.screenshots
          .map((u) => ExploreScreenshot(url: u, nsfw: seed.nsfw))
          .toList(),
    );
  }

  // ==================== 1. 全景横幅与信息展台 (Hero Stage) ====================

  Widget _buildHeroStage(
    BuildContext context, {
    required ExploreWorkDetail detail,
    required int? effectiveLocalGameId,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final pageBg = KisakiColors.pageSurface(dark);
    final cyanInk = KisakiColors.temporalInk(dark);

    final hasDistinctBanner = detail.bannerUrl.isNotEmpty &&
        detail.bannerUrl != detail.coverUrl;
    final stageBgUrl =
        detail.bannerUrl.isNotEmpty ? detail.bannerUrl : detail.coverUrl;

    return Container(
      decoration: BoxDecoration(
        color: pageBg,
        border: Border(
          bottom: BorderSide(color: Elev.border(dark), width: 1),
        ),
      ),
      child: Stack(
        children: [
          // 全景宽幅背景层
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 290,
            child: stageBgUrl.isEmpty
                ? ColoredBox(color: _surfaceLevel(1, dark))
                : ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: hasDistinctBanner ? 1.0 : 22.0,
                        sigmaY: hasDistinctBanner ? 1.0 : 22.0,
                      ),
                      child: Opacity(
                        opacity: dark
                            ? (hasDistinctBanner ? 0.38 : 0.22)
                            : (hasDistinctBanner ? 0.28 : 0.16),
                        child: CoverImage(
                          path: '',
                          networkUrl: stageBgUrl,
                          nsfw: detail.nsfw,
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                    ),
                  ),
          ),
          // 平滑渐变遮罩
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 290,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.45, 1.0],
                  colors: [
                    pageBg.withValues(alpha: dark ? 0.50 : 0.60),
                    pageBg.withValues(alpha: dark ? 0.78 : 0.82),
                    pageBg,
                  ],
                ),
              ),
            ),
          ),

          // 前景核心内容：返回栏 + 宽幅封面与信息
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 顶栏：导航返回 + 平台 ID 胶囊 + 刷新按钮
                    Row(
                      children: [
                        FluidPressable(
                          onTap: () => Navigator.of(context).maybePop(),
                          scaleFactor: 0.96,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceLevel(2, dark).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(Radii.sm),
                              border: Border.all(color: Elev.border(dark)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_back_rounded,
                                  size: 14,
                                  color: scheme.onSurface,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.localGameId != null
                                      ? '返回游戏详情'
                                      : '返回探索',
                                  style: Type.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (detail.nextmoeId.isNotEmpty) ...[
                          _SourceIdPill(
                            source: KisakiSources.kun,
                            id: detail.nextmoeId,
                            onTap: () => _openExternalUrl('https://www.kungal.com'),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (detail.bangumiId.isNotEmpty) ...[
                          _SourceIdPill(
                            source: KisakiSources.bangumi,
                            id: detail.bangumiId,
                            onTap: () => _openExternalUrl(
                              'https://bgm.tv/subject/${detail.bangumiId}',
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (detail.vndbId.isNotEmpty) ...[
                          _SourceIdPill(
                            source: KisakiSources.vndb,
                            id: 'v${detail.vndbId}',
                            onTap: () => _openExternalUrl(
                              'https://vndb.org/v${detail.vndbId}',
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        KIconAction(
                          icon: Icons.refresh_rounded,
                          tooltip: '强制刷新并重新聚合百科数据',
                          onTap: _loading ? null : () => _load(forceRefresh: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 封面 + 主刊头与动作区（开阔布局，消除拥挤感）
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 2:3 悬浮精装封面
                        FluidPressable(
                          onTap: detail.coverUrl.isEmpty
                              ? null
                              : () => _showImageLightbox(
                                    context,
                                    urls: [
                                      detail.coverUrl,
                                      ...detail.screenshots.map((e) => e.url),
                                    ],
                                    initialIndex: 0,
                                    title: detail.title,
                                  ),
                          child: Container(
                            width: 156,
                            height: 234,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.all(
                                color: _borderStrong(dark),
                                width: 1,
                              ),
                              boxShadow: _boxShadow(3, dark),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.md - 1),
                              child: CoverImage(
                                path: '',
                                networkUrl: detail.coverUrl,
                                nsfw: detail.nsfw,
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 26),

                        // 右侧主排印与操作栏
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 状态行：注意！R18 标记严格置于评分前面！
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (effectiveLocalGameId != null)
                                    KBadge(
                                      text: '已在库中',
                                      color: KisakiColors.success,
                                      icon: Icons.check_circle_rounded,
                                    ),
                                  // ★ 用户明确要求：把 R18 标记移到评分前面！
                                  if (detail.nsfw)
                                    const KBadge(
                                      text: 'R18',
                                      color: KisakiColors.danger,
                                      icon: Icons.explicit_rounded,
                                    ),
                                  // 多站点评分徽章
                                  for (final r in detail.ratings)
                                    _InteractiveRatingPill(
                                      rating: r,
                                      onTap: r.url.isEmpty
                                          ? null
                                          : () => _openExternalUrl(r.url),
                                    ),
                                  if (_loading)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 13,
                                          height: 13,
                                          child: KLoading(size: 13),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '正在聚合多源百科…',
                                          style: Type.micro.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (_error != null)
                                    Text(
                                      '部分数据源异常: $_error',
                                      style: Type.micro.copyWith(
                                        color: KisakiColors.danger,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 作品主标题
                              SelectableText(
                                GameExploreService.extractLocalizedText(
                                  detail.title,
                                ),
                                style: Type.display.copyWith(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),

                              // 原名与别名
                              if (detail.originalTitle.isNotEmpty) ...[
                                Builder(
                                  builder: (context) {
                                    final cleanTitle =
                                        GameExploreService.extractLocalizedText(
                                      detail.title,
                                    );
                                    final cleanOrig =
                                        GameExploreService.extractLocalizedText(
                                      detail.originalTitle,
                                      langPriority: const [
                                        'ja',
                                        'en',
                                        'zh-Hans'
                                      ],
                                    );
                                    if (cleanOrig.isEmpty ||
                                        cleanOrig == cleanTitle) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: SelectableText(
                                              cleanOrig,
                                              style: Type.body.copyWith(
                                                color: scheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (detail.aliases.isNotEmpty) ...[
                                            const SizedBox(width: 10),
                                            FluidPressable(
                                              onTap: () => setState(
                                                () =>
                                                    _showAliases = !_showAliases,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _surfaceLevel(2, dark),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    Radii.xs,
                                                  ),
                                                  border: Border.all(
                                                    color: Elev.border(dark),
                                                  ),
                                                ),
                                                child: Text(
                                                  _showAliases
                                                      ? '收起别名'
                                                      : '+${detail.aliases.length} 别名',
                                                  style: Type.micro.copyWith(
                                                    color: scheme.primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],

                              if (_showAliases && detail.aliases.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _surfaceLevel(1, dark)
                                        .withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(Radii.sm),
                                    border: Border.all(color: Elev.border(dark)),
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      for (final a in detail.aliases)
                                        SelectableText(
                                          '· $a',
                                          style: Type.caption.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),

                              // 核心规格行
                              _buildInlineFactsRow(context, detail),
                              const SizedBox(height: 18),

                              // 核心操作按钮行
                              Wrap(
                                spacing: Gap.sm,
                                runSpacing: Gap.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (effectiveLocalGameId != null)
                                    KPill(
                                      label: widget.localGameId != null
                                          ? '返回本地详情'
                                          : '在游戏库中打开',
                                      icon: Icons.library_books_rounded,
                                      color: cyanInk,
                                      onTap: () {
                                        if (widget.localGameId != null) {
                                          Navigator.of(context).maybePop();
                                        } else {
                                          Navigator.of(context).push(
                                            FadeThroughRoute.builder(
                                              builder: (_) => GameDetailPage(
                                                gameId: effectiveLocalGameId,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    )
                                  else
                                    KPill(
                                      label: _adding ? '正在加入游戏库…' : '一键加入游戏库',
                                      icon: Icons.library_add_rounded,
                                      color: scheme.primary,
                                      onTap: _adding ? null : _handleAddToLibrary,
                                    ),
                                  KPill(
                                    label: '查找下载资源',
                                    icon: Icons.cloud_download_rounded,
                                    filled: false,
                                    onTap: () {
                                      setState(() {
                                        _activeTab = ExplorePageTab.download;
                                      });
                                    },
                                  ),
                                  if (detail.screenshots.isNotEmpty)
                                    KPill(
                                      label: '画廊大图 (${detail.screenshots.length})',
                                      icon: Icons.photo_library_outlined,
                                      filled: false,
                                      onTap: () => _showImageLightbox(
                                        context,
                                        urls: detail.screenshots
                                            .map((e) => e.url)
                                            .toList(),
                                        initialIndex: 0,
                                        title: detail.title,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineFactsRow(BuildContext context, ExploreWorkDetail detail) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <(IconData, String, String)>[
      if (detail.developers.isNotEmpty)
        (Icons.business_rounded, '开发', detail.developers.take(2).join(' / ')),
      if (detail.publishers.isNotEmpty)
        (Icons.storefront_rounded, '发行', detail.publishers.take(2).join(' / ')),
      if (detail.releaseDate.isNotEmpty)
        (Icons.event_rounded, '首发日', detail.releaseDate),
      if (detail.engines.isNotEmpty)
        (Icons.memory_rounded, '引擎', detail.engines.join(' / ')),
      if (detail.series.isNotEmpty)
        (Icons.collections_bookmark_rounded, '系列', detail.series.join(' / ')),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final (icon, label, value) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
            decoration: BoxDecoration(
              color: _surfaceLevel(1, dark).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: Elev.border(dark)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  '$label: ',
                  style: Type.micro.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ==================== 2. 顶层主工作区 Segmented Tab 切换栏 ====================

  Widget _buildWorkspaceTabBar(
    BuildContext context, {
    required ExploreWorkDetail detail,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: _surfaceLevel(1, dark),
        border: Border(
          bottom: BorderSide(color: Elev.border(dark)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tab in ExplorePageTab.values)
                  _WorkspaceTabPill(
                    tab: tab,
                    count: _tabCount(detail, tab),
                    selected: _activeTab == tab,
                    onTap: () => setState(() => _activeTab = tab),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 3. Tab 主内容渲染器 ====================

  Widget _buildActiveTabContent(
    BuildContext context, {
    required ExploreWorkDetail detail,
    required bool inLibrary,
  }) {
    return switch (_activeTab) {
      ExplorePageTab.overview => _buildOverviewEncyclopediaTab(context, detail),
      ExplorePageTab.media => _buildMediaTabContent(context, detail),
      ExplorePageTab.anime => _buildCrossMediaListTabContent(
          context,
          items: detail.animeList,
          emptyTitle: '暂无关联动画条目',
          emptySubtitle: '该作品在 Bangumi 暂未登记改编动画、OVA 或剧场版关联记录',
          emptyIcon: Icons.movie_filter_outlined,
          fallbackSearchLabel: '在 Bangumi 搜索动画',
          fallbackSearchUrl:
              'https://bgm.tv/subject_search/${Uri.encodeComponent(detail.title)}?cat=2',
        ),
      ExplorePageTab.music => _buildCrossMediaListTabContent(
          context,
          items: detail.musicList,
          emptyTitle: '暂无关联音乐专辑',
          emptySubtitle: '该作品在 Bangumi 暂未登记 OST 原声集、主题曲或广播剧 CD',
          emptyIcon: Icons.album_outlined,
          fallbackSearchLabel: '在 VGMdb 检索原声带',
          fallbackSearchUrl:
              'https://vgmdb.net/search?q=${Uri.encodeComponent(detail.originalTitle.isNotEmpty ? detail.originalTitle : detail.title)}',
        ),
      ExplorePageTab.manga => _buildCrossMediaListTabContent(
          context,
          items: detail.mangaList,
          emptyTitle: '暂无关联漫画作品',
          emptySubtitle: '该作品暂未登记改编单行本漫画、四格漫画或选集',
          emptyIcon: Icons.menu_book_outlined,
          fallbackSearchLabel: '在 Bangumi 搜索漫画',
          fallbackSearchUrl:
              'https://bgm.tv/subject_search/${Uri.encodeComponent(detail.title)}?cat=1',
        ),
      ExplorePageTab.novel => _buildCrossMediaListTabContent(
          context,
          items: detail.novelList,
          emptyTitle: '暂无关联轻小说与设定集',
          emptySubtitle: '该作品暂未登记官方轻小说、外传小说或 Visual Fanbook',
          emptyIcon: Icons.auto_stories_outlined,
          fallbackSearchLabel: '在 BOOK☆WALKER 搜索轻小说',
          fallbackSearchUrl:
              'https://bookwalker.jp/search/?word=${Uri.encodeComponent(detail.originalTitle.isNotEmpty ? detail.originalTitle : detail.title)}',
        ),
      ExplorePageTab.download => ResourceLinkSection(
          game: detail.enrichedScrapedGame,
          inLibrary: inLibrary,
          adding: _adding,
          onAdd: _handleAddToLibrary,
          shrinkWrap: true,
        ),
    };
  }

  /// 百科资料 Tab：简介、角色、发行、人员、相关游戏（开阔优雅，不再挤在子栏中）
  Widget _buildOverviewEncyclopediaTab(
    BuildContext context,
    ExploreWorkDetail detail,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 故事简介与标签
        Container(
          key: _synopsisKey,
          child: _buildSynopsisCard(context, detail),
        ),
        const SizedBox(height: 26),

        // 角色与声优
        Container(
          key: _charsKey,
          child: _buildCharactersCard(context, detail),
        ),
        const SizedBox(height: 26),

        // 发行资料与平台版本
        Container(
          key: _releasesKey,
          child: _buildReleasesCard(context, detail),
        ),
        const SizedBox(height: 26),

        // 制作人员署名
        Container(
          key: _staffKey,
          child: _buildCreditsCard(context, detail),
        ),
        const SizedBox(height: 26),

        // 相关游戏
        Container(
          key: _relatedKey,
          child: _buildRelatedGamesCard(context, detail),
        ),
      ],
    );
  }

  // ==================== 百科分区组件 ====================

  Widget _buildSynopsisCard(BuildContext context, ExploreWorkDetail detail) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);
    final long = detail.summary.length > 280;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceLevel(1, dark),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KSectionTitle(
            '故事简介与标签名录',
            padding: const EdgeInsets.only(bottom: 12),
            trailing: long
                ? FluidPressable(
                    onTap: () => setState(() => _expandSynopsis = !_expandSynopsis),
                    child: Text(
                      _expandSynopsis ? '收起正文' : '展开全文',
                      style: Type.micro.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : null,
          ),
          if (detail.summary.isEmpty)
            Text(
              _loading ? '正在载入故事简介…' : '暂无作品简介。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            SelectableText(
              detail.summary,
              maxLines: (!_expandSynopsis && long) ? 6 : null,
              style: Type.body.copyWith(
                height: 1.76,
                color: scheme.onSurface.withValues(alpha: 0.94),
              ),
            ),
          if (detail.tags.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(height: 1, thickness: 1, color: Elev.border(dark)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in detail.tags)
                  KChip(
                    label: '#$tag',
                    color: cyanInk,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCharactersCard(BuildContext context, ExploreWorkDetail detail) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final allChars = detail.characters;
    final hasSpoilers = allChars.any((c) => c.spoiler);
    final filtered = allChars.where((c) {
      if (!_showSpoilers && c.spoiler) return false;
      if (_charRoleFilter == 'main') {
        return c.role == 'main' || c.role == 'protagonist';
      }
      if (_charRoleFilter == 'secondary') {
        return c.role != 'main' && c.role != 'protagonist';
      }
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceLevel(1, dark),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KSectionTitle(
                  '角色与声优 (${allChars.length})',
                  padding: EdgeInsets.zero,
                ),
              ),
              if (allChars.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    KChip(
                      label: '全部',
                      selected: _charRoleFilter == 'all',
                      onTap: () => setState(() => _charRoleFilter = 'all'),
                    ),
                    KChip(
                      label: '主角',
                      selected: _charRoleFilter == 'main',
                      onTap: () => setState(() => _charRoleFilter = 'main'),
                    ),
                    KChip(
                      label: '配角 / 其他',
                      selected: _charRoleFilter == 'secondary',
                      onTap: () => setState(() => _charRoleFilter = 'secondary'),
                    ),
                    if (hasSpoilers)
                      KChip(
                        label: _showSpoilers ? '隐藏剧透' : '显示剧透角色',
                        selected: _showSpoilers,
                        color: KisakiColors.danger,
                        onTap: () => setState(() => _showSpoilers = !_showSpoilers),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (allChars.isEmpty)
            Text(
              _loading ? '正在加载角色档案…' : '暂无角色与声优记录。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            )
          else if (filtered.isEmpty)
            Text(
              '当前筛选下暂无角色。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in filtered)
                  _CharacterCardSpacious(character: c),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildReleasesCard(BuildContext context, ExploreWorkDetail detail) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final allReleases = detail.releases;

    final filtered = allReleases.where((r) {
      if (_releaseLangFilter == 'zh') {
        return r.languages.any((l) => l.contains('中文'));
      }
      if (_releaseLangFilter == 'ja') {
        return r.languages.any((l) => l.contains('日语'));
      }
      if (_releaseLangFilter == 'en') {
        return r.languages.any((l) => l.contains('英语'));
      }
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceLevel(1, dark),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KSectionTitle(
                  '发行版本与平台资料 (${allReleases.length})',
                  padding: EdgeInsets.zero,
                ),
              ),
              if (allReleases.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    KChip(
                      label: '全部版本',
                      selected: _releaseLangFilter == 'all',
                      onTap: () => setState(() => _releaseLangFilter = 'all'),
                    ),
                    KChip(
                      label: '含中文版',
                      selected: _releaseLangFilter == 'zh',
                      onTap: () => setState(() => _releaseLangFilter = 'zh'),
                    ),
                    KChip(
                      label: '日文版',
                      selected: _releaseLangFilter == 'ja',
                      onTap: () => setState(() => _releaseLangFilter = 'ja'),
                    ),
                    KChip(
                      label: '英文版',
                      selected: _releaseLangFilter == 'en',
                      onTap: () => setState(() => _releaseLangFilter = 'en'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (allReleases.isEmpty)
            Text(
              _loading ? '正在检索多平台发行版本…' : '暂无发行版本数据。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            )
          else if (filtered.isEmpty)
            Text(
              '当前筛选条件下没有匹配的版本。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: Elev.border(dark)),
                  _ReleaseRowTile(
                    release: filtered[i],
                    onOpenUrl: _openExternalUrl,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCreditsCard(BuildContext context, ExploreWorkDetail detail) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final groups = detail.credits;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceLevel(1, dark),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KSectionTitle(
            '制作人员名单 (${groups.length} 职位组)',
            padding: const EdgeInsets.only(bottom: 18),
          ),
          if (groups.isEmpty)
            Text(
              _loading ? '正在读取制作人员署名…' : '暂无制作人员数据。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final g in groups)
                  _CreditGroupCardSpacious(group: g),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRelatedGamesCard(BuildContext context, ExploreWorkDetail detail) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final rels = detail.relatedGames;

    final grouped = <String, List<ExploreRelatedWork>>{};
    for (final r in rels) {
      grouped.putIfAbsent(r.groupLabel, () => []).add(r);
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceLevel(1, dark),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KSectionTitle(
                  '相关游戏关联 (${rels.length})',
                  padding: EdgeInsets.zero,
                ),
              ),
              if (rels.isNotEmpty)
                Text(
                  '点击任意游戏可在探索百科内继续深入',
                  style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (rels.isEmpty)
            Text(
              _loading ? '正在检索同系列与关联游戏…' : '暂无相关游戏记录。',
              style: Type.body.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, top: 6),
                    child: Text(
                      entry.key,
                      style: Type.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final item in entry.value)
                        _RelatedGameCardSpacious(
                          work: item,
                          onTap: () => _openRelatedWork(item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // ==================== 独立 Tab 内容（媒体 / 跨媒体列表） ====================

  Widget _buildMediaTabContent(BuildContext context, ExploreWorkDetail detail) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final videos = detail.mediaLinks.where((l) => l.isVideo).toList();
    final storesAndSites = detail.mediaLinks.where((l) => !l.isVideo).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              '高清截图与 CG 画廊 (${detail.screenshots.length})',
              style: Type.section.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (detail.screenshots.isNotEmpty)
              Text(
                '点击任意图片可进入全屏缩放灯箱',
                style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (detail.screenshots.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _surfaceLevel(2, dark).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: Elev.border(dark)),
            ),
            child: Text(
              _loading ? '正在检索游戏画面与 CG…' : '暂无截图预览',
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 290,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 16 / 9,
            ),
            itemCount: detail.screenshots.length.clamp(0, 24),
            itemBuilder: (context, idx) {
              final shot = detail.screenshots[idx];
              return FluidPressable(
                onTap: () => _showImageLightbox(
                  context,
                  urls: detail.screenshots.map((e) => e.url).toList(),
                  initialIndex: idx,
                  title: detail.title,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: Elev.border(dark)),
                    boxShadow: _boxShadow(1, dark),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm - 1),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CoverImage(
                          path: '',
                          networkUrl: shot.url,
                          nsfw: shot.nsfw,
                          borderRadius: BorderRadius.zero,
                        ),
                        if (shot.caption.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              color: Colors.black.withValues(alpha: 0.65),
                              child: Text(
                                shot.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Type.micro.copyWith(color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

        if (videos.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '宣传片映像与 OP 动画检索',
                style: Type.section.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final v in videos)
                _MediaLinkCard(link: v, onTap: () => _openExternalUrl(v.url)),
            ],
          ),
        ],

        if (storesAndSites.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              Icon(Icons.language_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '官方网站、数字商店与百科主页',
                style: Type.section.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final s in storesAndSites)
                _MediaLinkCard(link: s, onTap: () => _openExternalUrl(s.url)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCrossMediaListTabContent(
    BuildContext context, {
    required List<ExploreCrossMediaItem> items,
    required String emptyTitle,
    required String emptySubtitle,
    required IconData emptyIcon,
    required String fallbackSearchLabel,
    required String fallbackSearchUrl,
  }) {
    final scheme = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      if (_loading) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const KLoading(size: 26),
                const SizedBox(height: 12),
                Text(
                  '正在查询 Bangumi 跨媒体关联条目…',
                  style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: KEmpty(
          icon: emptyIcon,
          title: emptyTitle,
          subtitle: emptySubtitle,
          actionLabel: fallbackSearchLabel,
          actionIcon: Icons.open_in_new_rounded,
          onAction: () => _openExternalUrl(fallbackSearchUrl),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _CrossMediaItemCard(
            item: items[i],
            onOpenUrl: _openExternalUrl,
          ),
        ],
      ],
    );
  }

  // ==================== 全屏图片灯箱预览 ====================

  void _showImageLightbox(
    BuildContext context, {
    required List<String> urls,
    required int initialIndex,
    required String title,
  }) {
    if (urls.isEmpty) return;
    showKisakiDialog<void>(
      context: context,
      builder: (_) => _ScreenshotLightboxDialog(
        urls: urls,
        initialIndex: initialIndex,
        title: title,
      ),
    );
  }
}

// ============================ 子组件定义 ============================

class _WorkspaceTabPill extends StatelessWidget {
  final ExplorePageTab tab;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _WorkspaceTabPill({
    required this.tab,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return FluidPressable(
      onTap: onTap,
      scaleFactor: 0.96,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.enter,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: selected ? scheme.primary : Elev.border(dark),
          ),
          boxShadow: selected ? _boxShadow(1, dark) : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 15,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              tab.label,
              style: Type.caption.copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
            if (tab != ExplorePageTab.overview && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.onPrimary.withValues(alpha: 0.22)
                      : _surfaceLevel(2, dark),
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: Text(
                  tab == ExplorePageTab.download ? '5源' : '$count',
                  style: Type.mono.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceIdPill extends StatelessWidget {
  final String source;
  final String id;
  final VoidCallback? onTap;

  const _SourceIdPill({
    required this.source,
    required this.id,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FluidPressable(
      onTap: onTap,
      scaleFactor: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _surfaceLevel(2, dark).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: Elev.border(dark)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SourceBadge(source: source),
            const SizedBox(width: 5),
            Text(
              id,
              style: Type.mono.copyWith(fontSize: 10.5),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.open_in_new_rounded, size: 11),
          ],
        ),
      ),
    );
  }
}

class _InteractiveRatingPill extends StatelessWidget {
  final ExploreSourceRating rating;
  final VoidCallback? onTap;

  const _InteractiveRatingPill({
    required this.rating,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ratingColor = KisakiColors.ratingInk(dark);

    return FluidPressable(
      onTap: onTap,
      scaleFactor: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: ratingColor.withValues(alpha: dark ? 0.14 : 0.10),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: ratingColor.withValues(alpha: dark ? 0.35 : 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 14, color: ratingColor),
            const SizedBox(width: 4),
            Text(
              rating.label,
              style: Type.micro.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              rating.displayScore,
              style: Type.mono.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: ratingColor,
              ),
            ),
            if (rating.voteCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                '(${rating.voteCount})',
                style: Type.micro.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CharacterCardSpacious extends StatelessWidget {
  final ExploreCharacter character;

  const _CharacterCardSpacious({required this.character});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final isMain = character.role == 'main' || character.role == 'protagonist';
    final roleColor = isMain ? scheme.primary : KisakiColors.temporalInk(dark);

    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surfaceLevel(2, dark).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (character.imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xs),
              child: SizedBox(
                width: 64,
                height: 80,
                child: CoverImage(
                  path: '',
                  networkUrl: character.imageUrl,
                  nsfw: character.nsfw,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    KBadge(text: character.roleLabel, color: roleColor),
                    if (character.spoiler) ...[
                      const SizedBox(width: 4),
                      const KBadge(text: '剧透', color: KisakiColors.danger),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  character.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (character.originalName.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    character.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  character.voiceActorLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.micro.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
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

class _CreditGroupCardSpacious extends StatelessWidget {
  final ExploreCreditGroup group;

  const _CreditGroupCardSpacious({required this.group});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceLevel(2, dark).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
              Text(
                '${group.people.length} 人',
                style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final p in group.people)
                Text(
                  p.originalName.isNotEmpty
                      ? '${p.name} (${p.originalName})'
                      : p.name,
                  style: Type.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RelatedGameCardSpacious extends StatelessWidget {
  final ExploreRelatedWork work;
  final VoidCallback onTap;

  const _RelatedGameCardSpacious({
    required this.work,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);

    return KCard(
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: SizedBox(
        width: 290,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xs),
              child: SizedBox(
                width: 58,
                height: 80,
                child: CoverImage(
                  path: '',
                  networkUrl: work.coverUrl,
                  nsfw: work.nsfw,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      KBadge(text: work.relationLabel, color: cyanInk),
                      const Spacer(),
                      SourceBadge(source: work.source),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    work.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  if (work.originalTitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      work.originalTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseRowTile extends StatelessWidget {
  final ExploreReleaseItem release;
  final void Function(String url) onOpenUrl;

  const _ReleaseRowTile({
    required this.release,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              release.date.isEmpty ? '日期未知' : release.date,
              style: Type.mono.copyWith(
                fontSize: 12,
                color: release.date.isEmpty
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Align(
              alignment: Alignment.centerLeft,
              child: KBadge(
                text: release.kindLabel,
                color: release.kind == 'patch' || release.kind == 'trial'
                    ? scheme.secondary
                    : scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  release.title,
                  maxLines: 1,
                  style: Type.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final lang in release.languages)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: lang.contains('中文')
                              ? cyanInk.withValues(alpha: 0.16)
                              : _surfaceLevel(2, dark),
                          borderRadius: BorderRadius.circular(Radii.xs),
                          border: Border.all(
                            color: lang.contains('中文')
                                ? cyanInk.withValues(alpha: 0.45)
                                : Elev.border(dark),
                          ),
                        ),
                        child: Text(
                          lang,
                          style: Type.micro.copyWith(
                            fontWeight: lang.contains('中文')
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: lang.contains('中文')
                                ? cyanInk
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final plat in release.platforms)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceLevel(2, dark),
                          borderRadius: BorderRadius.circular(Radii.xs),
                        ),
                        child: Text(
                          plat,
                          style: Type.micro.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    if (release.engine.isNotEmpty)
                      Text(
                        '引擎: ${release.engine}',
                        style: Type.micro.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (release.links.isNotEmpty) ...[
            const SizedBox(width: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final link in release.links.take(3))
                  FluidPressable(
                    onTap: () => onOpenUrl(link.url),
                    scaleFactor: 0.95,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _surfaceLevel(2, dark),
                        borderRadius: BorderRadius.circular(Radii.xs),
                        border: Border.all(color: Elev.border(dark)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 11,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            link.label,
                            style: Type.micro.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaLinkCard extends StatelessWidget {
  final ExploreExternalLink link;
  final VoidCallback onTap;

  const _MediaLinkCard({
    required this.link,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final accent = link.isVideo
        ? KisakiColors.danger
        : (link.isStore
            ? KisakiColors.temporalInk(dark)
            : scheme.primary);

    return FluidPressable(
      onTap: onTap,
      scaleFactor: 0.98,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _surfaceLevel(2, dark).withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: Elev.border(dark)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Icon(
                link.isVideo
                    ? Icons.ondemand_video_rounded
                    : (link.isStore
                        ? Icons.shopping_bag_outlined
                        : Icons.open_in_new_rounded),
                size: 16,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    link.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (link.subtitle.isNotEmpty)
                    Text(
                      link.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrossMediaItemCard extends StatelessWidget {
  final ExploreCrossMediaItem item;
  final void Function(String url) onOpenUrl;

  const _CrossMediaItemCard({
    required this.item,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final ratingInk = KisakiColors.ratingInk(dark);
    final cyanInk = KisakiColors.temporalInk(dark);
    final isMusic = item.category == 'music';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceLevel(1, dark),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Elev.border(dark)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isMusic ? 104 : 92,
            height: isMusic ? 104 : 132,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: Elev.border(dark)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm - 1),
              child: CoverImage(
                path: '',
                networkUrl: item.coverUrl,
                nsfw: false,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    KBadge(text: item.relationLabel, color: cyanInk),
                    if (item.date.isNotEmpty)
                      Text(
                        item.date,
                        style: Type.mono.copyWith(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (item.score > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 14, color: ratingInk),
                          const SizedBox(width: 2),
                          Text(
                            item.score.toStringAsFixed(1),
                            style: Type.mono.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: ratingInk,
                            ),
                          ),
                          if (item.voteCount > 0)
                            Text(
                              ' (${item.voteCount})',
                              style: Type.micro.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                SelectableText(
                  item.title,
                  style: Type.section.copyWith(fontWeight: FontWeight.w800),
                ),
                if (item.originalTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SelectableText(
                    item.originalTitle,
                    style: Type.micro.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (item.facts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final e in item.facts.entries.take(6))
                        RichText(
                          text: TextSpan(
                            style: Type.micro.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            children: [
                              TextSpan(text: '${e.key}：'),
                              TextSpan(
                                text: e.value,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (item.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
                if (item.links.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final link in item.links)
                        FluidPressable(
                          onTap: () => onOpenUrl(link.url),
                          scaleFactor: 0.96,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceLevel(2, dark),
                              borderRadius: BorderRadius.circular(Radii.xs),
                              border: Border.all(color: Elev.border(dark)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_in_new_rounded,
                                  size: 11.5,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  link.label,
                                  style: Type.micro.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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

class _ScreenshotLightboxDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String title;

  const _ScreenshotLightboxDialog({
    required this.urls,
    required this.initialIndex,
    required this.title,
  });

  @override
  State<_ScreenshotLightboxDialog> createState() =>
      _ScreenshotLightboxDialogState();
}

class _ScreenshotLightboxDialogState extends State<_ScreenshotLightboxDialog> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
  }

  void _prev() {
    setState(() {
      _index = (_index - 1 + widget.urls.length) % widget.urls.length;
    });
  }

  void _next() {
    setState(() {
      _index = (_index + 1) % widget.urls.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final url = widget.urls[_index];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 740),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceLevel(2, dark),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: _borderStrong(dark)),
          boxShadow: _boxShadow(3, dark),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.title} · 画面预览 (${_index + 1} / ${widget.urls.length})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.section.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.urls.length > 1) ...[
                  KIconAction(
                    icon: Icons.chevron_left_rounded,
                    tooltip: '上一张',
                    onTap: _prev,
                  ),
                  const SizedBox(width: 6),
                  KIconAction(
                    icon: Icons.chevron_right_rounded,
                    tooltip: '下一张',
                    onTap: _next,
                  ),
                  const SizedBox(width: 10),
                ],
                KIconAction(
                  icon: Icons.close_rounded,
                  tooltip: '关闭预览',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
