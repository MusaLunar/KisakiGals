/// KisakiGals 设计系统与物理流体动效引擎 (誌面 Shimen Edition).
///
/// 核心工程准则：
/// - 物理弹簧系统 (AppleSpringSimulation)：支持 (dampingRatio, response) 直观参数
///   转换 ω0 = 2π / response，并在中途打断时继承当前位置与速度 (velocity handoff)。
/// - 指数衰减动量投射 (FluidPhysics.project)：遵循 Apple WWDC 精确衰减公式
///   (v0 / 1000) * d / (1 - d) 与对数橡皮筋边界阻尼 c = 0.55。
/// - 指针直驱与 10px 迟滞回弹 (FluidPressable)：t = 0 瞬发响应，支持拖出 10px 边界外
///   平滑取消按压、拖回重新按压，以及中途打断速度继承。
/// - 光学字号排版 (Type)：大字号紧字距与紧行高、正文字号舒适行高、微字号正字距与等宽数字。
/// - 无障碍降级：自动感知 MediaQuery.disableAnimationsOf 与 highContrastOf。
library;

import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================ 1. 物理弹簧与流体力学 ============================

/// 二阶阻尼谐振子弹簧模拟：
/// m * x'' + c * x' + k * (x - x_target) = 0
///
/// 支持直接传入固有角频率 [angularFrequency] (ω0) 或通过 [AppleSpringSimulation.fromResponse]
/// 传入周期响应时间 `response` (秒，ω0 = 2π / response)。
class AppleSpringSimulation extends Simulation {
  final double startPosition;
  final double endPosition;
  final double initialVelocity;
  final double dampingRatio; // ζ
  final double angularFrequency; // ω0

  final double _c1;
  final double _c2;
  final double _omegaD;
  final double _settlingTime;

  AppleSpringSimulation({
    required this.startPosition,
    required this.endPosition,
    this.initialVelocity = 0.0,
    this.dampingRatio = 1.0,
    this.angularFrequency = 28.0,
    super.tolerance = const Tolerance(distance: 0.0008, velocity: 0.0008),
  })  : _c1 = startPosition - endPosition,
        _c2 = (dampingRatio >= 1.0)
            ? (initialVelocity + angularFrequency * (startPosition - endPosition))
            : ((initialVelocity +
                    dampingRatio *
                        angularFrequency *
                        (startPosition - endPosition)) /
                (angularFrequency *
                    math.sqrt(
                        math.max(0.0001, 1.0 - dampingRatio * dampingRatio)))),
        _omegaD = angularFrequency *
            math.sqrt(math.max(0.0001, 1.0 - dampingRatio * dampingRatio)),
        _settlingTime = (dampingRatio >= 1.0)
            ? (6.5 / angularFrequency)
            : (5.0 / ( math.max(0.15, dampingRatio) * angularFrequency));

  /// 使用设计师友好的 (dampingRatio, response) 参数构造弹簧：
  /// - `dampingRatio`: 阻尼比 ζ (1.0 为临界阻尼无超调，0.75~0.85 为轻柔单次弹性)
  /// - `response`: 弹簧周期响应秒数 (ω0 = 2π / response)
  factory AppleSpringSimulation.fromResponse({
    required double start,
    required double end,
    double velocity = 0.0,
    double dampingRatio = 1.0,
    double response = 0.32,
  }) {
    final safeResponse = response.clamp(0.05, 5.0);
    final omega0 = (2.0 * math.pi) / safeResponse;
    return AppleSpringSimulation(
      startPosition: start,
      endPosition: end,
      initialVelocity: velocity,
      dampingRatio: dampingRatio,
      angularFrequency: omega0,
    );
  }

