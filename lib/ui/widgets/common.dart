/// 通用 UI 组件：封面图版、半透明面板、铭黄专色评分、源徽标。
library;

import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../core/paths.dart';
import '../../providers.dart';
import '../design.dart';
import '../theme.dart';

/// 封面宽高比：Galgame 封面标准 **2:3**（宽:高）。
const double kCoverAspect = 2 / 3;

/// 按 2:3 由宽度算高度（宽 220 → 高 330）。
double coverHeight(double width) => width / kCoverAspect;

/// 可拖动窗口区域。
class WindowDragBar extends StatelessWidget {
  final Widget? child;
  final double height;
  const WindowDragBar({super.key, this.child, this.height = 26});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      },
      child: SizedBox(height: height, width: double.infinity, child: child),
    );
  }
}

/// 本地图片存在性缓存：避免每帧/每张卡片都做同步 stat。
final Map<String, bool> _fileExistsCache = {};

bool _existsCached(String path) {
  final hit = _fileExistsCache[path];
  if (hit != null) return hit;
  bool exists;
  try {
    exists = File(path).existsSync();
  } catch (_) {
    exists = false;
  }
  if (_fileExistsCache.length > 2000) _fileExistsCache.clear();
  _fileExistsCache[path] = exists;
  return exists;
}

/// 供其它页面复用的存在性检查（带缓存）。
bool cachedFileExists(String path) => path.isNotEmpty && _existsCached(path);

/// 清除文件存在性缓存并在更新后驱逐图片内存缓存。
void invalidateFileExistsCache([String? path]) {
  if (path != null && path.isNotEmpty) {
    _fileExistsCache.remove(path);
    try {
      PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
    } catch (_) {}
  } else {
    _fileExistsCache.clear();
    try {
      PaintingBinding.instance.imageCache.clear();
    } catch (_) {}
  }
}

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
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.md)),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!nsfw) {
      return _renderImage(context, dark, blur: false);
    }
    final mode = ref.watch(nsfwModeProvider);
    if (mode == 'show') {
      return _renderImage(context, dark, blur: false);
    }
    if (mode == 'blur') {
      final blurStrength = ref.watch(nsfwBlurProvider);
      return _renderImage(context, dark, blur: true, sigma: blurStrength);
    }
    return _frame(context, child: _placeholder(dark));
  }

  /// 按显示尺寸与设备像素比计算合理的解码宽度，避免直接把 1200x1800+ 原图全量解码进显存。
  int _computeDecodeWidth(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.5);
    final w = width;
    if (w != null && w.isFinite && w > 0) {
      return (w * dpr).round().clamp(96, 960);
    }
    // 网格卡片内 AspectRatio 未显式传 width 时，按 210lp * dpr 解码
    return (210 * dpr).round().clamp(280, 560);
  }

  Widget _renderImage(BuildContext context, bool dark,
      {required bool blur, double sigma = 12}) {
    Widget? image;
    final decodeWidth = _computeDecodeWidth(context);
    final resolvedPath =
        path.isEmpty ? '' : AppPaths.instance.resolveStored(path);
    if (resolvedPath.isNotEmpty && _existsCached(resolvedPath)) {
      image = Image.file(
        File(resolvedPath),
        fit: fit,
        width: width,
        height: height,
        cacheWidth: decodeWidth,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
      );
    } else if ((networkUrl ?? '').isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: networkUrl!,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: decodeWidth,
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
    return _frame(context,
        child: ClipRRect(borderRadius: borderRadius, child: content));
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
        color: dark ? KisakiColors.nightContainer : KisakiColors.paperContainer,
        child: Icon(
          Icons.auto_stories_rounded,
          size: 30,
          color: dark
              ? KisakiColors.nightInkSoft.withValues(alpha: 0.55)
              : KisakiColors.inkSoft.withValues(alpha: 0.45),
        ),
      );
}

/// 毛玻璃面板。
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final Color? tint;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.xl)),
    this.padding = const EdgeInsets.all(20),
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ??
        (dark
            ? const Color(0xCC161820)
            : const Color(0xE0FAF7F2));
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
              color: Elev.border(dark),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 评分条（可交互，采用专色铭黄 Y）。
class RatingBar extends StatelessWidget {
  final double value; // 0-10
  final ValueChanged<double>? onChanged;
  final double size;

  const RatingBar(
      {super.key, required this.value, this.onChanged, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = KisakiColors.ratingInk(dark);
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

/// 源徽标（显示数据来源，杂志角标排版）。
class SourceBadge extends StatelessWidget {
  final String source;
  const SourceBadge({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final isCustom = source == 'custom';
    final color = isCustom
        ? scheme.onSurfaceVariant
        : (dark ? KisakiColors.magentaDark : KisakiColors.magenta);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        color: isCustom
            ? scheme.surfaceContainerHigh
            : color.withValues(alpha: dark ? 0.18 : 0.10),
        border: Border.all(
          color: isCustom
              ? Elev.border(dark)
              : color.withValues(alpha: dark ? 0.36 : 0.25),
          width: 1,
        ),
      ),
      child: Text(
        isCustom ? '自定义' : source.toUpperCase(),
        style: Type.micro.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.35,
          color: color,
        ),
      ),
    );
  }
}

/// 平台评分显示（标签+分数，专色铭黄 Y + 等宽数字）。
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
    final ratingColor = KisakiColors.ratingInk(dark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        color: ratingColor.withValues(alpha: dark ? 0.14 : 0.10),
        border: Border.all(
          color: ratingColor.withValues(alpha: dark ? 0.35 : 0.26),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 13, color: ratingColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: Type.micro.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            rating.toStringAsFixed(1),
            style: Type.mono.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: ratingColor,
            ),
          ),
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
  const PlayStatusChip(this.status,
      {super.key, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(status.label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      avatar: Icon(_icon,
          size: 16, color: selected ? scheme.onPrimary : scheme.primary),
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
