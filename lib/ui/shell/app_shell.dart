/// 应用外壳：Microsoft Fluent 2 (Windows 11) Mica 基底 + 左侧 NavigationView 导航栏 + 右侧圆角内嵌内容帧.
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
  StreamSubscription<PlayPathCaptureEvent>? _captureSub;

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

    _captureSub = AppServices.I.tracker.onScreenshotCaptured.listen((event) {
      if (!mounted) return;
      if (event.node != null) {
        ref.read(playPathVersionProvider.notifier).state++;
        showNotice('已截取游戏画面并保存至游玩路径');
      } else if (event.error != null) {
        showNotice(event.error!, error: true);
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
    _captureSub?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    // 窗口获焦时不触发整棵 AppShell 重建，避免切回应用时卡顿。
  }

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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSidebar(
                  current: tab,
                  onSelect: (i) =>
                      ref.read(tabIndexProvider.notifier).state = i,
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 2, right: 4, bottom: 4),
                    decoration: BoxDecoration(
                      color: KisakiColors.pageSurface(dark),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Elev.border(dark), width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(19),
                      child: _LazyKeepAliveTabStack(
                        currentTab: tab,
                        builder: _pageFor,
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
  final Map<int, Widget> _tabWidgets = {};
  late final AnimationController _animController;
  late final Animation<double> _anim;

  int? _prevTab;
  double _direction = 1.0; // 1.0 = 向下切换（新页面自下而上滑入）；-1.0 = 向上切换

  @override
  void initState() {
    super.initState();
    _mountedTabs.add(widget.currentTab);
    _tabWidgets[widget.currentTab] = RepaintBoundary(
      child: widget.builder(widget.currentTab),
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _anim = CurvedAnimation(
      parent: _animController,
      curve: Motion.enter,
    );
    _animController.value = 1.0;
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _prevTab != null && mounted) {
        setState(() {
          _prevTab = null;
        });
      }
    });
  }

  Widget _tabChild(int index) {
    return _tabWidgets.putIfAbsent(
      index,
      () => RepaintBoundary(child: widget.builder(index)),
    );
  }

  @override
  void didUpdateWidget(covariant _LazyKeepAliveTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_mountedTabs.contains(widget.currentTab)) {
      _mountedTabs.add(widget.currentTab);
      _tabChild(widget.currentTab);
    }
    if (widget.currentTab != oldWidget.currentTab) {
      _prevTab = oldWidget.currentTab;
      _direction = widget.currentTab > oldWidget.currentTab ? 1.0 : -1.0;
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _tabWidgets.clear();
    _animController.dispose();
    super.dispose();
  }

  Widget _buildStaticStack() {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(Tabs.count, (index) {
        if (!_mountedTabs.contains(index)) {
          return const SizedBox.shrink();
        }
        final isCurrent = index == widget.currentTab;
        return Offstage(
          offstage: !isCurrent,
          child: TickerMode(
            enabled: isCurrent,
            child: _tabChild(index),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    if (disableAnimations || !_animController.isAnimating || _prevTab == null) {
      return _buildStaticStack();
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
              // 保留已挂载页的状态与滚动位置，避免下次切回重新查询与重建
              return Offstage(
                offstage: true,
                child: TickerMode(
                  enabled: false,
                  child: _tabChild(index),
                ),
              );
            }

            if (isPrevious) {
              final offset = Offset(0.0, -0.05 * _direction * progress);
              final opacity = (1.0 - progress).clamp(0.0, 1.0);
              return Positioned.fill(
                child: TickerMode(
                  enabled: false,
                  child: Transform.translate(
                    offset: offset * 280,
                    child: Opacity(
                      opacity: opacity,
                      child: _tabChild(index),
                    ),
                  ),
                ),
              );
            }

            final offset = Offset(0.0, 0.06 * _direction * (1.0 - progress));
            final opacity = progress.clamp(0.0, 1.0);
            return Positioned.fill(
              child: TickerMode(
                enabled: true,
                child: Transform.translate(
                  offset: offset * 280,
                  child: Opacity(
                    opacity: opacity,
                    child: _tabChild(index),
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

/// Microsoft Fluent 2 `NavigationView` 左侧导航栏
class AppSidebar extends ConsumerStatefulWidget {
  final int current;
  final ValueChanged<int> onSelect;
  const AppSidebar({super.key, required this.current, required this.onSelect});

  static const primaryItems = [
    (Icons.home_outlined, Icons.home_rounded, '主页', Tabs.home),
    (
      Icons.videogame_asset_outlined,
      Icons.videogame_asset_rounded,
      '游戏库',
      Tabs.library
    ),
    (
      Icons.explore_outlined,
      Icons.explore_rounded,
      '探索',
      Tabs.discover
    ),
    (Icons.insights_outlined, Icons.insights_rounded, '统计', Tabs.stats),
    (
      Icons.auto_awesome_outlined,
      Icons.auto_awesome_rounded,
      'AI 助手',
      Tabs.ai
    ),
  ];

  static const footerItem = (
    Icons.settings_outlined,
    Icons.settings_rounded,
    '设置',
    Tabs.settings,
  );

  static const items = [
    (Icons.home_rounded, '主页', Tabs.home, ''),
    (Icons.videogame_asset_rounded, '游戏库', Tabs.library, ''),
    (Icons.explore_rounded, '探索', Tabs.discover, ''),
    (Icons.insights_rounded, '统计', Tabs.stats, ''),
    (Icons.auto_awesome_rounded, 'AI 助手', Tabs.ai, ''),
    (Icons.settings_rounded, '设置', Tabs.settings, ''),
  ];

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar>
    with SingleTickerProviderStateMixin {
  static const double _kTopPad = 6.0;
  static const double _kItemHeight = 42.0;
  static const double _kItemGap = 4.0;
  static const double _kItemStride = _kItemHeight + _kItemGap;

  late final AnimationController _tabSpringController;
  late double _animatedIndex;

  int? _primarySlotForTab(int tab) {
    for (var i = 0; i < AppSidebar.primaryItems.length; i++) {
      if (AppSidebar.primaryItems[i].$4 == tab) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _animatedIndex = (_primarySlotForTab(widget.current) ?? 0).toDouble();
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
      final slot = _primarySlotForTab(widget.current);
      if (slot == null) return;
      final targetSlot = slot.toDouble();
      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnimations) {
        _tabSpringController.stop();
        _tabSpringController.value = targetSlot;
        setState(() => _animatedIndex = targetSlot);
      } else {
        final inheritedVelocity = _tabSpringController.isAnimating
            ? _tabSpringController.velocity
            : 0.0;
        final simulation = AppleSpringSimulation.fromResponse(
          start: _animatedIndex,
          end: targetSlot,
          velocity: inheritedVelocity,
          dampingRatio: 1.0,
          response: 0.28,
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
    final tracking = ref.watch(trackingGameProvider);
    final isFooterSelected = widget.current == AppSidebar.footerItem.$4;
    final indicatorTop = _kTopPad + _animatedIndex * _kItemStride;

    return SizedBox(
      width: 204,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _kTopPad + AppSidebar.primaryItems.length * _kItemStride,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (!isFooterSelected)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: indicatorTop,
                      height: _kItemHeight,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                KisakiColors.m3Rose
                                    .withValues(alpha: dark ? 0.24 : 0.34),
                                KisakiColors.m3Lavender
                                    .withValues(alpha: dark ? 0.20 : 0.34),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(Radii.full),
                            border: Border.all(
                              color: KisakiColors.m3Rose
                                  .withValues(alpha: dark ? 0.36 : 0.42),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    top: _kTopPad,
                    child: Column(
                      children: [
                        for (final item in AppSidebar.primaryItems)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _kItemGap),
                            child: NavItem(
                              icon: widget.current == item.$4 ? item.$2 : item.$1,
                              label: item.$3,
                              selected: widget.current == item.$4,
                              dark: dark,
                              showPill: false,
                              onTap: () => widget.onSelect(item.$4),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Elev.border(dark),
              ),
            ),
            NavItem(
              icon: isFooterSelected
                  ? AppSidebar.footerItem.$2
                  : AppSidebar.footerItem.$1,
              label: AppSidebar.footerItem.$3,
              selected: isFooterSelected,
              dark: dark,
              showPill: true,
              onTap: () => widget.onSelect(AppSidebar.footerItem.$4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Material Design 3 `NavigationDrawer` 胶囊导航项
class NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String indexCode;
  final bool selected;
  final bool dark;
  final bool showPill;
  final VoidCallback onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    this.indexCode = '',
    required this.selected,
    required this.dark,
    this.showPill = true,
    required this.onTap,
  });

  @override
  State<NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final idle =
        widget.dark ? KisakiColors.nightInkMedium : KisakiColors.inkMedium;
    final fgColor = widget.selected
        ? (widget.dark ? KisakiColors.nightInk : KisakiColors.ink)
        : idle;
    final iconColor = widget.selected
        ? KisakiColors.roseInk(widget.dark)
        : idle;
    final hoverBg = widget.dark
        ? KisakiColors.m3Lavender.withValues(alpha: 0.08)
        : KisakiColors.m3Rose.withValues(alpha: 0.09);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: FluidPressable(
        onTap: widget.onTap,
        scaleFactor: 0.985,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: (!widget.showPill || !widget.selected)
                ? (_hover && !widget.selected ? hoverBg : Colors.transparent)
                : null,
            gradient: (widget.showPill && widget.selected)
                ? LinearGradient(
                    colors: [
                      KisakiColors.m3Rose
                          .withValues(alpha: widget.dark ? 0.24 : 0.34),
                      KisakiColors.m3Lavender
                          .withValues(alpha: widget.dark ? 0.20 : 0.34),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(Radii.full),
            border: (widget.showPill && widget.selected)
                ? Border.all(
                    color: KisakiColors.m3Rose
                        .withValues(alpha: widget.dark ? 0.36 : 0.42),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 19, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(
                    fontSize: 13.5,
                    color: fgColor,
                    fontWeight:
                        widget.selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
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