  /// 临界阻尼 (ζ = 1.0, response ≈ 0.22s / ω0 = 28.0)：
  /// 最快速度收敛且零超调，用于页缘索引滑块、导航切换与模态弹窗。
  factory AppleSpringSimulation.criticallyDamped({
    required double start,
    required double end,
    double velocity = 0.0,
    double angularFrequency = 28.0,
  }) =>
      AppleSpringSimulation(
        startPosition: start,
        endPosition: end,
        initialVelocity: velocity,
        dampingRatio: 1.0,
        angularFrequency: angularFrequency,
      );

  /// 动量欠阻尼 (ζ = 0.80, ω0 = 32.0)：
  /// 具备温和物理动量感，用于卡片/按钮按压释放与手势回弹。
  factory AppleSpringSimulation.momentum({
    required double start,
    required double end,
    double velocity = 0.0,
    double dampingRatio = 0.80,
    double angularFrequency = 32.0,
  }) =>
      AppleSpringSimulation(
        startPosition: start,
        endPosition: end,
        initialVelocity: velocity,
        dampingRatio: dampingRatio,
        angularFrequency: angularFrequency,
      );

  double _rawX(double time) {
    if (time <= 0) return startPosition;
    if (dampingRatio >= 0.999) {
      final envelope = math.exp(-angularFrequency * time);
      return endPosition + (_c1 + _c2 * time) * envelope;
    } else {
      final envelope = math.exp(-dampingRatio * angularFrequency * time);
      final oscillation =
          _c1 * math.cos(_omegaD * time) + _c2 * math.sin(_omegaD * time);
      return endPosition + envelope * oscillation;
    }
  }

  double _rawDx(double time) {
    if (time <= 0) return initialVelocity;
    if (dampingRatio >= 0.999) {
      final envelope = math.exp(-angularFrequency * time);
      return (_c2 - angularFrequency * (_c1 + _c2 * time)) * envelope;
    } else {
      final envelope = math.exp(-dampingRatio * angularFrequency * time);
      final decay = -dampingRatio * angularFrequency;
      final posPart =
          _c1 * math.cos(_omegaD * time) + _c2 * math.sin(_omegaD * time);
      final velPart = -_c1 * _omegaD * math.sin(_omegaD * time) +
          _c2 * _omegaD * math.cos(_omegaD * time);
      return envelope * (decay * posPart + velPart);
    }
  }

  @override
  double x(double time) {
    if (time <= 0) return startPosition;
    if (isDone(time)) return endPosition;
    return _rawX(time);
  }

  @override
  double dx(double time) {
    if (time <= 0) return initialVelocity;
    if (isDone(time)) return 0.0;
    return _rawDx(time);
  }

  @override
  bool isDone(double time) {
    if (time <= 0) {
      return (startPosition - endPosition).abs() <= tolerance.distance &&
          initialVelocity.abs() <= tolerance.velocity;
    }
    if (time >= _settlingTime) return true;
    final currentPos = _rawX(time);
    final currentVel = _rawDx(time);
    return (currentPos - endPosition).abs() <= tolerance.distance &&
        currentVel.abs() <= tolerance.velocity;
  }
}

/// 流体力学边界阻尼与动量预测
class FluidPhysics {
  /// UIScrollView 标准减速率 (normal = 0.998, fast = 0.990)
  static const double decelerationNormal = 0.998;
  static const double decelerationFast = 0.990;

  /// Apple 对数橡皮筋边界阻尼公式：
  /// f(x) = (x * c * d) / (d + c * x), c = 0.55
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

  /// Apple WWDC 精确指数衰减投射位移 (px)：
  /// [initialVelocity] 单位为 px/s，[decelerationRate] 默认为 0.998。
  static double project(
    double initialVelocity, {
    double decelerationRate = decelerationNormal,
  }) {
    final safeRate = decelerationRate.clamp(0.80, 0.9999);
    return (initialVelocity / 1000.0) * safeRate / (1.0 - safeRate);
  }

