/// 游戏库紧凑条目：左侧 2:3 图版缩略图 + 名称两行 + CMYK 专色徽标 + 右侧等宽时长列.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../kit.dart';
import '../theme.dart';
import 'game_card_actions.dart';

class GameListTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);
    final ratingColor = KisakiColors.ratingInk(dark);
    final picked = selectionMode && selected;

    final rating = game.userRating > 0
        ? game.userRating
        : ((bestPlatformRating != null && bestPlatformRating! > 0)
            ? bestPlatformRating!
            : 0.0);

    return KMediaRow(
      coverPath: game.coverPath,
      nsfw: game.nsfw,
      title: game.displayName,
      subtitle: _subtitle(game, bestPlatformRating),
      badges: [
        KBadge(
          text: game.playStatus.label,
          color: game.playStatus == PlayStatus.playing
              ? cyanInk
              : scheme.primary,
        ),
        if (rating > 0)
          KBadge(
            text: rating.toStringAsFixed(1),
            icon: Icons.star_rounded,
            color: ratingColor,
          ),
        if (game.developer.isNotEmpty)
          Text(
            game.developer,
            style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
      timeText: game.totalSeconds > 0 ? fmtDuration(game.totalSeconds) : null,
      selected: picked,
      onTap: () async {
        if (selectionMode) {
          onSelectionChanged?.call(!selected);
          return;
        }
        await Navigator.of(context).push(FadeThroughRoute.builder(
            builder: (_) => GameDetailPage(gameId: game.id!, initial: game)));
        if (!context.mounted) return;
        ref.read(libraryVersionProvider.notifier).state++;
      },
      onSecondaryTapAt: (position) =>
          GameCardActions.showContextMenu(context, ref, game, position),
      trailing: selectionMode
          ? KSelectDot(selected: picked)
          : (game.isFavorite
              ? Icon(Icons.favorite_rounded, size: 15, color: scheme.primary)
              : null),
    );
  }

  static String _subtitle(Game g, double? platformRating) {
    final parts = <String>[g.playStatus.label];
    if (g.developer.isNotEmpty) parts.add(g.developer);
    if (g.totalSeconds > 0) parts.add(fmtDuration(g.totalSeconds));
    if (g.userRating > 0) {
      parts.add('我的 ${g.userRating.toStringAsFixed(1)}');
    } else if (platformRating != null && platformRating > 0) {
      parts.add('评分 ${platformRating.toStringAsFixed(1)}');
    }
    return parts.join(' · ');
  }
}
