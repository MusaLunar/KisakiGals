/// 应用外壳：Fluent 2 NavigationView + TitleBar（全局搜索与运行中徽章）+ 保活标签栈.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_services.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../main.dart' show shotBoundaryKey;
import '../../providers.dart';
import '../../services/playtime_tracker.dart';
import '../../services/save_backup.dart';
import '../add/add_game_page.dart';
import '../ai/ai_page.dart';
import '../detail/game_detail_page.dart';
import '../discover/discover_page.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../home/home_page.dart';
import '../library/game_actions.dart';
import '../library/library_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import 'tabs.dart';

class AppShell extends ConsumerStatefulWidget {
  final bool enableWindowHooks;

  const AppShell({super.key, this.enableWindowHooks = true});

  static int tabToPaneIndex(int tab) => switch (tab) {
        Tabs.home => 0,
        Tabs.library => 1,
        Tabs.discover => 2,
        Tabs.stats => 3,
        Tabs.ai => 4,
        Tabs.add => 5,
        Tabs.settings => 6,
        _ => 0,
      };

  static int paneIndexToTab(int paneIndex) => switch (paneIndex) {
        0 => Tabs.home,
        1 => Tabs.library,
        2 => Tabs.discover,
        3 => Tabs.stats,
        4 => Tabs.ai,
        5 => Tabs.add,
        6 => Tabs.settings,
        _ => Tabs.home,
      };

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WindowListener {
  StreamSubscription<PlaySessionEnd>? _sessionSub;
  StreamSubscription<PlayPathCaptureEvent>? _captureSub;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableWindowHooks) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((v) {
        if (mounted && v != _isMaximized) {
          setState(() => _isMaximized = v);
        }
      }).catchError((_) {});
    }
    HardwareKeyboard.instance.addHandler(_onKey);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = lastRelocateResult;
      if (r != null) {
        lastRelocateResult = null;
        if (r.relocated.isNotEmpty) {
          showNotice(
            '已自动重新定位 ${r.relocated.length} 部游戏的路径：'
            '${r.relocated.take(3).join("、")}${r.relocated.length > 3 ? " 等" : ""}',
          );
        }
        if (r.missing.isNotEmpty) {
          showNotice(
            '${r.missing.length} 部游戏的可执行文件未找到，请在编辑信息中重新设置',
            error: true,
          );
        }
      }
      if (lastMediaRepairCount > 0) {
        final count = lastMediaRepairCount;
        lastMediaRepairCount = 0;
        showNotice('已修复 $count 部游戏的封面路径');
      }
      if (lastCoverRefetch > 0) {
        final count = lastCoverRefetch;
        lastCoverRefetch = 0;
        showNotice('已自动补回 $count 张缺失封面');
      }
    });

    final services = tryAppServices();
    if (services != null) {
      _sessionSub = services.tracker.onSessionEnd.listen((event) async {
        if (event.session != null) {
          await services.repo.addSession(event.session!);
          await _maybeAutoBackupSave(event.gameId);
          if (mounted) {
            invalidateDailyTrend(event.gameId);
            ref.read(libraryVersionProvider.notifier).state++;
          }
        }
        if (mounted && ref.read(trackingGameProvider) == event.gameId) {
          ref.read(trackingGameProvider.notifier).state = null;
        }
      });

      _captureSub = services.tracker.onScreenshotCaptured.listen((event) {
        if (!mounted) return;
        if (event.node != null) {
          ref.read(playPathVersionProvider.notifier).state++;
          showNotice('已截取游戏画面并保存至游玩路径');
        } else if (event.error != null) {
          showNotice(event.error!, error: true);
        }
      });
    }
  }

  Future<void> _maybeAutoBackupSave(int gameId) async {
    final services = tryAppServices();
    if (services == null) return;
    try {
      final settings = services.settings;
      if (!await settings.getBool('save.autosave_$gameId', def: false)) return;
      final game = await services.repo.getGame(gameId);
      if (game == null || game.savePath.isEmpty) return;
      if (!Directory(game.savePath).existsSync()) return;
      final keep = await settings.getInt(SettingsStore.kSaveBackupKeep, 10);
      final name = await SaveBackupService(services.paths.root).backup(
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
      final file = File(
        '${dir.path}/auto_$stamp.png'.replaceAll('/', Platform.pathSeparator),
      );
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('screenshot saved: ${file.path}');
    } catch (e) {
      debugPrint('screenshot failed: $e');
    }
  }

  @override
  void dispose() {
    if (widget.enableWindowHooks) {
      windowManager.removeListener(this);
    }
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sessionSub?.cancel();
    _captureSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowFocus() {
    // 窗口获焦时不触发整棵 AppShell 重建，避免切回应用时卡顿。
  }

  T _watchOptional<T>(ProviderListenable<T> provider, T fallback) {
    try {
      return ref.watch(provider);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _toggleNsfwMode() async {
    final current = ref.read(nsfwModeProvider);
    final next = current == 'blur' ? 'show' : 'blur';
    ref.read(nsfwModeProvider.notifier).state = next;
    final services = tryAppServices();
    if (services != null) {
      await services.settings.setString(SettingsStore.kNsfwMode, next);
    }
  }

  void _toggleTheme() {
    final brightness = FluentTheme.of(context).brightness;
    final next = brightness == Brightness.dark
        ? ThemeModePref.light
        : ThemeModePref.dark;
    try {
      ref.read(themeProvider.notifier).set(next);
    } catch (_) {}
  }

  Future<void> _toggleMaximize() async {
    if (!widget.enableWindowHooks) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  void _openGameDetail(Game game) {
    final id = game.id;
    if (id == null) return;
    Navigator.of(context).push(
      FluentPageRoute<void>(
        builder: (_) => GameDetailPage(gameId: id, initial: game),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(tabIndexProvider);
    final nsfwMode = ref.watch(nsfwModeProvider);
    final isBlurred = nsfwMode == 'blur';
    final themePref = _watchOptional(themeProvider, ThemeModePref.system);
    final isDark = switch (themePref) {
      ThemeModePref.dark => true,
      ThemeModePref.light => false,
      ThemeModePref.system =>
        FluentTheme.of(context).brightness == Brightness.dark,
    };
    final games = ref.watch(gamesProvider).valueOrNull ?? const <Game>[];
    final trackingId = ref.watch(trackingGameProvider);
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final fluent = FluentTheme.of(context);

    return NavigationView(
      titleBar: TitleBar(
        isBackButtonVisible: true,
        backButton: canPop
            ? IconButton(
                icon: const Icon(FluentIcons.arrow_left_16_regular, size: 16),
                onPressed: () => Navigator.maybeOf(context)?.maybePop(),
              )
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
                child: _KisakiEmblem(accent: fluent.accentColor),
              ),
        title: DragToMoveArea(
          child: Text(
            'KisakiGals',
            style: fluent.typography.bodyStrong?.copyWith(fontSize: 13),
          ),
        ),
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _GameQuickSearchBox(
              controller: _searchCtrl,
              games: games,
              onSelected: _openGameDetail,
            ),
          ),
        ),
        endHeader: trackingId != null
            ? Flexible(
                child: _ActiveTrackingPill(
                  gameId: trackingId,
                  games: games,
                ),
              )
            : null,
        captionControls: _WindowCaptionButtons(
          enabled: widget.enableWindowHooks,
          isMaximized: _isMaximized,
          onToggleMaximize: _toggleMaximize,
        ),
        onDragStarted:
            widget.enableWindowHooks ? windowManager.startDragging : null,
        onDoubleTap: widget.enableWindowHooks ? _toggleMaximize : null,
      ),
      pane: NavigationPane(
        displayMode: PaneDisplayMode.auto,
        size: const NavigationPaneSize(openWidth: 210),
        selected: AppShell.tabToPaneIndex(tab),
        onChanged: (paneIndex) {
          ref.read(tabIndexProvider.notifier).state =
              AppShell.paneIndexToTab(paneIndex);
        },
        items: [
          _buildPaneItem(
            tab: Tabs.home,
            currentTab: tab,
            regularIcon: FluentIcons.home_20_regular,
            filledIcon: FluentIcons.home_20_filled,
            label: '主页',
          ),
          _buildPaneItem(
            tab: Tabs.library,
            currentTab: tab,
            regularIcon: FluentIcons.library_20_regular,
            filledIcon: FluentIcons.library_20_filled,
            label: '游戏库',
          ),
          _buildPaneItem(
            tab: Tabs.discover,
            currentTab: tab,
            regularIcon: FluentIcons.compass_northwest_20_regular,
            filledIcon: FluentIcons.compass_northwest_20_filled,
            label: '探索',
          ),
          _buildPaneItem(
            tab: Tabs.stats,
            currentTab: tab,
            regularIcon: FluentIcons.data_histogram_20_regular,
            filledIcon: FluentIcons.data_histogram_20_filled,
            label: '统计',
          ),
          _buildPaneItem(
            tab: Tabs.ai,
            currentTab: tab,
            regularIcon: FluentIcons.sparkle_20_regular,
            filledIcon: FluentIcons.sparkle_20_filled,
            label: 'AI 助手',
          ),
        ],
        footerItems: [
          _buildPaneItem(
            tab: Tabs.add,
            currentTab: tab,
            regularIcon: FluentIcons.add_circle_20_regular,
            filledIcon: FluentIcons.add_circle_20_filled,
            label: '入库',
          ),
          _buildPaneItem(
            tab: Tabs.settings,
            currentTab: tab,
            regularIcon: FluentIcons.settings_20_regular,
            filledIcon: FluentIcons.settings_20_filled,
            label: '设置',
          ),
          PaneItemSeparator(),
          PaneItemAction(
            key: const ValueKey('nav_action_nsfw'),
            icon: Icon(
              isBlurred
                  ? FluentIcons.eye_off_20_regular
                  : FluentIcons.eye_20_regular,
            ),
            title: Text(isBlurred ? 'R18 已模糊' : 'R18 已显示'),
            tooltip: isBlurred ? '点击显示 R18 封面' : '点击模糊 R18 封面',
            onTap: _toggleNsfwMode,
          ),
          PaneItemAction(
            key: const ValueKey('nav_action_theme'),
            icon: Icon(
              isDark
                  ? FluentIcons.weather_sunny_20_regular
                  : FluentIcons.weather_moon_20_regular,
            ),
            title: Text(isDark ? '切换浅色' : '切换深色'),
            tooltip: isDark ? '切换为浅色主题' : '切换为深色主题',
            onTap: _toggleTheme,
          ),
        ],
      ),
      paneBodyBuilder: (_, __) => _LazyKeepAliveTabStack(
        currentTab: tab,
        builder: _pageFor,
      ),
    );
  }

  PaneItem _buildPaneItem({
    required int tab,
    required int currentTab,
    required IconData regularIcon,
    required IconData filledIcon,
    required String label,
  }) {
    return PaneItem(
      key: ValueKey('nav_tab_$tab'),
      icon: Icon(tab == currentTab ? filledIcon : regularIcon),
      title: Text(label),
      body: const SizedBox.shrink(),
    );
  }

  Widget _pageFor(int tab) {
    return switch (tab) {
      Tabs.home => const HomePage(key: ValueKey(Tabs.home)),
      Tabs.library => const LibraryPage(key: ValueKey(Tabs.library)),
      Tabs.discover => const DiscoverPage(key: ValueKey(Tabs.discover)),
      Tabs.stats => const StatsPage(key: ValueKey(Tabs.stats)),
      Tabs.ai => const AiPage(key: ValueKey(Tabs.ai)),
      Tabs.add => const AddGamePage(key: ValueKey(Tabs.add)),
      _ => const SettingsPage(key: ValueKey(Tabs.settings)),
    };
  }
}

class _KisakiEmblem extends StatelessWidget {
  final Color accent;
  const _KisakiEmblem({required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        'assets/logo/logo_32.png',
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          FluentIcons.book_open_20_regular,
          size: 18,
          color: accent,
        ),
      ),
    );
  }
}

class _GameQuickSearchBox extends StatelessWidget {
  final TextEditingController controller;
  final List<Game> games;
  final ValueChanged<Game> onSelected;

  const _GameQuickSearchBox({
    required this.controller,
    required this.games,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AutoSuggestBox<Game>(
      controller: controller,
      placeholder: '搜索库中作品、原名或开发商...',
      leadingIcon: const Padding(
        padding: EdgeInsetsDirectional.only(start: 8),
        child: Icon(FluentIcons.search_16_regular, size: 14),
      ),
      items: [
        for (final g in games)
          AutoSuggestBoxItem<Game>(
            value: g,
            label: g.displayName,
          ),
      ],
      sorter: (text, items) {
        final q = text.trim().toLowerCase();
        if (q.isEmpty) return const [];
        return items.where((item) {
          final g = item.value;
          if (g == null) return false;
          return g.displayName.toLowerCase().contains(q) ||
              g.name.toLowerCase().contains(q) ||
              g.nameCn.toLowerCase().contains(q) ||
              g.developer.toLowerCase().contains(q) ||
              g.aliases.any((a) => a.toLowerCase().contains(q));
        }).take(20).toList();
      },
      onSelected: (item) {
        final game = item.value;
        if (game != null) onSelected(game);
      },
    );
  }
}

class _ActiveTrackingPill extends ConsumerStatefulWidget {
  final int gameId;
  final List<Game> games;

  const _ActiveTrackingPill({
    required this.gameId,
    required this.games,
  });

  @override
  ConsumerState<_ActiveTrackingPill> createState() =>
      _ActiveTrackingPillState();
}

class _ActiveTrackingPillState extends ConsumerState<_ActiveTrackingPill> {
  Timer? _ticker;
  Game? _cachedGame;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _resolveGame();
    final services = tryAppServices();
    if (services != null) {
      _seconds = services.tracker.liveSeconds;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _seconds = services.tracker.liveSeconds;
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ActiveTrackingPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId || oldWidget.games != widget.games) {
      _resolveGame();
    }
  }

  Future<void> _resolveGame() async {
    for (final g in widget.games) {
      if (g.id == widget.gameId) {
        if (mounted) setState(() => _cachedGame = g);
        return;
      }
    }
    final fetched = await tryAppServices()?.repo.getGame(widget.gameId);
    if (mounted && fetched != null) {
      setState(() => _cachedGame = fetched);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor;
    final game = _cachedGame;
    final title = game?.displayName ?? '正在游玩';

    return HoverButton(
      key: const ValueKey('active_tracking_pill'),
      onPressed: game?.id == null
          ? null
          : () {
              Navigator.of(context).push(
                FluentPageRoute<void>(
                  builder: (_) => GameDetailPage(gameId: game!.id!, initial: game),
                ),
              );
            },
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: states.isHovered ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.resources.textFillColorPrimary,
                    ),
                  ),
                ),
              ),
              if (_seconds > 0) ...[
                const SizedBox(width: 6),
                Text(
                  _formatElapsed(_seconds),
                  style: theme.typography.caption?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('active_tracking_stop'),
                icon: Icon(
                  FluentIcons.stop_16_filled,
                  size: 12,
                  color: accent,
                ),
                onPressed: () => stopActiveGameSession(ref),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WindowCaptionButtons extends StatelessWidget {
  final bool enabled;
  final bool isMaximized;
  final VoidCallback onToggleMaximize;

  const _WindowCaptionButtons({
    required this.enabled,
    required this.isMaximized,
    required this.onToggleMaximize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: FluentIcons.subtract_16_regular,
          tooltip: '最小化',
          onPressed: enabled ? windowManager.minimize : null,
        ),
        _CaptionButton(
          icon: isMaximized
              ? FluentIcons.square_multiple_16_regular
              : FluentIcons.maximize_16_regular,
          tooltip: isMaximized ? '还原' : '最大化',
          onPressed: enabled ? onToggleMaximize : null,
        ),
        _CaptionButton(
          icon: FluentIcons.dismiss_16_regular,
          tooltip: '关闭',
          isClose: true,
          onPressed: enabled ? windowManager.close : null,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isClose;
  final VoidCallback? onPressed;

  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final idleFg = theme.resources.textFillColorSecondary;
    final hoverFg = isClose ? Colors.white : theme.resources.textFillColorPrimary;
    final hoverBg = isClose
        ? const Color(0xFFC42B1C)
        : (isDark ? const Color(0x14FFFFFF) : const Color(0x0F000000));

    return Tooltip(
      message: tooltip,
      child: HoverButton(
        onPressed: onPressed,
        builder: (context, states) {
          final active = states.isHovered || states.isPressed;
          return AnimatedContainer(
            duration: FluentMotion.fast,
            curve: FluentMotion.enterCurve,
            width: 44,
            height: 40,
            alignment: Alignment.center,
            color: active ? hoverBg : Colors.transparent,
            child: Icon(
              icon,
              size: 14,
              color: active ? hoverFg : idleFg,
            ),
          );
        },
      ),
    );
  }
}

/// 懒加载 + 状态保活 + Fluent 过渡的 Tab 容器
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

class _LazyKeepAliveTabStackState extends State<_LazyKeepAliveTabStack> {
  final Set<int> _mountedTabs = {};
  final Map<int, Widget> _tabWidgets = {};

  @override
  void initState() {
    super.initState();
    _mountedTabs.add(widget.currentTab);
    _tabChild(widget.currentTab);
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
  }

  @override
  void dispose() {
    _tabWidgets.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = fluentAnimationsDisabled(context);

    return Stack(
      fit: StackFit.expand,
      children: List.generate(Tabs.count, (index) {
        if (!_mountedTabs.contains(index)) {
          return const SizedBox.shrink();
        }
        final isCurrent = index == widget.currentTab;
        Widget child = _tabChild(index);
        if (!disableAnimations) {
          child = child
              .animate(
                target: isCurrent ? 1.0 : 0.0,
                autoPlay: false,
              )
              .fadeIn(
                duration: FluentMotion.standard,
                curve: FluentMotion.enterCurve,
              )
              .moveY(
                begin: 8,
                end: 0,
                duration: FluentMotion.standard,
                curve: FluentMotion.enterCurve,
              );
        }
        return Offstage(
          offstage: !isCurrent,
          child: TickerMode(
            enabled: isCurrent,
            child: child,
          ),
        );
      }),
    );
  }
}
