/// 游戏库紧凑条目：左侧 2:3 小封面 + 右侧名称两行 + 次要信息。
///
/// 适合一页浏览/管理多个游戏。结构走 kit 的 [KMediaRow]（固定 34px 标题区、
/// hover 上浮 + 柔光阴影），本文件只负责把 [Game] 的数据映射到行上，
/// 交互与 [GameCard] 完全一致：点击进详情（批量模式下切换选中）、右键菜单。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final game = this.game;
    final picked = selectionMode && selected;

    return KMediaRow(
      coverPath: game.coverPath,
      nsfw: game.nsfw,
      title: game.displayName,
      subtitle: _subtitle(game, bestPlatformRating),
      selected: picked,
      onTap: () async {
        // 批量模式：整行都是一次选中开关
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
      onSecondaryTapAt: (position) =>
          GameCardActions.showContextMenu(context, ref, game, position),
      trailing: selectionMode
          ? _SelectDot(selected: picked)
          : (game.isFavorite
              ? const Icon(Icons.favorite_rounded,
                  size: 15, color: KisakiColors.pink)
              : null),
    );
  }

  /// 次要信息：状态 · 开发商 · 时长 · 评分（无内容时才退化为状态名）。
  /// 状态用文字而非图标，[KMediaRow] 的次要信息位只接受一行文本。
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

/// 批量勾选圈：未选中也要明显（否则看不出这里可以点）。
/// 直径 22、1.5px 描边；选中为主色实心 + 白勾。
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
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.onSurfaceVariant.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}
