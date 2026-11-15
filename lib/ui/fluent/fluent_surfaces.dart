/// Fluent 2 表面、R18 保护封面与通用展示原语。
library;

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/media_paths.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import 'fluent_icons.dart';
import 'fluent_theme.dart';

/// 标准 Win11 卡片容器：中性层 + 1px 微妙描边 + 8px 圆角 + 可选悬停高亮。
class FluentSurfaceCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final bool elevated;
  final Color? backgroundColor;

  const FluentSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = 8,
    this.elevated = false,
    this.backgroundColor,
  });

  @override
  State<FluentSurfaceCard> createState() => _FluentSurfaceCardState();
}

class _FluentSurfaceCardState extends State<FluentSurfaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseBg = widget.backgroundColor ??
        (isDark ? const Color(0xD82C2C2C) : const Color(0xEBFFFFFF));
    final hoverBg = isDark ? const Color(0xE8353535) : const Color(0xFFFFFFFF);
    final borderColor = _hovered && widget.onTap != null
        ? theme.accentColor
            .defaultBrushFor(theme.brightness)
            .withValues(alpha: 0.65)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.07));

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _hovered && widget.onTap != null ? hoverBg : baseBg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: widget.elevated || (_hovered && widget.onTap != null)
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                  blurRadius: _hovered ? 16 : 8,
                  offset: Offset(0, _hovered ? 6 : 2),
                ),
              ]
            : null,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return box;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: box,
      ),
    );
  }
}

/// 局部 Fluent Acrylic 玻璃层，适合浮层提示/英雄横幅渐变蒙版/拖拽覆盖层。
class FluentAcrylicPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final double luminosityAlpha;
  final double tintAlpha;

  const FluentAcrylicPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 10,
    this.tint,
    this.luminosityAlpha = 0.72,
    this.tintAlpha = 0.72,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Acrylic(
        luminosityAlpha: luminosityAlpha,
        tintAlpha: tintAlpha,
        tint: tint ??
            (isDark ? const Color(0xFF232323) : const Color(0xFFF6F6F6)),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.black.withValues(alpha: 0.07),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 小标签胶囊（状态、数量、来源、评分）。
class FluentBadge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? foreground;
  final Color? background;
  final VoidCallback? onTap;

  const FluentBadge({
    super.key,
    required this.text,
    this.icon,
    this.foreground,
    this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = foreground ??
        (isDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF1E1E1E));
    final bg = background ??
        (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05));

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: (foreground ?? bg).withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.15,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// 游玩状态或自定义语义状态胶囊。
class FluentStatusPill extends StatelessWidget {
  final PlayStatus? status;
  final String? label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  const FluentStatusPill({
    super.key,
    required PlayStatus this.status,
    this.icon,
    this.color,
    this.onTap,
  }) : label = null;

  const FluentStatusPill.label({
    super.key,
    required String this.label,
    this.icon,
    this.color,
    this.onTap,
  }) : status = null;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolvedText = label ?? status!.label;
    final resolvedIcon = icon ?? _iconFor(status);
    final resolvedColor = color ?? _colorFor(status, theme, isDark);

    return FluentBadge(
      text: resolvedText,
      icon: resolvedIcon,
      foreground: resolvedColor,
      background: resolvedColor.withValues(alpha: isDark ? 0.18 : 0.11),
      onTap: onTap,
    );
  }

  static IconData? _iconFor(PlayStatus? s) => switch (s) {
        PlayStatus.wish => FluentIcons.bookmark_16_regular,
        PlayStatus.playing => FluentIcons.play_circle_16_regular,
        PlayStatus.played => FluentIcons.checkmark_circle_16_regular,
        PlayStatus.onHold => FluentIcons.pause_circle_16_regular,
        PlayStatus.dropped => FluentIcons.dismiss_circle_16_regular,
        null => null,
      };

  static Color _colorFor(PlayStatus? s, FluentThemeData theme, bool isDark) {
    return switch (s) {
      PlayStatus.wish => theme.accentColor.defaultBrushFor(theme.brightness),
      PlayStatus.playing =>
        isDark ? const Color(0xFF6CCB5F) : const Color(0xFF107C10),
      PlayStatus.played =>
        isDark ? const Color(0xFF60CDFF) : const Color(0xFF0078D4),
      PlayStatus.onHold =>
        isDark ? const Color(0xFFFCE100) : const Color(0xFF9D5D00),
      PlayStatus.dropped =>
        isDark ? const Color(0xFFFF99A4) : const Color(0xFFD13438),
      null => theme.accentColor.defaultBrushFor(theme.brightness),
    };
  }
}

/// R18 徽章强制位于评分徽章之前（产品规范强制不变量）。
class FluentR18ScoreRow extends StatelessWidget {
  final bool nsfw;
  final String? scoreText;
  final String? voteText;
  final List<Widget> trailing;

  const FluentR18ScoreRow({
    super.key,
    required this.nsfw,
    this.scoreText,
    this.voteText,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (nsfw)
          const FluentBadge(
            text: 'R18',
            foreground: Color(0xFFD13438),
            background: Color(0x22D13438),
          ),
        if (scoreText != null && scoreText!.isNotEmpty)
          FluentBadge(
            icon: FluentIcons.star_16_filled,
            text: voteText != null && voteText!.isNotEmpty
                ? '$scoreText · $voteText'
                : scoreText!,
            foreground: accent,
            background: accent.withValues(alpha: 0.14),
          ),
        ...trailing,
      ],
    );
  }
}

