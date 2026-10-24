/// KisakiGals UI 组件库 (Kit) - Designable & Impeccable 工艺级重构.
///
/// 核心准则：
/// - 纯粹的视觉小说沉浸式作品管理体验；
/// - 彻底清除 AI-Slop 通病：无 eyebrow/kicker 眉标，无 zero-blur 假硬边阴影；
/// - 采用 Apple 级物理流体触觉组件 (FluidPressable + AppleGlassSurface)；
/// - 全局保证文本对比度 ≥ 4.5:1，数字全量对齐 Tabular 字形。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'theme.dart';
import 'widgets/common.dart'
    show CoverImage, cachedFileExists;
export 'widgets/common.dart' show invalidateFileExistsCache;

// ============================ 1. 页面骨架 ============================

/// 页面骨架：呼吸感极强的宏大排版，无杂音眉标，专注作品与操作
class KPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final IconData? leadingIcon;
  final List<Widget> actions;
  final Widget child;
  final bool scrollable;
  final double? maxContentWidth;

  const KPage({
    super.key,
    required this.title,
    this.maxContentWidth,
    this.subtitle,
    this.subtitleWidget,
    this.leadingIcon,
    this.actions = const [],
    required this.child,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: dark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(leadingIcon, size: 20, color: scheme.primary),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Type.display.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: 4),
                      subtitleWidget!,
                    ] else if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Type.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 16),
                Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Divider(
            color: scheme.outlineVariant,
            height: 1,
            thickness: 0.5,
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxContentWidth ?? double.infinity,
              ),
              child: scrollable
                  ? KScrollArea(child: child)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Gap.pageH, 12, Gap.pageH, 0),
                      child: child,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 滚动区域：定制细腻滚动条与底部微光渐隐
class KScrollArea extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool bottomFade;
  final double fadeHeight;

  const KScrollArea({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(Gap.pageH, 12, Gap.pageH, Gap.xxl),
    this.bottomFade = true,
    this.fadeHeight = 36,
  });

  @override
  State<KScrollArea> createState() => _KScrollAreaState();
}

class _KScrollAreaState extends State<KScrollArea> {
  final _controller = ScrollController();
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 8;
    if (atEnd != _atEnd) setState(() => _atEnd = atEnd);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = KisakiColors.pageSurface(
        Theme.of(context).brightness == Brightness.dark);
    final scroll = Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        padding: widget.padding,
        child: widget.child,
      ),
    );
    if (!widget.bottomFade) return scroll;
    return Stack(
      children: [
        scroll,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: widget.fadeHeight,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _atEnd ? 0 : 1,
              duration: Motion.normal,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [surface.withValues(alpha: 0), surface],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 区块槽位（保证多列标题对齐）
class KSectionSlot extends StatelessWidget {
  final Widget? child;
  const KSectionSlot({super.key, this.child});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 38, child: Center(child: child ?? const SizedBox.shrink()));
}

/// 区块标题
class KSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;
  final bool reserveSlot;

  const KSectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 12),
    this.reserveSlot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            text,
            style: Type.section.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            trailing!
          else if (reserveSlot)
            const KSectionSlot(),
        ],
      ),
    );
  }
}

// ============================ 2. 卡片与触觉表面 ============================

/// 全应用核心卡片原语：融合 AppleGlassSurface 与物理按压回弹
class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final bool glass;
  final bool dense;
  final Color? color;
  final bool overlayShadow;
  final bool flat;
  final Color? borderColor;
  final void Function(Offset position)? onSecondaryTapAt;

  const KCard({
    super.key,
    required this.child,
    this.padding = Gap.cardPadding,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.lg)),
    this.glass = false,
    this.dense = false,
    this.color,
    this.overlayShadow = false,
    this.flat = false,
    this.borderColor,
    this.onSecondaryTapAt,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final pad = dense ? Gap.cardPaddingDense : padding;
    final fill = color ?? (dark ? KisakiColors.nightCard : Colors.white);

    if (glass) {
      final surface = AppleGlassSurface(
        borderRadius: borderRadius.topLeft.x,
        padding: pad,
        tintColor: color,
        borderWidth: 0.5,
        borderColor: borderColor,
        shadows: flat
            ? null
            : (overlayShadow ? Elev.overlay(dark) : Elev.card(dark, scheme.primary)),
        child: child,
      );
      if (onTap == null && onSecondaryTapAt == null) return surface;
      return FluidPressable(
        onTap: onTap,
        onSecondaryTapAt: onSecondaryTapAt,
        child: surface,
      );
    }

    final shadows = flat
        ? const <BoxShadow>[]
        : (overlayShadow
            ? Elev.overlay(dark)
            : Elev.card(dark, scheme.primary));

    if (onTap != null || onSecondaryTapAt != null) {
      return InteractiveSurface(
        onTap: onTap,
        onSecondaryTapAt: onSecondaryTapAt,
        borderRadius: borderRadius,
        color: fill,
        outline: scheme.primary,
        padding: pad,
        elevated: !overlayShadow && !flat,
        child: child,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? Elev.border(dark),
          width: 0.5,
        ),
        boxShadow: shadows,
      ),
      child: Padding(padding: pad, child: child),
    );
  }
}