  /// 动量投掷最终落点预测：
  /// 若 [decelerationRate] < 1.0 则采用 Apple WWDC 指数衰减公式；
  /// 若 >= 1.0 则兼容线性阻尼率 start + velocity / decelerationRate。
  static double projectMomentum({
    required double start,
    required double velocity,
    double decelerationRate = decelerationNormal,
  }) {
    if (decelerationRate < 1.0) {
      return start + project(velocity, decelerationRate: decelerationRate);
    }
    return start + (velocity / decelerationRate);
  }
}

// ============================ 2. 尺度与版心间距 ============================

/// 4px 基线的杂志版面间距阶梯
class Gap {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const huge = 40.0;

  static const page = EdgeInsets.fromLTRB(28, 16, 28, 0);
  static const cardPadding = EdgeInsets.all(18);
  static const cardPaddingDense = EdgeInsets.all(12);

  static const pageH = 28.0;
  static const pageV = 16.0;
  static const section = 26.0;
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

/// 连续曲率圆角阶梯（杂志图版与精装卡片收紧为利落切角 6px-12px）
class Radii {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const xl = 16.0;
  static const xxl = 20.0;
  static const full = 999.0;
  static const thumb = 6.0;

  static BorderRadius get chip => BorderRadius.circular(sm);
  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get sheet => BorderRadius.circular(xl);
  static BorderRadius get pill => BorderRadius.circular(full);
}

/// 纸张海拔与裁切线 (Declare Elevation Once)
class Elev {
  /// 静置图版轻投影
  static List<BoxShadow> card(bool dark, Color outline) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.035),
          offset: const Offset(0, 2),
          blurRadius: 10,
          spreadRadius: 0,
        ),
      ];

  /// 悬浮态：纸面抬升与主题色环境微光
  static List<BoxShadow> cardHover(bool dark, Color outline) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.44 : 0.08),
          offset: const Offset(0, 8),
          blurRadius: 22,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.26 : 0.14),
          offset: const Offset(0, 2),
          blurRadius: 12,
          spreadRadius: 0,
        ),
      ];

  /// 按钮悬浮微光
  static List<BoxShadow> buttonHover(bool dark, Color outline) => [
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.36 : 0.22),
          offset: const Offset(0, 4),
          blurRadius: 12,
          spreadRadius: -1,
        ),
      ];

  /// 焦点光晕（键盘导航与输入聚焦）
  static List<BoxShadow> focusGlow(bool dark, Color outline) => [
        BoxShadow(
          color: outline.withValues(alpha: dark ? 0.45 : 0.32),
          blurRadius: 8,
          spreadRadius: 1.0,
        ),
      ];

  /// 浮层（菜单/对话框/抽屉）
  static List<BoxShadow> overlay(bool dark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.62 : 0.14),
          blurRadius: 36,
          offset: const Offset(0, 14),
          spreadRadius: -4,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 3),
          spreadRadius: 0,
        ),
      ];

  /// 1px 杂志裁切细线 (Registration Hairline)
  static Color border(bool dark, {bool highContrast = false}) {
    if (highContrast) {
      return dark
          ? Colors.white.withValues(alpha: 0.28)
          : Colors.black.withValues(alpha: 0.26);
    }
    return dark
        ? Colors.white.withValues(alpha: 0.09)
        : const Color(0xFF16151A).withValues(alpha: 0.09);
  }

  /// 激活/高亮描边
  static Color borderActive(Color outline, bool dark) =>
      outline.withValues(alpha: dark ? 0.72 : 0.58);
}

/// 动效参数规范
class Motion {
  static const press = Duration(milliseconds: 85);
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 240);
  static const page = Duration(milliseconds: 300);
  static const out = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 360);
  static const pulse = Duration(milliseconds: 1600);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const standard = Curves.easeInOutCubic;
  static const emphasized = Curves.easeOutQuint;
  static const spring = Curves.easeOutBack;

  static const hoverLift = -2.5;
  static const hoverScale = 1.015;
  static const coverHoverScale = 1.035;
  static const pressScale = 0.972;
  static const dialogScaleFrom = 0.95;
  static const sheetSlideFrom = Offset(0, 0.06);

  static const barrier = Color(0x72000000);

  /// 是否开启了系统「减弱动态效果」(Reduce Motion)
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

