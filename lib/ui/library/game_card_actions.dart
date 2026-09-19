import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../services/game_launcher.dart';
import '../../services/game_launch_service.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';

/// 游戏卡片的共享操作：右键菜单与批量选择逻辑。
/// 网格卡片（[GameCard]）与紧凑列表卡片（[GameListTile]）共用，避免两份实现。
class GameCardActions {
  /// 在 [position] 处弹出右键菜单。
  static Future<void> showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Game game,
    Offset position, {
    bool allowDetail = true,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        if (allowDetail)
          const PopupMenuItem(value: 'detail', child: Text('查看详情')),
        const PopupMenuItem(value: 'open', child: Text('启动游戏')),
        if (game.directory.isNotEmpty)
          const PopupMenuItem(value: 'dir', child: Text('打开目录')),
        const PopupMenuItem(value: 'status', child: Text('更改状态')),
        PopupMenuItem(
            value: 'fav', child: Text(game.isFavorite ? '取消收藏' : '加入收藏')),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'delete',
            child: Text('删除游戏', style: TextStyle(color: Colors.red))),
      ],
    );
    if (action == null || !context.mounted) return;
    final repo = AppServices.I.repo;
    switch (action) {
      case 'detail':
        await Navigator.of(context).push(FadeThroughRoute.builder(
            builder: (_) =>
                GameDetailPage(gameId: game.id!, initial: game)));
        ref.read(libraryVersionProvider.notifier).state++;
        break;
      case 'open':
        await GameLaunchService.launchAndTrack(game, ref);
        break;
      case 'dir':
        GameLauncher.openDirectory(game.directory);
        break;
      case 'status':
        if (!context.mounted) return;
        final status = await showMenu<PlayStatus>(
          context: context,
          position: RelativeRect.fromLTRB(
              position.dx,
              position.dy,
              overlay.size.width - position.dx,
              overlay.size.height - position.dy),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          items: [
            for (final s in PlayStatus.values)
              PopupMenuItem(
                  value: s,
                  child: Row(children: [
                    if (game.playStatus == s)
                      const Icon(Icons.check_rounded, size: 16)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 6),
                    Text(s.label),
                  ])),
          ],
        );
        if (status != null) {
          game.playStatus = status;
          await repo.updateGame(game);
          ref.read(libraryVersionProvider.notifier).state++;
        }
        break;
      case 'fav':
        game.isFavorite = !game.isFavorite;
        await repo.updateGame(game);
        ref.read(libraryVersionProvider.notifier).state++;
        break;
      case 'delete':
        if (!context.mounted) return;
        final ok = await confirmDelete(context, game.displayName);
        if (ok) {
          await repo.deleteGame(game.id!);
          ref.read(libraryVersionProvider.notifier).state++;
        }
        break;
    }
  }

  /// 删除二次确认（游戏库批量删除、详情页也复用同一文案）。
  static Future<bool> confirmDelete(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除游戏'),
        content: Text('确定要删除「$name」吗？\n游玩记录与统计将一并删除。'),
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
    return ok == true;
  }
}
