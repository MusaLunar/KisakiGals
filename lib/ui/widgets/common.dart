/// 通用 UI 组件：封面图、玻璃面板、评分、空态。
library;

import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../providers.dart';
import '../theme.dart';

/// 可拖动窗口区域：包住全屏路由（添加/详情页）的顶栏空白处。
class WindowDragBar extends StatelessWidget {
  final Widget child;
  const WindowDragBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      },
      child: child,
    );
  }
}

/// 封面图：本地文件优先 → 网络缓存 → 占位；NSFW 可模糊/占位。
/// 模糊强度与显示模式来自响应式 provider，设置中切换立即生效。
class CoverImage extends ConsumerWidget {
  final String path;
  final String? networkUrl;
  final bool nsfw;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  const CoverImage({
    super.key,
    required this.path,
    this.networkUrl,
    this.nsfw = false,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mode = ref.watch(nsfwModeProvider);
    final blurStrength = ref.watch(nsfwBlurProvider);
    if (!nsfw || mode == 'show') {
      return _renderImage(context, dark, blur: false);
    }
    if (mode == 'blur') {
      return _renderImage(context, dark, blur: true, sigma: blurStrength);
    }
    // placeholder 占位图
    return _frame(context, child: _placeholder(dark));
  }

  Widget _renderImage(BuildContext context, bool dark, {required bool blur, double sigma = 12}) {
    Widget? image;
    if (path.isNotEmpty && File(path).existsSync()) {
      image = Image.file(File(path),
          fit: fit, width: width, height: height, gaplessPlayback: true);
    } else if ((networkUrl ?? '').isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: networkUrl!,
        fit: fit,
        width: width,
        height: height,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => _placeholder(dark),
        errorWidget: (_, __, ___) => _placeholder(dark),
      );
    }
    if (image == null) return _frame(context, child: _placeholder(dark));
    final content = blur
        ? ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: image)
        : image;
    return _frame(context, child: ClipRRect(borderRadius: borderRadius, child: content));
  }

  Widget _frame(BuildContext context, {required Widget child}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        child: ClipRRect(borderRadius: borderRadius, child: child),
      );

  Widget _placeholder(bool dark) => Container(
        alignment: Alignment.center,
        color: dark ? const Color(0xFF332A3C) : KisakiColors.pinkContainer,
        child: Icon(
          Icons.local_florist_rounded,
          size: 34,
          color: dark ? KisakiColors.nightInkSoft : KisakiColors.pink.withValues(alpha: 0.55),
        ),
      );
}

/// 毛玻璃面板（亚克力观感）。
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final Color? tint;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = const EdgeInsets.all(20),
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ??
        (dark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.72));
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: base,
            borderRadius: borderRadius,
            border: Border.all(
              color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.65),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 实心卡片面板（非玻璃）。
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Color? color;
  final VoidCallback? onTap;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color ??
          (dark ? KisakiColors.nightCard : Colors.white),
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 评分条（可交互）。
class RatingBar extends StatelessWidget {
  final double value; // 0-10
  final ValueChanged<double>? onChanged;
  final double size;

  const RatingBar({super.key, required this.value, this.onChanged, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final full = value >= (i + 1) * 2 - 0.5;
        final half = !full && value >= i * 2 + 0.5;
        return IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          icon: Icon(
            full
                ? Icons.star_rounded
                : half
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            color: color,
            size: size,
          ),
          onPressed: onChanged == null
              ? null
              : () => onChanged!(value == (i + 1) * 2 ? 0 : (i + 1) * 2.0),
        );
      }),
    );
  }
}

/// 空状态占位。
class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.title,
    this.subtitle = '',
    this.icon = Icons.local_florist_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? Colors.white.withValues(alpha: 0.05) : KisakiColors.pinkContainer,
            ),
            child: Icon(icon, size: 44,
                color: dark ? KisakiColors.nightInkSoft : KisakiColors.pink),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// 源徽标（显示数据来源）。
class SourceBadge extends StatelessWidget {
  final String source;
  const SourceBadge({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: source == 'custom'
            ? scheme.surfaceContainerHighest
            : dark
                ? KisakiColors.pink.withValues(alpha: 0.22)
                : KisakiColors.pinkContainer,
      ),
      child: Text(
        source == 'custom' ? '自定义' : source.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: dark ? KisakiColors.pinkSoft : KisakiColors.onPinkContainer,
        ),
      ),
    );
  }
}

/// 平台评分显示（标签+分数）。
class PlatformRatingChip extends StatelessWidget {
  final String label;
  final double rating;
  final int votes;
  const PlatformRatingChip(
      {super.key, required this.label, required this.rating, this.votes = 0});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (rating <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: dark
            ? KisakiColors.lavender.withValues(alpha: 0.2)
            : KisakiColors.lavenderContainer,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft)),
          const SizedBox(width: 5),
          Text(rating.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: dark ? KisakiColors.lavenderSoft : KisakiColors.lavender)),
        ],
      ),
    );
  }
}

/// 游戏状态徽标。
class PlayStatusChip extends StatelessWidget {
  final PlayStatus status;
  final bool selected;
  final VoidCallback? onTap;
  const PlayStatusChip(this.status, {super.key, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(status.label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      avatar: Icon(_icon, size: 16, color: selected ? scheme.onPrimary : scheme.primary),
      backgroundColor: Colors.transparent,
      showCheckmark: false,
    );
  }

  IconData get _icon => switch (status) {
        PlayStatus.wish => Icons.star_border_rounded,
        PlayStatus.playing => Icons.play_circle_outline_rounded,
        PlayStatus.played => Icons.check_circle_outline_rounded,
        PlayStatus.onHold => Icons.pause_circle_outline_rounded,
        PlayStatus.dropped => Icons.highlight_off_rounded,
      };
}
