import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/ui/design.dart';
import 'package:kisakigals/ui/kit.dart';
import 'package:kisakigals/ui/shell/app_shell.dart';
import 'package:kisakigals/ui/shell/tabs.dart';
import 'package:kisakigals/ui/theme.dart';

void main() {
  test('KisakiGals adopts Shimen CMYK Four-Ink functional palette and paper geometry', () {
    final light = buildLightTheme();
    final dark = buildDarkTheme();

    // 专色洋红 (Process Magenta — M)：主交互与书脊标尺
    expect(light.colorScheme.primary, const Color(0xFFE4005A));
    expect(light.colorScheme.onPrimary, Colors.white);
    expect(dark.colorScheme.primary, const Color(0xFFFF2E7E));

    // 专色青蓝 (Process Cyan — C)：时间与游玩时长专色
    expect(KisakiColors.temporalInk(false), const Color(0xFF0088B8));
    expect(KisakiColors.temporalInk(true), const Color(0xFF29B6E8));

    // 专色铭黄 (Process Yellow-Gold — Y)：评分专色
    expect(KisakiColors.ratingInk(false), const Color(0xFFD49400));
    expect(KisakiColors.ratingInk(true), const Color(0xFFFFC42E));

    // 铜版纸象牙白与凹版暗墨底版
    expect(KisakiColors.pageSurface(false), const Color(0xFFFAF7F2));
    expect(KisakiColors.pageSurface(true), const Color(0xFF13151C));

    // 杂志图版圆角与自然投影
    expect(Radii.lg, 12.0);
    expect(Radii.md, 8.0);
    expect(Radii.chip, BorderRadius.circular(6.0));

    final cardShadows = Elev.card(false, light.colorScheme.primary);
    expect(cardShadows.isNotEmpty, true);
    for (final s in cardShadows) {
      expect(s.blurRadius, greaterThan(0));
    }
  });

  test('AppleSpringSimulation supports response conversion and velocity handoff', () {
    // 临界阻尼模拟 (ζ = 1.0)
    final critical = AppleSpringSimulation.criticallyDamped(
      start: 0.0,
      end: 1.0,
      velocity: 0.0,
    );
    expect(critical.x(0.0), 0.0);
    expect(critical.x(1.0), closeTo(1.0, 0.01));

    // (dampingRatio, response) 转换：ω0 = 2π / response
    final fromResp = AppleSpringSimulation.fromResponse(
      start: 0.0,
      end: 3.0,
      velocity: 4.5,
      dampingRatio: 1.0,
      response: 0.30,
    );
    expect(fromResp.angularFrequency, closeTo(2.0 * math.pi / 0.30, 0.001));
    expect(fromResp.dx(0.0), closeTo(4.5, 0.001));
    expect(fromResp.x(1.0), closeTo(3.0, 0.01));

    // 欠阻尼动量模拟 (ζ = 0.80)
    final momentum = AppleSpringSimulation.momentum(
      start: 0.972,
      end: 1.0,
      velocity: 0.0,
    );
    expect(momentum.x(0.0), closeTo(0.972, 0.001));
    expect(momentum.x(0.5), closeTo(1.0, 0.02));
  });

  test('FluidPhysics rubber-banding and WWDC exponential-decay projection', () {
    final normal = FluidPhysics.clampWithRubberband(
      value: 50.0,
      min: 0.0,
      max: 100.0,
      dimension: 400.0,
    );
    expect(normal, 50.0);

    final over = FluidPhysics.clampWithRubberband(
      value: 150.0,
      min: 0.0,
      max: 100.0,
      dimension: 400.0,
    );
    expect(over, greaterThan(100.0));
    expect(over, lessThan(150.0));

    // WWDC 指数衰减公式：(v0 / 1000) * d / (1 - d), d = 0.998 => 0.998 / 0.002 = 499x
    final projected = FluidPhysics.project(1000.0, decelerationRate: 0.998);
    expect(projected, closeTo(499.0, 0.1));
  });

  testWidgets('KPage and AppSidebar Fore-Edge Index Tabs render cleanly',
      (tester) async {
    int selectedTab = Tabs.home;
    await tester.pumpWidget(
      ProviderScope(
        child: StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(
              body: Row(
                children: [
                  AppSidebar(
                    current: selectedTab,
                    onSelect: (i) => setState(() => selectedTab = i),
                  ),
                  Expanded(
                    child: KPage(
                      title: '游戏库',
                      subtitle: '共 42 部作品',
                      actions: [
                        KIconAction(
                          icon: Icons.add,
                          tooltip: '添加游戏',
                          onTap: () {},
                        ),
                      ],
                      child: const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('KISAKI / 游戏库'), findsNothing);
    expect(find.text('游戏库'), findsWidgets);
    expect(find.text('共 42 部作品'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);

    // 点击侧栏切换到「统计」页签，验证弹簧驱动的页缘索引标签无异常过渡
    await tester.tap(find.text('统计'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(selectedTab, Tabs.stats);
    await tester.pumpAndSettle();
  });
}
