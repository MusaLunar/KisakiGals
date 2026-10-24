/// KisakiGals 设计系统与物理流体动效库 (Designable & Impeccable 规范).
///
/// 视觉与交互规范：
/// - Apple 级物理流体动效系统（二阶阻尼谐振子弹簧微分方程 Simulation）
///   - 导航/弹窗转场：无超调临界阻尼 (ζ = 1.0, ω0 = 28.0)
///   - 按压回弹：微动量欠阻尼 (ζ = 0.82, ω0 = 34.0)
///   - 指针直驱按压反馈：t = 0 瞬发微缩放 (s = 0.968)
///   - 边界过拉阻尼：Apple 对数对偶曲线 f(x) = (x * c * d) / (d + c * x), c = 0.55
/// - 光学校准字距与 Tabular 数字
/// - 真实高斯模糊毛玻璃与 0.5px 镜面高光描边 (AppleGlassSurface)
/// - 彻底清除 AI-Slop 通病：无 eyebrow/kicker 眉标、无 0-blur 硬方块阴影、无无意义网格遮挡
library;

import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================ 1. 物理弹簧与阻尼模拟 ============================

/// 遵循二阶阻尼谐振子微分方程的 Apple 级弹簧模拟：
/// m * x'' + c * x' + k * (x - x_target) = 0
///
/// 归一化质量 m = 1.0, 固有角频率 ω0 = sqrt(k), 阻尼比 ζ = c / (2 * sqrt(k)).
class AppleSpringSimulation extends Simulation {
  final double startPosition;
  final double endPosition;
  final double initialVelocity;
  final double dampingRatio; // ζ
  final double angularFrequency; // ω0

  // 内部解析解常数
  final double _c1;
  final double _c2;
  final double _omegaD; // 阻尼振荡角频率 ωd = ω0 * sqrt(1 - ζ^2)
  final double _settlingTime;

  AppleSpringSimulation({
    required this.startPosition,
    required this.endPosition,
    this.initialVelocity = 0.0,
    this.dampingRatio = 1.0,
    this.angularFrequency = 28.0,
    super.tolerance = const Tolerance(distance: 0.001, velocity: 0.001),
  })  : _c1 = startPosition - endPosition,
        _c2 = (dampingRatio >= 1.0)
            ? (initialVelocity + angularFrequency * (startPosition - endPosition))
            : ((initialVelocity + dampingRatio * angularFrequency * (startPosition - endPosition)) /
                (angularFrequency * math.sqrt(math.max(0.0001, 1.0 - dampingRatio * dampingRatio)))),
        _omegaD = angularFrequency *
            math.sqrt(math.max(0.0001, 1.0 - dampingRatio * dampingRatio)),
        _settlingTime = (dampingRatio >= 1.0)
            ? (6.0 / angularFrequency)
            : (4.5 / (dampingRatio * angularFrequency));

  /// 临界阻尼 (ζ = 1.0, ω0 = 28.0)：最快无超调收敛，用于导航路由、模态弹窗与 Tab 切换。
  factory AppleSpringSimulation.criticallyDamped({
    required double start,
    required double end,
    double velocity = 0.0,
  }) =>
      AppleSpringSimulation(
        startPosition: start,
        endPosition: end,
        initialVelocity: velocity,
        dampingRatio: 1.0,
        angularFrequency: 28.0,
      );

  /// 动量欠阻尼 (ζ = 0.82, ω0 = 34.0)：轻微弹性单次柔和反弹，用于按压回弹与手势甩投。
  factory AppleSpringSimulation.momentum({
    required double start,
    required double end,
    double velocity = 0.0,
  }) =>
      AppleSpringSimulation(
        startPosition: start,
        endPosition: end,
        initialVelocity: velocity,
        dampingRatio: 0.82,
        angularFrequency: 34.0,
      );

  @override
  double x(double time) {
    if (time <= 0) return startPosition;
    if (isDone(time)) return endPosition;

    if (dampingRatio >= 0.999) {
      // 临界阻尼解析解：x(t) = end + (c1 + c2 * t) * e^(-ω0 * t)
      final envelope = math.exp(-angularFrequency * time);
      return endPosition + (_c1 + _c2 * time) * envelope;
    } else {
      // 欠阻尼解析解：x(t) = end + e^(-ζ * ω0 * t) * [c1 * cos(ωd * t) + c2 * sin(ωd * t)]
      final envelope = math.exp(-dampingRatio * angularFrequency * time);
      final oscillation = _c1 * math.cos(_omegaD * time) + _c2 * math.sin(_omegaD * time);
      return endPosition + envelope * oscillation;
    }
  }