// ============================ 3. 光学校准排版 (Optical Typography) ============================

/// 誌面 (Shimen) 光学校准排版阶梯：
/// - 展示级大字号 (Display 26px) 紧行高 (1.18) 与负字距 (-0.65)
/// - 标题 (Title 18.5px) 紧字距 (-0.37)
/// - 正文 (Body 13.5px) 舒适阅读行高 (1.55) 与零字距
/// - 微标签与编号 (Micro 10.5px / Mono 12px) 正字距与全量 Tabular 等宽数字
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
    fontWeight: FontWeight.w800,
    letterSpacing: -0.65,
    height: 1.18,
    fontFeatures: nums,
  );

  static const title = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 18.5,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.37,
    height: 1.26,
    fontFeatures: nums,
  );

  static const section = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.14,
    height: 1.32,
    fontFeatures: nums,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    height: 1.55,
  );

  static const label = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.05,
    height: 1.38,
    fontFeatures: nums,
  );

  static const formLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.05,
    height: 1.42,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.05,
    height: 1.42,
    fontFeatures: nums,
  );

  static const micro = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.16,
    height: 1.36,
    fontFeatures: nums,
  );

  static const numeric = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.20,
    height: 1.22,
    fontFeatures: nums,
  );

  static const mono = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.25,
    height: 1.35,
    fontFeatures: nums,
  );
}

// ============================ 4. 物理触觉与半透明材质原语 ============================

/// AppleGlassSurface：支持无障碍高对比度降级的光学半透明压印表面
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
    this.blur = 18.0,
    this.borderRadius = Radii.lg,
    this.tintColor,
    this.borderWidth = 1.0,
    this.borderColor,
    this.shadows,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final defaultTint = highContrast
        ? (dark ? const Color(0xEE161820) : const Color(0xF5FAF7F2))
        : (dark ? const Color(0xCC161820) : const Color(0xD8FAF7F2));
    final defaultBorder = Elev.border(dark, highContrast: highContrast);

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

    final effectiveBlur = (highContrast || disableAnimations) ? 0.0 : blur;
    if (effectiveBlur > 0) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
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

