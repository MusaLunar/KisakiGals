/// 应用外壳（标题栏 + 侧栏 + 内容区）。
///
/// 重构要点：外壳只负责「窗口装饰 + 导航 + 页面切换 + 全局事件」，
/// 不再承载业务界面；视觉全部走 kit.dart / design.dart 的 token。
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
import '../search/resource_search_page.dart';
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
    // F10：应用内截图（开发期视觉验收用）
    HardwareKeyboard.instance.addHandler(_onKey);

    // 启动提示：路径重定位 / 封面修复结果（换机或迁移后）
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

    // 会话结束 → 落库 + 自动备份存档 + 刷新统计
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

  /// 退出游戏后自动备份存档（需在「编辑信息 → 启动与存档」开启并指定目录）。
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
      backgroundColor: dark ? KisakiColors.nightBg : KisakiColors.cream,
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(
            child: Row(
              children: [
                AppSidebar(
                  current: tab,
                  onSelect: (i) =>
                      ref.read(tabIndexProvider.notifier).state = i,
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(Radii.xl)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF1B1721)
                            : const Color(0xFFFCFBFA),
                        border: Border(
                          left: BorderSide(color: Elev.border(dark)),
                          top: BorderSide(color: Elev.border(dark)),
                        ),
                      ),
                      child: FadeThroughSwitcher(
                        child: KeyedSubtree(
                          key: ValueKey(tab),
                          child: _pageFor(tab),
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

  /// 页面路由表（新增页面只需在此登记 + 侧栏加一项 + `tabs.dart` 加索引）。
  Widget _pageFor(int tab) {
    switch (tab) {
      case Tabs.home:
        return const HomePage(key: ValueKey(Tabs.home));
      case Tabs.library:
        return const LibraryPage(key: ValueKey(Tabs.library));
      case Tabs.discover:
        return const DiscoverPage(key: ValueKey(Tabs.discover));
      case Tabs.search:
        return const ResourceSearchPage(key: ValueKey(Tabs.search));
      case Tabs.stats:
        return const StatsPage(key: ValueKey(Tabs.stats));
      case Tabs.ai:
        return const AiPage(key: ValueKey(Tabs.ai));
      default:
        return const SettingsPage(key: ValueKey(Tabs.settings));
    }
  }
}

/// 侧栏：导航 + 底部运行态。
class AppSidebar extends ConsumerWidget {
  final int current;
  final ValueChanged<int> onSelect;
  const AppSidebar({super.key, required this.current, required this.onSelect});

  /// 侧栏条目（顺序必须与 [Tabs] 的索引一一对应）。
  static const items = [
    (Icons.home_rounded, '主页', Tabs.home),
    (Icons.videogame_asset_rounded, '游戏库', Tabs.library),
    (Icons.travel_explore_rounded, '探索', Tabs.discover),
    (Icons.manage_search_rounded, '资源搜索', Tabs.search),
    (Icons.insights_rounded, '统计', Tabs.stats),
    (Icons.auto_awesome_rounded, 'AI 助手', Tabs.ai),
    (Icons.settings_rounded, '设置', Tabs.settings),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tracking = ref.watch(trackingGameProvider);
    return SizedBox(
      width: 188,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          // 用条目自带的索引而不是循环下标：以后插入/重排条目时，
          // 选中态与跳转目标不会跟着下标错位
          for (final item in items)
            NavItem(
              icon: item.$1,
              label: item.$2,
              selected: current == item.$3,
              dark: dark,
              onTap: () => onSelect(item.$3),
            ),
          const Spacer(),
          if (tracking != null) const _SidebarRunning(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// 侧栏导航项：图标 + 文字，选中药丸底 + 右侧指示条。
class NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.label,
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
    final color = widget.selected ? scheme.primary : idle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 12, 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: widget.selected
                  ? scheme.primary.withValues(alpha: widget.dark ? 0.20 : 0.11)
                  : (_hover
                      ? (widget.dark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.04)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 19, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.label.copyWith(
                          color: color,
                          fontWeight: widget.selected
                              ? FontWeight.w700
                              : FontWeight.w500)),
                ),
                if (widget.selected)
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(2),
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

/// 侧栏底部：当前正在游玩的游戏（每秒刷新，点击进详情）。
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
    final scheme = Theme.of(context).colorScheme;
    final h = _seconds ~/ 3600;
    final m = (_seconds % 3600) ~/ 60;
    final s = _seconds % 60;
    final text = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: KCard(
        dense: true,
        onTap: () => Navigator.of(context).push(FadeThroughRoute.builder(
            builder: (_) => GameDetailPage(gameId: game.id!, initial: game))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: scheme.primary),
              ),
              const SizedBox(width: 6),
              Text('游玩中',
                  style: Type.micro.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 5),
            Text(game.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.caption.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(text, style: Type.numeric.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
