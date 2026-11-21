/// 游戏卡片、列表条目与主页货架共用的 Fluent 2 操作与右键 Flyout 菜单。
library;

import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import '../../services/game_explore_service.dart';
import '../../services/game_launch_service.dart';
import '../../services/game_launcher.dart';
import '../detail/edit_dialog.dart';
import '../detail/game_detail_page.dart';
import '../detail/rate_dialog.dart';
import '../detail/save_backup_dialog.dart';
import '../discover/game_explore_page.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';

export '../fluent/fluent_surfaces.dart'
    show ensureFluentScope, ensureFluentTheme;

/// 让 Flyout 蒙层同时响应左键与右键点击关闭（符合 Windows 原生右键菜单体验）。
class _AnyButtonBarrierRecognizer extends OneSequenceGestureRecognizer {
  final VoidCallback onDismiss;
  _AnyButtonBarrierRecognizer(this.onDismiss);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    resolve(GestureDisposition.accepted);
    onDismiss();
  }

  @override
  void handleEvent(PointerEvent event) {}

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'anyButtonBarrier';
}

/// 若全局服务尚未初始化（例如独立 Widget 测试），安全返回 null。
AppServices? tryAppServices() {
  try {
    final services = AppServices.I;
    return services.ready ? services : null;
  } catch (_) {
    return null;
  }
}

/// 统一页面导航：在 FluentApp 下使用 FluentPageRoute，兼容过渡期 MaterialApp。
Future<T?> pushFluentPage<T>(BuildContext context, WidgetBuilder builder) {
  final hasFluent = FluentTheme.maybeOf(context) != null;
  final navHasFluent =
      FluentTheme.maybeOf(Navigator.of(context).context) != null;
  if (hasFluent && navHasFluent) {
    return Navigator.of(context).push<T>(FluentPageRoute<T>(builder: builder));
  }
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => builder(ctx),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
}

/// 打开游戏详情页，返回后按需刷新库版本。
Future<void> openGameDetail(
  BuildContext context,
  int gameId, {
  Game? initial,
  bool scrollToPlayPath = false,
  WidgetRef? ref,
}) async {
  await pushFluentPage<void>(
    context,
    (_) => GameDetailPage(
      gameId: gameId,
      initial: initial,
      scrollToPlayPath: scrollToPlayPath,
    ),
  );
  if (ref != null && context.mounted) {
    bumpLibrary(ref);
  }
}

/// 打开游戏全景百科页。
Future<void> openGameExplore(
  BuildContext context, {
  required ScrapedGame seedGame,
  int? localGameId,
  List<SourceRecord> knownSources = const [],
}) {
  return pushFluentPage<void>(
    context,
    (_) => GameExplorePage(
      seedGame: seedGame,
      knownSources: knownSources,
      localGameId: localGameId,
    ),
  );
}

/// 从本地入库游戏构造百科种子并打开全景百科页。
Future<void> openGameExploreForGame(BuildContext context, Game game) async {
  final services = tryAppServices();
  List<SourceRecord> sources = const [];
  if (services != null && game.id != null) {
    try {
      sources = await services.repo.sourcesOf(game.id!);
    } catch (_) {}
  }
  if (!context.mounted) return;
  final seed = GameExploreService.seedFromLocalGame(game, sources);
  await openGameExplore(
    context,
    seedGame: seed,
    localGameId: game.id,
    knownSources: sources,
  );
}

/// 在资源管理器中打开并高亮选中游戏可执行文件或目录。
Future<void> openGameDir(Game g) async {
  final exe = g.exePath.trim();
  if (exe.isNotEmpty && File(exe).existsSync()) {
    await Process.run(
      'explorer.exe',
      ['/select,${exe.replaceAll('/', r'\')}'],
    );
    return;
  }
  final dir = g.directory.trim();
  if (dir.isNotEmpty) {
    await GameLauncher.openDirectory(dir);
    return;
  }
  showNotice('未设置游戏目录或可执行文件路径', error: true);
}

