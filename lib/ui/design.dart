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

  /// 间距节奏：区块标题 → 内容
  static const titleToContent = 12.0;

  /// 间距节奏：区块之间
  static const sectionGap = 28.0;

  // 常用对称内边距预设（基于 4px 阶梯，消除各页手写魔法数字）
  static const insetsHXs = EdgeInsets.symmetric(horizontal: xs);
  static const insetsHSm = EdgeInsets.symmetric(horizontal: sm);
  static const insetsHMd = EdgeInsets.symmetric(horizontal: md);
  static const insetsHLg = EdgeInsets.symmetric(horizontal: lg);
  static const insetsHXl = EdgeInsets.symmetric(horizontal: xl);
  static const insetsVXs = EdgeInsets.symmetric(vertical: xs);
  static const insetsVSm = EdgeInsets.symmetric(vertical: sm);
  static const insetsVMd = EdgeInsets.symmetric(vertical: md);
  static const insetsVLg = EdgeInsets.symmetric(vertical: lg);
  static const insetsAllXs = EdgeInsets.all(xs);
  static const insetsAllSm = EdgeInsets.all(sm);
  static const insetsAllMd = EdgeInsets.all(md);
  static const insetsAllLg = EdgeInsets.all(lg);
  static const insetsAllXl = EdgeInsets.all(xl);
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
  static const full = 999.0;

  static BorderRadius get chip => BorderRadius.circular(xs);
  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get sheet => BorderRadius.circular(xl);
  static BorderRadius get pill => BorderRadius.circular(full);
}

/// 阴影与描边：常态分层软阴影、hover 柔光辉光、浮层重投影。
class Elev {
  /// 静置卡片投影：双层自然软阴影，避免单层生硬，营造纸片悬浮呼吸感。
  static List<BoxShadow> card(bool dark, Color outline) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.32 : 0.045),
          offset: const Offset(0, 3),
          blurRadius: 8,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.18 : 0.02),
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  /// hover 柔光：双层深层投影 + 外圈主题色辉光（提取自 ChronoTide FocusGlow 与 Steam 现代卡片设计）。
  static List<BoxShadow> cardHover(bool dark, Color outline) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.45 : 0.09),
          offset: const Offset(0, 10),
          blurRadius: 22,
        ),
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.30 : 0.20),
          offset: const Offset(0, 1),
          blurRadius: 14,
          spreadRadius: 0.5,
        ),
      ];

  /// 按钮悬浮高光
  static List<BoxShadow> buttonHover(bool dark, Color outline) => [
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.36 : 0.24),
          offset: const Offset(0, 4),
          blurRadius: 12,
          spreadRadius: 0.2,
        ),
      ];

  /// 焦点光晕（键盘聚焦或选中文本框时外发光）
  static List<BoxShadow> focusGlow(bool dark, Color outline) => [
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.42 : 0.26),
          blurRadius: 10,
          spreadRadius: 1.2,
        ),
      ];

  /// 浮层（菜单/对话框/抽屉）：深沉柔和的大范围遮挡阴影
  static List<BoxShadow> overlay(bool dark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.55 : 0.14),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.25 : 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 卡片描边：低对比、极细
  static Color border(bool dark) => dark
      ? Colors.white.withValues(alpha: 0.085)
      : Colors.black.withValues(alpha: 0.06);

  /// 激活/高亮描边
  static Color borderActive(Color outline, bool dark) =>
      outline.withValues(alpha: dark ? 0.50 : 0.40);
}

/// 动效：统一时长与曲线（严格优先走硬件合成层 Composite）。
class Motion {
  /// 按压反馈
  static const press = Duration(milliseconds: 90);

  /// 微交互（hover、图标切换、微缩放）
  static const fast = Duration(milliseconds: 140);

  /// 常规（卡片状态、展开收起、抽屉滑动）
  static const normal = Duration(milliseconds: 220);

  /// 页面/浮层进场
  static const page = Duration(milliseconds: 260);

  /// 出场（比进场略快，减少等待感）
  static const out = Duration(milliseconds: 180);

  /// 内容进入（列表错落、换图）
  static const slow = Duration(milliseconds: 320);

  /// 呼吸脉冲时长（运行中状态灯）
  static const pulse = Duration(milliseconds: 1400);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const standard = Curves.easeInOutCubic;
  static const emphasized = Curves.easeOutQuint;
  static const spring = Curves.easeOutBack;

  // 位移/缩放量（微交互标准量级）
  static const hoverLift = -3.5;
  static const hoverScale = 1.018;
  static const pressScale = 0.975;
  static const dialogScaleFrom = 0.94;
  static const sheetSlideFrom = Offset(0, 0.08);

