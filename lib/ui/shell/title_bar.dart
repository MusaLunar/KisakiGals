/// 标题栏：品牌 + 运行中计时 + 窗口按钮。
///
/// 窗口按钮遵循 ChronoTide 规范：圆形热区、hover 淡底、
/// 关闭键 hover/按下转危险色、按压回弹（90ms / scale 0.92）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_services.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../theme.dart';

const double kTitleBarHeight = 40;

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: kTitleBarHeight,
        child: Row(
          children: [
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/logo/logo_64.png',
                width: 18,
                height: 18,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.local_florist_rounded,
                    size: 17,
                    color: KisakiColors.pink),
              ),
            ),
            const SizedBox(width: 8),
            Text('KisakiGals',
                style: Type.label.copyWith(
                    letterSpacing: 0.3,
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink)),
            const Spacer(),
            const _LiveBadge(),
            const SizedBox(width: 8),
            const _WindowButton(icon: Icons.horizontal_rule_rounded, kind: _BtnKind.minimize),
            const _WindowButton(icon: Icons.crop_square_rounded, kind: _BtnKind.maximize),
            const _WindowButton(icon: Icons.close_rounded, kind: _BtnKind.close),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// 标题栏常驻：当前游戏与本局实时时长（点击进详情）。
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
    final h = _seconds ~/ 3600;
    final m = (_seconds % 3600) ~/ 60;
    final s = _seconds % 60;
    final text = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return PressableScale(
      onTap: () => Navigator.of(context).push(FadeThroughRoute.builder(
          builder: (_) => GameDetailPage(gameId: game.id!, initial: game))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: KisakiColors.pink.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: KisakiColors.pink.withValues(alpha: 0.32)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videogame_asset_rounded,
              size: 12, color: KisakiColors.pink),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(game.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.caption.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Text(text,
              style: Type.caption.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: KisakiColors.pink)),
        ]),
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
  bool _pressed = false;

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
        : (dark ? Colors.white : Colors.black);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _act,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: Motion.press,
          curve: Motion.enter,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            width: 32,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _pressed
                  ? hoverColor.withValues(alpha: isClose ? 0.22 : 0.18)
                  : (_hover
                      ? hoverColor.withValues(alpha: isClose ? 0.13 : 0.08)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(widget.icon,
                size: 15,
                color: isClose && (_hover || _pressed) ? Colors.white : idle),
          ),
        ),
      ),
    );
  }
}