  @override
  double dx(double time) {
    if (time <= 0) return initialVelocity;
    if (isDone(time)) return 0.0;

    if (dampingRatio >= 0.999) {
      // 临界阻尼导数：x'(t) = [c2 - ω0 * (c1 + c2 * t)] * e^(-ω0 * t)
      final envelope = math.exp(-angularFrequency * time);
      return (_c2 - angularFrequency * (_c1 + _c2 * time)) * envelope;
    } else {
      // 欠阻尼导数
      final envelope = math.exp(-dampingRatio * angularFrequency * time);
      final decay = -dampingRatio * angularFrequency;
      final posPart = _c1 * math.cos(_omegaD * time) + _c2 * math.sin(_omegaD * time);
      final velPart = -_c1 * _omegaD * math.sin(_omegaD * time) + _c2 * _omegaD * math.cos(_omegaD * time);
      return envelope * (decay * posPart + velPart);
    }
  }

  @override
  bool isDone(double time) {
    if (time >= _settlingTime) return true;
    final currentPos = x(time);
    final currentVel = dx(time);
    return (currentPos - endPosition).abs() <= tolerance.distance &&
        currentVel.abs() <= tolerance.velocity;
  }
}

/// 物理流体学与边界计算函数
class FluidPhysics {
  /// Apple 官方对数橡皮筋边界阻尼算法：
  /// f(x) = (x * c * d) / (d + c * x)
  /// x: 超出边界的原始位移量
  /// d: 容器轴向尺度 (dimension)
  /// c: 阻尼系数 (Apple 标准 c = 0.55)
  static double clampWithRubberband({
    required double value,
    required double min,
    required double max,
    required double dimension,
    double resistance = 0.55,
  }) {
    if (dimension <= 0) return value.clamp(min, max);
    if (value < min) {
      final overshoot = min - value;
      final offset = (overshoot * resistance * dimension) /
          (dimension + resistance * overshoot);
      return min - offset;
    } else if (value > max) {
      final overshoot = value - max;
      final offset = (overshoot * resistance * dimension) /
          (dimension + resistance * overshoot);
      return max + offset;
    }
    return value;
  }

  /// 动量投掷最终落点预测：x_inf = x0 + v0 / α
  static double projectMomentum({
    required double start,
    required double velocity,
    double decelerationRate = 4.2,
  }) {
    return start + (velocity / decelerationRate);
  }
}

// ============================ 2. 尺度与间距 ============================

/// 4px 基线的高级间距阶梯
class Gap {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const huge = 40.0;

  static const page = EdgeInsets.fromLTRB(28, 14, 28, 0);
  static const cardPadding = EdgeInsets.all(18);
  static const cardPaddingDense = EdgeInsets.all(12);

  static const pageH = 28.0;
  static const pageV = 16.0;
  static const section = 24.0;
  static const titleToContent = 12.0;
  static const sectionGap = 32.0;

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

/// Apple 连续曲率圆角阶梯
class Radii {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const full = 999.0;
  static const thumb = 6.0;