/// 封面渲染组件：同时支持本地路径与网络 URL，并集成 R18 模糊保护与悬停揭露。
class FluentCoverImage extends ConsumerStatefulWidget {
  final String pathOrUrl;
  final bool nsfw;
  final BoxFit fit;
  final double radius;
  final double? width;
  final double? height;
  final bool allowRevealOnHover;

  const FluentCoverImage({
    super.key,
    required this.pathOrUrl,
    this.nsfw = false,
    this.fit = BoxFit.cover,
    this.radius = 6,
    this.width,
    this.height,
    this.allowRevealOnHover = true,
  });

  @override
  ConsumerState<FluentCoverImage> createState() => _FluentCoverImageState();
}

class _FluentCoverImageState extends ConsumerState<FluentCoverImage> {
  bool _revealed = false;

  static File? _tryResolveExistingFile(String raw) {
    try {
      final resolved = MediaPaths.instance.resolveStored(raw);
      if (resolved.isEmpty) return null;
      final file = File(resolved);
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(nsfwModeProvider);
    final blurSigma = ref.watch(nsfwBlurProvider);
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget buildPlaceholder() => Container(
          width: widget.width,
          height: widget.height,
          color: isDark ? const Color(0xFF282828) : const Color(0xFFEBEBEB),
          child: Center(
            child: Icon(
              FluentIcons.image_24_regular,
              size: 28,
              color: theme.inactiveColor.withValues(alpha: 0.45),
            ),
          ),
        );

    final hideAsPlaceholder = widget.nsfw && mode == 'placeholder' && !_revealed;
    final applyBlur = widget.nsfw && mode == 'blur' && !_revealed;
    final trimmed = widget.pathOrUrl.trim();

    Widget img;
    if (hideAsPlaceholder || trimmed.isEmpty) {
      img = buildPlaceholder();
    } else if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      img = CachedNetworkImage(
        imageUrl: trimmed,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (_, __) => buildPlaceholder(),
        errorWidget: (_, __, ___) => buildPlaceholder(),
      );
    } else {
      final file = _tryResolveExistingFile(trimmed);
      if (file == null) {
        img = buildPlaceholder();
      } else {
        img = Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => buildPlaceholder(),
        );
      }
    }

    final renderedImg = applyBlur && blurSigma > 0
        ? ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
            ),
            child: img,
          )
        : img;

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          renderedImg,
          if (applyBlur || hideAsPlaceholder)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.28),
                padding: const EdgeInsets.all(4),
                alignment: Alignment.center,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FluentBadge(
                    icon: FluentIcons.eye_off_16_regular,
                    text: 'R18 已遮罩',
                    foreground: Colors.white,
                    background: Color(0xAA1F1F1F),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.nsfw && widget.allowRevealOnHover && mode != 'show') {
      content = MouseRegion(
        onEnter: (_) => setState(() => _revealed = true),
        onExit: (_) => setState(() => _revealed = false),
        child: content,
      );
    }
    return content;
  }
}

class FluentSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  const FluentSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 18,
            color: theme.accentColor.defaultBrushFor(theme.brightness),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.typography.subtitle),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class FluentEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const FluentEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: theme.inactiveColor.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.typography.bodyLarge),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 若上层缺少 [FluentTheme]，则提供兜底 Win11 Fluent 主题（测试/局部挂载安全）。
Widget ensureFluentTheme(BuildContext context, Widget child) {
  if (FluentTheme.maybeOf(context) != null) return child;
  final brightness =
      MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
  return FluentTheme(
    data: buildFluentTheme(
      brightness: brightness,
      preset: AccentPreset.system,
      systemAccent: kDefaultWin11Azure,
      backdrop: BackdropEffectPref.mica,
    ),
    child: child,
  );
}

/// 确保子树同时具备 [FluentTheme]、[FluentLocalizations] 与（可选）[Overlay] 作用域。
///
/// 当所需祖先均已存在时直接返回 [child] 本身，避免在生产页面树中引入多余包裹层。
Widget ensureFluentScope(
  BuildContext context,
  Widget child, {
  bool ensureOverlay = false,
}) {
  final hasTheme = FluentTheme.maybeOf(context) != null;
  final hasLoc = Localizations.of<FluentLocalizations>(
        context,
        FluentLocalizations,
      ) !=
      null;
  final hasOverlay = !ensureOverlay || Overlay.maybeOf(context) != null;
  if (hasTheme && hasLoc && hasOverlay) return child;

  var wrapped = child;
  if (!hasOverlay) {
    wrapped = Overlay.wrap(child: wrapped);
  }
  if (!hasLoc) {
    wrapped = Localizations.override(
      context: context,
      delegates: const [FluentLocalizations.delegate],
      child: wrapped,
    );
  }
  if (!hasTheme) {
    wrapped = ensureFluentTheme(context, wrapped);
  }
  return wrapped;
}
