/// 游戏卡片的共享操作：右键菜单、单条/批量删除确认。
///
/// 网格卡片（[GameCard]）与紧凑列表条目（[GameListTile]）共用这一份实现，
/// 避免两套菜单出现行为差异。视觉全部走 design.dart 的 token 与 kit 原语，
/// 不再各页手写菜单外观。
library;

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
import '../theme.dart';

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
    final rect = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );
    final action = await showMenu<String>(
      context: context,
      position: rect,
      shape: RoundedRectangleBorder(borderRadius: Radii.button),
      items: [
        if (allowDetail)
          const PopupMenuItem(
            value: 'detail',
            height: _menuItemHeight,
            child: _MenuEntry(icon: Icons.info_outline_rounded, label: '查看详情'),
          ),
        const PopupMenuItem(
          value: 'open',
          height: _menuItemHeight,
          child: _MenuEntry(icon: Icons.play_arrow_rounded, label: '启动游戏'),
        ),
        if (game.directory.isNotEmpty)
          const PopupMenuItem(
            value: 'dir',
            height: _menuItemHeight,
            child: _MenuEntry(icon: Icons.folder_open_rounded, label: '打开目录'),
          ),
        const PopupMenuItem(
          value: 'status',
          height: _menuItemHeight,
          child: _MenuEntry(
              icon: Icons.radio_button_checked_rounded, label: '更改状态'),
        ),
        PopupMenuItem(
          value: 'fav',
          height: _menuItemHeight,
          child: _MenuEntry(
            icon: game.isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: game.isFavorite ? '取消收藏' : '加入收藏',
            color: game.isFavorite ? KisakiColors.pink : null,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          height: _menuItemHeight,
          child: _MenuEntry(
              icon: Icons.delete_outline_rounded,
              label: '删除游戏',
              color: KisakiColors.danger),
        ),
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
          position: rect,
          shape: RoundedRectangleBorder(borderRadius: Radii.button),
          items: [
            for (final s in PlayStatus.values)
              PopupMenuItem(
                value: s,
                height: _menuItemHeight,
                child: _StatusEntry(status: s, current: game.playStatus),
              ),
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
    final ok = await showKisakiDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除游戏'),
        content: Text('确定要删除「$name」吗？\n游玩记录与统计将一并删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: KisakiColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    return ok == true;
  }

  /// 批量删除二次确认：与单条删除同一套外观，只换文案与计数。
  static Future<bool> confirmBatchDelete(BuildContext context, int count) async {
    final ok = await showKisakiDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 $count 部游戏吗？\n游玩记录与统计将一并删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: KisakiColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    return ok == true;
  }

  /// 右键菜单项高度（比 Material 默认 48 紧凑，桌面鼠标操作更顺手）。
  static const double _menuItemHeight = 38;
}

/// 菜单项：图标 + 文字（危险操作用语义色）。
class _MenuEntry extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuEntry({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: 10),
        Text(label, style: Type.body.copyWith(color: color)),
      ],
    );
  }
}

/// 状态子菜单项：当前状态打勾（保持勾选位占位，文字左对齐不跳动）。
class _StatusEntry extends StatelessWidget {
  final PlayStatus status;
  final PlayStatus current;

  const _StatusEntry({required this.status, required this.current});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: status == current
              ? Icon(Icons.check_rounded, size: 16, color: scheme.primary)
              : null,
        ),
        const SizedBox(width: 10),
        Text(status.label, style: Type.body),
      ],
    );
  }
}
