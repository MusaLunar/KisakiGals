/// 设计 token 与交互动效组件。
///
/// 风格取向：ChronoTide 式的**精致**（硬阴影常态 → hover 柔光、
/// 微上浮与微缩放、按压回弹、极细描边）+ ReinaManager 式的**简约**
/// （4px 间距基线、低饱和配色、次要信息弱化、克制的圆角与留白）。
library;

import 'package:flutter/material.dart';

// ============================ 尺度 ============================

/// 4px 基线的间距阶梯。
class Gap {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const huge = 40.0;

  static const page = EdgeInsets.fromLTRB(26, 10, 26, 0);
  static const cardPadding = EdgeInsets.all(18);
  static const cardPaddingDense = EdgeInsets.all(12);

  /// 页面横向留白 / 纵向留白（页面与卡片的统一节奏）
  static const pageH = 24.0;
  static const pageV = 14.0;

  /// 分区之间的间距（比卡片内间距大一档，用于拉开层次）
  static const section = 20.0;
}

/// 圆角阶梯。
class Radii {
  /// 缩略图/小徽标（封面小图、图标底）
  static const thumb = 8.0;
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const xxl = 28.0;

  static BorderRadius get chip => BorderRadius.circular(xs);
  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get sheet => BorderRadius.circular(xl);
}

/// 阴影与描边：常态硬阴影、hover 柔光、浮层重投影。
class Elev {
  /// 静置：零模糊位移投影（贴上纸片的感觉）。
  /// 用中性黑而非主色：主色投影在浅色底上几乎看不见，会显得"卡片是扁平的"。
  static List<BoxShadow> card(bool dark, Color outline) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.45 : 0.075),
          offset: const Offset(2, 3),
          blurRadius: 0,
        ),
      ];

  /// hover：柔和光晕（与静置的硬阴影形成对比，"精致感"的关键）
  static List<BoxShadow> cardHover(bool dark, Color outline) => [
        BoxShadow(
          color: dark
              ? Colors.black.withValues(alpha: 0.55)
              : outline.withValues(alpha: 0.26),
          offset: const Offset(2, 8),
          blurRadius: 18,
        ),
      ];

  /// 浮层（菜单/对话框）
  static List<BoxShadow> overlay(bool dark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];

  /// 卡片描边：低对比、极细
  static Color border(bool dark) => dark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.055);
}

/// 动效：统一时长与曲线。
class Motion {
  /// 按压反馈
  static const press = Duration(milliseconds: 90);

  /// 微交互（hover、图标切换）
  static const fast = Duration(milliseconds: 150);

  /// 常规（卡片状态、展开收起）
  static const normal = Duration(milliseconds: 200);

  /// 页面/浮层进场
  static const page = Duration(milliseconds: 250);

  /// 出场（比进场略快）
  static const out = Duration(milliseconds: 200);

  /// 内容进入（列表错落、换图）
  static const slow = Duration(milliseconds: 300);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const standard = Curves.easeInOutCubic;
  static const emphasized = Curves.easeOutQuint;

  // 位移/缩放量（ChronoTide 量级）
  static const hoverLift = -3.0;
  static const hoverScale = 1.015;
  static const pressScale = 0.975;
  static const dialogScaleFrom = 0.94;

  static const barrier = Color(0x66000000);
}

/// 排版阶梯（以 13.5 正文为基准，靠字重与字号双维度区分层级）。
class Type {
  static const display = TextStyle(
      fontSize: 25,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      height: 1.25);
  static const title = TextStyle(
      fontSize: 17.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.3);
  static const section = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      height: 1.3);
  static const body = TextStyle(fontSize: 13.5, height: 1.55);
  static const label = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);

  /// 表单行标签（设置项/编辑项的行标题）
  static const formLabel =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35);
  static const caption = TextStyle(fontSize: 11.5, height: 1.4);
  static const micro = TextStyle(fontSize: 10.5, height: 1.3);

  /// 时长/计数等需要对齐的数字
  static const numeric = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      fontFeatures: [FontFeature.tabularFigures()]);
}

// ============================ 交互动效 ============================