  static const barrier = Color(0x66000000);
}

/// 排版阶梯。
///
/// 中文排印要点（Windows 桌面）：
/// - **不要用负字距**：中文没有西文的"字侧空白"，负字距会挤在一起；
/// - **避免 w800/w900**：微软雅黑只有 Regular/Bold 两档，超过 w700 会走
///   合成加粗（笔画糊、边缘发虚），因此标题最高用 w700；
/// - 中文行高需要比西文更大（正文 1.6、标题 1.35），否则密排发闷；
/// - 数字统一用等宽字形（tabular），时长/计数在多行之间才能对齐。
class Type {
  /// 字体族：**内置思源黑体**（Source Han Sans / Noto Sans SC 同源设计，
  /// 简体子集），中英文与数字字形统一、字重齐备（400/500/700）。
  /// 回退链保证极端情况下（字体资源缺失）仍有可用字形。
  static const fontFamily = 'NotoSansSC';
  static const fontFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Segoe UI',
    'Arial',
  ];

  /// 数字等宽字形（时长、计数、日期）
  static const nums = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );
  static const title = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );
  static const section = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,fontSize: 13.5, height: 1.6);
  static const label =
      TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4);

  /// 表单行标签（设置项/编辑项的行标题）
  static const formLabel =
      TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,fontSize: 13, fontWeight: FontWeight.w600, height: 1.45);
  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,fontSize: 11.5, height: 1.5);
  static const micro = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,fontSize: 10.5, height: 1.4);

  /// 时长/计数：等宽数字 + 稍紧的行高
  static const numeric = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.25,
    fontFeatures: nums,
  );
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
                  ? Elev.borderActive(widget.outline, dark)
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
          child: RepaintBoundary(
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 按压回弹（用于图标按钮、chip 等小元素，严格走合成层与弹性曲线）。
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.92,
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
      child: RepaintBoundary(
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1.0,
          duration: Motion.press,
          curve: Motion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 焦点辉光容器（参考 ChronoTide FocusGlow / FocusBorder）：
/// 自动监听焦点状态，获得焦点时展示主题外发光与加粗描边。
class FocusGlow extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color? focusColor;
  final double borderWidth;
  final bool autofocus;

  const FocusGlow({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.md)),
    this.focusColor,
    this.borderWidth = 1.6,
    this.autofocus = false,
  });

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final activeColor = widget.focusColor ?? scheme.primary;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (has) {
        if (_focused != has) setState(() => _focused = has);
      },
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.enter,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _focused ? activeColor : Colors.transparent,
            width: widget.borderWidth,
          ),
          boxShadow: _focused ? Elev.focusGlow(dark, activeColor) : null,
        ),
        child: widget.child,
      ),
    );
  }
}

/// 呼吸/脉冲动效组件（运行态指示灯、活动徽标等）：
/// 在合成层上执行平滑循环淡入淡出与微缩放，杜绝频繁触发布局与重绘。
class PulsingGlow extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minOpacity;
  final double maxOpacity;
  final double minScale;
  final double maxScale;

  const PulsingGlow({
    super.key,
    required this.child,
    this.duration = Motion.pulse,
    this.minOpacity = 0.55,
    this.maxOpacity = 1.0,
    this.minScale = 0.95,
    this.maxScale = 1.05,
  });

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    final curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _opacity = Tween<double>(begin: widget.minOpacity, end: widget.maxOpacity)
        .animate(curve);
    _scale = Tween<double>(begin: widget.minScale, end: widget.maxScale)
        .animate(curve);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

// ============================ 转场与内容动画 ============================

/// 页面转场：淡入 + 轻微上移（比默认横向滑动安静，适合桌面应用，硬件合成加速）。
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
      child: RepaintBoundary(child: child),
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

/// 内容切换（Tab/模式切换）：淡入 + 轻微上移（硬件合成层隔离开销）。
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
          child: RepaintBoundary(child: child),
        ),
      ),
      child: child,
    );
  }
}

/// 统一的对话框：进场 260ms（缩放 0.94→1 + 淡入）、退场 180ms，
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
          child: RepaintBoundary(child: child),
        ),
      );
    },
  );
}

/// 统一的抽屉/底部弹层：进场 260ms（Slide 向上滑入 + 淡入）、退场 180ms，
/// 严格走硬件合成层（SlideTransition + FadeTransition + RepaintBoundary）。
Future<T?> showKisakiSheet<T>({
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
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        type: MaterialType.transparency,
        child: builder(context),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: Motion.sheetSlideFrom, end: Offset.zero)
              .animate(curved),
          child: RepaintBoundary(child: child),
        ),
      );
    },
  );
}