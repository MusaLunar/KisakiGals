/// Fluent 2 表面、搜索框、分段器、骨架屏、R18 保护封面与通用展示原语。
library;

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/media_paths.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import 'fluent_icons.dart';
import 'fluent_motion.dart';
import 'fluent_theme.dart';

/// 标准 Win11 卡片容器：中性层 + 1px 描边 + 8px 圆角 + 键盘焦点环与平滑悬停态。
class FluentSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final bool elevated;
  final Color? backgroundColor;
  final bool selected;
  final String? semanticLabel;

  const FluentSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = 8,
    this.elevated = false,
    this.backgroundColor,
    this.selected = false,
    this.semanticLabel,
  });

  Widget _buildBox(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
  }) {
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final disableAnim = fluentAnimationsDisabled(context);

    final defaultBase =
        isDark ? const Color(0xD82C2C2C) : const Color(0xEBFFFFFF);
    final baseBg = backgroundColor ??
        (selected
            ? Color.alphaBlend(
                theme.accentInk.withValues(alpha: isDark ? 0.14 : 0.08),
                defaultBase,
              )
            : defaultBase);

    Color resolvedBg = baseBg;
    if (onTap != null) {
      if (pressed) {
        resolvedBg = Color.alphaBlend(theme.subtlePressed, baseBg);
      } else if (hovered) {
        resolvedBg = backgroundColor != null || selected
            ? Color.alphaBlend(theme.subtleHover, baseBg)
            : (isDark ? const Color(0xE8353535) : const Color(0xFFFFFFFF));
      }
    }

    final borderColor = (selected || (hovered && onTap != null))
        ? theme.accentInk.withValues(alpha: selected ? 0.85 : 0.65)
        : theme.surfaceStroke;

    return AnimatedContainer(
      duration: disableAnim ? Duration.zero : FluentMotion.fast,
      curve: FluentMotion.enterCurve,
      padding: padding,
      decoration: BoxDecoration(
        color: resolvedBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: elevated || (hovered && onTap != null)
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.07),
                  blurRadius: hovered ? 16 : 8,
                  offset: Offset(0, hovered ? 5 : 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return _buildBox(context, hovered: false, pressed: false);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: HoverButton(
        cursor: SystemMouseCursors.click,
        onPressed: onTap,
        builder: (context, states) => FocusBorder(
          focused: states.isFocused,
          renderOutside: false,
          child: _buildBox(
            context,
            hovered: states.isHovered,
            pressed: states.isPressed,
          ),
        ),
      ),
    );
  }
}

