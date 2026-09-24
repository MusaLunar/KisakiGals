/// KisakiGals UI 组件库（Kit）。
///
/// 全应用**只使用这里的原语**构建界面，页面里不再出现裸 Container +
/// 手写 BoxDecoration。风格取向：
/// - 简约（参考 ReinaManager）：大圆角、近明度两级底色、1px 低对比描边、
///   去渐变、4/8px 栅格、次要信息弱化。
/// - 精致（参考 ChronoTide）：常态硬阴影 → hover 柔光、微上浮与微缩放、
///   按压回弹、克制的动效时长。
library;

import 'package:flutter/material.dart';

import 'design.dart';
import 'theme.dart';
import 'widgets/common.dart' show CoverImage, cachedFileExists, GlassPanel;

// ============================ 页面骨架 ============================

/// 页面骨架：统一标题区（大标题 + 副标题 + 右侧操作）+ 内容留白。
class KPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;

  /// 标题左侧图标（页面语义标识）
  final IconData? leadingIcon;
  final List<Widget> actions;
  final Widget child;
  final bool scrollable;

  /// 内容最大宽度（超宽屏下避免元素被拉得过稀；null = 自适应全宽）
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: scheme.primary.withValues(alpha: 0.11),
                  ),
                  child: Icon(leadingIcon, size: 20, color: scheme.primary),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Type.display),
                    if (subtitleWidget != null) ...
                      [const SizedBox(height: 3), subtitleWidget!]
                    else if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          style: Type.caption
                              .copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              // 超宽屏下限制内容宽度，避免元素被拉得过稀（评审：>1600px 时
              // Hero 数据带跟着窗口一起变宽，观感松散）
              constraints: BoxConstraints(
                  maxWidth: maxContentWidth ?? double.infinity),
              child: scrollable
                  ? Scrollbar(
                      // 桌面端默认滚动条只在滚动时出现；这里常驻显示，避免
                      // 「内容被裁但看不出还能滚」的观感问题
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        primary: true,
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        child: child,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                      child: child,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 分区标题的固定槽位：并排两列时保证标题行等高（否则卡片顶边会错位）。
class KSectionSlot extends StatelessWidget {
  final Widget? child;
  const KSectionSlot({super.key, this.child});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 38, child: Center(child: child ?? const SizedBox.shrink()));
}

/// 分区标题（用于页面内的分组）。
class KSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  /// 是否预留 38 高的右侧槽位（并排/无动作的区块也放空槽位，
  /// 使各区块标题行等高、节奏一致）
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
        children: [
          Text(text, style: Type.section),
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

// ============================ 卡片 ============================

/// 全应用唯一的卡片原语。
class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final bool glass;
  final bool dense;
  final Color? color;

  /// 浮层阴影（菜单/浮动操作栏用）；为 true 时改用 Elev.overlay
  final bool overlayShadow;

  /// 扁平卡：只描边、不投影（用于卡内再嵌卡片，避免硬阴影叠加显脏）
  final bool flat;

  /// 自定义描边色（语义化浮层，例如错误通知卡）
  final Color? borderColor;

  /// 右键菜单（避免外部再包一层 GestureDetector）
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
      final panel = GlassPanel(
        borderRadius: borderRadius,
        padding: pad,
        tint: color,
        child: child,
      );
      // 毛玻璃卡也要能点（GlassPanel 本身没有点击能力）
      return onTap == null
          ? panel
          : GestureDetector(
              behavior: HitTestBehavior.opaque, onTap: onTap, child: panel);
    }
    final shadows = flat
        ? const <BoxShadow>[]
        : (overlayShadow
            ? Elev.overlay(dark)
            : Elev.card(dark, scheme.primary));
    final body = onTap != null
        ? InteractiveSurface(
            onTap: onTap,
            borderRadius: borderRadius,
            color: fill,
            outline: scheme.primary,
            padding: pad,
            // 浮层/扁平模式下不再叠加硬阴影，避免双层投影
            elevated: !overlayShadow && !flat,
            child: child,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor ?? Elev.border(dark)),
              boxShadow: shadows,
            ),
            child: Padding(padding: pad, child: child),
          );
    if (onSecondaryTapAt == null) return body;
    return GestureDetector(
      onSecondaryTapUp: (d) => onSecondaryTapAt!(d.globalPosition),
      child: body,
    );
  }
}

/// 统计块：图标 + 标签 + 数值 + 说明（主页/详情页共用）。
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
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withValues(alpha: dark ? 0.20 : 0.12),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 3),
                AnimatedCount(
                  text: value,
                  style: Type.numeric.copyWith(
                      color: dark ? KisakiColors.nightInk : KisakiColors.ink),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.micro
                          .copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ 控件 ============================

/// 工具栏：页面顶部一排操作（搜索、筛选、视图切换、主操作）。
class KToolbar extends StatelessWidget {
  final List<Widget> children;
  const KToolbar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: children),
    );
  }
}

