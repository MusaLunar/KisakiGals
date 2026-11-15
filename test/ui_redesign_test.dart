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
  test('KisakiGals adopts Material Design 3 tokens (#DA839C / #D0C0F5 / #EDABA0)', () {
    final light = buildLightTheme();
    final dark = buildDarkTheme();

    // Material Design 3 三原色令牌 (#DA839C / #D0C0F5 / #EDABA0)
    expect(light.colorScheme.primary, const Color(0xFFDA839C));
    expect(light.colorScheme.secondary, const Color(0xFFD0C0F5));
    expect(light.colorScheme.tertiary, const Color(0xFFEDABA0));
    expect(light.colorScheme.onPrimary, const Color(0xFF3A0E1E));
    expect(dark.colorScheme.primary, const Color(0xFFDA839C));

    // 高对比度可读辅助强调色（薰衣紫 & 暖桃珊瑚）
    expect(KisakiColors.temporalInk(false), const Color(0xFF6B53B8));
    expect(KisakiColors.temporalInk(true), const Color(0xFFD0C0F5));
    expect(KisakiColors.ratingInk(false), const Color(0xFF9E5142));
    expect(KisakiColors.ratingInk(true), const Color(0xFFEDABA0));

    // Material 3 Tonal 表面色阶
    expect(KisakiColors.spineSurface(false), const Color(0xFFF6F1F5));
    expect(KisakiColors.spineSurface(true), const Color(0xFF151215));
    expect(KisakiColors.pageSurface(false), const Color(0xFFFFFBFD));
    expect(KisakiColors.pageSurface(true), const Color(0xFF1B171B));

    // M3 大圆角尺度与阴影
    expect(Radii.xxl, 28.0);
    expect(Radii.xl, 24.0);
    expect(Radii.lg, 16.0);
    expect(Radii.md, 14.0);
    expect(Radii.sm, 10.0);
    expect(Radii.chip, BorderRadius.circular(10.0));

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

  testWidgets('KPage and Fluent 2 NavigationView AppSidebar render cleanly',
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

    expect(find.text('SHIMEN INDEX'), findsNothing);
    expect(find.text('KISAKI / 游戏库'), findsNothing);
    expect(find.text('游戏库'), findsWidgets);
    expect(find.text('共 42 部作品'), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    // 点击侧栏切换到「统计」页签，验证 Fluent 2 NavigationView 切换无异常
    await tester.tap(find.text('统计'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(selectedTab, Tabs.stats);
    await tester.pumpAndSettle();
  });
}