/// 局部 Fluent 浮层面板：默认使用轻量半透明磨砂底衬，按需通过 [enableBlur] 启用实时 Acrylic 模糊。
class FluentAcrylicPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final double luminosityAlpha;
  final double tintAlpha;
  final bool enableBlur;

  const FluentAcrylicPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 10,
    this.tint,
    this.luminosityAlpha = 0.72,
    this.tintAlpha = 0.72,
    this.enableBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final resolvedTint =
        tint ?? (isDark ? const Color(0xFF232323) : const Color(0xFFF6F6F6));
    final border = Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.09)
          : Colors.black.withValues(alpha: 0.07),
    );
    if (!enableBlur || fluentAnimationsDisabled(context)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: resolvedTint.withValues(alpha: isDark ? 0.90 : 0.94),
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: child,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Acrylic(
        luminosityAlpha: luminosityAlpha,
        tintAlpha: tintAlpha,
        tint: resolvedTint,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Fluent 2 统一搜索输入栏：对齐 Windows 11 SearchBox 形态、前置放大镜与即时清除按钮。
class FluentSearchBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;
  final bool enabled;
  final bool autofocus;
  final bool compact;
  final String? shortcutHint;
  final Widget? trailing;
  final double? maxWidth;

  const FluentSearchBox({
    super.key,
    required this.controller,
    this.focusNode,
    required this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
    this.enabled = true,
    this.autofocus = false,
    this.compact = false,
    this.shortcutHint,
    this.trailing,
    this.maxWidth,
  });

  @override
  State<FluentSearchBox> createState() => _FluentSearchBoxState();
}

class _FluentSearchBoxState extends State<FluentSearchBox> {
  late FocusNode _focusNode = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant FluentSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_onFocusChange);
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onCleared?.call();
    if (_focusNode.canRequestFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final accent = theme.accentInk;
    final boxHeight = widget.compact ? 31.0 : 34.0;
    final radius = BorderRadius.circular(6);

    final field = Focus(
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (widget.controller.text.isNotEmpty) {
            _clear();
            return KeyEventResult.handled;
          }
          if (_focusNode.hasFocus) {
            _focusNode.unfocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final hasText = value.text.isNotEmpty;
          final focused = _focusNode.hasFocus;
          return SizedBox(
            height: boxHeight,
            child: TextBox(
              controller: widget.controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              placeholder: widget.placeholder,
              textInputAction: TextInputAction.search,
              style: theme.typography.body?.copyWith(fontSize: 13),
              placeholderStyle: theme.typography.body?.copyWith(
                fontSize: 13,
                color: theme.textSecondary,
              ),
              padding: EdgeInsetsDirectional.fromSTEB(
                8,
                widget.compact ? 4 : 6,
                6,
                widget.compact ? 4 : 6,
              ),
              decoration: WidgetStateProperty.resolveWith((states) {
                final fill = !widget.enabled
                    ? res.controlFillColorDisabled
                    : (states.isFocused || states.isPressed)
                        ? res.controlFillColorInputActive
                        : states.isHovered
                            ? res.controlFillColorSecondary
                            : res.controlFillColorDefault;
                return BoxDecoration(
                  color: fill,
                  borderRadius: radius,
                  border: Border.all(
                    color: states.isFocused
                        ? accent.withValues(alpha: 0.45)
                        : res.controlStrokeColorDefault,
                  ),
                );
              }),
              foregroundDecoration: WidgetStateProperty.resolveWith((states) {
                if (states.isFocused) {
                  return BoxDecoration(
                    borderRadius: radius,
                    border: Border(
                      bottom: BorderSide(color: accent, width: 2),
                    ),
                  );
                }
                if (!widget.enabled) return const BoxDecoration();
                return BoxDecoration(
                  borderRadius: radius,
                  border: Border(
                    bottom: BorderSide(
                      color: res.controlStrongStrokeColorDefault
                          .withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                );
              }),
              prefix: Padding(
                padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
                child: Icon(
                  FluentIcons.search_16_regular,
                  size: 14,
                  color: !widget.enabled
                      ? theme.textDisabled
                      : focused
                          ? accent
                          : theme.textSecondary,
                ),
              ),
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasText && widget.enabled)
                    Tooltip(
                      message: '清空搜索',
                      child: Semantics(
                        label: '清空搜索',
                        button: true,
                        child: IconButton(
                          icon: const Icon(
                            FluentIcons.dismiss_12_regular,
                            size: 12,
                          ),
                          onPressed: _clear,
                        ),
                      ),
                    )
                  else if (!hasText && !focused && widget.shortcutHint != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.surfaceCardSecondary,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: theme.surfaceStroke),
                        ),
                        child: Text(
                          widget.shortcutHint!,
                          style: theme.typography.caption?.copyWith(
                            fontSize: 10.5,
                            color: theme.textTertiary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
              onChanged: widget.onChanged,
              onSubmitted: widget.enabled ? widget.onSubmitted : null,
            ),
          );
        },
      ),
    );

    if (widget.maxWidth == null) return field;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth!),
      child: field,
    );
  }
}

/// 分段切换选项定义。
class FluentSegmentItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final String? tooltip;
  final bool showLabel;
  final Key? key;

  const FluentSegmentItem({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
    this.showLabel = true,
    this.key,
  });
}

/// Fluent 2 分段控制器（单选语义，恒定 1px 描边避免切换抖动）。
class FluentSegmentedControl<T> extends StatelessWidget {
  final List<FluentSegmentItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool compact;

