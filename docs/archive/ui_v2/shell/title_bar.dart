/// 标题栏：品牌标识 + 运行中计时胶囊 + 窗口控制按钮.
///
/// 遵循 Designable & Impeccable 规范：
/// - 纯粹的深曜石 / 冷瓷镜面质感；
/// - 窗口控制按钮使用微触觉反馈与平滑色彩过渡；
/// - 游玩中计时药丸使用 Tabular 字体特征与山茶花粉主题脉冲。
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

const double kTitleBarHeight = 44;

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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? KisakiColors.nightBg : KisakiColors.cream,
          border: Border(
            bottom: BorderSide(
              color: KisakiColors.outline(dark),
              width: 0.5,
            ),
          ),
        ),
        child: SizedBox(
          height: kTitleBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xs),
                child: Image.asset(
                  'assets/logo/logo_64.png',
                  width: 18,
                  height: 18,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.local_florist_rounded,
                    size: 17,
                    color: KisakiColors.primaryRose,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'KisakiGals',
                style: Type.label.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                ),
              ),
              const Spacer(),
              const _LiveBadge(),
              const SizedBox(width: 8),
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
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题栏常驻：当前游玩中游戏与实时计时胶囊
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
    final scheme = Theme.of(context).colorScheme;

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: dark ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.45),
            width: 0.5,
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
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                game.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: dark ? KisakiColors.nightInk : KisakiColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              text,
              style: Type.caption.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.primary,
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
        : (dark ? Colors.white : Colors.black);

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
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? (isClose
                    ? KisakiColors.danger.withValues(alpha: 0.85)
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
