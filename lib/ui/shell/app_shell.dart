/// 应用外壳（标题栏 + 书脊页缘索引侧栏 + 主版面内容区）.
///
/// 核心视觉签名 — 「页缘索引标签」(Fore-Edge Index Tabs)：
/// - 左侧导览区采用装帧书脊槽底色 (KisakiColors.spineSurface)，右侧主内容区为连贯纸页 (KisakiColors.pageSurface)；
/// - 激活的页缘索引标签通过临界阻尼物理弹簧 (dampingRatio: 1.0, response: 0.30s) 在条目间平滑滑动，
///   支持中途打断速度继承 (velocity handoff)；
/// - 滑块右侧跨越 1px 裁切缝与主版面纸张无缝贯通，左侧压印 3.5px 专色洋红书脊标尺。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_services.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../main.dart' show shotBoundaryKey;
import '../../providers.dart';
import '../../services/playtime_tracker.dart';
import '../../services/save_backup.dart';
import '../ai/ai_page.dart';
import '../design.dart';
import '../detail/game_detail_page.dart';
import '../discover/discover_page.dart';
import '../home/home_page.dart';
import '../kit.dart';
import '../library/library_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import '../theme.dart';
import '../widgets/notifications.dart';
import 'tabs.dart';
import 'title_bar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WindowListener {
  StreamSubscription<PlaySessionEnd>? _sessionSub;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_onKey);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = lastRelocateResult;
      if (r != null) {
        if (r.relocated.isNotEmpty) {
          showNotice('已自动重新定位 ${r.relocated.length} 部游戏的路径：'
              '${r.relocated.take(3).join("、")}${r.relocated.length > 3 ? " 等" : ""}');
        }
        if (r.missing.isNotEmpty) {
          showNotice('${r.missing.length} 部游戏的可执行文件未找到，请在编辑信息中重新设置',
              error: true);
        }
      }
      if (lastMediaRepairCount > 0) {
        showNotice('已修复 $lastMediaRepairCount 部游戏的封面路径');
      }
      if (lastCoverRefetch > 0) {
        showNotice('已自动补回 $lastCoverRefetch 张缺失封面');
      }
    });

    _sessionSub = AppServices.I.tracker.onSessionEnd.listen((event) async {
      if (event.session != null) {
        await AppServices.I.repo.addSession(event.session!);
        await _maybeAutoBackupSave(event.gameId);
      }
      if (!mounted) return;
      if (event.session != null) {
        invalidateDailyTrend(event.gameId);
        ref.read(libraryVersionProvider.notifier).state++;
      }
      final gid = ref.read(trackingGameProvider);
      if (gid == event.gameId) {
        ref.read(trackingGameProvider.notifier).state = null;
      }
    });
  }

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
      final boundary = shotBoundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('docs/screens');
      dir.createSync(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file =
          File('$dir/auto_$stamp.png'.replaceAll('/', Platform.pathSeparator));
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('screenshot saved: ${file.path}');
    } catch (e) {
      debugPrint('screenshot failed: $e');
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
  void onWindowFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(tabIndexProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: KisakiColors.spineSurface(dark),
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(
            child: Stack(
              children: [
                // 右侧主版面纸张（偏移留出左侧 176px 书脊槽位）
                Positioned.fill(
                  left: 176,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: KisakiColors.pageSurface(dark),
                      border: Border(
                        left: BorderSide(color: Elev.border(dark), width: 1),
                      ),
                    ),
                    child: _LazyKeepAliveTabStack(
                      currentTab: tab,
                      builder: _pageFor,
                    ),
                  ),
                ),
                // 左侧书脊与跨缝页缘索引标签（置于上层以令激活标签向右跨越 1px 裁切线）
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 177,
                  child: AppSidebar(
                    current: tab,
                    onSelect: (i) =>
                        ref.read(tabIndexProvider.notifier).state = i,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageFor(int tab) {
    switch (tab) {
      case Tabs.home:
        return const HomePage(key: ValueKey(Tabs.home));
      case Tabs.library:
        return const LibraryPage(key: ValueKey(Tabs.library));
      case Tabs.discover:
        return const DiscoverPage(key: ValueKey(Tabs.discover));
      case Tabs.stats:
        return const StatsPage(key: ValueKey(Tabs.stats));
      case Tabs.ai:
        return const AiPage(key: ValueKey(Tabs.ai));
      default:
        return const SettingsPage(key: ValueKey(Tabs.settings));
    }
  }
}

/// 懒加载 + 状态保活 + 纵向滚动平滑过渡的 Tab 容器
class _LazyKeepAliveTabStack extends StatefulWidget {
  final int currentTab;
  final Widget Function(int tab) builder;
  const _LazyKeepAliveTabStack({
    required this.currentTab,
    required this.builder,
  });

  @override
  State<_LazyKeepAliveTabStack> createState() => _LazyKeepAliveTabStackState();
}

class _LazyKeepAliveTabStackState extends State<_LazyKeepAliveTabStack>
    with SingleTickerProviderStateMixin {
  final Set<int> _mountedTabs = {};
  late final AnimationController _animController;
  late final Animation<double> _anim;

  int? _prevTab;
  double _direction = 1.0; // 1.0 = 向下切换（新页面自下而上滑入）；-1.0 = 向上切换

  @override
  void initState() {
    super.initState();
    _mountedTabs.add(widget.currentTab);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _anim = CurvedAnimation(
      parent: _animController,
      curve: Motion.enter,
    );
    _animController.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _LazyKeepAliveTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_mountedTabs.contains(widget.currentTab)) {
      _mountedTabs.add(widget.currentTab);
    }
    if (widget.currentTab != oldWidget.currentTab) {
      _prevTab = oldWidget.currentTab;
      _direction = widget.currentTab > oldWidget.currentTab ? 1.0 : -1.0;
      _animController.forward(from: 0.0).then((_) {
        if (mounted) {
          setState(() {
            _prevTab = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    if (disableAnimations) {
      return Stack(
        fit: StackFit.expand,
        children: List.generate(Tabs.count, (index) {
          final isCurrent = index == widget.currentTab;
          if (!_mountedTabs.contains(index)) {
            return const SizedBox.shrink();
          }
          return Offstage(
            offstage: !isCurrent,
            child: TickerMode(
              enabled: isCurrent,
              child: widget.builder(index),
            ),
          );
        }),
      );
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final progress = _anim.value;

        return Stack(
          fit: StackFit.expand,
          children: List.generate(Tabs.count, (index) {
            if (!_mountedTabs.contains(index)) {
              return const SizedBox.shrink();
            }

            final isCurrent = index == widget.currentTab;
            final isPrevious = index == _prevTab;

            if (!isCurrent && !isPrevious) {
              return const SizedBox.shrink();
            }

            if (isPrevious) {
              // 离开的前一个页面：按方向向上/下滑出微弱位移并渐隐
              final offset = Offset(0.0, -0.06 * _direction * progress);
              final opacity = (1.0 - progress).clamp(0.0, 1.0);
              return Positioned.fill(
                child: TickerMode(
                  enabled: false,
                  child: Transform.translate(
                    offset: offset * 300,
                    child: Opacity(
                      opacity: opacity,
                      child: widget.builder(index),
                    ),
                  ),
                ),
              );
            }

            // 当前激活的页面：按方向自下/上滑入并渐显（滚动翻页质感）
            final offset = Offset(0.0, 0.08 * _direction * (1.0 - progress));
            final opacity = progress.clamp(0.0, 1.0);
            return Positioned.fill(
              child: TickerMode(
                enabled: true,
                child: Transform.translate(
                  offset: offset * 300,
                  child: Opacity(
                    opacity: opacity,
                    child: widget.builder(index),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 书脊页缘索引侧栏 (Fore-Edge Index Spine)
class AppSidebar extends ConsumerStatefulWidget {
  final int current;
  final ValueChanged<int> onSelect;
  const AppSidebar({super.key, required this.current, required this.onSelect});

  static const items = [
    (Icons.home_rounded, '主页', Tabs.home, '01'),
    (Icons.videogame_asset_rounded, '游戏库', Tabs.library, '02'),
    (Icons.travel_explore_rounded, '探索', Tabs.discover, '03'),
    (Icons.insights_rounded, '统计', Tabs.stats, '04'),
    (Icons.auto_awesome_rounded, 'AI 助手', Tabs.ai, '05'),
    (Icons.settings_rounded, '设置', Tabs.settings, '06'),
  ];

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar>
    with SingleTickerProviderStateMixin {
  static const double _kTopPad = 14.0;
  static const double _kItemHeight = 40.0;
  static const double _kItemGap = 4.0;
  static const double _kItemStride = _kItemHeight + _kItemGap;

  late final AnimationController _tabSpringController;
  late double _animatedIndex;

  int _slotForTab(int tab) {
    for (var i = 0; i < AppSidebar.items.length; i++) {
      if (AppSidebar.items[i].$3 == tab) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _animatedIndex = _slotForTab(widget.current).toDouble();
    _tabSpringController = AnimationController.unbounded(
      vsync: this,
      value: _animatedIndex,
    )..addListener(() {
        if (mounted) {
          setState(() {
            _animatedIndex = _tabSpringController.value;
          });
        }
      });
  }

  @override
  void didUpdateWidget(covariant AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      final targetSlot = _slotForTab(widget.current).toDouble();
      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnimations) {
        _tabSpringController.stop();
        _tabSpringController.value = targetSlot;
        setState(() => _animatedIndex = targetSlot);
      } else {
        // 继承当前瞬时速度，确保连续快速切页时页缘索引标签平滑转向
        final inheritedVelocity = _tabSpringController.isAnimating
            ? _tabSpringController.velocity
            : 0.0;
        final simulation = AppleSpringSimulation.fromResponse(
          start: _animatedIndex,
          end: targetSlot,
          velocity: inheritedVelocity,
          dampingRatio: 1.0,
          response: 0.30,
        );
        _tabSpringController.animateWith(simulation);
      }
    }
  }

  @override
  void dispose() {
    _tabSpringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final tracking = ref.watch(trackingGameProvider);

    final indicatorTop = _kTopPad + _animatedIndex * _kItemStride;

    return SizedBox(
      width: 177,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _kTopPad + AppSidebar.items.length * _kItemStride + 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 物理弹簧驱动的跨缝页缘索引标签背景 (与右侧主版面纸张同色贯通)
                Positioned(
                  top: indicatorTop,
                  left: 10,
                  right: 0,
                  height: _kItemHeight,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ForeEdgeTabPainter(
                        pageColor: KisakiColors.pageSurface(dark),
                        borderColor: Elev.border(dark),
                        spineAccent: scheme.primary,
                      ),
                    ),
                  ),
                ),
                // 导航条目层
                Positioned.fill(
                  top: _kTopPad,
                  child: Column(
                    children: [
                      for (final item in AppSidebar.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _kItemGap),
                          child: NavItem(
                            icon: item.$1,
                            label: item.$2,
                            indexCode: item.$4,
                            selected: widget.current == item.$3,
                            dark: dark,
                            onTap: () => widget.onSelect(item.$3),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (tracking != null) const _SidebarRunning(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'SHIMEN INDEX',
                  style: Type.micro.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0.9,
                    color:
                        dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft,
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

/// 页缘索引标签绘制器：
/// 绘制左、上、下 1px 裁切边与左侧 3.5px 专色洋红书脊标尺，右侧完全敞开与主纸页融为一体。
class _ForeEdgeTabPainter extends CustomPainter {
  final Color pageColor;
  final Color borderColor;
  final Color spineAccent;

  const _ForeEdgeTabPainter({
    required this.pageColor,
    required this.borderColor,
    required this.spineAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(Radii.md);
    final rrect = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: r,
      bottomLeft: r,
    );

    // 1. 填充与右侧主版面相同的纸张底色（向右覆盖 1px 边框缝隙）
    final fillPaint = Paint()
      ..color = pageColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fillPaint);

    // 2. 左侧 3.5px 专色洋红书脊定位标尺
    final barRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 7, 3.5, size.height - 14),
      topRight: const Radius.circular(2),
      bottomRight: const Radius.circular(2),
    );
    canvas.drawRRect(barRect, Paint()..color = spineAccent);

    // 3. 上、左、下三边 1px 裁切线（右边不画线，实现纸页贯通）
    final borderPath = Path()
      ..moveTo(size.width, 0.5)
      ..lineTo(Radii.md, 0.5)
      ..arcToPoint(
        const Offset(0.5, Radii.md),
        radius: r,
        clockwise: false,
      )
      ..lineTo(0.5, size.height - Radii.md)
      ..arcToPoint(
        Offset(Radii.md, size.height - 0.5),
        radius: r,
        clockwise: false,
      )
      ..lineTo(size.width, size.height - 0.5);

    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(borderPath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _ForeEdgeTabPainter oldDelegate) =>
      oldDelegate.pageColor != pageColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.spineAccent != spineAccent;
}

/// 侧栏导航项：图标 + 栏目标题 + 页缘等宽索引码
class NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String indexCode;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    this.indexCode = '',
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  State<NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final idle =
        widget.dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft;
    final fgColor = widget.selected
        ? (widget.dark ? KisakiColors.nightInk : KisakiColors.ink)
        : idle;
    final iconColor = widget.selected ? scheme.primary : idle;

    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: FluidPressable(
          onTap: widget.onTap,
          scaleFactor: 0.975,
          child: Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(13, 0, 12, 0),
            decoration: BoxDecoration(
              color: (!widget.selected && _hover)
                  ? (widget.dark ? Colors.white : const Color(0xFF16151A))
                      .withValues(alpha: 0.045)
                  : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(Radii.md),
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.label.copyWith(
                      color: fgColor,
                      fontWeight:
                          widget.selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.indexCode.isNotEmpty)
                  Text(
                    widget.indexCode,
                    style: Type.mono.copyWith(
                      fontSize: 10,
                      fontWeight:
                          widget.selected ? FontWeight.w800 : FontWeight.w500,
                      color: widget.selected
                          ? scheme.primary
                          : idle.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧栏底部：当前正在游玩的游戏（专色青蓝 C 实时计时卡片）
class _SidebarRunning extends ConsumerStatefulWidget {
  const _SidebarRunning();

  @override
  ConsumerState<_SidebarRunning> createState() => _SidebarRunningState();
}

class _SidebarRunningState extends ConsumerState<_SidebarRunning> {
  Timer? _t;
  int _seconds = 0;
  Game? _game;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) async {
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
    _t?.cancel();
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 12, 8),
      child: KCard(
        dense: true,
        borderColor: cyanInk.withValues(alpha: dark ? 0.40 : 0.28),
        onTap: () => Navigator.of(context).push(FadeThroughRoute.builder(
            builder: (_) => GameDetailPage(gameId: game.id!, initial: game))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              PulsingGlow(
                minOpacity: 0.55,
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
              const SizedBox(width: 6),
              Text(
                '正在运行',
                style: Type.micro.copyWith(
                  color: cyanInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
            const SizedBox(height: 5),
            Text(
              game.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.caption.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              text,
              style: Type.mono.copyWith(
                fontSize: 13,
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