  const FluentSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final accent = theme.accentInk;
    final disableAnim = fluentAnimationsDisabled(context);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorSecondary,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: theme.surfaceStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items) ...[
            _SegmentButton<T>(
              key: item.key,
              item: item,
              selected: item.value == selected,
              compact: compact,
              accent: accent,
              isDark: isDark,
              disableAnim: disableAnim,
              onPressed: () => onChanged(item.value),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  final FluentSegmentItem<T> item;
  final bool selected;
  final bool compact;
  final Color accent;
  final bool isDark;
  final bool disableAnim;
  final VoidCallback onPressed;

  const _SegmentButton({
    super.key,
    required this.item,
    required this.selected,
    required this.compact,
    required this.accent,
    required this.isDark,
    required this.disableAnim,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final btn = Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: HoverButton(
        cursor: SystemMouseCursors.click,
        onPressed: onPressed,
        builder: (context, states) {
          final bg = selected
              ? (isDark ? const Color(0xFF383838) : const Color(0xFFFFFFFF))
              : states.isPressed
                  ? theme.subtlePressed
                  : states.isHovered
                      ? theme.subtleHover
                      : Colors.transparent;
          final borderColor = selected
              ? theme.surfaceStroke
              : Colors.transparent;
          final fg = selected
              ? theme.textPrimary
              : states.isHovered
                  ? theme.textPrimary
                  : theme.textSecondary;

          return FocusBorder(
            focused: states.isFocused,
            renderOutside: false,
            child: AnimatedContainer(
              duration: disableAnim ? Duration.zero : FluentMotion.fast,
              curve: FluentMotion.enterCurve,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 5 : 6,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.24 : 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.icon != null) ...[
                    Icon(
                      item.icon,
                      size: 14,
                      color: selected ? accent : fg,
                    ),
                    if (item.showLabel) const SizedBox(width: 6),
                  ],
                  if (item.showLabel)
                    Text(
                      item.label,
                      style: theme.typography.body?.copyWith(
                        fontSize: compact ? 12.5 : 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (item.tooltip != null && item.tooltip!.isNotEmpty) {
      return Tooltip(message: item.tooltip!, child: btn);
    }
    return btn;
  }
}

/// 骨架加载占位块（自动遵循减少动画无障碍偏好）。
class FluentCardSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const FluentCardSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final disableAnim = fluentAnimationsDisabled(context);

    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.surfaceStroke),
      ),
    );

    return box.fluentShimmer(
      disable: disableAnim,
      highlightColor: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.55),
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
  final bool selected;
  final String? tooltip;

  const FluentBadge({
    super.key,
    required this.text,
    this.icon,
    this.foreground,
    this.background,
    this.onTap,
    this.selected = false,
    this.tooltip,
  });

  Widget _buildPill(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
  }) {
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;
    final fg = foreground ?? theme.textPrimary;
    final baseBg = background ??
        (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05));
    final resolvedBg = onTap == null
        ? baseBg
        : pressed
            ? Color.alphaBlend(theme.subtlePressed, baseBg)
            : hovered
                ? Color.alphaBlend(theme.subtleHover, baseBg)
                : baseBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: resolvedBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: (foreground ?? baseBg).withValues(alpha: hovered ? 0.45 : 0.22),
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
  }

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      final pill = _buildPill(context, hovered: false, pressed: false);
      return tooltip != null ? Tooltip(message: tooltip!, child: pill) : pill;
    }

    final interactive = Semantics(
      button: true,
      selected: selected,
      label: text,
      child: HoverButton(
        cursor: SystemMouseCursors.click,
        onPressed: onTap,
        builder: (context, states) => FocusBorder(
          focused: states.isFocused,
          renderOutside: false,
          child: _buildPill(
            context,
            hovered: states.isHovered,
            pressed: states.isPressed,
          ),
        ),
      ),
    );
    return tooltip != null
        ? Tooltip(message: tooltip!, child: interactive)
        : interactive;
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
    final isDark = theme.isDark;
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
      PlayStatus.wish => theme.accentInk,
      PlayStatus.playing => theme.successInk,
      PlayStatus.played =>
        isDark ? const Color(0xFF60CDFF) : const Color(0xFF0078D4),
      PlayStatus.onHold => theme.warningInk,
      PlayStatus.dropped => theme.dangerInk,
      null => theme.accentInk,
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
    final accent = theme.accentInk;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (nsfw)
          FluentBadge(
            text: 'R18',
            foreground: theme.dangerInk,
            background: theme.dangerTint,
          ),
        if (scoreText != null && scoreText!.isNotEmpty)
          FluentBadge(
            icon: FluentIcons.star_16_filled,
            text: voteText != null && voteText!.isNotEmpty
                ? '$scoreText · $voteText'
                : scoreText!,
            foreground: accent,
            background: accent.withValues(alpha: theme.isDark ? 0.18 : 0.12),
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
  final int? maxDecodeWidth;

  const FluentCoverImage({
    super.key,
    required this.pathOrUrl,
    this.nsfw = false,
    this.fit = BoxFit.cover,
    this.radius = 6,
    this.width,
    this.height,
    this.allowRevealOnHover = true,
    this.maxDecodeWidth,
  });

  @override
  ConsumerState<FluentCoverImage> createState() => _FluentCoverImageState();
}

class _FluentCoverImageState extends ConsumerState<FluentCoverImage> {
  bool _revealed = false;
  File? _resolvedFile;
  bool _isNetworkUrl = false;
  String? _resolvedForRaw;

  @override
  void initState() {
    super.initState();
    _syncSource();
  }

  @override
  void didUpdateWidget(covariant FluentCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathOrUrl != widget.pathOrUrl) {
      _syncSource();
    }
    if (oldWidget.nsfw != widget.nsfw && !widget.nsfw) {
      _revealed = false;
    }
  }

  void _syncSource() {
    final trimmed = widget.pathOrUrl.trim();
    if (_resolvedForRaw == trimmed) return;
    _resolvedForRaw = trimmed;
    if (trimmed.isEmpty) {
      _isNetworkUrl = false;
      _resolvedFile = null;
      return;
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      _isNetworkUrl = true;
      _resolvedFile = null;
      return;
    }
    _isNetworkUrl = false;
    _resolvedFile = _tryResolveExistingFile(trimmed);
  }

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
    final mode = widget.nsfw ? ref.watch(nsfwModeProvider) : 'show';
    final blurSigma = widget.nsfw ? ref.watch(nsfwBlurProvider) : 0.0;
    final theme = FluentTheme.of(context);
    final isDark = theme.isDark;

    Widget buildPlaceholder() => Container(
          width: widget.width,
          height: widget.height,
          color: isDark ? const Color(0xFF282828) : const Color(0xFFEBEBEB),
          child: Center(
            child: Icon(
              FluentIcons.image_24_regular,
              size: 26,
              color: theme.textTertiary.withValues(alpha: 0.7),
            ),
          ),
        );

    final hideAsPlaceholder = widget.nsfw && mode == 'placeholder' && !_revealed;
    final applyBlur = widget.nsfw && mode == 'blur' && !_revealed;
    final trimmed = _resolvedForRaw ?? widget.pathOrUrl.trim();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final decodeWidth = widget.maxDecodeWidth ??
        ((widget.width != null &&
                widget.width!.isFinite &&
                widget.width! > 0)
            ? (widget.width! * dpr).round().clamp(96, 960)
            : (360 * dpr).round().clamp(320, 640));

    Widget img;
    if (hideAsPlaceholder || trimmed.isEmpty) {
      img = buildPlaceholder();
    } else if (_isNetworkUrl) {
      img = CachedNetworkImage(
        imageUrl: trimmed,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: decodeWidth,
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) => buildPlaceholder(),
        errorWidget: (_, __, ___) => buildPlaceholder(),
      );
    } else {
      final file = _resolvedFile;
      if (file == null) {
        img = buildPlaceholder();
      } else {
        img = Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: decodeWidth,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => buildPlaceholder(),
        );
      }
    }

    final renderedImg = applyBlur && blurSigma > 0
        ? RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: img,
            ),
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
            color: theme.accentInk,
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
                      color: theme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
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
              color: theme.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.typography.bodyLarge),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.typography.caption?.copyWith(
                  color: theme.textSecondary,
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
      backdrop: BackdropEffectPref.solid,
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
