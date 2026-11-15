/// Fluent 2 动效原语（基于 flutter_animate，遵守系统无障碍减少动画）。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

class FluentMotion {
  const FluentMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration section = Duration(milliseconds: 280);
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve curve = enterCurve;
}

extension FluentMotionWidgetExt on Widget {
  /// 轻量级交错入场（仅首屏前 6 项递增延迟，避免长列表累积等待）。
  Widget fluentEntrance({
    int index = 0,
    double slideYOffset = 0.035,
    bool disable = false,
  }) {
    if (disable) return this;
    final capped = index.clamp(0, 6);
    final delay = Duration(milliseconds: 22 * capped);
    return animate(delay: delay)
        .fadeIn(duration: FluentMotion.standard, curve: FluentMotion.enterCurve)
        .slideY(
          begin: slideYOffset,
          end: 0,
          duration: FluentMotion.standard,
          curve: FluentMotion.enterCurve,
        );
  }

  /// 页面主体柔和滑入过渡。
  Widget fluentPageTransition({bool disable = false}) {
    if (disable) return this;
    return animate()
        .fadeIn(duration: FluentMotion.standard, curve: FluentMotion.enterCurve)
        .slideY(
          begin: 0.02,
          end: 0,
          duration: FluentMotion.standard,
          curve: FluentMotion.enterCurve,
        );
  }

  /// 加载骨架微光效果。
  Widget fluentShimmer({bool disable = false, Color? highlightColor}) {
    if (disable) return this;
    return animate(onPlay: (c) => c.repeat()).shimmer(
      duration: const Duration(milliseconds: 1200),
      color: highlightColor ?? const Color(0x33FFFFFF),
    );
  }
}

bool fluentAnimationsDisabled(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