/// 紧凑 Bento 统计块
class KStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final Color? accent;
  final bool glass;
  final VoidCallback? onTap;

  const KStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
    this.accent,
    this.glass = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;

    return KCard(
      glass: glass,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              color: color.withValues(alpha: dark ? 0.20 : 0.12),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedCount(
                  text: value,
                  style: Type.numeric.copyWith(
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.micro.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ 3. 操作控件 ============================

/// 响应式工具栏
class KToolbar extends StatelessWidget {
  final List<Widget> children;
  const KToolbar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          return compact
              ? Wrap(
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    for (final child in children)
                      if (child is! Spacer) child,
                  ],
                )
              : Row(children: children);
        },
      ),
    );
  }
}

/// 图标动作按钮：带有瞬发按压反馈与镜面微光
class KIconAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool enabled;

  const KIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.enabled = true,
  });

  @override
  State<KIconAction> createState() => _KIconActionState();
}

class _KIconActionState extends State<KIconAction> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled && widget.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          enabled: widget.enabled && widget.onTap != null,
          label: widget.tooltip,
          selected: widget.active,
          child: Focus(
            onFocusChange: (value) => setState(() => _focused = value),
            onKeyEvent: (node, event) {
              if (widget.enabled &&
                  event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                widget.onTap?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: FluidPressable(
              onTap: widget.enabled ? widget.onTap : null,
              child: AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.enter,
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: widget.active
                      ? scheme.primary.withValues(alpha: dark ? 0.22 : 0.12)
                      : (_focused
                          ? scheme.primary.withValues(alpha: dark ? 0.16 : 0.08)
                          : (_hover
                              ? (dark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05))
                              : Colors.transparent)),
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: widget.active || _focused
                        ? scheme.primary.withValues(alpha: 0.45)
                        : (_hover ? Elev.border(dark) : Colors.transparent),
                    width: 0.5,
                  ),
                  boxShadow: widget.active || _focused
                      ? Elev.focusGlow(dark, scheme.primary)
                      : null,
                ),
                child: Icon(
                  widget.icon,
                  size: 19,
                  color: !widget.enabled
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
                      : (widget.active
                          ? scheme.primary
                          : scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 胶囊筛选标签
class KChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;
  final IconData? icon;

  const KChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.color,
    this.icon,
  });

  @override
  State<KChip> createState() => _KChipState();
}

