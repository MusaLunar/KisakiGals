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
import '../../services/plugin_system.dart';
import '../../services/save_backup.dart';
import '../add/scrape_search_dialog.dart';
import '../fluent/fluent_chrome.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import '../library/game_actions.dart';
import '../shell/tabs.dart';
import '../widgets/save_dir_picker_dialog.dart';
import 'edit_dialog.dart';
import 'play_path_tab.dart';
import 'rate_dialog.dart';
import 'save_backup_dialog.dart';

final Map<int, List<DailyPoint>> _dailyTrendCache = {};
final ValueNotifier<int> _dailyTrendEpoch = ValueNotifier<int>(0);

/// 使 [gameId] 的 30 天游玩趋势缓存失效，供会话结束后即时刷新详情图表。
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

bool _canOpenMediaLightbox(String? resolved) {
  if (resolved == null || resolved.isEmpty) return false;
  if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
    return true;
  }
  try {
    return File(resolved).existsSync();
  } catch (_) {
    return false;
  }
}

/// Fluent 2 作品详情页：含无边框标题栏、渐变融合背板、Split 启动按钮、
/// 左对齐 Pivot 标签页、游玩路径时间线、档案标签与会话存档统计。
class GameDetailPage extends ConsumerStatefulWidget {
  const GameDetailPage({
    super.key,
    required this.gameId,
    this.initial,
    this.scrollToPlayPath = false,
    this.enableWindowHooks,
  });

  final int gameId;
  final Game? initial;
  final bool scrollToPlayPath;
  final bool? enableWindowHooks;

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  final _scrollCtrl = ScrollController();
  final _tabBarKey = GlobalKey();
  final _statusFlyoutCtrl = FlyoutController();
  int _tabIndex = 0;
  int _backupReloadEpoch = 0;

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

  bool get _windowHooksEnabled =>
      widget.enableWindowHooks ?? (tryAppServices() != null);

