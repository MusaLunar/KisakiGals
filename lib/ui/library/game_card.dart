/// 游戏库网格卡片：2:3 大封面 + 标题两行 + 次要信息。
///
/// 视觉取向（上一轮评审重点）：
/// - 卡片**不透明**：常态就有底色（白 / nightCard）+ 硬阴影 + 1px 描边；
/// - hover：上浮 + 微缩放 + 柔光阴影（由 kit 的 InteractiveSurface 提供）；
/// - 角标压在封面上，用半透明深色底座保证任何封面下都能看清。
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

/// 网格卡片内边距：封面按**卡片内容宽度**严格保持 2:3。
const EdgeInsets kGameCardPadding = EdgeInsets.all(6);

/// 网格卡片**封面下方**的文字区高度：
/// 间距 8 + 标题两行 36 + 间距 2 + 次要信息 17 = 63。
/// library_page 用它推算网格单元高度，避免封面被单元比例拉伸。
const double kGameCardMetaHeight = 63;

/// 标题区固定两行高度：一行标题与两行标题的基线保持一致。
const double _titleBoxHeight = 36;

/// 封面角标的半透明深色底座（黑 55%）。
const Color _coverScrim = Color(0x8C000000);

class GameCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final game = this.game;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final picked = selectionMode && selected;
    // 平台评分优先，其次我的评分（都没有就不显示角标）
    final rating = (bestPlatformRating != null && bestPlatformRating! > 0)
        ? bestPlatformRating
        : (game.userRating > 0 ? game.userRating : null);

    // 选中态底色与卡片底色混合成不透明色，避免卡片"透出"页面背景
    final baseFill = dark ? KisakiColors.nightCard : Colors.white;
    final fill = picked
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: dark ? 0.22 : 0.10), baseFill)
        : null;

    return GestureDetector(
      // 右键菜单：InteractiveSurface 只接管主键手势，副键在这里补
      onSecondaryTapUp: (details) => GameCardActions.showContextMenu(
          context, ref, game, details.globalPosition),
      child: KCard(
        padding: kGameCardPadding,
        color: fill,
        onTap: () async {
          // 批量模式：整张卡片都是一次选中开关
          if (selectionMode) {
            onSelectionChanged?.call(!selected);
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
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CoverImage(
                      path: game.coverPath,
                      nsfw: game.nsfw,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                  ),
                  // 状态角标（想玩是默认状态，不显示，免得整页都是角标）
                  if (game.playStatus != PlayStatus.wish)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _StatusBadge(status: game.playStatus),
                    ),
                  // 批量勾选圈 / 收藏星标（批量模式下让位给勾选）
                  Positioned(
                    right: 6,
                    top: 6,
                    child: selectionMode
                        ? _SelectDot(selected: picked)
                        : _FavoriteButton(game: game),
                  ),
                  // 游玩中
                  if (ref.watch(trackingGameProvider) == game.id)
                    const Positioned(
                      left: 6,
                      bottom: 6,
                      child: _PlayingTag(),
                    ),
                  // 评分角标
                  if (rating != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _RatingTag(value: rating),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.sm),
            // 固定两行高度：长标题最多两行省略号，不与次要信息抢位
            SizedBox(
              height: _titleBoxHeight,
              child: Text(
                game.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Type.body.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                  color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                ),
              ),
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              _secondary(game),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 次要信息：开发商优先，其次最近游玩时间。
  static String _secondary(Game g) => g.developer.isNotEmpty
      ? g.developer
      : (g.lastPlayedAt != null
          ? '上次游玩 ${fmtRelative(g.lastPlayedAt!)}'
          : '尚未游玩');
}

// ============================ 封面角标 ============================

/// 封面角标底座：半透明深色药丸（保证在任意封面上都可读）。
class _CoverTag extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;

  const _CoverTag({
    required this.child,
    this.color = _coverScrim,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: child,
      );
}

/// 游玩状态角标（图标 + 深色底）。
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
      child: Icon(icon, size: 15, color: Colors.white),
    );
  }
}

/// 评分角标：星标 + 分数（平台评分优先，其次我的评分）。
class _RatingTag extends StatelessWidget {
  final double value;
  const _RatingTag({required this.value});

  @override
  Widget build(BuildContext context) => _CoverTag(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFD54F)),
            const SizedBox(width: 3),
            Text(
              value.toStringAsFixed(1),
              style: Type.caption.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700, height: 1.2),
            ),
          ],
        ),
      );
}

/// 游玩中角标（主色实心，与侧栏「游玩中」呼应）。
class _PlayingTag extends StatelessWidget {
  const _PlayingTag();

  @override
  Widget build(BuildContext context) => _CoverTag(
        color: Theme.of(context).colorScheme.primary,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 3),
            Text('游戏中',
                style: Type.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.2)),
          ],
        ),
      );
}

/// 批量勾选圈（压在封面上）：未选中用深色底 + 白描边，任何封面都看得见。
class _SelectDot extends StatelessWidget {
  final bool selected;
  const _SelectDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : _coverScrim,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// 收藏星标：卡片上的快捷开关（与右键菜单里的「加入/取消收藏」同一份数据）。
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _coverScrim,
            ),
            child: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 15,
              color: fav ? KisakiColors.pink : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
