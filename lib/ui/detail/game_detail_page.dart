import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/media_paths.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../services/game_launch_service.dart';
import '../../services/save_backup.dart';
import '../add/scrape_search_dialog.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../library/game_actions.dart';
import '../shell/tabs.dart';
import '../widgets/save_dir_picker_dialog.dart';
import 'edit_dialog.dart';
import 'play_path_tab.dart';
import 'rate_dialog.dart';
import 'save_backup_dialog.dart';

final Map<int, List<DailyPoint>> _dailyTrendCache = {};
final ValueNotifier<int> _dailyTrendEpoch = ValueNotifier<int>(0);

/// Invalidates cached 30-day trend data for [gameId] so open detail views
/// refresh immediately when a play session ends.
void invalidateDailyTrend(int gameId) {
  _dailyTrendCache.remove(gameId);
  _dailyTrendEpoch.value++;
}

String? _safeResolveMedia(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  try {
    return MediaPaths.instance.resolveStored(trimmed);
  } catch (_) {
    return trimmed;
  }
}

/// Fluent 2 Game Detail Page with split acrylic hero, BreadcrumbBar, CommandBar,
/// Play Path timeline, Archive & Tags view, and Sessions & Saves analytics.
class GameDetailPage extends ConsumerStatefulWidget {
  const GameDetailPage({
    super.key,
    required this.gameId,
    this.initial,
    this.scrollToPlayPath = false,
  });