/// 停止当前追踪中的游戏会话并保存记录。
Future<void> stopActiveGameSession(WidgetRef ref) async {
  tryAppServices()?.tracker.stopTracking(saveSession: true);
  ref.read(trackingGameProvider.notifier).state = null;
  bumpLibrary(ref);
  showNotice('已结束游玩会话并保存记录');
}

Future<void> toggleGameFavorite(WidgetRef ref, Game game) async {
  final prev = game.isFavorite;
  game.isFavorite = !prev;
  try {
    await tryAppServices()?.repo.updateGame(game);
    bumpLibrary(ref);
    showNotice(game.isFavorite
        ? '已收藏「${game.displayName}」'
        : '已取消收藏「${game.displayName}」');
  } catch (e) {
    game.isFavorite = prev;
    showNotice('更新收藏状态失败：$e', error: true);
  }
}

Future<void> updateGamePlayStatus(
  WidgetRef ref,
  Game game,
  PlayStatus status,
) async {
  if (game.playStatus == status) return;
  final prev = game.playStatus;
  game.playStatus = status;
  try {
    await tryAppServices()?.repo.updateGame(game);
    bumpLibrary(ref);
    showNotice('已将「${game.displayName}」状态设为「${status.label}」');
  } catch (e) {
    game.playStatus = prev;
    showNotice('更新游玩状态失败：$e', error: true);
  }
}

/// 单条移出库二次确认。
Future<bool> confirmDeleteGame(
  BuildContext context,
  WidgetRef ref,
  Game game,
) async {
  final ok = await showFluentConfirmDialog(
    context,
    title: '移出游戏库',
    content: '确定要将「${game.displayName}」移出游戏库吗？\n游玩记录与统计将一并删除。',
    confirmLabel: '移出',
    cancelLabel: '取消',
    destructive: true,
  );
  if (!ok) return false;
  if (game.id != null) {
    await tryAppServices()?.repo.deleteGame(game.id!);
  }
  try {
    bumpLibrary(ref);
  } catch (_) {}
  showNotice('已移出「${game.displayName}」');
  return true;
}

/// 批量移出库二次确认。
Future<bool> confirmBatchDeleteGames(BuildContext context, int count) {
  return showFluentConfirmDialog(
    context,
    title: '批量移出',
    content: '确定要移出选中的 $count 部游戏吗？\n游玩记录与统计将一并删除。',
    confirmLabel: '移出',
    cancelLabel: '取消',
    destructive: true,
  );
}

