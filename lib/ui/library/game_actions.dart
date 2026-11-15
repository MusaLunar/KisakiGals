/// 游戏卡片、列表条目与主页货架共用的 Fluent 2 操作与右键 Flyout 菜单。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../main.dart' show minimizeToTray;
import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import '../../services/game_explore_service.dart';
import '../../services/game_launch_service.dart';
import '../../services/game_launcher.dart';
import '../detail/game_detail_page.dart';
import '../detail/save_backup_dialog.dart';
import '../discover/game_explore_page.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_theme.dart';

/// 若全局服务尚未初始化（例如独立 Widget 测试），安全返回 null。
AppServices? tryAppServices() {
  try {
    final services = AppServices.I;
    return services.ready ? services : null;
  } catch (_) {
    return null;
  }
}

/// 在任务 9 全面切换 FluentApp 之前，若上层缺少 FluentTheme 则提供兜底主题。
Widget ensureFluentTheme(BuildContext context, Widget child) {
  if (FluentTheme.maybeOf(context) != null) return child;
  final brightness =
      MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
  return FluentTheme(
    data: buildFluentTheme(
      brightness: brightness,
      preset: AccentPreset.system,
      systemAccent: kDefaultWin11Azure,
      backdrop: BackdropEffectPref.mica,
    ),
    child: child,
  );
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
    await Process.run('explorer.exe', ['/select,', exe.replaceAll('/', r'\')]);
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
}

/// 使用 Locale Emulator 转区启动（不覆盖游戏原有的持久 localeMode 设置）。
Future<void> launchGameWithLocaleEmulator(Game game, WidgetRef ref) async {
  if (game.id == null) return;
  if (game.useLocaleEmulator) {
    await GameLaunchService.launchAndTrack(game, ref);
    return;
  }
  final services = tryAppServices();
  if (services == null) {
    showNotice('服务尚未就绪，无法启动游戏', error: true);
    return;
  }
  if (services.tracker.refreshAndCheckActive()) {
    final runningId = services.tracker.trackedGameId;
    if (runningId == game.id) {
      showNotice('「${game.displayName}」已在运行中，无需重复启动', error: true);
    } else {
      final runningGame =
          runningId != null ? await services.repo.getGame(runningId) : null;
      final title = runningGame?.displayName ?? '其他游戏';
      showNotice('「$title」正在后台运行，请先关闭当前游戏或结束会话后再启动', error: true);
    }
    return;
  }
  if (game.exePath.isEmpty || !File(game.exePath).existsSync()) {
    showNotice('未找到游戏可执行文件，请先在「编辑信息」中设置', error: true);
    return;
  }

  final lePath = await services.settings.getString(SettingsStore.kLePath, '');
  if (lePath.isEmpty || !File(lePath).existsSync()) {
    showNotice('未配置 Locale Emulator 路径，请在设置中指定 LEProc.exe', error: true);
    return;
  }

  final result = await GameLauncher.launch(
    game.exePath,
    directory: game.directory,
    localeEmulatorPath: lePath,
  );
  if (!result.ok) {
    showNotice(result.message.isEmpty ? '启动失败' : result.message, error: true);
    return;
  }
  if (result.message.isNotEmpty) showNotice(result.message);

  final mode = await services.settings.trackingMode();
  services.tracker.startTracking(
    gameId: game.id!,
    exePath: game.exePath,
    directory: game.directory,
    mode: mode,
  );
  ref.read(trackingGameProvider.notifier).state = game.id!;
  await services.settings.setString('runtime.last_game', '${game.id}');

  final after = await services.settings.getString(SettingsStore.kAfterLaunch, 'none');
  if (after == 'minimize') {
    await minimizeToTray();
  }

  if (game.playStatus == PlayStatus.wish) {
    game.playStatus = PlayStatus.playing;
    await services.repo.updateGame(game);
  }
  bumpLibrary(ref);
}

Future<void> toggleGameFavorite(WidgetRef ref, Game game) async {
  game.isFavorite = !game.isFavorite;
  await tryAppServices()?.repo.updateGame(game);
  bumpLibrary(ref);
}

Future<void> updateGamePlayStatus(
  WidgetRef ref,
  Game game,
  PlayStatus status,
) async {
  if (game.playStatus == status) return;
  game.playStatus = status;
  await tryAppServices()?.repo.updateGame(game);
  bumpLibrary(ref);
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
  if (context.mounted) {
    bumpLibrary(ref);
  }
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
  final dangerColor =
      isDark ? const Color(0xFFFF99A4) : const Color(0xFFD13438);
  final favColor = isDark ? const Color(0xFFF47299) : const Color(0xFFC4315B);
  final isRunning =
      game.id != null && ref.read(trackingGameProvider) == game.id;

  return controller.showFlyout<void>(
    position: position,
    barrierDismissible: true,
    dismissWithEsc: true,
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
            text: Text(isRunning ? '停止会话' : '启动游戏'),
            onPressed: () {
              if (isRunning) {
                stopActiveGameSession(ref);
              } else {
                GameLaunchService.launchAndTrack(game, ref);
              }
            },
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.translate_16_regular, size: 16),
            text: const Text('LE 转区启动'),
            onPressed: () => launchGameWithLocaleEmulator(game, ref),
          ),
          const MenuFlyoutSeparator(),
          if (allowDetail && game.id != null)
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.open_16_regular, size: 16),
              text: const Text('查看详情'),
              onPressed: () => openGameDetail(
                context,
                game.id!,
                initial: game,
                ref: ref,
              ),
            ),
          MenuFlyoutItem(
            leading:
                const Icon(FluentIcons.compass_northwest_16_regular, size: 16),
            text: const Text('探索百科'),
            onPressed: () => openGameExploreForGame(context, game),
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
            onPressed: onEdit ??
                (game.id == null
                    ? null
                    : () => openGameDetail(
                          context,
                          game.id!,
                          initial: game,
                          ref: ref,
                        )),
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.star_16_regular, size: 16),
            text: const Text('评分'),
            onPressed: onRate ??
                (game.id == null
                    ? null
                    : () => openGameDetail(
                          context,
                          game.id!,
                          initial: game,
                          ref: ref,
                        )),
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.archive_16_regular, size: 16),
            text: const Text('存档备份'),
            onPressed: () => showSaveBackupDialog(context, ref, game),
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.folder_open_16_regular, size: 16),
            text: const Text('打开目录'),
            onPressed: (game.directory.isEmpty && game.exePath.isEmpty)
                ? null
                : () => openGameDir(game),
          ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: Icon(
              FluentIcons.delete_16_regular,
              size: 16,
              color: dangerColor,
            ),
            text: Text('移出库', style: TextStyle(color: dangerColor)),
            onPressed: () => confirmDeleteGame(context, ref, game),
          ),
        ],
      ),
    ),
  );
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
