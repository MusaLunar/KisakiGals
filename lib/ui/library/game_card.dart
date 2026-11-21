/// Fluent 2 游戏库网格卡片：统一封面纵横比 + 键盘聚焦/无障碍语义 + Acrylic 悬停快捷操作条 + 右键 Flyout 菜单。
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

class FluentGameCard extends ConsumerStatefulWidget {
  final Game game;
  final double? bestPlatformRating;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onRate;

  const FluentGameCard({
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
  ConsumerState<FluentGameCard> createState() => _FluentGameCardState();
}

class _FluentGameCardState extends ConsumerState<FluentGameCard> {
  final FlyoutController _flyoutCtrl = FlyoutController();
  final GlobalKey _moreBtnKey = GlobalKey();
  final ValueNotifier<bool> _hoveredNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hoveredNotifier.dispose();
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

  void _openContextMenu([Offset? globalPos]) {
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

    final rating = game.userRating > 0
        ? game.userRating
        : ((widget.bestPlatformRating != null && widget.bestPlatformRating! > 0)
            ? widget.bestPlatformRating
            : null);

    // 预构建并隔离封面节点，避免悬停/焦点态切换触发整卡重绘封面像素
    final coverWidget = RepaintBoundary(
      child: FluentCoverImage(
        pathOrUrl: game.coverPath,
        nsfw: game.nsfw,
        radius: 0,
        width: double.infinity,
        height: double.infinity,
        maxDecodeWidth: 440,
      ),
    );

    Widget buildCoverArea({required bool statesHovered, required bool isFocused}) {
      return ValueListenableBuilder<bool>(
        valueListenable: _hoveredNotifier,
        child: coverWidget,
        builder: (context, pointerHovered, staticCover) {
          final isHovered = pointerHovered || statesHovered;
          final activeHighlight = isHovered || isFocused;
          final showActionStrip =
              (activeHighlight || isRunning) && !widget.selectionMode;
          final showFavChip =
              widget.selectionMode || game.isFavorite || activeHighlight;
          final resolvedCover = staticCover ?? coverWidget;
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (disableAnim)
                  resolvedCover
                else
                  AnimatedScale(
                    scale: isHovered ? 1.03 : 1.0,
                    duration: FluentMotion.fast,
                    curve: FluentMotion.enterCurve,
                    child: resolvedCover,
                  ),
                if (isRunning)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: FluentBadge(
                      icon: FluentIcons.play_16_filled,
                      text: '游戏中',
                      foreground: theme.onAccentInk,
                      background: accent.withValues(alpha: 0.94),
                    ),
                  ),
                if (widget.selectionMode)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xBB1F1F1F)
                            : const Color(0xD8FFFFFF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: picked ? accent : theme.surfaceStroke,
                        ),
                      ),
                      child: Checkbox(
                        checked: picked,
                        onChanged: (v) =>
                            widget.onSelectionChanged?.call(v == true),
                      ),
                    ),
                  )
                else if (showFavChip)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _CardFavoriteChip(
                      favorite: game.isFavorite,
                      onTap: () => toggleGameFavorite(ref, game),
                    ),
                  ),
                if (showActionStrip)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: FluentAcrylicPanel(
                      radius: 6,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StripButton(
                              icon: isRunning
                                  ? FluentIcons.stop_16_filled
                                  : FluentIcons.play_16_filled,
                              label: isRunning ? '停止' : '启动',
                              accent: isRunning ? accent : null,
                              onTap: () {
                                if (isRunning) {
                                  stopActiveGameSession(ref);
                                } else {
                                  GameLaunchService.launchAndTrack(game, ref);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          _StripButton(
                            key: _moreBtnKey,
                            icon: FluentIcons.more_horizontal_16_regular,
                            label: '更多',
                            tooltip: '更多操作 (右键)',
                            onTap: () =>
                                _openContextMenu(_moreAnchorPosition()),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    final metaSection = <Widget>[
      const SizedBox(height: 8),
      Text(
        game.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.typography.bodyStrong?.copyWith(height: 1.25),
      ),
      const SizedBox(height: 3),
      Text(
        _secondaryText(game),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.typography.caption?.copyWith(color: theme.textSecondary),
      ),
      const SizedBox(height: 6),
      FluentR18ScoreRow(
        nsfw: game.nsfw,
        scoreText: rating?.toStringAsFixed(1),
        trailing: [
          FluentStatusPill(status: game.playStatus),
        ],
      ),
    ];

    return FlyoutTarget(
      controller: _flyoutCtrl,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (details) => _openContextMenu(details.globalPosition),
        child: Semantics(
          button: true,
          selected: picked,
          label: '${game.displayName}，${game.playStatus.label}',
          child: HoverButton(
            cursor: SystemMouseCursors.click,
            onPressed: _handleTap,
            onPointerEnter: (_) => _hoveredNotifier.value = true,
            onPointerExit: (_) => _hoveredNotifier.value = false,
            builder: (context, states) {
              final coverWidgetBuilt = buildCoverArea(
                statesHovered: states.isHovered,
                isFocused: states.isFocused,
              );
              final baseBg =
                  isDark ? const Color(0xD82C2C2C) : const Color(0xEBFFFFFF);
              final hoverBg =
                  isDark ? const Color(0xE8353535) : const Color(0xFFFFFFFF);
              final cardBg = picked
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
                      ? accent.withValues(alpha: 0.72)
                      : theme.surfaceStroke);

              return FocusBorder(
                focused: states.isFocused,
                renderOutside: false,
                child: AnimatedContainer(
                  duration: disableAnim ? Duration.zero : FluentMotion.fast,
                  curve: FluentMotion.enterCurve,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                      width: 1,
                    ),
                    boxShadow: (states.isHovered || isRunning)
                        ? [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.28 : 0.09),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.hasBoundedHeight) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: coverWidgetBuilt),
                            ...metaSection,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AspectRatio(
                            aspectRatio: 2 / 3,
                            child: coverWidgetBuilt,
                          ),
                          ...metaSection,
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _secondaryText(Game g) {
    final parts = <String>[];
    if (g.developer.isNotEmpty) parts.add(g.developer);
    if (g.totalSeconds > 0) parts.add(fmtDuration(g.totalSeconds));
    if (parts.isNotEmpty) return parts.join(' · ');
    if (g.lastPlayedAt != null) return '上次 ${fmtRelativeShort(g.lastPlayedAt!)}';
    return '尚未游玩';
  }
}

class _CardFavoriteChip extends StatelessWidget {
  final bool favorite;
  final VoidCallback onTap;

  const _CardFavoriteChip({required this.favorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Tooltip(
      message: favorite ? '取消收藏' : '收藏',
      child: Semantics(
        button: true,
        selected: favorite,
        label: favorite ? '取消收藏' : '收藏',
        child: HoverButton(
          cursor: SystemMouseCursors.click,
          onPressed: onTap,
          builder: (context, states) {
            final bg = states.isPressed
                ? const Color(0xCC2C2C2C)
                : states.isHovered
                    ? const Color(0xCC222222)
                    : const Color(0xAA1F1F1F);
            return FocusBorder(
              focused: states.isFocused,
              renderOutside: false,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white
                        .withValues(alpha: states.isHovered ? 0.42 : 0.22),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  favorite
                      ? FluentIcons.heart_16_filled
                      : FluentIcons.heart_16_regular,
                  size: 14,
                  color: favorite ? theme.favoriteInk : Colors.white,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;
  final String? tooltip;
  final VoidCallback onTap;

  const _StripButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final btn = Semantics(
      button: true,
      label: label,
      child: HoverButton(
        cursor: SystemMouseCursors.click,
        onPressed: onTap,
        builder: (context, states) {
          final fg = accent ?? theme.textPrimary;
          final bg = states.isPressed
              ? theme.subtlePressed
              : states.isHovered
                  ? theme.subtleHover
                  : Colors.transparent;
          return FocusBorder(
            focused: states.isFocused,
            renderOutside: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}