/// 弹出 Fluent 2 `MenuFlyout` 右键 / 更多操作菜单。
Future<void> showGameMenuFlyout(
  BuildContext context,
  WidgetRef ref, {
  required FlyoutController controller,
  required Game game,
  Offset? position,
  bool allowDetail = true,
  VoidCallback? onEdit,
  VoidCallback? onRate,
}) {
  final theme = FluentTheme.maybeOf(context);
  final isDark = theme?.brightness == Brightness.dark;
  final dangerColor = theme?.dangerInk ??
      (isDark ? const Color(0xFFFF99A4) : const Color(0xFFC42B1C));
  final favColor = theme?.favoriteInk ??
      (isDark ? const Color(0xFFFF7AA2) : const Color(0xFFC4315B));
  final isRunning =
      game.id != null && ref.read(trackingGameProvider) == game.id;
  final hasExe = game.exePath.trim().isNotEmpty;
  final hasDir = game.directory.trim().isNotEmpty || hasExe;
  final hasId = game.id != null;

  void defer(VoidCallback action) {
    Future.microtask(() {
      if (context.mounted) action();
    });
  }

  late final _AnyButtonBarrierRecognizer barrierRecognizer;
  barrierRecognizer = _AnyButtonBarrierRecognizer(() {
    if (controller.isOpen) {
      controller.close<void>();
    }
  });

  return controller
      .showFlyout<void>(
    position: position,
    barrierDismissible: true,
    dismissWithEsc: true,
    barrierRecognizer: barrierRecognizer,
    builder: (flyoutCtx) => ensureFluentTheme(
      flyoutCtx,
      MenuFlyout(
        items: [
          MenuFlyoutItem(
            leading: Icon(
              isRunning
                  ? FluentIcons.stop_16_regular
                  : FluentIcons.play_16_regular,
              size: 16,
            ),
            text: Text(
              isRunning ? '停止会话' : '启动游戏',
              style: isRunning || hasExe
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
            onPressed: (!isRunning && !hasExe)
                ? null
                : () {
                    if (isRunning) {
                      stopActiveGameSession(ref);
                    } else {
                      GameLaunchService.launchAndTrack(game, ref);
                    }
                  },
          ),
          const MenuFlyoutSeparator(),
          if (allowDetail && hasId)
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.open_16_regular, size: 16),
              text: const Text('查看详情'),
              onPressed: () => defer(
                () => openGameDetail(
                  context,
                  game.id!,
                  initial: game,
                  ref: ref,
                ),
              ),
            ),
          MenuFlyoutItem(
            leading:
                const Icon(FluentIcons.compass_northwest_16_regular, size: 16),
            text: const Text('探索百科'),
            onPressed: () => defer(() => openGameExploreForGame(context, game)),
          ),
          MenuFlyoutSubItem(
            leading: const Icon(FluentIcons.bookmark_16_regular, size: 16),
            text: const Text('游玩状态'),
            items: (_) => [
              for (final s in PlayStatus.values)
                RadioMenuFlyoutItem<PlayStatus>(
                  text: Text(s.label),
                  value: s,
                  groupValue: game.playStatus,
                  onChanged: (_) => updateGamePlayStatus(ref, game, s),
                ),
            ],
          ),
          MenuFlyoutItem(
            leading: Icon(
              game.isFavorite
                  ? FluentIcons.heart_16_filled
                  : FluentIcons.heart_16_regular,
              size: 16,
              color: game.isFavorite ? favColor : null,
            ),
            text: Text(game.isFavorite ? '取消收藏' : '收藏'),
            onPressed: () => toggleGameFavorite(ref, game),
          ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.edit_16_regular, size: 16),
            text: const Text('编辑信息'),
            onPressed: onEdit != null
                ? () => defer(onEdit)
                : (hasId
                    ? () => defer(() => showEditGameDialog(context, ref, game))
                    : null),
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.star_16_regular, size: 16),
            text: const Text('评分'),
            onPressed: onRate != null
                ? () => defer(onRate)
                : (hasId
                    ? () => defer(() => showRateGameDialog(context, ref, game))
                    : null),
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.archive_16_regular, size: 16),
            text: const Text('存档备份'),
            onPressed: hasId
                ? () => defer(() => showSaveBackupDialog(context, ref, game))
                : null,
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.folder_open_16_regular, size: 16),
            text: const Text('打开目录'),
            onPressed: hasDir ? () => openGameDir(game) : null,
          ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: Icon(
              FluentIcons.delete_16_regular,
              size: 16,
              color: hasId ? dangerColor : null,
            ),
            text: Text(
              '移出库',
              style: hasId ? TextStyle(color: dangerColor) : null,
            ),
            onPressed: hasId
                ? () => defer(() => confirmDeleteGame(context, ref, game))
                : null,
          ),
        ],
      ),
    ),
  )
      .whenComplete(barrierRecognizer.dispose);
}

/// [showGameMenuFlyout] 的便捷别名。
Future<void> showGameContextMenu(
  BuildContext context,
  WidgetRef ref, {
  required FlyoutController controller,
  required Game game,
  Offset? position,
  bool allowDetail = true,
  VoidCallback? onEdit,
  VoidCallback? onRate,
}) =>
    showGameMenuFlyout(
      context,
      ref,
      controller: controller,
      game: game,
      position: position,
      allowDetail: allowDetail,
      onEdit: onEdit,
      onRate: onRate,
    );
