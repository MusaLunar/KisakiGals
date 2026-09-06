/// 应用外壳：自绘标题栏 + 左侧导航栏 + 页面切换。
library;

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../app_services.dart';
import '../main.dart' show shotBoundaryKey;
import '../providers.dart';
import 'home/home_page.dart';
import 'library/library_page.dart';
import 'ai/ai_page.dart';
import 'stats/stats_page.dart';
import 'settings/settings_page.dart';
import 'theme.dart';

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> with WindowListener {

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // F10：应用内截图（保存到 docs/screens/，用于视觉验收）
    HardwareKeyboard.instance.addHandler(_onKey);
    // 会话结束 → 落库 + 刷新统计
    AppServices.I.tracker.onSessionEnd.listen((event) async {
      if (event.session != null) {
        await AppServices.I.repo.addSession(event.session!);
      }
      if (mounted) {
        if (event.session != null) {
          ref.read(libraryVersionProvider.notifier).state++;
        }
        final gid = ref.read(trackingGameProvider);
        if (gid == event.gameId) {
          ref.read(trackingGameProvider.notifier).state = null;
        }
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.f10 &&
        shotBoundaryKey.currentContext != null) {
      _capture();
      return true;
    }
    return false;
  }

  Future<void> _capture() async {
    try {
      final boundary =
          shotBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      const dir = 'E:/Programming/KisakiGals/docs/screens';
      Directory(dir).createSync(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('$dir/auto_$stamp.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('screenshot saved: ${file.path}');
    } catch (e) {
      debugPrint('screenshot failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(tabIndexProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          _TitleBar(dark: dark),
          Expanded(
            child: Row(
              children: [
                _NavRail(
                    tab: tab,
                    onChanged: (i) =>
                        ref.read(tabIndexProvider.notifier).state = i),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        color: dark
                            ? KisakiColors.nightCard.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.66),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          child: switch (tab) {
                            0 => const HomePage(key: ValueKey(0)),
                            1 => const LibraryPage(key: ValueKey(1)),
                            2 => const StatsPage(key: ValueKey(2)),
                            3 => const AiPage(key: ValueKey(3)),
                            _ => const SettingsPage(key: ValueKey(4)),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

class _TitleBar extends StatelessWidget {
  final bool dark;
  const _TitleBar({required this.dark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo/logo_64.png',
                width: 22,
                height: 22,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.local_florist_rounded,
                  size: 20,
                  color: KisakiColors.pink,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'KisakiGals',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: dark ? KisakiColors.nightInk : KisakiColors.ink,
              ),
            ),
            const Spacer(),
            _WindowButton(
              icon: Icons.horizontal_rule_rounded,
              onTap: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: Icons.crop_square_rounded,
              onTap: () async {
                await windowManager.isMaximized()
                    ? windowManager.unmaximize()
                    : windowManager.maximize();
              },
            ),
            _WindowButton(
              icon: Icons.close_rounded,
              onTap: () => windowManager.close(),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WindowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 38,
        height: 30,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 17,
          color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onChanged;
  const _NavRail({required this.tab, required this.onChanged});

  static const _items = [
    (Icons.home_rounded, '主页'),
    (Icons.videogame_asset_rounded, '游戏库'),
    (Icons.insights_rounded, '统计'),
    (Icons.auto_awesome_rounded, 'AI'),
    (Icons.settings_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 96,
      margin: const EdgeInsets.only(left: 10, bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.6),
      ),
      child: Column(
        children: List.generate(_items.length, (i) {
          final selected = tab == i;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Material(
              color: selected
                  ? (dark
                      ? KisakiColors.pink.withValues(alpha: 0.22)
                      : KisakiColors.pinkContainer)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onChanged(i),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(
                        _items[i].$1,
                        size: 26,
                        color: selected
                            ? scheme.primary
                            : (dark
                                ? KisakiColors.nightInkSoft
                                : KisakiColors.inkSoft),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _items[i].$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? scheme.primary
                              : (dark
                                  ? KisakiColors.nightInkSoft
                                  : KisakiColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