/// 图标按钮：hover 淡底 + 按压回弹 + 选中态。
class KIconAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  /// 置灰但保留位置（例如未选中任何项时的批量操作）
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: PressableScale(
          onTap: widget.onTap,
          pressedScale: 0.92,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            width: 38,
            height: 38,
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              color: widget.active
                  ? scheme.primary.withValues(alpha: dark ? 0.24 : 0.14)
                  : (_hover
                      ? (dark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.04))
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: widget.active
                    ? scheme.primary.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Icon(widget.icon,
                size: 19,
                color: !widget.enabled
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
                    : (widget.active
                        ? scheme.primary
                        : scheme.onSurfaceVariant)),
          ),
        ),
      ),
    );
  }
}

/// 标签（筛选/状态）：选中为主色淡底 + 主色描边。
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
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.selected
                ? color.withValues(alpha: dark ? 0.24 : 0.13)
                : (_hover
                    ? (dark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.05)
                    : Colors.transparent),
            borderRadius: Radii.chip,
            border: Border.all(
              color: widget.selected
                  ? color.withValues(alpha: 0.55)
                  : Elev.border(dark),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[
              Icon(widget.icon,
                  size: 12,
                  color: widget.selected ? color : scheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              widget.label,
              style: Type.caption.copyWith(
                color: widget.selected ? color : scheme.onSurfaceVariant,
                fontWeight:
                    widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 主按钮（药丸）：统一高度与内边距。
class KPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;

  const KPill({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(label),
          ]);
    return filled
        ? FilledButton(onPressed: onTap, child: child)
        : OutlinedButton(onPressed: onTap, child: child);
  }
}

/// 空状态。
class KEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;

  /// 紧凑变体：用于卡片内部（图标圈与间距更小）
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 40 : 58,
            height: compact ? 40 : 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.10),
            ),
            child: Icon(icon,
                size: compact ? 19 : 26,
                color: scheme.primary.withValues(alpha: 0.8)),
          ),
          SizedBox(height: compact ? 9 : 14),
          Text(title, style: compact ? Type.label : Type.section),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style:
                    Type.caption.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            KPill(label: actionLabel!, icon: actionIcon, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

/// 加载指示（统一尺寸与线宽）。
class KLoading extends StatelessWidget {
  final double size;
  const KLoading({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
}

/// 骨架占位块（加载态用，避免各页手写裸 Container + BoxDecoration）。
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

/// 骨架文本行（末行按比例缩短，视觉上更像真实段落）。
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

/// 小徽标（来源/状态/计数）。
class KBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const KBadge({super.key, required this.text, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 3),
        ],
        Text(text,
            style: Type.micro
                .copyWith(color: c, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// 列表行：左内容 + 右尾部（设置项、资源结果等复用）。
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
    // 用透明 Material 承载水波纹：否则反馈会被 KCard 的不透明底色遮住
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.body),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.caption
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
      ),
    );
  }
}

/// 封面缩略图（左封面右文字的行式条目，游戏库紧凑列表与搜索结果共用）。
class KMediaRow extends StatelessWidget {
  final String coverPath;

  /// 网络封面（本地无封面时使用，例如搜刮预览/推荐结果）
  final String? coverUrl;
  final String title;
  final String? subtitle;
  final double coverWidth;
  final bool selected;
  final bool nsfw;

  /// 徽章换行间距（徽章较多时避免挤在一起）
  final double badgeRunSpacing;

  /// 标题区高度（默认 34，容纳两行标题）
  final double titleHeight;

  /// 右侧时间文本（等宽数字 + 固定宽度右对齐，用于时间线类列表）
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
    return GestureDetector(
      onSecondaryTapUp: onSecondaryTapAt == null
          ? null
          : (d) => onSecondaryTapAt!(d.globalPosition),
      child: InteractiveSurface(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        borderRadius: BorderRadius.circular(Radii.lg),
        // 选中态用不透明底色（半透明会在卡片上显得发灰）
        color: selected
            ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.10),
                dark ? KisakiColors.nightCard : Colors.white)
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
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                // 顶对齐：一行/两行标题的行基线保持一致
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: titleHeight,
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.body.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: dark
                                ? KisakiColors.nightInk
                                : KisakiColors.ink)),
                  ),
                  const SizedBox(height: 2),
                  if (badges.isNotEmpty)
                    Wrap(spacing: 5, runSpacing: badgeRunSpacing, children: badges)
                  else if (subtitle != null)
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.caption
                            .copyWith(color: scheme.onSurfaceVariant)),
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
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 封面图存在性检查（供页面复用，避免各页自行 stat）。
bool coverExists(String path) => cachedFileExists(path);

// ============================ 封面之上的浮层元素 ============================
//
// 以下三个原语用于「压在封面图上的角标 / 按钮 / 勾选圈」：
// 它们必须自带遮罩或描边，否则在任意封面图上都会看不清。

/// 封面角标（状态、平台评分、游玩中等）。
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
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(text,
            style: Type.micro
                .copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// 封面上的圆形按钮（收藏、移除等）。
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
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: PressableScale(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: _hover ? 0.68 : 0.5),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(widget.icon, size: widget.size * 0.55, color: c),
          ),
        ),
      ),
    );
  }
}

/// 批量选择勾选圈（压在封面上）：未选中也有清晰描边。
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
            : Colors.black.withValues(alpha: 0.42),
        border: Border.all(color: Colors.white, width: 1.6),
      ),
      child: selected
          ? Icon(Icons.check_rounded,
              size: size * 0.62, color: Colors.white)
          : const SizedBox.shrink(),
    );
  }
}