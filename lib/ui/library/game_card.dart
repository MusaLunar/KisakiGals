/// Fluent 2 游戏库网格卡片：2:3 封面 + 悬停 Acrylic 快捷操作条 + 右键 Flyout 菜单。
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
  bool _hovered = false;

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
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final isRunning =
        game.id != null && ref.watch(trackingGameProvider) == game.id;
    final picked = widget.selectionMode && widget.selected;

    final rating = game.userRating > 0
        ? game.userRating
        : ((widget.bestPlatformRating != null && widget.bestPlatformRating! > 0)
            ? widget.bestPlatformRating
            : null);

    final baseBg =
        isDark ? const Color(0xD82C2C2C) : const Color(0xEBFFFFFF);
    final hoverBg =
        isDark ? const Color(0xE8353535) : const Color(0xFFFFFFFF);
    final cardBg = picked
        ? Color.alphaBlend(accent.withValues(alpha: isDark ? 0.24 : 0.12), baseBg)
        : (_hovered ? hoverBg : baseBg);

    final borderColor = picked || isRunning
        ? accent
        : (_hovered
            ? accent.withValues(alpha: 0.72)
            : (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07)));

    final showActionStrip = (_hovered || isRunning) && !widget.selectionMode;

    Widget buildCoverArea() => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: AnimatedScale(
                  scale: _hovered ? 1.035 : 1.0,
                  duration: FluentMotion.fast,
                  curve: FluentMotion.enterCurve,
                  child: FluentCoverImage(
                    pathOrUrl: game.coverPath,
                    nsfw: game.nsfw,
                    radius: 6,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
              if (isRunning)
                Positioned(
                  left: 6,
                  top: 6,
                  child: FluentBadge(
                    icon: FluentIcons.play_16_filled,
                    text: '游戏中',
                    foreground: Colors.white,
                    background: accent.withValues(alpha: 0.92),
                  ),
                ),
              Positioned(
                right: 6,
                top: 6,
                child: widget.selectionMode
                    ? Checkbox(
                        checked: picked,
                        onChanged: (v) =>
                            widget.onSelectionChanged?.call(v == true),
                      )
                    : _CardFavoriteChip(
                        favorite: game.isFavorite,
                        onTap: () => toggleGameFavorite(ref, game),
                      ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: IgnorePointer(
                  ignoring: !showActionStrip,
                  child: AnimatedOpacity(
                    opacity: showActionStrip ? 1.0 : 0.0,
                    duration: FluentMotion.fast,
                    curve: FluentMotion.enterCurve,
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
                            onTap: () =>
                                _openContextMenu(_moreAnchorPosition()),
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
        style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onSecondaryTapUp: (details) =>
              _openContextMenu(details.globalPosition),
          child: AnimatedContainer(
            duration: FluentMotion.fast,
            curve: FluentMotion.enterCurve,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: (picked || isRunning) ? 1.5 : 1.0,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.28 : 0.09),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
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
                      Expanded(child: buildCoverArea()),
                      ...metaSection,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(aspectRatio: 2 / 3, child: buildCoverArea()),
                    ...metaSection,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static String _secondaryText(Game g) {
    if (g.developer.isNotEmpty) return g.developer;
    if (g.totalSeconds > 0) return fmtDuration(g.totalSeconds);
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
    return Tooltip(
      message: favorite ? '取消收藏' : '收藏',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xAA1F1F1F),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          alignment: Alignment.center,
          child: Icon(
            favorite
                ? FluentIcons.heart_16_filled
                : FluentIcons.heart_16_regular,
            size: 13,
            color: favorite ? const Color(0xFFFF7AA2) : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _StripButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color? accent;
  final VoidCallback onTap;

  const _StripButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  @override
  State<_StripButton> createState() => _StripButtonState();
}

class _StripButtonState extends State<_StripButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = widget.accent ??
        (isDark ? Colors.white : const Color(0xFF1F1F1F));
    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 13, color: fg),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