class _KChipState extends State<KChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.color ?? scheme.primary;

    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        enabled: widget.onTap != null,
        selected: widget.selected,
        label: widget.label,
        child: FluidPressable(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: widget.selected
                  ? color.withValues(alpha: dark ? 0.22 : 0.12)
                  : (_hover
                      ? (dark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.05)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(Radii.full),
              border: Border.all(
                color: widget.selected
                    ? color.withValues(alpha: 0.60)
                    : Elev.border(dark),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 13,
                    color: widget.selected ? color : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  widget.label,
                  style: Type.caption.copyWith(
                    color: widget.selected ? color : scheme.onSurfaceVariant,
                    fontWeight:
                        widget.selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 核心动作药丸按钮：支持实心与线框态
class KPill extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;
  final Color? color;

  const KPill({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.filled = true,
    this.color,
  });

  @override
  State<KPill> createState() => _KPillState();
}

class _KPillState extends State<KPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final primary = widget.color ?? scheme.primary;
    final enabled = widget.onTap != null;

    final child = widget.icon == null
        ? Text(widget.label, style: Type.label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 17),
              const SizedBox(width: 7),
              Text(widget.label, style: Type.label),
            ],
          );

    final bgColor = widget.filled
        ? primary
        : (_hover
            ? primary.withValues(alpha: dark ? 0.16 : 0.08)
            : Colors.transparent);
    final fgColor = widget.filled
        ? scheme.onPrimary
        : (widget.color ?? scheme.onSurface);
    final borderColor = widget.filled
        ? Colors.transparent
        : (_hover
            ? primary.withValues(alpha: dark ? 0.45 : 0.35)
            : Elev.border(dark));

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: FluidPressable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: (widget.filled && _hover && enabled)
                ? Elev.buttonHover(dark, primary)
                : null,
          ),
          child: DefaultTextStyle(
            style: Type.label.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
            ),
            child: IconTheme(
              data: IconThemeData(color: fgColor, size: 17),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 空状态容器
class KEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;
  final bool compact;

  const KEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.refresh_rounded,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 42 : 64,
              height: compact ? 42 : 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.10),
              ),
              child: Icon(
                icon,
                size: compact ? 20 : 30,
                color: scheme.primary,
              ),
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(
              title,
              style: (compact ? Type.label : Type.title).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              KPill(label: actionLabel!, icon: actionIcon, onTap: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// 加载圈
class KLoading extends StatelessWidget {
  final double size;
  const KLoading({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
}

/// 骨架块
class KSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const KSkeleton({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 骨架文本多行
class KSkeletonLines extends StatelessWidget {
  final int lines;
  final double lastLineFactor;
  final double gap;

  const KSkeletonLines({
    super.key,
    this.lines = 2,
    this.lastLineFactor = 0.55,
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines; i++) ...[
          if (i > 0) SizedBox(height: gap),
          if (i == lines - 1 && lines > 1)
            FractionallySizedBox(
              widthFactor: lastLineFactor,
              child: const KSkeleton(height: 10),
            )
          else
            const KSkeleton(height: 11, width: double.infinity),
        ],
      ],
    );
  }
}

/// 小徽章
class KBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const KBadge({super.key, required this.text, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3.5),
          ],
          Text(
            text,
            style: Type.micro.copyWith(
              color: c,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表项行
class KRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const KRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.caption
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 媒体行（列表视图中的游戏卡）
class KMediaRow extends StatelessWidget {
  final String coverPath;
  final String? coverUrl;
  final String title;
  final String? subtitle;
  final double coverWidth;
  final bool selected;
  final bool nsfw;
  final double badgeRunSpacing;
  final double titleHeight;
  final String? timeText;
  final double timeWidth;
  final Widget? trailing;
  final VoidCallback? onTap;
  final void Function(Offset position)? onSecondaryTapAt;
  final List<Widget> badges;

  const KMediaRow({
    super.key,
    this.coverPath = '',
    this.coverUrl,
    required this.title,
    this.subtitle,
    this.coverWidth = 44,
    this.selected = false,
    this.nsfw = false,
    this.badgeRunSpacing = 4,
    this.titleHeight = 34,
    this.timeText,
    this.timeWidth = 78,
    this.trailing,
    this.onTap,
    this.onSecondaryTapAt,
    this.badges = const [],
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final coverH = coverWidth / (2 / 3);

    return InteractiveSurface(
      onTap: onTap,
      onSecondaryTapAt: onSecondaryTapAt,
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      borderRadius: BorderRadius.circular(Radii.lg),
      color: selected
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: dark ? 0.22 : 0.12),
              dark ? KisakiColors.nightCard : Colors.white,
            )
          : (dark ? KisakiColors.nightCard : Colors.white),
      outline: scheme.primary,
      child: Row(
        children: [
          SizedBox(
            width: coverWidth,
            height: coverH,
            child: CoverImage(
              path: coverPath,
              networkUrl: coverUrl,
              nsfw: nsfw,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: titleHeight,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                if (badges.isNotEmpty)
                  Wrap(
                    spacing: 5,
                    runSpacing: badgeRunSpacing,
                    children: badges,
                  )
                else if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (timeText != null) ...[
            SizedBox(
              width: timeWidth,
              child: Text(
                timeText!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

bool coverExists(String path) => cachedFileExists(path);

// ============================ 4. 封面浮层小部件 ============================

/// 封面浮层标签
class KOverlayTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;

  const KOverlayTag({
    super.key,
    required this.text,
    this.icon,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.20),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: Type.micro.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面上的圆形按钮
class KOverlayIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final double size;

  const KOverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.size = 28,
  });

  @override
  State<KOverlayIconButton> createState() => _KOverlayIconButtonState();
}

class _KOverlayIconButtonState extends State<KOverlayIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? Colors.white;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: FluidPressable(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: _hover ? 0.72 : 0.52),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
                width: 0.5,
              ),
            ),
            child: Icon(widget.icon, size: widget.size * 0.55, color: c),
          ),
        ),
      ),
    );
  }
}

/// 批量选择勾选圆点
class KSelectDot extends StatelessWidget {
  final bool selected;
  final double size;

  const KSelectDot({super.key, required this.selected, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? scheme.primary
            : Colors.black.withValues(alpha: 0.45),
        border: Border.all(
          color: Colors.white,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(
              Icons.check_rounded,
              size: size * 0.65,
              color: Colors.white,
            )
          : const SizedBox.shrink(),
    );
  }
}
