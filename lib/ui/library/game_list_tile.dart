/// Fluent 2 游戏库紧凑列表条目：前置复选 + 左封面 + 中元数据与 R18/评分行 + 右快捷操作与 Flyout 菜单。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../services/game_launch_service.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import 'game_actions.dart';

class FluentGameListTile extends ConsumerStatefulWidget {
  final Game game;
  final double? bestPlatformRating;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onRate;

  const FluentGameListTile({
    super.key,
    required this.game,
    this.bestPlatformRating,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
    this.onTap,
    this.onEdit,
    this.onRate,
  });

  @override
  ConsumerState<FluentGameListTile> createState() => _FluentGameListTileState();
}

class _FluentGameListTileState extends ConsumerState<FluentGameListTile> {
  final FlyoutController _flyoutCtrl = FlyoutController();
  final GlobalKey _moreBtnKey = GlobalKey();

  @override
  void dispose() {
    _flyoutCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.selectionMode) {
      widget.onSelectionChanged?.call(!widget.selected);
      return;
    }
    if (widget.onTap != null) {
      widget.onTap!.call();
      return;
    }
    final id = widget.game.id;
    if (id != null) {
      openGameDetail(context, id, initial: widget.game, ref: ref);
    }
  }

  void _openMenu([Offset? globalPos]) {
    showGameMenuFlyout(
      context,
      ref,
      controller: _flyoutCtrl,
      game: widget.game,
      position: globalPos,
      onEdit: widget.onEdit,
      onRate: widget.onRate,
    );
  }

  Offset? _moreAnchorPosition() {
    final box = _moreBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height));
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final accent = theme.accentInk;
    final disableAnim = fluentAnimationsDisabled(context);
    final isRunning = ref.watch(
      trackingGameProvider.select((id) => game.id != null && id == game.id),
    );
    final picked = widget.selectionMode && widget.selected;
    final hasExe = game.exePath.trim().isNotEmpty;

    final rating = game.userRating > 0
        ? game.userRating
        : ((widget.bestPlatformRating != null && widget.bestPlatformRating! > 0)
            ? widget.bestPlatformRating!
            : 0.0);

    return FlyoutTarget(
      controller: _flyoutCtrl,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (details) => _openMenu(details.globalPosition),
        child: Semantics(
          button: true,
          selected: picked,
          label: '${game.displayName}，${game.playStatus.label}',
          child: HoverButton(
            cursor: SystemMouseCursors.click,
            onPressed: _handleTap,
            builder: (context, states) {
              final baseBg =
                  isDark ? const Color(0xD82C2C2C) : const Color(0xEBFFFFFF);
              final hoverBg =
                  isDark ? const Color(0xE8353535) : const Color(0xFFFFFFFF);
              final bg = picked
                  ? Color.alphaBlend(
                      accent.withValues(alpha: isDark ? 0.22 : 0.12),
                      baseBg,
                    )
                  : states.isPressed
                      ? Color.alphaBlend(theme.subtlePressed, baseBg)
                      : (states.isHovered ? hoverBg : baseBg);

              final borderColor = (picked || isRunning)
                  ? accent
                  : (states.isHovered
                      ? accent.withValues(alpha: 0.7)
                      : theme.surfaceStroke);

              return FocusBorder(
                focused: states.isFocused,
                renderOutside: false,
                child: AnimatedContainer(
                  duration: disableAnim ? Duration.zero : FluentMotion.fast,
                  curve: FluentMotion.enterCurve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (widget.selectionMode) ...[
                        Checkbox(
                          checked: picked,
                          onChanged: (v) =>
                              widget.onSelectionChanged?.call(v == true),
                        ),
                        const SizedBox(width: 10),
                      ],
                      FluentCoverImage(
                        pathOrUrl: game.coverPath,
                        nsfw: game.nsfw,
                        width: 48,
                        height: 70,
                        radius: 5,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              game.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.bodyStrong,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _subtitle(game),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.caption?.copyWith(
                                color: theme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            FluentR18ScoreRow(
                              nsfw: game.nsfw,
                              scoreText:
                                  rating > 0 ? rating.toStringAsFixed(1) : null,
                              trailing: [
                                if (isRunning)
                                  FluentBadge(
                                    icon: FluentIcons.play_16_filled,
                                    text: '游戏中',
                                    foreground: theme.onAccentInk,
                                    background: accent,
                                  )
                                else
                                  FluentStatusPill(status: game.playStatus),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (game.totalSeconds > 0) ...[
                            Text(
                              fmtDuration(game.totalSeconds),
                              style: theme.typography.caption?.copyWith(
                                color: theme.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (!widget.selectionMode) ...[
                            Tooltip(
                              message: game.isFavorite ? '取消收藏' : '收藏',
                              child: IconButton(
                                icon: Icon(
                                  game.isFavorite
                                      ? FluentIcons.heart_16_filled
                                      : FluentIcons.heart_16_regular,
                                  size: 16,
                                  color: game.isFavorite
                                      ? theme.favoriteInk
                                      : null,
                                ),
                                onPressed: () => toggleGameFavorite(ref, game),
                              ),
                            ),
                            Tooltip(
                              message: isRunning
                                  ? '停止会话'
                                  : (hasExe ? '启动游戏' : '请先在编辑中设置可执行文件'),
                              child: IconButton(
                                icon: Icon(
                                  isRunning
                                      ? FluentIcons.stop_16_filled
                                      : FluentIcons.play_16_filled,
                                  size: 16,
                                  color: isRunning ? accent : null,
                                ),
                                onPressed: (!isRunning && !hasExe)
                                    ? null
                                    : () {
                                        if (isRunning) {
                                          stopActiveGameSession(ref);
                                        } else {
                                          GameLaunchService.launchAndTrack(
                                            game,
                                            ref,
                                          );
                                        }
                                      },
                              ),
                            ),
                            Tooltip(
                              message: '更多操作',
                              child: IconButton(
                                key: _moreBtnKey,
                                icon: const Icon(
                                  FluentIcons.more_horizontal_16_regular,
                                  size: 16,
                                ),
                                onPressed: () =>
                                    _openMenu(_moreAnchorPosition()),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _subtitle(Game g) {
    final parts = <String>[];
    if (g.developer.isNotEmpty) parts.add(g.developer);
    if (g.releaseDate.isNotEmpty) parts.add(g.releaseDate);
    if (g.lastPlayedAt != null) {
      parts.add('上次 ${fmtRelativeShort(g.lastPlayedAt!)}');
    } else if (parts.isEmpty) {
      parts.add('尚未游玩');
    }
    return parts.join(' · ');
  }
}