/// FluidPressable:
/// - t = 0 瞬发指针按下响应
/// - 10px 迟滞边界追踪 (Hysteresis)：按住并拖出组件边界 10px 外时平滑回弹取消按压态，
///   松手前拖回边界内则重新进入按压态
/// - 100% 速度继承 (Velocity Handoff)：中途打断弹簧时继承当前 `_controller.velocity`，绝不归零重置
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
  static const double _hysteresisSlop = 10.0;

  late final AnimationController _controller;
  double _currentScale = 1.0;
  bool _isDown = false;
  bool _isInside = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this, value: 1.0);
    _controller.addListener(() {
      if (mounted) {
        setState(() {
          _currentScale = _controller.value;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _interactive =>
      widget.onTap != null ||
      widget.onSecondaryTap != null ||
      widget.onSecondaryTapAt != null;

  bool _hitTestWithHysteresis(Offset localPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return true;
    final rect = (Offset.zero & box.size).inflate(_hysteresisSlop);
    return rect.contains(localPosition);
  }

  void _animateToScale(double target, {bool criticallyDamped = false}) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      _controller.stop();
      _controller.value = target;
      setState(() => _currentScale = target);
      return;
    }

    // 继承当前弹簧运动中的瞬时速度，杜绝中途打断时的速度突变
    final currentVelocity = _controller.isAnimating ? _controller.velocity : 0.0;
    final simulation = criticallyDamped
        ? AppleSpringSimulation.criticallyDamped(
            start: _currentScale,
            end: target,
            velocity: currentVelocity,
            angularFrequency: 34.0,
          )
        : AppleSpringSimulation.momentum(
            start: _currentScale,
            end: target,
            velocity: currentVelocity,
            dampingRatio: 0.80,
            angularFrequency: 32.0,
          );
    _controller.animateWith(simulation);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!_interactive) return;
    _isDown = true;
    _isInside = true;

    final wasAnimating = _controller.isAnimating;
    final inheritedVelocity = wasAnimating ? _controller.velocity : 0.0;
    _controller.stop();

    if (wasAnimating && inheritedVelocity.abs() > 0.01) {
      // 若正在回弹途中再次按下，通过弹簧携带当前动量平滑压下
      _animateToScale(widget.scaleFactor, criticallyDamped: true);
    } else {
      // 静置态 t = 0 瞬发微缩放响应
      _controller.value = widget.scaleFactor;
      setState(() {
        _currentScale = widget.scaleFactor;
      });
    }

    if (widget.haptic) {
      HapticFeedback.lightImpact();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_isDown) return;
    final insideNow = _hitTestWithHysteresis(e.localPosition);
    if (insideNow != _isInside) {
      _isInside = insideNow;
      _animateToScale(
        _isInside ? widget.scaleFactor : 1.0,
        criticallyDamped: true,
      );
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (!_isDown) return;
    _isDown = false;
    _isInside = false;
    _animateToScale(1.0);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (!_isDown) return;
    _isDown = false;
    _isInside = false;
    _animateToScale(1.0);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
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

/// InteractiveSurface：纸张图版与交互区块统一原语
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
      widget.onTap != null ||
      widget.onSecondaryTap != null ||
      widget.onSecondaryTapAt != null;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final hovered = _hover && _interactive;
    final dy = (hovered && !disableAnimations) ? widget.lift : 0.0;

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
          duration: disableAnimations ? Duration.zero : Motion.fast,
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
                      ? Elev.border(dark, highContrast: highContrast)
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

/// 兼容按压缩放包装器
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
    this.borderWidth = 1.5,
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

/// 呼吸脉冲动效（在系统开启减弱动态效果时自动静止）
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
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      return widget.child;
    }
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

/// 静默透传容器（兼容旧签名）
class EngineeringGrid extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const EngineeringGrid({super.key, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) => child;
}

// ============================ 5. 路由与转场动效 ============================

/// 页面转场：微上浮 + 淡入（支持减弱动态效果降级）
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
  final disableAnimations =
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
  if (disableAnimations) {
    return FadeTransition(opacity: curved, child: child);
  }
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.012), end: Offset.zero)
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
        milliseconds: widget.index.clamp(0, widget.maxStagger) * 18);
    Future.delayed(delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      return widget.child;
    }
    return AnimatedOpacity(
      opacity: _shown ? 1.0 : 0.0,
      duration: Motion.slow,
      curve: Motion.enter,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.028),
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
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      return Text(text, style: style);
    }
    return AnimatedSwitcher(
      duration: Motion.normal,
      switchInCurve: Motion.enter,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.20), end: Offset.zero)
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
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: disableAnimations ? Duration.zero : Motion.normal,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: disableAnimations
            ? child
            : SlideTransition(
                position:
                    Tween(begin: const Offset(0, 0.012), end: Offset.zero)
                        .animate(animation),
                child: RepaintBoundary(child: child),
              ),
      ),
      child: child,
    );
  }
}

/// 统一的对话框：临界阻尼缩放进入 (0.95 -> 1.0)
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
      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      if (disableAnimations) {
        return FadeTransition(opacity: curved, child: child);
      }
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

/// 统一的抽屉/底部弹层：平滑上浮 + 淡入
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
      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      if (disableAnimations) {
        return FadeTransition(opacity: curved, child: child);
      }
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
