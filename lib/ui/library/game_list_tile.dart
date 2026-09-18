/// 游戏库紧凑卡片：左封面 + 右名称，适合一页浏览/管理多个游戏。
///
/// 与 [GameCard] 共用同一套交互：点击进详情（批量模式下切换选中）、
/// 右键菜单（打开游戏 / 目录 / 状态 / 收藏 / 编辑 / 存档备份 / 删除）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../detail/game_detail_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'game_card_actions.dart';

class GameListTile extends ConsumerStatefulWidget {
  final Game game;
  final double? bestPlatformRating;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;

  const GameListTile({
    super.key,
    required this.game,
    this.bestPlatformRating,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  @override
  ConsumerState<GameListTile> createState() => _GameListTileState();
}

class _GameListTileState extends ConsumerState<GameListTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final picked = widget.selectionMode && widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () async {
          if (widget.selectionMode) {
            widget.onSelectionChanged?.call(!widget.selected);
            return;
          }
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  GameDetailPage(gameId: game.id!, initial: game)));
          ref.read(libraryVersionProvider.notifier).state++;
        },
        onSecondaryTapUp: (d) =>
            GameCardActions.showContextMenu(context, ref, game, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: picked
                ? scheme.primary.withValues(alpha: 0.10)
                : (_hover
                    ? scheme.primary.withValues(alpha: 0.05)
                    : (dark ? KisakiColors.nightCard : Colors.white)),
            border: Border.all(
              color: picked
                  ? scheme.primary
                  : (_hover
                      ? scheme.primary.withValues(alpha: 0.4)
                      : (dark ? Colors.white12 : Colors.black.withValues(alpha: 0.05))),
              width: picked ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // 左侧封面（2:3，小尺寸）
              SizedBox(
                width: 44,
                height: 44 / kCoverAspect,
                child: CoverImage(
                  path: game.coverPath,
                  nsfw: game.nsfw,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 10),
              // 右侧：名称 + 次要信息
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          _statusIcon(game.playStatus),
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _subtitle(game, widget.bestPlatformRating),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // 收藏星标 / 批量勾选
              if (widget.selectionMode)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: picked ? scheme.primary : Colors.transparent,
                    border: Border.all(
                        color: picked ? scheme.primary : scheme.outlineVariant,
                        width: 1.5),
                  ),
                  child: picked
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : const SizedBox.shrink(),
                )
              else if (game.isFavorite)
                const Icon(Icons.favorite_rounded,
                    size: 15, color: KisakiColors.pink),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _statusIcon(PlayStatus s) {
    switch (s) {
      case PlayStatus.wish:
        return Icons.bookmark_border_rounded;
      case PlayStatus.playing:
        return Icons.play_circle_outline_rounded;
      case PlayStatus.played:
        return Icons.check_circle_outline_rounded;
      case PlayStatus.onHold:
        return Icons.pause_circle_outline_rounded;
      case PlayStatus.dropped:
        return Icons.remove_circle_outline_rounded;
    }
  }

  static String _subtitle(Game g, double? platformRating) {
    final parts = <String>[];
    if (g.developer.isNotEmpty) parts.add(g.developer);
    if (g.totalSeconds > 0) parts.add(fmtDuration(g.totalSeconds));
    if (g.userRating > 0) {
      parts.add('我的 ${g.userRating.toStringAsFixed(0)}');
    } else if (platformRating != null && platformRating > 0) {
      parts.add('评分 ${platformRating.toStringAsFixed(1)}');
    }
    return parts.isEmpty ? g.playStatus.label : parts.join(' · ');
  }
}