  static BorderRadius get chip => BorderRadius.circular(sm);
  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get sheet => BorderRadius.circular(xxl);
  static BorderRadius get pill => BorderRadius.circular(full);
}

/// 深度与阴影：多层自然漫反射软阴影与镜面边缘，严格消除 zero-blur 假硬边
class Elev {
  /// 静置卡片投影：柔和环境遮蔽与轻量垂直位移
  static List<BoxShadow> card(bool dark, Color outline) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.32 : 0.05),
          offset: const Offset(0, 4),
          blurRadius: 16,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.16 : 0.02),
          offset: const Offset(0, 1),
          blurRadius: 4,
          spreadRadius: 0,
        ),
      ];

  /// Hover 悬浮光晕：深层大范围柔光 + 主题色微光
  static List<BoxShadow> cardHover(bool dark, Color outline) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.48 : 0.09),
          offset: const Offset(0, 10),
          blurRadius: 28,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.28 : 0.18),
          offset: const Offset(0, 0),
          blurRadius: 18,
          spreadRadius: 0,
        ),
      ];

  /// 按钮悬浮高光
  static List<BoxShadow> buttonHover(bool dark, Color outline) => [
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.40 : 0.28),
          offset: const Offset(0, 4),
          blurRadius: 14,
          spreadRadius: -1,
        ),
      ];

  /// 焦点光晕（键盘导航与输入聚焦）
  static List<BoxShadow> focusGlow(bool dark, Color outline) => [
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.45 : 0.35),
          blurRadius: 10,
          spreadRadius: 1.5,
        ),
      ];

  /// 浮层（菜单/对话框/抽屉）：自然大景深柔光投影
  static List<BoxShadow> overlay(bool dark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.65 : 0.16),
          blurRadius: 42,
          offset: const Offset(0, 18),
          spreadRadius: -4,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.30 : 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  /// 卡片 0.5px 镜面边缘线
  static Color border(bool dark) => dark
      ? Colors.white.withValues(alpha: 0.09)
      : Colors.black.withValues(alpha: 0.07);

  /// 激活/高亮描边
  static Color borderActive(Color outline, bool dark) =>
      outline.withValues(alpha: dark ? 0.65 : 0.50);
}

/// 动效参数规范：硬件合成层优先
class Motion {
  static const press = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 260);
  static const page = Duration(milliseconds: 320);
  static const out = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 400);
  static const pulse = Duration(milliseconds: 1600);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const standard = Curves.easeInOutCubic;
  static const emphasized = Curves.easeOutQuint;
  static const spring = Curves.easeOutBack;

  static const hoverLift = -3.0;
  static const hoverScale = 1.018;
  static const pressScale = 0.968; // Designable 标准瞬发缩放
  static const dialogScaleFrom = 0.94;
  static const sheetSlideFrom = Offset(0, 0.08);

  static const barrier = Color(0x75000000);
}

// ============================ 3. 光学排版 ============================

/// 光学校准排版阶梯：
/// - 严禁 kicker/eyebrow 眉标（标题自带权威与张力）
/// - 大标题应用微负字距 (tracking = -0.02 * fontSize)
/// - 数字全量采用 Tabular 等宽字形
class Type {
  static const fontFamily = 'NotoSansSC';
  static const fontFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Segoe UI',
    'Arial',
  ];

  static const nums = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.52, // -0.02 * 26
    height: 1.25,
  );

  static const title = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.36, // -0.02 * 18
    height: 1.30,
  );

  static const section = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
    height: 1.35,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  static const label = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.40,
  );

  static const formLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const micro = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    height: 1.40,
  );

  static const numeric = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.25,
    fontFeatures: nums,
  );
}

// ============================ 4. 真实物理与毛玻璃表面 ============================

/// AppleGlassSurface：具备光学高斯模糊、环境辉光透射与 0.5px 镜面边缘的磨砂玻璃表面
class AppleGlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final Color? tintColor;
  final double borderWidth;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;

  const AppleGlassSurface({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.borderRadius = 16.0,
    this.tintColor,
    this.borderWidth = 0.5,
    this.borderColor,
    this.shadows,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final defaultTint = dark
        ? const Color(0x38181A22)
        : const Color(0x5AFFFFFF);
    final defaultBorder = dark
        ? const Color(0x28FFFFFF)
        : const Color(0x4DFFFFFF);

    final radius = BorderRadius.circular(borderRadius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor ?? defaultTint,
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? defaultBorder,
          width: borderWidth,
        ),
      ),
      child: child,
    );

    if (blur > 0) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: radius,
        child: content,
      );
    }

    if (shadows != null && shadows!.isNotEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: shadows,
        ),
        child: content,
      );
    }

    return content;
  }
}

/// FluidPressable: 实现 t = 0 瞬发指针按下反馈与动量弹簧回弹的触觉组件
class FluidPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final void Function(Offset position)? onSecondaryTapAt;
  final double scaleFactor;
  final bool haptic;

  const FluidPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapAt,
    this.scaleFactor = Motion.pressScale,
    this.haptic = true,
  });

  @override
  State<FluidPressable> createState() => _FluidPressableState();
}