  bool _isEditingText() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return ensureFluentScope(
      context,
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              _navigateBackToLibrary,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_isEditingText()) {
              _navigateBackToLibrary();
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Builder(builder: _buildFluentContent),
        ),
      ),
    );
  }

  Widget _buildFluentContent(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final disableAnim = fluentAnimationsDisabled(context);

    final gameAsync = ref.watch(gameProvider(widget.gameId));
    final game = gameAsync.valueOrNull ?? widget.initial;
    final sources =
        ref.watch(gameSourcesProvider(widget.gameId)).valueOrNull ?? const [];
    final tags =
        ref.watch(gameTagsProvider(widget.gameId)).valueOrNull ?? const [];
    final nodesCount =
        ref.watch(playPathProvider(widget.gameId)).valueOrNull?.length;
    final trackingId = ref.watch(trackingGameProvider);
    final isTracking = trackingId != null && trackingId == widget.gameId;
    final blurSigma = ref.watch(detailBgBlurProvider);
    final nsfwMode = ref.watch(nsfwModeProvider);

    Widget buildSubpageFrame({
      required Widget child,
      String titleText = '作品详情',
      Game? loadedGame,
      bool showFavorite = false,
    }) {
      return ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Column(
          children: [
            FluentSubpageTitleBar(
              enableWindowHooks: _windowHooksEnabled,
              onBack: _navigateBackToLibrary,
              breadcrumb: BreadcrumbBar<String>(
                items: [
                  const BreadcrumbItem<String>(
                    label: Text('游戏库'),
                    value: 'library',
                  ),
                  BreadcrumbItem<String>(
                    label: Text(
                      loadedGame?.displayName ?? titleText,
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
              trailing: [
                if (isTracking)
                  FluentBadge(
                    icon: FluentIcons.play_16_filled,
                    text: '游玩计时中',
                    foreground: theme.onAccentInk,
                    background: accent,
                  ),
                if (showFavorite && loadedGame != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: loadedGame.isFavorite ? '取消收藏' : '加入收藏',
                    child: IconButton(
                      icon: Icon(
                        loadedGame.isFavorite
                            ? FluentIcons.heart_16_filled
                            : FluentIcons.heart_16_regular,
                        size: 16,
                        color:
                            loadedGame.isFavorite ? theme.favoriteInk : null,
                      ),
                      onPressed: () => _toggleFavorite(loadedGame),
                    ),
                  ),
                ],
              ],
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    if (game == null) {
      if (gameAsync.isLoading) {
        return buildSubpageFrame(
          titleText: '加载中…',
          child: const Center(child: ProgressRing()),
        );
      }
      return buildSubpageFrame(
        titleText: '未找到作品',
        child: Center(
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

    final maskBackdrop = game.nsfw && nsfwMode != 'show';

    return buildSubpageFrame(
      loadedGame: game,
      showFavorite: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: _DetailBackdrop(
              rawBg: game.backgroundUrl.isNotEmpty
                  ? game.backgroundUrl
                  : game.coverPath,
              blurSigma: blurSigma,
              accent: accent,
              nsfwMasked: maskBackdrop,
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHero(
                        context,
                        theme,
                        accent,
                        game,
                        sources,
                        isTracking,
                      ).fluentEntrance(index: 0, disable: disableAnim),
                      const SizedBox(height: 18),
                      Align(
                        key: _tabBarKey,
                        alignment: Alignment.centerLeft,
                        child: _DetailPivotTabs(
                          index: _tabIndex,
                          playPathCount: nodesCount,
                          onChanged: (i) => setState(() => _tabIndex = i),
                        ),
                      ).fluentEntrance(index: 1, disable: disableAnim),
                      const SizedBox(height: 16),
                      _LazyDetailTabBody(
                        index: _tabIndex,
                        playPathBuilder: () => PlayPathTab(game: game),
                        archiveBuilder: () => _ArchiveAndTagsTab(
                          game: game,
                          sources: sources,
                          tags: tags,
                          onEdit: () => showEditGameDialog(context, ref, game),
                          onScrape: () =>
                              showScrapeSearchDialog(context, ref, game),
                          onFilterDeveloper: (dev) =>
                              _filterLibrary(developer: dev),
                          onFilterTag: (tag) => _filterLibrary(tag: tag),
                          onFilterSource: (src) =>
                              _filterLibrary(source: src),
                        ),
                        sessionsBuilder: () => _SessionsAndSavesTab(
                          game: game,
                          reloadEpoch: _backupReloadEpoch,
                          onEditSaveDir: () => _pickSaveDir(game),
                          onOpenBackups: () async {
                            await showSaveBackupDialog(context, ref, game);
                            if (mounted) {
                              setState(() => _backupReloadEpoch++);
                            }
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
    if (!mounted || picked == null || picked.isEmpty) return;
    game.savePath = picked;
    await tryAppServices()?.repo.updateGame(game);
    if (!mounted) return;
    if (game.id != null) ref.invalidate(gameProvider(game.id!));
    bumpLibrary(ref);
    setState(() => _backupReloadEpoch++);
    showNotice('已更新存档目录');
  }

  Future<void> _toggleFavorite(Game game) async {
    await toggleGameFavorite(ref, game);
    if (!mounted) return;
    if (game.id != null) ref.invalidate(gameProvider(game.id!));
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
    final canOpenCover = _canOpenMediaLightbox(coverResolved);
    final hasExe = game.exePath.trim().isNotEmpty;
    final remoteRating = _bestRemoteRating(sources);
    final displayScore = game.userRating > 0
        ? game.userRating
        : (remoteRating > 0 ? remoteRating : 0.0);

    Widget buildCover() {
      final cover = FluentCoverImage(
        pathOrUrl: game.coverPath,
        nsfw: game.nsfw,
        width: 158,
        height: 226,
        radius: 10,
      );
      if (!canOpenCover) return cover;
      return Tooltip(
        message: '查看大图',
        child: Semantics(
          button: true,
          label: '查看「${game.displayName}」封面大图',
          child: HoverButton(
            cursor: SystemMouseCursors.click,
            onPressed: () => showFluentLightboxDialog(
              context,
              pathOrUrl: coverResolved!,
              title: game.displayName,
            ),
            builder: (context, states) => FocusBorder(
              focused: states.isFocused,
              renderOutside: false,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: states.isHovered
                        ? accent.withValues(alpha: 0.72)
                        : Colors.transparent,
                  ),
                ),
                child: cover,
              ),
            ),
          ),
        ),
      );
    }

    Widget buildInfoColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            game.displayName,
            style: theme.typography.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.18,
            ),
          ),
          if (game.nameCn.isNotEmpty && game.name != game.displayName) ...[
            const SizedBox(height: 4),
            SelectableText(
              game.name,
              style: theme.typography.body?.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 强制约定：R18 徽章严格位于评分徽章之前
          FluentR18ScoreRow(
            nsfw: game.nsfw,
            scoreText:
                displayScore > 0 ? displayScore.toStringAsFixed(1) : null,
            trailing: [
              FlyoutTarget(
                controller: _statusFlyoutCtrl,
                child: Tooltip(
                  message: '点击切换游玩状态',
                  child: Semantics(
                    button: true,
                    label: '当前游玩状态：${game.playStatus.label}，点击更改',
                    child: HoverButton(
                      cursor: SystemMouseCursors.click,
                      onPressed: () => _openStatusMenu(game),
                      builder: (context, states) => FocusBorder(
                        focused: states.isFocused,
                        renderOutside: false,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FluentStatusPill(status: game.playStatus),
                            const SizedBox(width: 2),
                            Icon(
                              FluentIcons.chevron_down_16_regular,
                              size: 12,
                              color: states.isHovered
                                  ? accent
                                  : theme.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (game.developer.isNotEmpty)
                FluentBadge(
                  icon: FluentIcons.building_16_regular,
                  text: game.developer,
                  tooltip: '在游戏库中筛选「${game.developer}」',
                  onTap: () => _filterLibrary(developer: game.developer),
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
          const SizedBox(height: 10),
          Row(
            children: [
              isTracking
                  ? Button(
                      style: ButtonStyle(
                        backgroundColor:
                            WidgetStatePropertyAll(theme.dangerFill),
                        foregroundColor:
                            const WidgetStatePropertyAll(Colors.white),
                      ),
                      onPressed: () => stopActiveGameSession(ref),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.stop_16_filled, size: 15),
                          SizedBox(width: 6),
                          Text('停止会话'),
                        ],
                      ),
                    )
                  : Tooltip(
                      message: hasExe ? '直接启动游戏并计时' : '尚未设置可执行文件，点击引导配置',
                      child: FilledButton(
                        onPressed: () {
                          if (!hasExe) {
                            showEditGameDialog(context, ref, game);
                            return;
                          }
                          GameLaunchService.launchAndTrack(game, ref);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.play_16_filled, size: 15),
                            const SizedBox(width: 6),
                            Text(hasExe ? '启动游戏' : '配置启动程序'),
                          ],
                        ),
                      ),
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: CommandBar(
                  overflowBehavior: CommandBarOverflowBehavior.dynamicOverflow,
                  primaryItems: [
                    CommandBarButton(
                      icon: const Icon(FluentIcons.edit_16_regular),
                      label: const Text('编辑信息'),
                      onPressed: () => showEditGameDialog(context, ref, game),
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.star_16_regular),
                      label: const Text('评分'),
                      onPressed: () => showRateGameDialog(
                        context,
                        ref,
                        game,
                        sources: sources,
                      ),
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.archive_16_regular),
                      label: const Text('存档备份'),
                      onPressed: () async {
                        await showSaveBackupDialog(context, ref, game);
                        if (mounted) setState(() => _backupReloadEpoch++);
                      },
                    ),
                    CommandBarButton(
                      icon: const Icon(
                        FluentIcons.compass_northwest_16_regular,
                      ),
                      label: const Text('探索百科'),
                      onPressed: () => openGameExploreForGame(context, game),
                    ),
                  ],
                  secondaryItems: [
                    CommandBarButton(
                      closeAfterClick: false,
                      icon: const Icon(FluentIcons.translate_16_regular),
                      label: const Text(
                        'LE 转区启动',
                        key: ValueKey('detail_le_toggle_item'),
                      ),
                      trailing: IgnorePointer(
                        child: ToggleSwitch(
                          key: const ValueKey('detail_le_toggle_switch'),
                          checked: game.useLocaleEmulator,
                          onChanged: (_) {},
                        ),
                      ),
                      onPressed: () => _toggleLocaleEmulatorMode(game),
                    ),
                    const CommandBarSeparator(),
                    CommandBarButton(
                      closeAfterClick: false,
                      icon: const Icon(FluentIcons.search_16_regular),
                      label: const Text('重新搜刮'),
                      onPressed: () => showScrapeSearchDialog(context, ref, game),
                    ),
                    CommandBarButton(
                      closeAfterClick: false,
                      icon: const Icon(FluentIcons.folder_open_16_regular),
                      label: const Text('打开目录'),
                      onPressed: (game.directory.trim().isEmpty && !hasExe)
                          ? null
                          : () => openGameDir(game),
                    ),
                    CommandBarButton(
                      closeAfterClick: false,
                      icon: Icon(
                        FluentIcons.delete_16_regular,
                        color: theme.dangerInk,
                      ),
                      label: Text(
                        '移出库',
                        style: TextStyle(color: theme.dangerInk),
                      ),
                      onPressed: () async {
                        final ok = await confirmDeleteGame(context, ref, game);
                        if (ok && context.mounted) {
                          _navigateBackToLibrary();
                        }
                      },
                    ),
                  ],
                ),
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

  Future<void> _toggleLocaleEmulatorMode(Game game) async {
    final enable = !game.useLocaleEmulator;
    game.localeMode = enable ? 'japanese' : 'none';
    if (mounted) setState(() {});
    await tryAppServices()?.repo.updateGame(game);
    bumpLibrary(ref);
    if (game.id != null) {
      ref.invalidate(gameProvider(game.id!));
    }
    if (!enable) {
      showNotice('已关闭「${game.displayName}」的 LE 转区启动');
      return;
    }
    final services = tryAppServices();
    final lePlugin = services?.plugins.byId(kLocaleEmulatorPluginId);
    if (services != null && (lePlugin == null || !lePlugin.enabled)) {
      showNotice(
        '已开启 LE 转区启动，请先在「设置 → 插件与关于」安装并启用 Locale Emulator 插件',
        error: true,
      );
      return;
    }
    if (services != null) {
      final lePath = (lePlugin?.config['le_path'] ?? '').toString().trim();
      if (lePath.isEmpty) {
        showNotice(
          '已开启 LE 转区启动，请先在「设置 → 插件与关于」配置 LEProc.exe 路径',
          error: true,
        );
        return;
      }
    }
    showNotice('已为「${game.displayName}」开启 LE 转区启动');
  }

  void _openStatusMenu(Game game) {
    _statusFlyoutCtrl.showFlyout<void>(
      barrierDismissible: true,
      dismissWithEsc: true,
      dismissOnPointerMoveAway: false,
      builder: (flyoutCtx) => ensureFluentTheme(
        flyoutCtx,
        MenuFlyout(
          items: [
            for (final status in PlayStatus.values)
              RadioMenuFlyoutItem<PlayStatus>(
                text: Text(status.label),
                value: status,
                groupValue: game.playStatus,
                onChanged: (_) async {
                  // MenuFlyoutItem 默认自带 closeAfterClick，切勿再次手动 pop 误关详情页。
                  await updateGamePlayStatus(ref, game, status);
                  if (!mounted) return;
                  if (game.id != null) ref.invalidate(gameProvider(game.id!));
                },
              ),
          ],
        ),
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

class _DetailBackdrop extends StatefulWidget {
  const _DetailBackdrop({
    required this.rawBg,
    required this.blurSigma,
    required this.accent,
    this.nsfwMasked = false,
  });

  final String rawBg;
  final double blurSigma;
  final Color accent;
  final bool nsfwMasked;

  @override
  State<_DetailBackdrop> createState() => _DetailBackdropState();
}

class _DetailBackdropState extends State<_DetailBackdrop> {
  String? _resolved;
  bool _isUrl = false;
  bool _fileExists = false;

  @override
  void initState() {
    super.initState();
    _syncSource();
  }

  @override
  void didUpdateWidget(covariant _DetailBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawBg != widget.rawBg ||
        oldWidget.nsfwMasked != widget.nsfwMasked) {
      _syncSource();
    }
  }

  void _syncSource() {
    if (widget.nsfwMasked) {
      _resolved = null;
      _isUrl = false;
      _fileExists = false;
      return;
    }
    final r = _safeResolveMedia(widget.rawBg);
    _resolved = r;
    if (r == null) {
      _isUrl = false;
      _fileExists = false;
      return;
    }
    _isUrl = r.startsWith('http://') || r.startsWith('https://');
    _fileExists = !_isUrl && File(r).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final disableAnim = fluentAnimationsDisabled(context);

    Widget? bgImage;
    if (!widget.nsfwMasked && _resolved != null) {
      if (_isUrl) {
        bgImage = CachedNetworkImage(
          imageUrl: _resolved!,
          fit: BoxFit.cover,
          memCacheWidth: 640,
          filterQuality: FilterQuality.low,
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        );
      } else if (_fileExists) {
        bgImage = Image.file(
          File(_resolved!),
          fit: BoxFit.cover,
          cacheWidth: 640,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      }
    }

    final applyBlur =
        !disableAnim && widget.blurSigma > 0.1;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (bgImage != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 460,
            // 垂直透明度渐隐遮罩：在 Mica / Acrylic 透明底衬下无任何硬横切缝
            child: RepaintBoundary(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.42, 1.0],
                ).createShader(bounds),
                child: ClipRect(
                  child: applyBlur
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: widget.blurSigma,
                            sigmaY: widget.blurSigma,
                          ),
                          child: Opacity(
                            opacity: isDark ? 0.30 : 0.22,
                            child: bgImage,
                          ),
                        )
                      : Opacity(
                          opacity: isDark ? 0.26 : 0.18,
                          child: bgImage,
                        ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 360,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.accent.withValues(alpha: isDark ? 0.10 : 0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailPivotTabs extends StatelessWidget {
  const _DetailPivotTabs({
    required this.index,
    required this.onChanged,
    this.playPathCount,
  });

  final int index;
  final int? playPathCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final disableAnim = fluentAnimationsDisabled(context);

    final tabs = [
      (0, '游玩路径', FluentIcons.timeline_20_regular, playPathCount),
      (1, '档案与标签', FluentIcons.document_16_regular, null),
      (2, '会话与存档', FluentIcons.history_16_regular, null),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.surfaceStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in tabs)
            Semantics(
              button: true,
              selected: index == t.$1,
              label: t.$2,
              child: HoverButton(
                cursor: SystemMouseCursors.click,
                onPressed: () => onChanged(t.$1),
                builder: (context, states) {
                  final active = index == t.$1;
                  final bg = active
                      ? (theme.isDark
                          ? const Color(0xFF383838)
                          : const Color(0xFFFFFFFF))
                      : states.isPressed
                          ? theme.subtlePressed
                          : states.isHovered
                              ? theme.subtleHover
                              : Colors.transparent;
                  return FocusBorder(
                    focused: states.isFocused,
                    renderOutside: false,
                    child: AnimatedContainer(
                      duration: disableAnim ? Duration.zero : FluentMotion.fast,
                      curve: FluentMotion.enterCurve,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              active ? theme.surfaceStroke : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            t.$3,
                            size: 15,
                            color: active ? accent : theme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.$2,
                            style: theme.typography.body?.copyWith(
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w500,
                              color: active
                                  ? theme.textPrimary
                                  : theme.textSecondary,
                            ),
                          ),
                          if (t.$4 != null && t.$4! > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${t.$4}',
                              style: theme.typography.caption?.copyWith(
                                color: active ? accent : theme.textTertiary,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
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
}

class _LazyDetailTabBody extends StatefulWidget {
  final int index;
  final Widget Function() playPathBuilder;
  final Widget Function() archiveBuilder;
  final Widget Function() sessionsBuilder;

  const _LazyDetailTabBody({
    required this.index,
    required this.playPathBuilder,
    required this.archiveBuilder,
    required this.sessionsBuilder,
  });

  @override
  State<_LazyDetailTabBody> createState() => _LazyDetailTabBodyState();
}

class _LazyDetailTabBodyState extends State<_LazyDetailTabBody> {
  final Set<int> _mounted = {0};

  @override
  void didUpdateWidget(covariant _LazyDetailTabBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _mounted.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        _mounted.contains(0)
            ? widget.playPathBuilder()
            : const SizedBox.shrink(),
        _mounted.contains(1)
            ? widget.archiveBuilder()
            : const SizedBox.shrink(),
        _mounted.contains(2)
            ? widget.sessionsBuilder()
            : const SizedBox.shrink(),
      ],
    );
  }
}

class _ArchiveAndTagsTab extends StatelessWidget {
  const _ArchiveAndTagsTab({
    required this.game,
    required this.sources,
    required this.tags,
    required this.onEdit,
    required this.onScrape,
    required this.onFilterDeveloper,
    required this.onFilterTag,
    required this.onFilterSource,
  });

  final Game game;
  final List<SourceRecord> sources;
  final List<TagItem> tags;
  final VoidCallback onEdit;
  final VoidCallback onScrape;
  final ValueChanged<String> onFilterDeveloper;
  final ValueChanged<String> onFilterTag;
  final ValueChanged<String> onFilterSource;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final accent = theme.accentInk;

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
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
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
                  const Spacer(),
                  if (game.summary.trim().isEmpty)
                    HyperlinkButton(
                      onPressed: onEdit,
                      child: const Text('去补充'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                game.summary.trim().isNotEmpty ? game.summary : '暂无作品简介',
                style: theme.typography.body?.copyWith(
                  height: 1.6,
                  color: game.summary.trim().isEmpty
                      ? theme.textSecondary
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
              _MetaRow(label: '原名', value: game.name),
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
                _MetaRow(label: '安装目录', value: game.directory, copyable: true),
              if (game.exePath.isNotEmpty)
                _MetaRow(label: '启动程序', value: game.exePath, copyable: true),
              if (game.aliases.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '别名',
                  style: theme.typography.caption?.copyWith(
                    color: theme.textSecondary,
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
                              color: theme.surfaceStroke,
                            ),
                          ),
                          child: SelectableText(a, style: theme.typography.caption),
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
                  const Spacer(),
                  if (tags.isEmpty)
                    HyperlinkButton(
                      onPressed: onEdit,
                      child: const Text('管理标签'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (tags.isEmpty)
                Text(
                  '暂无标签',
                  style: theme.typography.caption?.copyWith(
                    color: theme.textSecondary,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags
                      .map(
                        (t) => FluentBadge(
                          text: '#${t.name}',
                          tooltip: '在游戏库筛选标签 #${t.name}',
                          onTap: () => onFilterTag(t.name),
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
                  const Spacer(),
                  if (sources.isEmpty)
                    HyperlinkButton(
                      onPressed: onScrape,
                      child: const Text('去搜刮关联'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (sources.isEmpty)
                Text(
                  '尚未关联外部元数据平台',
                  style: theme.typography.caption?.copyWith(
                    color: theme.textSecondary,
                  ),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < sources.length; i++) ...[
                      if (i > 0) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                      ],
                      _SourceLinkRow(
                        source: sources[i],
                        label: KisakiSources.labels[sources[i].source] ??
                            sources[i].source,
                        pageUrl: _sourcePageUrl(sources[i]),
                        accent: accent,
                        onFilterSource: () =>
                            onFilterSource(sources[i].source),
                        onOpenUrl: _openSourceUrl,
                      ),
                    ],
                  ],
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

class _SourceLinkRow extends StatelessWidget {
  final SourceRecord source;
  final String label;
  final String? pageUrl;
  final Color accent;
  final VoidCallback onFilterSource;
  final ValueChanged<String> onOpenUrl;

  const _SourceLinkRow({
    required this.source,
    required this.label,
    required this.pageUrl,
    required this.accent,
    required this.onFilterSource,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        FluentBadge(
          text: label,
          tooltip: '按来源「$label」筛选游戏库',
          onTap: onFilterSource,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            'ID: ${source.sourceId}',
            style: theme.typography.caption?.copyWith(
              color: theme.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (source.rating > 0) ...[
          Icon(FluentIcons.star_16_filled, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            source.rating.toStringAsFixed(1),
            style: theme.typography.bodyStrong?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (source.voteCount > 0)
            Text(
              ' (${source.voteCount})',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
        if (pageUrl != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: '在浏览器中打开原页面',
            child: IconButton(
              icon: const Icon(FluentIcons.open_16_regular, size: 14),
              onPressed: () => onOpenUrl(pageUrl!),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.onTap,
    this.copyable = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: onTap == null
                ? SelectableText(value, style: theme.typography.body)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: '在游戏库中筛选「$value」',
                      child: HyperlinkButton(
                        onPressed: onTap,
                        child: Text(
                          value,
                          style: TextStyle(color: accent),
                        ),
                      ),
                    ),
                  ),
          ),
          if (copyable && value.trim().isNotEmpty)
            Tooltip(
              message: '复制路径',
              child: IconButton(
                icon: const Icon(FluentIcons.copy_16_regular, size: 13),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  showNotice('已复制到剪贴板');
                },
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
    required this.reloadEpoch,
    required this.onEditSaveDir,
    required this.onOpenBackups,
  });

  final Game game;
  final int reloadEpoch;
  final VoidCallback onEditSaveDir;
  final Future<void> Function() onOpenBackups;

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
    if (oldWidget.game.id != widget.game.id ||
        oldWidget.reloadEpoch != widget.reloadEpoch) {
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

  Future<void> _openSaveFolder(String path) async {
    try {
      await Process.run('explorer.exe', [path.replaceAll('/', r'\')]);
    } catch (e) {
      showNotice('打开目录失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final g = widget.game;
    final hoursText = '${(g.totalSeconds / 3600).toStringAsFixed(1)} 小时';
    final durationValue =
        g.totalSeconds > 0 && g.totalSeconds < 360
            ? '${fmtDuration(g.totalSeconds)} ($hoursText)'
            : hoursText;
    final saveDirConfigured = g.savePath.trim().isNotEmpty;
    final saveDirMissing =
        saveDirConfigured && !Directory(g.savePath).existsSync();

    final kpis = [
      ('累计游玩', durationValue, FluentIcons.clock_16_regular),
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
                                    color: theme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              k.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                  if (saveDirMissing) ...[
                    FluentBadge(
                      text: '目录不存在',
                      foreground: theme.dangerInk,
                      background: theme.dangerTint,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_backups.isNotEmpty)
                    FluentBadge(text: '${_backups.length} 份备份'),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                saveDirConfigured ? g.savePath : '尚未配置本地存档目录',
                style: theme.typography.body?.copyWith(
                  color: saveDirMissing
                      ? theme.dangerInk
                      : (saveDirConfigured ? null : theme.textSecondary),
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
                  if (saveDirConfigured && !saveDirMissing)
                    Button(
                      onPressed: () => _openSaveFolder(g.savePath),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.folder_open_16_regular, size: 14),
                          SizedBox(width: 6),
                          Text('打开目录'),
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
                  Expanded(
                    child: Text('近期游玩会话', style: theme.typography.bodyStrong),
                  ),
                  if (_sessions.length >= 12)
                    Text(
                      '显示最近 12 条',
                      style: theme.typography.caption?.copyWith(
                        color: theme.textTertiary,
                      ),
                    ),
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
                    color: theme.textSecondary,
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
                            color: theme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ts != null ? fmtDateTime(ts) : '-',
                              style: theme.typography.body?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
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
  bool _loading = true;

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
      if (mounted) {
        setState(() {
          _points = cached;
          _loading = false;
        });
      }
      return;
    }

    final services = tryAppServices();
    if (services == null) {
      if (mounted) {
        setState(() {
          _points = const [];
          _loading = false;
        });
      }
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
      if (mounted) {
        setState(() {
          _points = filled;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _points = const [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
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
              Icon(
                FluentIcons.data_histogram_16_regular,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 8),
              Text('近 30 天游玩趋势（分钟）', style: theme.typography.bodyStrong),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const FluentCardSkeleton(height: 150)
          else if (!hasActivity)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '近 30 天暂无游玩记录',
                style: theme.typography.caption?.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            )
          else
            SizedBox(
              height: 164,
              child: BarChart(
                BarChartData(
                  maxY: maxMinutes * 1.15,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipRoundedRadius: 6,
                      tooltipBorder: BorderSide(color: theme.surfaceStroke),
                      getTooltipColor: (_) =>
                          theme.resources.solidBackgroundFillColorTertiary,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final point =
                            groupIndex >= 0 && groupIndex < _points.length
                                ? _points[groupIndex]
                                : null;
                        final label = point != null && point.date.isNotEmpty
                            ? '${point.date}\n${rod.toY.toStringAsFixed(0)} 分钟'
                            : '${rod.toY.toStringAsFixed(0)} 分钟';
                        return BarTooltipItem(
                          label,
                          (theme.typography.caption ?? const TextStyle())
                              .copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: theme.textTertiary.withValues(alpha: 0.22),
                      strokeWidth: 0.8,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        getTitlesWidget: (v, meta) {
                          if (v <= 0 || v >= meta.max * 0.96) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              '${v.round()}m',
                              style: theme.typography.caption?.copyWith(
                                fontSize: 10.5,
                                color: theme.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final idx = v.round();
                          if (idx < 0 || idx >= _points.length) {
                            return const SizedBox.shrink();
                          }
                          if (idx != 0 &&
                              idx != 14 &&
                              idx != _points.length - 1) {
                            return const SizedBox.shrink();
                          }
                          final raw = _points[idx].date;
                          final shortDate =
                              raw.length >= 10 ? raw.substring(5) : raw;
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              shortDate,
                              style: theme.typography.caption?.copyWith(
                                fontSize: 10.5,
                                color: theme.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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
                                : theme.textTertiary.withValues(alpha: 0.25),
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