/// 可交互容器：hover 时上浮 + 轻微放大 + 阴影由硬变柔，按压时回缩。
/// 这是把界面做"精致"的核心组件，卡片/列表项/按钮都可复用。
class InteractiveSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final BorderRadius borderRadius;
  final Color color;
  final Color outline;
  final EdgeInsets padding;
  final bool elevated;
  final double lift;
  final double hoverScale;
  final double pressScale;
  final bool borderOnIdle;
  final Offset? secondaryTapPosition;
  final void Function(Offset position)? onSecondaryTapAt;

  const InteractiveSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapAt,
    this.secondaryTapPosition,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.lg)),
    required this.color,
    required this.outline,
    this.padding = Gap.cardPadding,
    this.elevated = true,
    this.lift = Motion.hoverLift,
    this.hoverScale = Motion.hoverScale,
    this.pressScale = Motion.pressScale,
    this.borderOnIdle = true,
  });

  @override
  State<InteractiveSurface> createState() => _InteractiveSurfaceState();
}

class _InteractiveSurfaceState extends State<InteractiveSurface> {
  bool _hover = false;
  bool _pressed = false;

  bool get _interactive =>
      widget.onTap != null || widget.onSecondaryTapAt != null;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hovered = _hover && _interactive;

    final scale = _pressed
        ? widget.pressScale
        : (hovered ? widget.hoverScale : 1.0);
    final dy = _pressed ? 0.0 : (hovered ? widget.lift : 0.0);

    return MouseRegion(
      cursor: _interactive
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel:
            _interactive ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapAt == null
            ? null
            : (d) => widget.onSecondaryTapAt!(d.globalPosition),
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          transform: Matrix4.identity()
            ..translateByDouble(0, dy, 0, 1)
            ..scaleByDouble(scale, scale, 1, 1),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: hovered
                  ? widget.outline.withValues(alpha: dark ? 0.45 : 0.35)
                  : (widget.borderOnIdle
                      ? Elev.border(dark)
                      : Colors.transparent),
              width: 1,
            ),
            boxShadow: widget.elevated
                ? (hovered
                    ? Elev.cardHover(dark, widget.outline)
                    : Elev.card(dark, widget.outline))
                : null,
          ),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}

/// 按压回弹（用于图标按钮、chip 等小元素）。
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.9,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp:
          widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: Motion.press,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}

// ============================ 转场与内容动画 ============================

/// 页面转场：淡入 + 轻微上移（比默认横向滑动安静，适合桌面应用）。
class FadeThroughRoute<T> extends PageRouteBuilder<T> {
  FadeThroughRoute.builder({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: Motion.page,
          reverseTransitionDuration: Motion.out,
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: _transitions,
        );
}

Widget _transitions(BuildContext context, Animation<double> animation,
    Animation<double> _, Widget child) {
  final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.012), end: Offset.zero)
          .animate(curved),
      child: child,
    ),
  );
}

/// 列表项进入：依次淡入上移（首屏错落出现）。
class StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int index;
  final int maxStagger;

  const StaggeredFadeIn({
    super.key,
    required this.child,
    this.index = 0,
    this.maxStagger = 12,
  });

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: widget.index.clamp(0, widget.maxStagger) * 16);
    Future.delayed(delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: Motion.slow,
      curve: Motion.enter,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.03),
        duration: Motion.slow,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}

/// 数字/文本变化时的平滑切换（时长、计数）。
class AnimatedCount extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const AnimatedCount({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.normal,
      switchInCurve: Motion.enter,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                  .animate(animation),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}

/// 内容切换（Tab/模式切换）：淡入 + 轻微上移。
class FadeThroughSwitcher extends StatelessWidget {
  final Widget child;
  const FadeThroughSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.normal,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween(begin: const Offset(0, 0.015), end: Offset.zero)
                  .animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 统一的对话框：进场 250ms（缩放 0.94→1 + 淡入）、退场 200ms，
/// 与 ReinaManager 的"大圆角 + 轻描边"外观配合（圆角由 dialogTheme 控制）。
Future<T?> showKisakiDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Motion.barrier,
    transitionDuration: Motion.page,
    pageBuilder: (context, _, __) => builder(context),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: Motion.dialogScaleFrom, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}