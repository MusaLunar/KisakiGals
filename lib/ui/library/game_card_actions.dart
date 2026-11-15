/// 游戏卡片的共享操作：Material Design 3 自定义右键菜单、单条/批量删除确认。
///
/// 网格卡片（[GameCard]）与紧凑列表条目（[GameListTile]）共用这一份实现，
/// 避免两套菜单出现行为差异。视觉全部遵循 Material Design 3 三原色规范。
library;

import 'dart:math' as math;

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
import '../widgets/common.dart';

class GameCardActions {
  /// 在 [position] 右侧弹出 Material Design 3 自定义上下文菜单。
  static Future<void> showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Game game,
    Offset position, {
    bool allowDetail = true,
  }) async {
    final screen = MediaQuery.sizeOf(context);
    const double menuWidth = 276.0;
    final estimatedHeight = (allowDetail ? 404.0 : 362.0) +
        (game.directory.isNotEmpty ? 40.0 : 0.0);

    // 优先呈现在鼠标右侧；若右侧超出可视区域则翻转至左侧
    double left = position.dx + 8;
    if (left + menuWidth > screen.width - 12) {
      left = (position.dx - menuWidth - 8)
          .clamp(12.0, math.max(12.0, screen.width - menuWidth - 12));
    } else {
      left = left.clamp(12.0, math.max(12.0, screen.width - menuWidth - 12));
    }

    final maxTop = math.max(12.0, screen.height - estimatedHeight - 12);
    final top = position.dy.clamp(12.0, maxTop);

    final result = await showGeneralDialog<_ContextMenuAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭右键菜单',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (dialogCtx, _, __) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(dialogCtx).pop(),
                onSecondaryTap: () => Navigator.of(dialogCtx).pop(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: menuWidth,
                  maxHeight: math.max(220.0, screen.height - 24),
                ),
                child: _M3GameContextMenu(
                  game: game,
                  allowDetail: allowDetail,
                  width: menuWidth,
                  onSelect: (action) => Navigator.of(dialogCtx).pop(action),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Motion.enter,
          reverseCurve: Motion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );

    if (result == null || !context.mounted) return;
    final repo = AppServices.I.repo;
    switch (result.kind) {
      case 'detail':
        await Navigator.of(context).push(FadeThroughRoute.builder(
            builder: (_) =>
                GameDetailPage(gameId: game.id!, initial: game)));
        ref.read(libraryVersionProvider.notifier).state++;
        break;
      case 'play_path':
        await Navigator.of(context).push(FadeThroughRoute.builder(
            builder: (_) => GameDetailPage(
                gameId: game.id!, initial: game, scrollToPlayPath: true)));
        ref.read(libraryVersionProvider.notifier).state++;
        break;
      case 'open':
        await GameLaunchService.launchAndTrack(game, ref);
        break;
      case 'dir':
        GameLauncher.openDirectory(game.directory);
        break;
      case 'status':
        final status = result.status;
        if (status != null && status != game.playStatus) {
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

  /// 批量删除二次确认（占位保持 API 一致）。
  static const double _menuItemHeight = 40;
}

class _ContextMenuAction {
  final String kind;
  final PlayStatus? status;
  const _ContextMenuAction(this.kind, [this.status]);
}

class _M3GameContextMenu extends StatelessWidget {
  final Game game;
  final bool allowDetail;
  final double width;
  final ValueChanged<_ContextMenuAction> onSelect;

  const _M3GameContextMenu({
    required this.game,
    required this.allowDetail,
    required this.width,
    required this.onSelect,
  });

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return '尚未游玩';
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final menuBg =
        dark ? KisakiColors.nightElevated : KisakiColors.paperElevated;
    final roseInk = KisakiColors.roseInk(dark);
    final lavInk = KisakiColors.temporalInk(dark);
    final peachInk = KisakiColors.ratingInk(dark);

    final subtitleParts = <String>[
      _formatMinutes(game.totalSeconds ~/ 60),
      if (game.userRating > 0) '★ ${game.userRating.toStringAsFixed(1)}',
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: menuBg,
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: Elev.border(dark), width: 1),
          boxShadow: Elev.overlay(dark),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.xl - 1),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. M3 三色调迷你封面抬头
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        KisakiColors.m3Rose
                            .withValues(alpha: dark ? 0.22 : 0.24),
                        KisakiColors.m3Lavender
                            .withValues(alpha: dark ? 0.18 : 0.24),
                        KisakiColors.m3Peach
                            .withValues(alpha: dark ? 0.16 : 0.22),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(
                      color: KisakiColors.m3Rose
                          .withValues(alpha: dark ? 0.30 : 0.26),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        height: 50,
                        child: CoverImage(
                          path: game.coverPath,
                          nsfw: game.nsfw,
                          borderRadius: BorderRadius.circular(Radii.xs),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              game.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.label.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitleParts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.caption.copyWith(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // 2. 单击直达 5 状态胶囊条
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: dark
                        ? KisakiColors.nightCard
                        : KisakiColors.paperSunken,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: Elev.border(dark), width: 1),
                  ),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      for (final s in PlayStatus.values)
                        _M3StatusChip(
                          status: s,
                          selected: s == game.playStatus,
                          dark: dark,
                          onTap: () =>
                              onSelect(_ContextMenuAction('status', s)),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // 3. Tonal 图标操作列表
                _M3ContextRow(
                  icon: Icons.play_arrow_rounded,
                  label: '启动游戏',
                  badgeColor: KisakiColors.m3Rose,
                  iconInk: roseInk,
                  emphasized: true,
                  dark: dark,
                  onTap: () => onSelect(const _ContextMenuAction('open')),
                ),
                if (allowDetail)
                  _M3ContextRow(
                    icon: Icons.info_outline_rounded,
                    label: '查看详情',
                    badgeColor: KisakiColors.m3Lavender,
                    iconInk: lavInk,
                    dark: dark,
                    onTap: () => onSelect(const _ContextMenuAction('detail')),
                  ),
                _M3ContextRow(
                  icon: Icons.route_rounded,
                  label: '游玩路径 / 笔记',
                  badgeColor: KisakiColors.m3Peach,
                  iconInk: peachInk,
                  dark: dark,
                  onTap: () => onSelect(const _ContextMenuAction('play_path')),
                ),
                if (game.directory.isNotEmpty)
                  _M3ContextRow(
                    icon: Icons.folder_open_rounded,
                    label: '打开目录',
                    badgeColor: KisakiColors.m3Lavender,
                    iconInk: lavInk,
                    dark: dark,
                    onTap: () => onSelect(const _ContextMenuAction('dir')),
                  ),
                _M3ContextRow(
                  icon: game.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: game.isFavorite ? '取消收藏' : '加入收藏',
                  badgeColor: KisakiColors.m3Rose,
                  iconInk: roseInk,
                  dark: dark,
                  onTap: () => onSelect(const _ContextMenuAction('fav')),
                ),

                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Divider(height: 1, color: Elev.border(dark)),
                ),

                _M3ContextRow(
                  icon: Icons.delete_outline_rounded,
                  label: '删除游戏',
                  badgeColor: KisakiColors.danger,
                  iconInk: KisakiColors.danger,
                  textColor: KisakiColors.danger,
                  dark: dark,
                  onTap: () => onSelect(const _ContextMenuAction('delete')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _M3StatusChip extends StatefulWidget {
  final PlayStatus status;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const _M3StatusChip({
    required this.status,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  State<_M3StatusChip> createState() => _M3StatusChipState();
}

class _M3StatusChipState extends State<_M3StatusChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoverBg = widget.dark
        ? Colors.white.withValues(alpha: 0.08)
        : KisakiColors.m3Rose.withValues(alpha: 0.14);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: widget.selected
                ? null
                : (_hover ? hoverBg : Colors.transparent),
            gradient: widget.selected
                ? const LinearGradient(
                    colors: [KisakiColors.m3Rose, KisakiColors.m3Peach],
                  )
                : null,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Text(
            widget.status.label,
            style: Type.micro.copyWith(
              fontSize: 11.5,
              fontWeight:
                  widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: widget.selected
                  ? const Color(0xFF3A0E1E)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _M3ContextRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color badgeColor;
  final Color iconInk;
  final Color? textColor;
  final bool emphasized;
  final bool dark;
  final VoidCallback onTap;

  const _M3ContextRow({
    required this.icon,
    required this.label,
    required this.badgeColor,
    required this.iconInk,
    this.textColor,
    this.emphasized = false,
    required this.dark,
    required this.onTap,
  });

  @override
  State<_M3ContextRow> createState() => _M3ContextRowState();
}

class _M3ContextRowState extends State<_M3ContextRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoverFill = widget.textColor == KisakiColors.danger
        ? KisakiColors.danger.withValues(alpha: widget.dark ? 0.16 : 0.10)
        : widget.badgeColor.withValues(alpha: widget.dark ? 0.16 : 0.20);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          height: GameCardActions._menuItemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover ? hoverFill : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: widget.badgeColor
                      .withValues(alpha: widget.dark ? 0.20 : 0.26),
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
                child: Icon(widget.icon, size: 15, color: widget.iconInk),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(
                    fontWeight:
                        widget.emphasized ? FontWeight.w600 : FontWeight.w500,
                    color: widget.textColor ?? scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