  final int gameId;
  final Game? initial;
  final bool scrollToPlayPath;

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  final _scrollCtrl = ScrollController();
  final _tabBarKey = GlobalKey();
  final _statusFlyoutCtrl = FlyoutController();
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.scrollToPlayPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _tabBarKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: FluentMotion.standard,
            curve: FluentMotion.enterCurve,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _statusFlyoutCtrl.dispose();
    super.dispose();
  }

  Widget _wrapFluent(BuildContext context, Widget child) {
    final hasTheme = FluentTheme.maybeOf(context) != null;
    final hasLoc = Localizations.of<FluentLocalizations>(
          context,
          FluentLocalizations,
        ) !=
        null;
    if (hasTheme && hasLoc) return child;
    var wrapped = child;
    if (!hasLoc) {
      wrapped = Localizations.override(
        context: context,
        delegates: const [FluentLocalizations.delegate],
        child: wrapped,
      );
    }
    if (!hasTheme) {
      wrapped = ensureFluentTheme(context, wrapped);
    }
    return wrapped;
  }

  @override
  Widget build(BuildContext context) {
    return _wrapFluent(
      context,
      Builder(builder: _buildFluentContent),
    );
  }

  Widget _buildFluentContent(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final disableAnim = fluentAnimationsDisabled(context);

    final gameAsync = ref.watch(gameProvider(widget.gameId));
    final game = gameAsync.valueOrNull ?? widget.initial;
    final sources =
        ref.watch(gameSourcesProvider(widget.gameId)).valueOrNull ?? const [];
    final tags =
        ref.watch(gameTagsProvider(widget.gameId)).valueOrNull ?? const [];
    final trackingId = ref.watch(trackingGameProvider);
    final isTracking = trackingId != null && trackingId == widget.gameId;
    final blurSigma = ref.watch(detailBgBlurProvider);

    if (game == null) {
      if (gameAsync.isLoading) {
        return const ScaffoldPage(
          content: Center(child: ProgressRing()),
        );
      }
      return ScaffoldPage(
        content: Center(
          child: FluentEmptyState(
            icon: FluentIcons.games_24_regular,
            title: '未找到该作品',
            message: '该游戏可能已被移出库，或数据尚未加载完成。',
            action: FilledButton(
              onPressed: _navigateBackToLibrary,
              child: const Text('返回游戏库'),
            ),
          ),
        ),
      );
    }

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Stack(
        children: [
          Positioned.fill(
            child: _DetailBackdrop(
              rawBg: game.backgroundUrl.isNotEmpty
                  ? game.backgroundUrl
                  : game.coverPath,
              blurSigma: blurSigma,
              accent: accent,
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(context, theme, accent, game, isTracking),
                      const SizedBox(height: 12),
                      _buildHero(
                        context,
                        theme,
                        accent,
                        game,
                        sources,
                        isTracking,
                      ).fluentEntrance(index: 0, disable: disableAnim),
                      const SizedBox(height: 18),
                      Container(
                        key: _tabBarKey,
                        child: _SegmentedTabs(
                          index: _tabIndex,
                          onChanged: (i) => setState(() => _tabIndex = i),
                        ),
                      ).fluentEntrance(index: 1, disable: disableAnim),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: disableAnim
                            ? Duration.zero
                            : FluentMotion.standard,
                        switchInCurve: FluentMotion.enterCurve,
                        switchOutCurve: Curves.easeInCubic,
                        child: KeyedSubtree(
                          key: ValueKey('detail-tab-$_tabIndex'),
                          child: switch (_tabIndex) {
                            0 => PlayPathTab(game: game),
                            1 => _ArchiveAndTagsTab(
                                game: game,
                                sources: sources,
                                tags: tags,
                                onFilterDeveloper: (dev) =>
                                    _filterLibrary(developer: dev),
                                onFilterTag: (tag) => _filterLibrary(tag: tag),
                                onFilterSource: (src) =>
                                    _filterLibrary(source: src),
                              ),
                            _ => _SessionsAndSavesTab(
                                game: game,
                                onEditSaveDir: () => _pickSaveDir(game),
                                onOpenBackups: () =>
                                    showSaveBackupDialog(context, ref, game),
                              ),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateBackToLibrary() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      ref.read(tabIndexProvider.notifier).state = Tabs.library;
    }
  }

  void _filterLibrary({String? developer, String? tag, String? source}) {
    jumpToLibraryFiltered(
      ref,
      developer: developer,
      tag: tag,
      source: source,
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickSaveDir(Game game) async {
    final picked = await showSaveDirPickerDialog(context, game);
    if (picked == null || picked.isEmpty) return;
    game.savePath = picked;
    await tryAppServices()?.repo.updateGame(game);
    if (game.id != null) ref.invalidate(gameProvider(game.id!));
    bumpLibrary(ref);
    showNotice('已更新存档目录');
  }

  Widget _buildTopBar(
    BuildContext context,
    FluentThemeData theme,
    Color accent,
    Game game,
    bool isTracking,
  ) {
    final res = theme.resources;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: res.cardBackgroundFillColorDefault.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: res.cardStrokeColorDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: BreadcrumbBar<String>(
              items: [
                const BreadcrumbItem<String>(
                  label: Text('游戏库'),
                  value: 'library',
                ),
                BreadcrumbItem<String>(
                  label: Text(
                    game.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: 'current',
                ),
              ],
              onItemPressed: (item) {
                if (item.value == 'library') {
                  _navigateBackToLibrary();
                }
              },
            ),
          ),
          if (isTracking) ...[
            const SizedBox(width: 8),
            FluentBadge(
              icon: FluentIcons.play_16_filled,
              text: '游玩计时中',
              foreground: Colors.white,
              background: accent,
            ),
          ],
          const SizedBox(width: 6),
          Tooltip(
            message: game.isFavorite ? '取消收藏' : '加入收藏',
            child: IconButton(
              icon: Icon(
                game.isFavorite
                    ? FluentIcons.heart_16_filled
                    : FluentIcons.heart_16_regular,
                size: 16,
                color: game.isFavorite ? const Color(0xFFE0527F) : null,
              ),
              onPressed: () async {
                await toggleGameFavorite(ref, game);
                if (game.id != null) ref.invalidate(gameProvider(game.id!));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(
    BuildContext context,
    FluentThemeData theme,
    Color accent,
    Game game,
    List<SourceRecord> sources,
    bool isTracking,
  ) {
    final coverResolved = _safeResolveMedia(game.coverPath);
    final remoteRating = _bestRemoteRating(sources);
    final displayScore = game.userRating > 0
        ? game.userRating
        : (remoteRating > 0 ? remoteRating : 0.0);

    Widget buildCover() {
      final cover = FluentCoverImage(
        pathOrUrl: game.coverPath,
        nsfw: false,
        width: 158,
        height: 226,
        radius: 10,
      );
      if (coverResolved == null) return cover;
      return GestureDetector(
        onTap: () => showFluentLightboxDialog(
          context,
          pathOrUrl: coverResolved,
          title: game.displayName,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: cover,
        ),
      );
    }

    Widget buildInfoColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            game.displayName,
            style: theme.typography.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.18,
            ),
          ),
          if (game.nameCn.isNotEmpty && game.name != game.displayName) ...[
            const SizedBox(height: 4),
            Text(
              game.name,
              style: theme.typography.body?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Mandatory UX invariant: R18 badge strictly precedes rating scores.
          FluentR18ScoreRow(
            nsfw: game.nsfw,
            scoreText:
                displayScore > 0 ? displayScore.toStringAsFixed(1) : null,
            trailing: [
              FlyoutTarget(
                controller: _statusFlyoutCtrl,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _openStatusMenu(game),
                    child: FluentStatusPill(status: game.playStatus),
                  ),
                ),
              ),
              if (game.developer.isNotEmpty)
                Button(
                  onPressed: () => _filterLibrary(developer: game.developer),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.building_16_regular, size: 13),
                      const SizedBox(width: 5),
                      Text(game.developer),
                    ],
                  ),
                ),
              if (game.releaseDate.isNotEmpty)
                FluentBadge(
                  icon: FluentIcons.calendar_16_regular,
                  text: game.releaseDate,
                ),
              FluentBadge(
                icon: FluentIcons.clock_16_regular,
                text: game.totalSeconds > 0
                    ? fmtDuration(game.totalSeconds)
                    : '尚未游玩',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 8),
          CommandBar(
            overflowBehavior: CommandBarOverflowBehavior.dynamicOverflow,
            primaryItems: [
              CommandBarButton(
                icon: Icon(
                  isTracking
                      ? FluentIcons.stop_16_filled
                      : FluentIcons.play_16_filled,
                  color: accent,
                ),
                label: Text(isTracking ? '停止计时' : '启动游戏'),
                onPressed: () {
                  if (isTracking) {
                    stopActiveGameSession(ref);
                  } else {
                    GameLaunchService.launchAndTrack(game, ref);
                  }
                },
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.translate_16_regular),
                label: const Text('LE 启动'),
                onPressed: () => launchGameWithLocaleEmulator(game, ref),
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.edit_16_regular),
                label: const Text('编辑'),
                onPressed: () => showEditGameDialog(context, ref, game),
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.star_16_regular),
                label: const Text('评分'),
                onPressed: () =>
                    showRateGameDialog(context, ref, game, sources: sources),
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.archive_16_regular),
                label: const Text('存档备份'),
                onPressed: () => showSaveBackupDialog(context, ref, game),
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.compass_northwest_16_regular),
                label: const Text('发现探索'),
                onPressed: () => openGameExploreForGame(context, game),
              ),
            ],
            secondaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.search_16_regular),
                label: const Text('重新搜刮'),
                onPressed: () => showScrapeSearchDialog(context, ref, game),
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.folder_open_16_regular),
                label: const Text('打开目录'),
                onPressed: () => openGameDir(game),
              ),
              CommandBarButton(
                icon: Icon(
                  game.isFavorite
                      ? FluentIcons.heart_16_filled
                      : FluentIcons.heart_16_regular,
                ),
                label: Text(game.isFavorite ? '取消收藏' : '加入收藏'),
                onPressed: () async {
                  await toggleGameFavorite(ref, game);
                  if (game.id != null) ref.invalidate(gameProvider(game.id!));
                },
              ),
              CommandBarButton(
                icon: Icon(FluentIcons.delete_16_regular, color: Colors.red),
                label: Text('删除作品', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  final ok = await confirmDeleteGame(context, ref, game);
                  if (ok && context.mounted) {
                    _navigateBackToLibrary();
                  }
                },
              ),
            ],
          ),
        ],
      );
    }

    return FluentAcrylicPanel(
      radius: 12,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: buildCover()),
                const SizedBox(height: 16),
                buildInfoColumn(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildCover(),
              const SizedBox(width: 20),
              Expanded(child: buildInfoColumn()),
            ],
          );
        },
      ),
    );
  }

  void _openStatusMenu(Game game) {
    _statusFlyoutCtrl.showFlyout<void>(
      barrierDismissible: true,
      dismissOnPointerMoveAway: false,
      builder: (flyoutCtx) => MenuFlyout(
        items: [
          for (final status in PlayStatus.values)
            MenuFlyoutItem(
              leading: Icon(
                status == game.playStatus
                    ? FluentIcons.checkmark_circle_16_regular
                    : FluentIcons.circle_16_regular,
                size: 14,
              ),
              text: Text(status.label),
              onPressed: () async {
                Navigator.of(flyoutCtx).pop();
                await updateGamePlayStatus(ref, game, status);
                if (game.id != null) ref.invalidate(gameProvider(game.id!));
              },
            ),
        ],
      ),
    );
  }

  static double _bestRemoteRating(List<SourceRecord> sources) {
    var best = 0.0;
    for (final s in sources) {
      if (s.rating > best) best = s.rating;
    }
    return best;
  }
}

