/// KisakiGals UI 组件库 (Kit) — 誌面 (Shimen) 视觉小说杂志特辑版面系统.
///
/// 核心准则：
/// - 铜版纸象牙白 / 凹版暗墨底版 + CMYK 专色职能分工；
/// - 杜绝 eyebrow/kicker 眉标杂音，采用杂志栏头定位标尺与 1px 裁切细线；
/// - 全量接入 FluidPressable (t=0 瞬发 + 10px 迟滞边界 + 速度继承弹簧)；
/// - 时间、评分与统计数字强制使用 Tabular 等宽字形对齐。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'theme.dart';
import 'widgets/common.dart' show CoverImage, cachedFileExists;
export 'widgets/common.dart' show invalidateFileExistsCache;

// ============================ 1. 杂志版心骨架 ============================

/// 页面骨架：杂志刊头式顶栏 + 1px 裁切细线 + 宽幅版心
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
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 专色洋红书眉定位标尺
              Container(
                width: 3.5,
                height: subtitle != null || subtitleWidget != null ? 36 : 24,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (leadingIcon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: dark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.28),
                      width: 1,
                    ),
                  ),
                  child: Icon(leadingIcon, size: 18, color: scheme.primary),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.display.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: 4),
                      subtitleWidget!,
                    ] else if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.38,
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
            color: Elev.border(dark),
            height: 1,
            thickness: 1,
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
                          Gap.pageH, 14, Gap.pageH, 0),
                      child: child,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 滚动区域：定制滚动条与底部纸色渐隐
class KScrollArea extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool bottomFade;
  final double fadeHeight;

  const KScrollArea({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(Gap.pageH, 14, Gap.pageH, Gap.xxl),
    this.bottomFade = true,
    this.fadeHeight = 32,
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

/// 区块槽位（保证多栏标题水平基线对齐）
class KSectionSlot extends StatelessWidget {
  final Widget? child;
  const KSectionSlot({super.key, this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 36, child: Center(child: child ?? const SizedBox.shrink()));
}

/// 杂志分栏标题：带 2.5px 专色标尺与延展细线
class KSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;
  final bool reserveSlot;
  final Color? accentColor;

  const KSectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 12),
    this.reserveSlot = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tickColor = accentColor ?? scheme.primary;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: tickColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          Text(
            text,
            style: Type.section.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: Elev.border(dark),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ] else if (reserveSlot)
            const KSectionSlot(),
        ],
      ),
    );
  }
}

// ============================ 2. 纸张图版与统计格 ============================

/// 全应用核心图版卡片原语（严格遵循单一海拔原则：1px 裁切细线或浮层阴影）
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
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final scheme = Theme.of(context).colorScheme;
    final pad = dense ? Gap.cardPaddingDense : padding;
    final fill = color ?? (dark ? KisakiColors.nightCard : Colors.white);

    if (glass) {
      final surface = AppleGlassSurface(
        borderRadius: borderRadius.topLeft.x,
        padding: pad,
        tintColor: color,
        borderWidth: 1.0,
        borderColor: borderColor,
        shadows: flat
            ? null
            : (overlayShadow
                ? Elev.overlay(dark)
                : Elev.card(dark, scheme.primary)),
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
          color: borderColor ?? Elev.border(dark, highContrast: highContrast),
          width: 1,
        ),
        boxShadow: shadows,
      ),
      child: Padding(padding: pad, child: child),
    );
  }
}

/// 杂志数据格 (Bento Stat Cell)：支持 CMYK 专色标尺与 Tabular 大数字
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
    final color = accent ?? KisakiColors.temporalInk(dark);

    return KCard(
      glass: glass,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              color: color.withValues(alpha: dark ? 0.16 : 0.10),
              border: Border.all(
                color: color.withValues(alpha: dark ? 0.32 : 0.22),
                width: 1,
              ),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 13),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedCount(
                  text: value,
                  style: Type.numeric.copyWith(
                    fontSize: 17,
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

/// 图标动作按钮：1px 细线框 + 瞬发按压反馈
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
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: widget.active
                      ? scheme.primary.withValues(alpha: dark ? 0.22 : 0.12)
                      : (_focused
                          ? scheme.primary.withValues(alpha: dark ? 0.16 : 0.08)
                          : (_hover
                              ? (dark
                                  ? Colors.white.withValues(alpha: 0.07)
                                  : const Color(0xFF16151A)
                                      .withValues(alpha: 0.05))
                              : Colors.transparent)),
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: widget.active || _focused
                        ? scheme.primary.withValues(alpha: 0.55)
                        : (_hover ? Elev.border(dark) : Colors.transparent),
                    width: 1,
                  ),
                  boxShadow: widget.active || _focused
                      ? Elev.focusGlow(dark, scheme.primary)
                      : null,
                ),
                child: AnimatedSwitcher(
                  duration: Motion.fast,
                  switchInCurve: Motion.spring,
                  switchOutCurve: Motion.exit,
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: Tween<double>(begin: 0.72, end: 1.0).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    widget.icon,
                    key: ValueKey<int>(Object.hash(widget.icon, widget.active)),
                    size: 18,
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
      ),
    );
  }
}

