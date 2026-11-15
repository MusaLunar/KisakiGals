/// Windows 11 Fluent 2 标题栏：Mica 基底融合 + 实时游玩胶囊 + 明暗切换 + 标准 Win11 右上角窗口控制键.
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

const double kTitleBarHeight = 38;

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
      child: ColoredBox(
        color: KisakiColors.spineSurface(dark),
        child: SizedBox(
          height: kTitleBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      KisakiColors.m3Rose,
                      KisakiColors.m3Lavender,
                      KisakiColors.m3Peach,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  child: Image.asset(
                    'assets/logo/logo_64.png',
                    width: 15,
                    height: 15,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.auto_stories_rounded,
                      size: 15,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'KisakiGals',
                style: Type.caption.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              // M3 三色韵律点缀（#DA839C / #D0C0F5 / #EDABA0）
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  _TriColorDot(color: KisakiColors.m3Rose),
                  SizedBox(width: 3),
                  _TriColorDot(color: KisakiColors.m3Lavender),
                  SizedBox(width: 3),
                  _TriColorDot(color: KisakiColors.m3Peach),
                ],
              ),
              const Spacer(),
              const _LiveBadge(),
              const SizedBox(width: 6),
              Tooltip(
                message: dark ? '切换为浅色模式' : '切换为深色模式',
                child: _TitleBarIconAction(
                  icon: dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  onTap: () => _toggleTheme(ref, dark),
                ),
              ),
              const SizedBox(width: 2),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBarIconAction extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TitleBarIconAction({required this.icon, required this.onTap});

  @override
  State<_TitleBarIconAction> createState() => _TitleBarIconActionState();
}

class _TitleBarIconActionState extends State<_TitleBarIconAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          width: 36,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? (dark
                    ? KisakiColors.m3Lavender.withValues(alpha: 0.14)
                    : KisakiColors.m3Rose.withValues(alpha: 0.12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Icon(
            widget.icon,
            size: 15,
            color: scheme.onSurfaceVariant,
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              KisakiColors.m3Lavender.withValues(alpha: dark ? 0.20 : 0.34),
              KisakiColors.m3Rose.withValues(alpha: dark ? 0.16 : 0.24),
            ],
          ),
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(
            color: cyanInk.withValues(alpha: dark ? 0.48 : 0.28),
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
    final iconSize = switch (widget.kind) {
      _BtnKind.minimize => 15.0,
      _BtnKind.maximize => 14.0,
      _BtnKind.close => 16.0,
    };
    final idle = dark ? KisakiColors.nightInkMedium : KisakiColors.inkMedium;
    final hoverBg = isClose
        ? const Color(0xFFC42B1C)
        : (dark ? const Color(0x14FFFFFF) : const Color(0x0F000000));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _act,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          width: 46,
          height: kTitleBarHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.zero,
          ),
          child: Icon(
            widget.icon,
            size: iconSize,
            color: isClose && _hover
                ? Colors.white
                : (_hover ? Theme.of(context).colorScheme.onSurface : idle),
          ),
        ),
      ),
    );
  }
}

class _TriColorDot extends StatelessWidget {
  final Color color;
  const _TriColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
