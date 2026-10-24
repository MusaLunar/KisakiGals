/// 标题栏：书眉刊头标识 + 专色青蓝运行计时胶囊 + 明暗纸张切换 + 窗口控制按钮.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_services.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../theme.dart';

const double kTitleBarHeight = 42;

class AppTitleBar extends ConsumerWidget {
  const AppTitleBar({super.key});

  Future<void> _toggleTheme(WidgetRef ref, bool currentlyDark) async {
    await ref.read(themeProvider.notifier).set(
          currentlyDark ? ThemeModePref.light : ThemeModePref.dark,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      },
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: KisakiColors.spineSurface(dark),
          border: Border(
            bottom: BorderSide(
              color: Elev.border(dark),
              width: 1,
            ),
          ),
        ),
        child: SizedBox(
          height: kTitleBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 14),
              // 专色洋红定位方印 + 应用图标
              Container(
                width: 22,
                height: 22,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: dark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image.asset(
                    'assets/logo/logo_64.png',
                    width: 16,
                    height: 16,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.auto_stories_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'KisakiGals',
                style: Type.label.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                  color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 12,
                color: Elev.border(dark),
              ),
              const SizedBox(width: 8),
              Text(
                '视觉小说藏书志',
                style: Type.micro.copyWith(
                  color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              const _LiveBadge(),
              const SizedBox(width: 6),
              Tooltip(
                message: dark ? '切换为浅色铜版纸' : '切换为深色凹版墨',
                child: FluidPressable(
                  onTap: () => _toggleTheme(ref, dark),
                  child: Container(
                    width: 30,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Icon(
                      dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 15,
                      color: dark
                          ? KisakiColors.nightInkSoft
                          : KisakiColors.inkSoft,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const _WindowButton(
                icon: Icons.horizontal_rule_rounded,
                kind: _BtnKind.minimize,
              ),
              const _WindowButton(
                icon: Icons.crop_square_rounded,
                kind: _BtnKind.maximize,
              ),
              const _WindowButton(
                icon: Icons.close_rounded,
                kind: _BtnKind.close,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题栏常驻：当前游玩中游戏与专色青蓝 (Process Cyan) 实时计时胶囊
class _LiveBadge extends ConsumerStatefulWidget {
  const _LiveBadge();

  @override
  ConsumerState<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends ConsumerState<_LiveBadge> {
  Timer? _ticker;
  int _seconds = 0;
  Game? _game;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final id = ref.read(trackingGameProvider);
      if (id == null) {
        if (mounted && _game != null) setState(() => _game = null);
        return;
      }
      final g = _game?.id == id ? _game : await AppServices.I.repo.getGame(id);
      if (!mounted) return;
      setState(() {
        _game = g;
        _seconds = AppServices.I.tracker.liveSeconds;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cyanInk = KisakiColors.temporalInk(dark);

    final h = _seconds ~/ 3600;
    final m = (_seconds % 3600) ~/ 60;
    final s = _seconds % 60;
    final text = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return FluidPressable(
      onTap: () => Navigator.of(context).push(FadeThroughRoute.builder(
          builder: (_) => GameDetailPage(gameId: game.id!, initial: game))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: cyanInk.withValues(alpha: dark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: cyanInk.withValues(alpha: dark ? 0.45 : 0.32),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulsingGlow(
              minOpacity: 0.6,
              maxOpacity: 1.0,
              minScale: 0.85,
              maxScale: 1.15,
              child: Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cyanInk,
                ),
              ),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: Text(
                game.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: Type.mono.copyWith(
                fontWeight: FontWeight.w800,
                color: cyanInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BtnKind { minimize, maximize, close }

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final _BtnKind kind;
  const _WindowButton({required this.icon, required this.kind});

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  Future<void> _act() async {
    switch (widget.kind) {
      case _BtnKind.minimize:
        await windowManager.minimize();
      case _BtnKind.maximize:
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      case _BtnKind.close:
        await windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isClose = widget.kind == _BtnKind.close;
    final idle = dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft;
    final hoverColor = isClose
        ? KisakiColors.danger
        : (dark ? Colors.white : const Color(0xFF16151A));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: FluidPressable(
        onTap: _act,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          width: 34,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? (isClose
                    ? KisakiColors.danger
                    : hoverColor.withValues(alpha: dark ? 0.10 : 0.06))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Icon(
            widget.icon,
            size: 15,
            color: isClose && _hover ? Colors.white : idle,
          ),
        ),
      ),
    );
  }
}