/// 索引筛选标签
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
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
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
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
            decoration: BoxDecoration(
              color: widget.selected
                  ? color.withValues(alpha: dark ? 0.22 : 0.12)
                  : (_hover
                      ? (dark ? Colors.white : const Color(0xFF16151A))
                          .withValues(alpha: 0.05)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(
                color: widget.selected
                    ? color.withValues(alpha: 0.65)
                    : Elev.border(dark),
                width: 1,
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

/// 核心动作按钮：支持实心专色洋红与 1px 裁切线框态
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
              Icon(widget.icon, size: 16),
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
            ? primary.withValues(alpha: dark ? 0.55 : 0.42)
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9.5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: (widget.filled && _hover && enabled)
                ? Elev.buttonHover(dark, primary)
                : null,
          ),
          child: DefaultTextStyle(
            style: Type.label.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w700,
            ),
            child: IconTheme(
              data: IconThemeData(color: fgColor, size: 16),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 42 : 60,
              height: compact ? 42 : 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                color: scheme.primary.withValues(alpha: dark ? 0.14 : 0.08),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                size: compact ? 20 : 28,
                color: scheme.primary,
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
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
              const SizedBox(height: 16),
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

/// 印刷专色小徽章
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
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(
          color: c.withValues(alpha: 0.28),
          width: 1,
        ),
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

/// 发售表/目录式媒体行：严格对齐 Tabular 时间列与图版微缩图
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
    this.timeWidth = 84,
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
      borderRadius: BorderRadius.circular(Radii.md),
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
              borderRadius: BorderRadius.circular(Radii.xs),
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
                      fontWeight: FontWeight.w700,
                      height: 1.24,
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
                    style:
                        Type.caption.copyWith(color: scheme.onSurfaceVariant),
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
                style: Type.mono.copyWith(
                  color: KisakiColors.temporalInk(dark),
                  fontWeight: FontWeight.w600,
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

// ============================ 4. 封面图版角标小部件 ============================

/// 封面图版角标标签
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
        color: const Color(0xFF0F1015).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3.5),
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

/// 封面上的圆形动作按钮
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
    this.size = 26,
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
        cursor:
            widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
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
              color: const Color(0xFF0F1015)
                  .withValues(alpha: _hover ? 0.86 : 0.72),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
                width: 1,
              ),
            ),
            child: AnimatedSwitcher(
              duration: Motion.fast,
              switchInCurve: Motion.spring,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween<double>(begin: 0.65, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                widget.icon,
                key: ValueKey<Object>(Object.hash(widget.icon, c)),
                size: widget.size * 0.54,
                color: c,
              ),
            ),
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
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.enter,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? scheme.primary
            : const Color(0xFF0F1015).withValues(alpha: 0.65),
        border: Border.all(
          color: Colors.white,
          width: 1.5,
        ),
      ),
      child: AnimatedSwitcher(
        duration: Motion.fast,
        switchInCurve: Motion.spring,
        switchOutCurve: Motion.exit,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: Tween<double>(begin: 0.55, end: 1.0).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                key: const ValueKey('kselect-checked'),
                size: size * 0.64,
                color: Colors.white,
              )
            : const SizedBox.shrink(key: ValueKey('kselect-empty')),
      ),
    );
  }
}

// ============================ 5. 统一书目网格与列表排版度量 ============================

/// 游戏库与探索页共用的标准工具栏搜索框宽度（保证切页时工具栏节奏完全一致）。
const double kCatalogSearchWidth = 300;

/// 游戏库与探索页共用的网格/列表间距（16px）。
const double kCatalogGridSpacing = Gap.lg;

/// 游戏库与探索页共用的大封面卡片内边距（6px）。
const EdgeInsets kCatalogCardPadding = EdgeInsets.all(6);

/// 游戏库与探索页共用的卡片标题区固定高度（两行 13.5px 标题）。
const double kCatalogCardTitleHeight = 36;

/// 游戏库与探索页共用的卡片底部元数据区总高度（间距 + 两行标题 + 副信息行）。
const double kCatalogCardMetaHeight = 63;

/// 构建游戏库与探索页统一的 2:3 大封面网格 Delegate：
/// 封面严格按内容宽度保持 2:3 比例，再加上内边距与底部文字区高度反推单元格宽高比。
SliverGridDelegateWithFixedCrossAxisCount buildCatalogGridDelegate(
  double maxWidth, {
  double coverAspect = 2 / 3,
}) {
  final count = (maxWidth / 184).floor().clamp(2, 8);
  final cellW = (maxWidth - kCatalogGridSpacing * (count - 1)) / count;
  final coverW = cellW - kCatalogCardPadding.horizontal;
  final cellH = coverW / coverAspect +
      kCatalogCardPadding.vertical +
      kCatalogCardMetaHeight;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    mainAxisSpacing: kCatalogGridSpacing,
    crossAxisSpacing: kCatalogGridSpacing,
    childAspectRatio: cellW / cellH,
  );
}

/// 构建游戏库与探索页统一的紧凑列表 Delegate（固定行高 88px，自适应多列）。
SliverGridDelegateWithFixedCrossAxisCount buildCatalogListDelegate(
  double maxWidth,
) {
  const tileW = 320.0;
  final cols = (maxWidth / tileW).floor().clamp(1, 6);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: cols,
    mainAxisSpacing: kCatalogGridSpacing,
    crossAxisSpacing: kCatalogGridSpacing,
    mainAxisExtent: 88,
  );
}