class _DetailBackdrop extends StatelessWidget {
  const _DetailBackdrop({
    required this.rawBg,
    required this.blurSigma,
    required this.accent,
  });

  final String rawBg;
  final double blurSigma;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolved = _safeResolveMedia(rawBg);

    Widget? bgImage;
    if (resolved != null) {
      final isUrl =
          resolved.startsWith('http://') || resolved.startsWith('https://');
      if (isUrl) {
        bgImage = CachedNetworkImage(
          imageUrl: resolved,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        );
      } else {
        final file = File(resolved);
        if (file.existsSync()) {
          bgImage = Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        }
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: theme.scaffoldBackgroundColor),
        if (bgImage != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 440,
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: Opacity(
                  opacity: isDark ? 0.30 : 0.24,
                  child: bgImage,
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 460,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: isDark ? 0.08 : 0.05),
                  theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
                  theme.scaffoldBackgroundColor,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const _tabs = [
    ('游玩路径', FluentIcons.timeline_24_regular),
    ('档案与标签', FluentIcons.document_16_regular),
    ('会话与存档', FluentIcons.history_16_regular),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: res.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: res.cardStrokeColorDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: HoverButton(
                onPressed: () => onChanged(i),
                builder: (context, states) {
                  final active = index == i;
                  final bg = active
                      ? accent.withValues(alpha: 0.14)
                      : states.isHovered
                          ? res.subtleFillColorSecondary
                          : Colors.transparent;
                  return AnimatedContainer(
                    duration: FluentMotion.fast,
                    curve: FluentMotion.enterCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: active
                            ? accent.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _tabs[i].$2,
                          size: 15,
                          color: active ? accent : theme.inactiveColor,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _tabs[i].$1,
                          style: theme.typography.body?.copyWith(
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w500,
                            color: active ? accent : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArchiveAndTagsTab extends StatelessWidget {
  const _ArchiveAndTagsTab({
    required this.game,
    required this.sources,
    required this.tags,
    required this.onFilterDeveloper,
    required this.onFilterTag,
    required this.onFilterSource,
  });

  final Game game;
  final List<SourceRecord> sources;
  final List<TagItem> tags;
  final ValueChanged<String> onFilterDeveloper;
  final ValueChanged<String> onFilterTag;
  final ValueChanged<String> onFilterSource;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (game.userReview.trim().isNotEmpty) ...[
          FluentSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(FluentIcons.star_16_filled, size: 15, color: accent),
                    const SizedBox(width: 8),
                    Text('我的短评', style: theme.typography.bodyStrong),
                    const Spacer(),
                    if (game.userRating > 0)
                      Text(
                        '${game.userRating.toStringAsFixed(1)} / 10',
                        style: theme.typography.bodyStrong?.copyWith(
                          color: accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  game.userReview,
                  style: theme.typography.body?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.document_16_regular,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Text('作品简介', style: theme.typography.bodyStrong),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                game.summary.trim().isNotEmpty ? game.summary : '暂无作品简介',
                style: theme.typography.body?.copyWith(
                  height: 1.6,
                  color: game.summary.trim().isEmpty
                      ? theme.inactiveColor
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.info_16_regular, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('制作信息与别名', style: theme.typography.bodyStrong),
                ],
              ),
              const SizedBox(height: 12),
              _MetaRow(
                label: '原名',
                value: game.name,
              ),
              if (game.nameCn.isNotEmpty)
                _MetaRow(label: '中文译名', value: game.nameCn),
              if (game.developer.isNotEmpty)
                _MetaRow(
                  label: '开发商',
                  value: game.developer,
                  onTap: () => onFilterDeveloper(game.developer),
                ),
              if (game.releaseDate.isNotEmpty)
                _MetaRow(label: '发售日期', value: game.releaseDate),
              if (game.directory.isNotEmpty)
                _MetaRow(label: '安装目录', value: game.directory),
              if (game.exePath.isNotEmpty)
                _MetaRow(label: '启动程序', value: game.exePath),
              if (game.aliases.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '别名',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: game.aliases
                      .map(
                        (a) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: res.controlFillColorDefault,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: res.cardStrokeColorDefault,
                            ),
                          ),
                          child: Text(a, style: theme.typography.caption),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.tag_16_regular, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('作品标签', style: theme.typography.bodyStrong),
                ],
              ),
              const SizedBox(height: 10),
              if (tags.isEmpty)
                Text(
                  '暂无标签',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags
                      .map(
                        (t) => Button(
                          onPressed: () => onFilterTag(t.name),
                          child: Text('#${t.name}'),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.database_16_regular,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Text('关联数据源', style: theme.typography.bodyStrong),
                ],
              ),
              const SizedBox(height: 10),
              if (sources.isEmpty)
                Text(
                  '尚未关联外部元数据平台',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                )
              else
                Column(
                  children: sources.map((s) {
                    final label = KisakiSources.labels[s.source] ?? s.source;
                    final pageUrl = _sourcePageUrl(s);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: res.controlFillColorDefault,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: res.cardStrokeColorDefault,
                          ),
                        ),
                        child: Row(
                          children: [
                            Button(
                              onPressed: () => onFilterSource(s.source),
                              child: Text(label),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ID: ${s.sourceId}',
                                style: theme.typography.caption?.copyWith(
                                  color: theme.inactiveColor,
                                ),
                              ),
                            ),
                            if (s.rating > 0) ...[
                              Icon(
                                FluentIcons.star_16_filled,
                                size: 13,
                                color: accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                s.rating.toStringAsFixed(1),
                                style: theme.typography.bodyStrong,
                              ),
                              if (s.voteCount > 0)
                                Text(
                                  ' (${s.voteCount})',
                                  style: theme.typography.caption?.copyWith(
                                    color: theme.inactiveColor,
                                  ),
                                ),
                            ],
                            if (pageUrl != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  FluentIcons.open_16_regular,
                                  size: 14,
                                ),
                                onPressed: () => _openSourceUrl(pageUrl),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String? _sourcePageUrl(SourceRecord s) {
    final rawUrl = (s.raw['url'] as String?)?.trim();
    if (rawUrl != null && rawUrl.startsWith('http')) return rawUrl;
    final sid = s.sourceId.trim();
    if (sid.isEmpty) return null;
    return switch (s.source) {
      KisakiSources.vndb =>
        'https://vndb.org/${sid.startsWith('v') ? sid : 'v$sid'}',
      KisakiSources.bangumi => 'https://bgm.tv/subject/$sid',
      KisakiSources.ymgal =>
        'https://www.ymgal.games/${sid.startsWith('G') ? sid : 'GA$sid'}',
      KisakiSources.steam => 'https://store.steampowered.com/app/$sid',
      KisakiSources.cngal => 'https://www.cngal.org/entries/index/$sid',
      KisakiSources.hikarinagi => 'https://www.hikarinagi.com/gal/$sid',
      KisakiSources.kun => 'https://www.kungal.com/galgame/$sid',
      KisakiSources.dlsite =>
        'https://www.dlsite.com/maniax/work/=/product_id/$sid.html',
      _ => null,
    };
  }

  Future<void> _openSourceUrl(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await Clipboard.setData(ClipboardData(text: raw));
      showNotice('无法唤起浏览器，已复制链接到剪贴板');
    }
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ),
          Expanded(
            child: onTap == null
                ? Text(value, style: theme.typography.body)
                : GestureDetector(
                    onTap: onTap,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        value,
                        style: theme.typography.body?.copyWith(
                          color: accent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionsAndSavesTab extends StatefulWidget {
  const _SessionsAndSavesTab({
    required this.game,
    required this.onEditSaveDir,
    required this.onOpenBackups,
  });

  final Game game;
  final VoidCallback onEditSaveDir;
  final VoidCallback onOpenBackups;

  @override
  State<_SessionsAndSavesTab> createState() => _SessionsAndSavesTabState();
}

class _SessionsAndSavesTabState extends State<_SessionsAndSavesTab> {
  List<Map<String, dynamic>> _sessions = const [];
  List<SaveBackupEntry> _backups = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant _SessionsAndSavesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final services = tryAppServices();
    final gameId = widget.game.id;
    if (services == null || gameId == null) return;
    setState(() => _loading = true);
    try {
      final rows = await services.db.query(
        'game_sessions',
        where: 'game_id = ? AND closed = 1',
        whereArgs: [gameId],
        orderBy: 'start_ts DESC',
        limit: 12,
      );
      final backups = SaveBackupService(services.paths.root).list(gameId);
      if (!mounted) return;
      setState(() {
        _sessions = rows;
        _backups = backups;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final g = widget.game;
    final hoursText = '${(g.totalSeconds / 3600).toStringAsFixed(1)} 小时';

    final kpis = [
      ('累计游玩', hoursText, FluentIcons.clock_16_regular),
      ('游玩次数', '${g.sessionCount} 次', FluentIcons.play_16_regular),
      (
        '首次游玩',
        g.firstPlayedAt != null ? fmtDate(g.firstPlayedAt!) : '尚未开始',
        FluentIcons.calendar_16_regular,
      ),
      (
        '最近游玩',
        g.lastPlayedAt != null ? fmtDate(g.lastPlayedAt!) : '尚未开始',
        FluentIcons.history_16_regular,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final twoCol = constraints.maxWidth < 680;
            final cardWidth = twoCol
                ? (constraints.maxWidth - 12) / 2
                : (constraints.maxWidth - 36) / 4;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kpis
                  .map(
                    (k) => SizedBox(
                      width: cardWidth.clamp(120, 400).toDouble(),
                      child: FluentSurfaceCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(k.$3, size: 15, color: accent),
                                const SizedBox(width: 6),
                                Text(
                                  k.$1,
                                  style: theme.typography.caption?.copyWith(
                                    color: theme.inactiveColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              k.$2,
                              style: theme.typography.subtitle?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 14),
        if (g.id != null) _DailyTrendCard(gameId: g.id!),
        const SizedBox(height: 14),
        FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.archive_16_regular, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('存档路径与备份快照', style: theme.typography.bodyStrong),
                  const Spacer(),
                  if (_backups.isNotEmpty)
                    FluentBadge(text: '${_backups.length} 份备份'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                g.savePath.isNotEmpty ? g.savePath : '尚未配置本地存档目录',
                style: theme.typography.body?.copyWith(
                  color: g.savePath.isEmpty ? theme.inactiveColor : null,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Button(
                    onPressed: widget.onEditSaveDir,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.wand_16_regular, size: 14),
                        SizedBox(width: 6),
                        Text('探测 / 修改存档目录'),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: widget.onOpenBackups,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.archive_16_regular, size: 14),
                        SizedBox(width: 6),
                        Text('管理存档快照'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FluentSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.history_16_regular, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('近期游玩会话', style: theme.typography.bodyStrong),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: ProgressRing()),
                )
              else if (_sessions.isEmpty)
                Text(
                  '暂无近期会话明细',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                )
              else
                Column(
                  children: _sessions.map((row) {
                    final ts =
                        DateTime.tryParse(row['start_ts'] as String? ?? '');
                    final sec = (row['seconds'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(
                            FluentIcons.clock_16_regular,
                            size: 13,
                            color: theme.inactiveColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ts != null ? fmtDateTime(ts) : '-',
                              style: theme.typography.body,
                            ),
                          ),
                          Text(
                            fmtDuration(sec),
                            style: theme.typography.bodyStrong?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyTrendCard extends StatefulWidget {
  const _DailyTrendCard({required this.gameId});

  final int gameId;

  @override
  State<_DailyTrendCard> createState() => _DailyTrendCardState();
}

class _DailyTrendCardState extends State<_DailyTrendCard> {
  List<DailyPoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _dailyTrendEpoch.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant _DailyTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId) _reload();
  }

  @override
  void dispose() {
    _dailyTrendEpoch.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final cached = _dailyTrendCache[widget.gameId];
    if (cached != null) {
      if (mounted) setState(() => _points = cached);
      return;
    }

    final services = tryAppServices();
    if (services == null) {
      if (mounted) setState(() => _points = const []);
      return;
    }

    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 29));
    final startStr = fmtDate(start);
    try {
      final rows = await services.db.rawQuery(
        'SELECT date, seconds FROM daily_stats '
        'WHERE game_id = ? AND date >= ? ORDER BY date ASC',
        [widget.gameId, startStr],
      );
      final byDate = <String, int>{
        for (final r in rows)
          (r['date'] as String): (r['seconds'] as num?)?.toInt() ?? 0,
      };
      final filled = <DailyPoint>[];
      for (var i = 0; i < 30; i++) {
        final d = fmtDate(start.add(Duration(days: i)));
        filled.add(DailyPoint(d, byDate[d] ?? 0));
      }
      _dailyTrendCache[widget.gameId] = filled;
      if (mounted) setState(() => _points = filled);
    } catch (_) {
      if (mounted) setState(() => _points = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final hasActivity = _points.any((p) => p.seconds > 0);
    final maxMinutes = _points.fold<double>(
      10,
      (prev, p) => (p.seconds / 60) > prev ? (p.seconds / 60) : prev,
    );

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.sparkle_16_regular, size: 16, color: accent),
              const SizedBox(width: 8),
              Text('近 30 天游玩趋势（分钟）', style: theme.typography.bodyStrong),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasActivity)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '近 30 天暂无游玩记录',
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  maxY: maxMinutes * 1.15,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: theme.resources.cardStrokeColorDefault,
                      strokeWidth: 0.8,
                    ),
                  ),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(),
                    rightTitles: AxisTitles(),
                    topTitles: AxisTitles(),
                    bottomTitles: AxisTitles(),
                  ),
                  barGroups: [
                    for (var i = 0; i < _points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: _points[i].seconds / 60.0,
                            width: 6,
                            borderRadius: BorderRadius.circular(3),
                            color: _points[i].seconds > 0
                                ? accent
                                : theme.resources.cardStrokeColorDefault,
                          ),
                        ],
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
