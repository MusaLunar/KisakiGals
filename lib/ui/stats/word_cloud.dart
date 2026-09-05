/// 自研加权标签词云：Wrap + 权重字号/色调抖动，轻量无依赖。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme.dart';

class WordCloud extends StatelessWidget {
  final List<TagItem> tags;
  const WordCloud({super.key, required this.tags});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;

    // 权重 → 字号 11-34，对数衰减避免头重脚轻
    final maxW = tags.map((t) => t.weight).reduce(math.max);
    final minW = tags.map((t) => t.weight).reduce(math.min);
    final range = (maxW - minW) <= 0 ? 1.0 : (maxW - minW);

    final palette = dark
        ? [
            KisakiColors.pinkSoft,
            KisakiColors.lavenderSoft,
            const Color(0xFF9AD0CD),
            const Color(0xFFF0C987),
            const Color(0xFFE8A1B8),
          ]
        : [
            KisakiColors.pink,
            KisakiColors.lavender,
            const Color(0xFF4FA8A0),
            const Color(0xFFD99A3C),
            const Color(0xFFD96A8E),
          ];

    final rng = math.Random(42);
    final children = <Widget>[];
    for (var i = 0; i < tags.length; i++) {
      final t = tags[i];
      final norm = (t.weight - minW) / range; // 0-1
      final fontSize = 11.0 + norm * 23.0;
      final color = palette[(i + rng.nextInt(2)) % palette.length];
      final opacity = 0.62 + norm * 0.38;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Text(
            t.name,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.1,
              fontWeight: norm > 0.66
                  ? FontWeight.w800
                  : norm > 0.33
                      ? FontWeight.w600
                      : FontWeight.w400,
              color: color.withValues(alpha: opacity.clamp(0.4, 1.0)),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
