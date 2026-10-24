/// 游戏库网格卡片：2:3 杂志图版封面 + 标题两行 + 次要信息 + CMYK 专色角标.
///
/// 视觉取向：
/// - 卡片采用铜版纸白 / 凹版暗炭底色 + 1px 裁切细线；
/// - 悬停时封面在裁切框内平滑放大 (1.035x)，纸面微抬升；
/// - 评分角标使用专色铭黄 (Process Yellow-Gold)，游玩中角标使用专色青蓝 (Process Cyan)，
///   收藏与批量选中状态使用专色洋红 (Process Magenta)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart' show CoverImage, kCoverAspect;
import 'game_card_actions.dart';

const EdgeInsets kGameCardPadding = kCatalogCardPadding;
const double kGameCardMetaHeight = kCatalogCardMetaHeight;
const double _titleBoxHeight = kCatalogCardTitleHeight;
const Color _coverScrim = Color(0xBF0F1015);

class GameCard extends ConsumerStatefulWidget {
  final Game game;
  final double? bestPlatformRating;
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
    final cyanInk = KisakiColors.temporalInk(dark);
    final picked = widget.selectionMode && widget.selected;
    final rating =
        (widget.bestPlatformRating != null && widget.bestPlatformRating! > 0)
            ? widget.bestPlatformRating
            : (game.userRating > 0 ? game.userRating : null);

    final baseFill = dark ? KisakiColors.nightCard : Colors.white;
    final fill = picked
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: dark ? 0.22 : 0.10), baseFill)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) => GameCardActions.showContextMenu(
            context, ref, game, details.globalPosition),
        child: KCard(
          padding: kGameCardPadding,
          color: fill,
          onTap: () async {
            if (widget.selectionMode) {
              widget.onSelectionChanged?.call(!widget.selected);
              return;
            }
            await Navigator.of(context).push(FadeThroughRoute.builder(
                builder: (_) =>
                    GameDetailPage(gameId: game.id!, initial: game)));
            if (!context.mounted) return;
            ref.read(libraryVersionProvider.notifier).state++;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: kCoverAspect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: AnimatedScale(
                            scale: _hover ? Motion.coverHoverScale : 1.0,
                            duration: Motion.fast,
                            curve: Motion.enter,
                            child: CoverImage(
                              path: game.coverPath,
                              nsfw: game.nsfw,
                              borderRadius: BorderRadius.circular(Radii.sm),
                            ),
                          ),
                        ),
                      ),
                      if (game.playStatus != PlayStatus.wish)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: _StatusBadge(status: game.playStatus),
                        ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: widget.selectionMode
                            ? KSelectDot(selected: picked)
                            : _FavoriteButton(game: game),
                      ),
                      if (ref.watch(
                          trackingGameProvider.select((id) => id == game.id)))
                        const Positioned(
                          left: 6,
                          bottom: 6,
                          child: _PlayingTag(),
                        ),
                      if (rating != null)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: _RatingTag(value: rating),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.sm),
              SizedBox(
                height: _titleBoxHeight,
                child: Text(
                  game.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.30,
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: Gap.xxs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _secondary(game),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Type.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (game.playStatus != PlayStatus.wish) ...[
                    const SizedBox(width: Gap.xs),
                    KBadge(
                      text: game.playStatus.label,
                      color: game.playStatus == PlayStatus.playing
                          ? cyanInk
                          : scheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _secondary(Game g) => g.developer.isNotEmpty
      ? g.developer
      : (g.lastPlayedAt != null
          ? '上次游玩 ${fmtRelative(g.lastPlayedAt!)}'
          : '尚未游玩');
}

// ============================ 封面角标 ============================

class _CoverTag extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;

  const _CoverTag({
    required this.child,
    this.color = _coverScrim,
    this.padding = const EdgeInsets.symmetric(horizontal: 6.5, vertical: 3),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: child,
      );
}

class _StatusBadge extends StatelessWidget {
  final PlayStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      PlayStatus.playing => Icons.play_circle_rounded,
      PlayStatus.played => Icons.check_circle_rounded,
      PlayStatus.onHold => Icons.pause_circle_rounded,
      _ => Icons.cancel_rounded,
    };
    return _CoverTag(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 14, color: Colors.white),
    );
  }
}

/// 评分角标：专色铭黄星标 + 等宽数字
class _RatingTag extends StatelessWidget {
  final double value;
  const _RatingTag({required this.value});

  @override
  Widget build(BuildContext context) => _CoverTag(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 12.5, color: KisakiColors.star),
            const SizedBox(width: 3),
            Text(
              value.toStringAsFixed(1),
              style: Type.mono.copyWith(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ],
        ),
      );
}

/// 游玩中角标：专色青蓝实心底
class _PlayingTag extends StatelessWidget {
  const _PlayingTag();

  @override
  Widget build(BuildContext context) => _CoverTag(
        color: KisakiColors.cyan,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulsingGlow(
              minOpacity: 0.65,
              maxOpacity: 1.0,
              minScale: 0.90,
              maxScale: 1.10,
              child: const Icon(Icons.play_arrow_rounded,
                  size: 13, color: Colors.white),
            ),
            const SizedBox(width: 3),
            Text(
              '游戏中',
              style: Type.micro.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ],
        ),
      );
}

class _FavoriteButton extends ConsumerWidget {
  final Game game;
  const _FavoriteButton({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = game.isFavorite;
    return Tooltip(
      message: fav ? '取消收藏' : '加入收藏',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: PressableScale(
          onTap: () async {
            game.isFavorite = !fav;
            await AppServices.I.repo.updateGame(game);
            if (!context.mounted) return;
            ref.read(libraryVersionProvider.notifier).state++;
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _coverScrim,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: AnimatedSwitcher(
              duration: Motion.fast,
              switchInCurve: Motion.spring,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween<double>(begin: 0.65, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey<bool>(fav),
                size: 14,
                color: fav ? KisakiColors.magentaDark : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
