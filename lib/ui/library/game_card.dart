/// 游戏库网格卡片：hover 高亮、右键菜单、批量选择。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../detail/game_detail_page.dart';
import 'game_card_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GameCard extends ConsumerStatefulWidget {
  final Game game;
  final double? bestPlatformRating;

  /// 批量管理
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;

  const GameCard({
    super.key,
    required this.game,
    this.bestPlatformRating,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<GameCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        // hover 只加边框不放大，避免边缘卡片被相邻卡片遮挡
        onTap: () async {
          if (widget.selectionMode) {
            widget.onSelectionChanged?.call(!widget.selected);
            return;
          }
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GameDetailPage(gameId: game.id!, initial: game)));
          ref.read(libraryVersionProvider.notifier).state++;
        },
        onSecondaryTapUp: (details) =>
            GameCardActions.showContextMenu(
                context, ref, game, details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.selectionMode && widget.selected
                  ? scheme.primary
                  : _hover
                      ? scheme.primary.withValues(alpha: 0.45)
                      : Colors.transparent,
              width: 2,
            ),
            color: widget.selectionMode && widget.selected
                ? scheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: kCoverAspect,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CoverImage(
                        path: game.coverPath,
                        nsfw: game.nsfw,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    // 状态角标
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _StatusBadge(status: game.playStatus),
                    ),
                    // 批量选择勾
                    if (widget.selectionMode)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.selected
                                ? scheme.primary
                                : Colors.black.withValues(alpha: 0.5),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: widget.selected
                              ? const Icon(Icons.check_rounded,
                                  size: 17, color: Colors.white)
                              : const SizedBox.shrink(),
                        ),
                      )
                    else ...[
                      // 收藏
                      Positioned(
                        right: 4,
                        top: 2,
                        child: IconButton(
                          icon: Icon(
                            game.isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 20,
                            color: game.isFavorite
                                ? KisakiColors.pink
                                : Colors.white.withValues(alpha: 0.9),
                            shadows: const [
                              Shadow(blurRadius: 6, color: Colors.black45)
                            ],
                          ),
                          onPressed: () async {
                            game.isFavorite = !game.isFavorite;
                            await AppServices.I.repo.updateGame(game);
                            Future.delayed(
                                const Duration(milliseconds: 400), () {
                              if (mounted) {
                                ref.read(libraryVersionProvider.notifier).state++;
                              }
                            });
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      // 评分角标
                      if (widget.bestPlatformRating != null ||
                          game.userRating > 0)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              color: Colors.black.withValues(alpha: 0.62),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 13, color: Color(0xFFFFD54F)),
                                const SizedBox(width: 3),
                                Text(
                                  (widget.bestPlatformRating ??
                                          game.userRating)
                                      .toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    // 游玩中
                    if (ref.watch(trackingGameProvider) == game.id)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            color: scheme.primary,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  size: 14, color: Colors.white),
                              Text('游戏中',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                game.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                game.developer.isNotEmpty
                    ? game.developer
                    : (game.lastPlayedAt != null
                        ? '上次游玩 ${fmtRelative(game.lastPlayedAt!)}'
                        : '尚未游玩'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 右键菜单：打开游戏 / 打开目录 / 更改状态 / 删除游戏。
}

class _StatusBadge extends StatelessWidget {
  final PlayStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == PlayStatus.wish) return const SizedBox.shrink();
    final icon = switch (status) {
      PlayStatus.playing => Icons.play_circle_rounded,
      PlayStatus.played => Icons.check_circle_rounded,
      PlayStatus.onHold => Icons.pause_circle_rounded,
      _ => Icons.cancel_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.55),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }
}
