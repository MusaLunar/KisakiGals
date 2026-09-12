/// 应用外壳：自绘标题栏 + 左侧导航栏 + 页面切换。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../app_services.dart';
import '../main.dart' show shotBoundaryKey;
import '../data/settings_store.dart';
import '../providers.dart';
import '../services/playtime_tracker.dart';
import '../services/save_backup.dart';
import '../data/models.dart';
import 'detail/game_detail_page.dart';
import 'home/home_page.dart';
import 'library/library_page.dart';
import 'ai/ai_page.dart';
import 'stats/stats_page.dart';
import 'settings/settings_page.dart';
import 'theme.dart';
import 'widgets/notifications.dart';

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> with WindowListener {
  StreamSubscription<PlaySessionEnd>? _sessionSub;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // F10：应用内截图（保存到 docs/screens/，用于视觉验收）
    HardwareKeyboard.instance.addHandler(_onKey);
    // 会话结束 → 落库 + 自动备份存档 + 刷新统计
    _sessionSub = AppServices.I.tracker.onSessionEnd.listen((event) async {
      if (event.session != null) {
        await AppServices.I.repo.addSession(event.session!);
        await _maybeAutoBackupSave(event.gameId);
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

  /// 退出游戏后自动备份存档（需在「编辑信息 → 启动与存档」中开启并指定目录）。
  Future<void> _maybeAutoBackupSave(int gameId) async {
    try {
      final settings = AppServices.I.settings;
      if (!await settings.getBool('save.autosave_$gameId', def: false)) return;
      final game = await AppServices.I.repo.getGame(gameId);
      if (game == null || game.savePath.isEmpty) return;
      if (!Directory(game.savePath).existsSync()) return;
      final keep = await settings.getInt(SettingsStore.kSaveBackupKeep, 10);
      final name = await SaveBackupService(AppServices.I.paths.root).backup(
        gameId,
        game.savePath,
        auto: true,
        keep: keep,
      );
      showNotice('已自动备份「${game.displayName}」的存档（$name）');
    } catch (e) {
      showNotice('自动备份存档失败：$e', error: true);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sessionSub?.cancel();
    windowManager.removeListener(this);
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
            // 运行中游戏 + 实时时长（参考 ReinaManager 的运行态显示）
            const _LivePlaytimeChip(),
            const SizedBox(width: 10),
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

/// 标题栏的「运行中」指示：显示当前游戏名与本局已记录时长。
/// 每秒刷新（与计时器同源），点击进入该游戏详情页。
class _LivePlaytimeChip extends ConsumerStatefulWidget {
  const _LivePlaytimeChip();

  @override
  ConsumerState<_LivePlaytimeChip> createState() => _LivePlaytimeChipState();
}

class _LivePlaytimeChipState extends ConsumerState<_LivePlaytimeChip> {
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
      final seconds = AppServices.I.tracker.liveSeconds;
      final needLoad = _game?.id != id;
      final game = needLoad ? await AppServices.I.repo.getGame(id) : _game;
      if (!mounted) return;
      setState(() {
        _game = game;
        _seconds = seconds;
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
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GameDetailPage(gameId: game.id!))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: KisakiColors.pink.withValues(alpha: 0.14),
          border: Border.all(color: KisakiColors.pink.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videogame_asset_rounded,
              size: 13, color: KisakiColors.pink),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(game.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: KisakiColors.pink)),
        ]),
      ),
    );
  }
}