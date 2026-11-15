/// Fluent 2 加权标签词云：中心螺旋排布 + 强调色阶 + 悬停 Tooltip + 点击筛选游戏库。
library;

import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';

/// 兼容旧名引用。
typedef TagWordCloud = FluentTagWordCloud;

/// 交互式标签词云组件：基于 Fluent 主题强调色透明梯度与螺旋重心排列。
class FluentTagWordCloud extends ConsumerWidget {
  final List<TagItem> tags;
  final ValueChanged<TagItem>? onTagTap;

  const FluentTagWordCloud({
    super.key,
    required this.tags,
    this.onTagTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final accentAlt =
        isDark ? theme.accentColor.lighter : theme.accentColor.darker;
    final neutralTint =
        theme.typography.body?.color ?? (isDark ? Colors.white : Colors.black);

    final sorted = [...tags]..sort((a, b) => b.weight.compareTo(a.weight));
    final maxW = sorted.first.weight;
    final minW = sorted.last.weight;
    final range = (maxW - minW) <= 0 ? 1.0 : (maxW - minW);

    // 螺旋式重心排列：权重最高标签居于中心，其余交替向外延展。
    final spiral = <TagItem>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i.isEven) {
        spiral.add(sorted[i]);
      } else {
        spiral.insert(0, sorted[i]);
      }
    }

    final palette = [
      accent,
      accentAlt,
      Color.lerp(accent, neutralTint, 0.25) ?? accent,
    ];

    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          for (var i = 0; i < spiral.length; i++)
            _buildChip(
              context: context,
              ref: ref,
              tag: spiral[i],
              index: i,
              minW: minW,
              range: range,
              palette: palette,
            ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required WidgetRef ref,
    required TagItem tag,
    required int index,
    required double minW,
    required double range,
    required List<Color> palette,
  }) {
    final norm = ((tag.weight - minW) / range).clamp(0.0, 1.0);
    final fontSize = 12.0 + math.sqrt(norm) * 19.0;
    final baseColor = palette[index % palette.length];
    final alpha = (0.56 + norm * 0.44).clamp(0.45, 1.0);
    final fontWeight = norm > 0.66
        ? FontWeight.w700
        : norm > 0.33
            ? FontWeight.w600
            : FontWeight.w400;

    return _WordCloudTag(
      tag: tag,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: baseColor.withValues(alpha: alpha),
      onTap: () {
        if (onTagTap != null) {
          onTagTap!(tag);
        } else {
          jumpToLibraryFiltered(ref, tag: tag.name);
        }
      },
    );
  }
}

class _WordCloudTag extends StatefulWidget {
  final TagItem tag;
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;
  final VoidCallback onTap;

  const _WordCloudTag({
    required this.tag,
    required this.fontSize,
    required this.fontWeight,
    required this.color,
    required this.onTap,
  });

  @override
  State<_WordCloudTag> createState() => _WordCloudTagState();
}

class _WordCloudTagState extends State<_WordCloudTag> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final weightLabel = widget.tag.weight >= 10
        ? widget.tag.weight.toStringAsFixed(0)
        : widget.tag.weight.toStringAsFixed(1);

    return Tooltip(
      message: '${widget.tag.name} · 权重 $weightLabel（点击筛选游戏库）',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _hovered
                  ? accent.withValues(alpha: isDark ? 0.20 : 0.12)
                  : accent.withValues(alpha: isDark ? 0.06 : 0.04),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _hovered
                    ? accent.withValues(alpha: 0.55)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Text(
              widget.tag.name,
              style: (theme.typography.body ?? const TextStyle()).copyWith(
                fontSize: widget.fontSize,
                height: 1.15,
                fontWeight: widget.fontWeight,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