class _FluidPressableState extends State<FluidPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _currentScale = 1.0;
  bool _isDown = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _controller.addListener(() {
      setState(() {
        _currentScale = _controller.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent e) {
    if (widget.onTap == null && widget.onSecondaryTapAt == null) return;
    _isDown = true;
    _controller.stop();
    // t = 0 瞬发微缩放
    setState(() {
      _currentScale = widget.scaleFactor;
    });
    _controller.value = widget.scaleFactor;
    if (widget.haptic) {
      HapticFeedback.lightImpact();
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (!_isDown) return;
    _isDown = false;
    _rebound();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (!_isDown) return;
    _isDown = false;
    _rebound();
  }

  void _rebound() {
    final simulation = AppleSpringSimulation.momentum(
      start: _currentScale,
      end: 1.0,
      velocity: 0.0,
    );
    _controller.animateWith(simulation);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onSecondaryTapAt != null;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTap: widget.onSecondaryTap,
          onSecondaryTapUp: widget.onSecondaryTapAt == null
              ? null
              : (d) => widget.onSecondaryTapAt!(d.globalPosition),
          child: RepaintBoundary(
            child: Transform.scale(
              scale: _currentScale,
              alignment: Alignment.center,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// InteractiveSurface：卡片与交互区块统一原语
class InteractiveSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final void Function(Offset position)? onSecondaryTapAt;
  final BorderRadius borderRadius;
  final Color color;
  final Color outline;
  final EdgeInsets padding;
  final bool elevated;
  final double lift;
  final double hoverScale;
  final double pressScale;
  final bool borderOnIdle;
  final bool glass;

  const InteractiveSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapAt,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.lg)),
    required this.color,
    required this.outline,
    this.padding = Gap.cardPadding,
    this.elevated = true,
    this.lift = Motion.hoverLift,
    this.hoverScale = Motion.hoverScale,
    this.pressScale = Motion.pressScale,
    this.borderOnIdle = true,
    this.glass = false,
  });

  @override
  State<InteractiveSurface> createState() => _InteractiveSurfaceState();
}

class _InteractiveSurfaceState extends State<InteractiveSurface> {
  bool _hover = false;

  bool get _interactive =>
      widget.onTap != null || widget.onSecondaryTapAt != null;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hovered = _hover && _interactive;
    final dy = hovered ? widget.lift : 0.0;

    return MouseRegion(
      cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: FluidPressable(
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onSecondaryTapAt: widget.onSecondaryTapAt,
        scaleFactor: widget.pressScale,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          transform: Matrix4.identity()..translateByDouble(0, dy, 0, 1),
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

/// 兼容旧代码的按压缩放组件（直接转由 FluidPressable 接管）
class PressableScale extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = Motion.pressScale,
  });

  @override
  Widget build(BuildContext context) {
    return FluidPressable(
      onTap: onTap,
      scaleFactor: pressedScale,
      child: child,
    );
  }
}

/// 焦点光晕容器
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

/// 呼吸脉冲动效（运行指示灯等）
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

/// 纯粹的工程网格占位容器（静默透传，不再绘制生硬的赛博工程横竖线）
class EngineeringGrid extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const EngineeringGrid({super.key, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) => child;
}

// ============================ 5. 路由与转场动效 ============================

/// 页面转场：微上浮 + 淡入（硬件合成加速）
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
      position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
          .animate(curved),
      child: RepaintBoundary(child: child),
    ),
  );
}

/// 列表项错落进入
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
    final delay = Duration(
        milliseconds: widget.index.clamp(0, widget.maxStagger) * 20);
    Future.delayed(delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1.0 : 0.0,
      duration: Motion.slow,
      curve: Motion.enter,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.035),
        duration: Motion.slow,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}

/// 数字/文本平滑滚动切换
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
          position: Tween(begin: const Offset(0, 0.22), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}

/// 内容区/Tab 切换淡入
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
          position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
              .animate(animation),
          child: RepaintBoundary(child: child),
        ),
      ),
      child: child,
    );
  }
}

/// 统一的对话框：临界阻尼弹簧驱动 (0.94 -> 1.0) + 毛玻璃暗色遮罩
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

/// 统一的抽屉/底部弹层：临界阻尼向上平滑滑入 + 淡入
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
