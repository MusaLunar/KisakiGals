/// 应用外壳：Fluent 2 NavigationView + 扩展 SearchBox TitleBar + 保活标签栈.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
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
import '../add/add_game_page.dart';
import '../ai/ai_page.dart';
import '../detail/game_detail_page.dart';
import '../discover/discover_page.dart';
import '../fluent/fluent_chrome.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
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
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _libSearchTimer;
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
    if (e is KeyDownEvent) {
      if (e.logicalKey == LogicalKeyboardKey.f10 &&
          shotBoundaryKey.currentContext != null) {
        _capture();
        return true;
      }
      final isFocusSearchKey = e.logicalKey == LogicalKeyboardKey.keyK ||
          (e.logicalKey == LogicalKeyboardKey.keyF &&
              ref.read(tabIndexProvider) == Tabs.library);
      if (isFocusSearchKey &&
          HardwareKeyboard.instance.isControlPressed &&
          _searchFocusNode.canRequestFocus) {
        _searchFocusNode.requestFocus();
        if (_searchCtrl.text.isNotEmpty) {
          _searchCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchCtrl.text.length,
          );
        }
        return true;
      }
      if (e.logicalKey == LogicalKeyboardKey.escape &&
          _searchFocusNode.hasFocus) {
        if (_searchCtrl.text.isNotEmpty) {
          _searchCtrl.clear();
          if (ref.read(tabIndexProvider) == Tabs.library) {
            _libSearchTimer?.cancel();
            ref.read(libraryFilterProvider).query = '';
            ref.read(libraryVersionProvider.notifier).state++;
          }
          return true;
        }
        _searchFocusNode.unfocus();
        return true;
      }
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
    _libSearchTimer?.cancel();
    _sessionSub?.cancel();
    _captureSub?.cancel();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
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
      if (!mounted) return;
      if (ref.read(tabIndexProvider) == Tabs.library) {
        _syncSearchCtrlText(ref.read(libraryFilterProvider).query);
      } else {
        _searchCtrl.clear();
      }
    });
  }

  void _syncSearchCtrlText(String target) {
    if (_searchCtrl.value.composing.isValid || _searchCtrl.text == target) {
      return;
    }
    _searchCtrl.value = TextEditingValue(
      text: target,
      selection: TextSelection.collapsed(offset: target.length),
    );
  }

  void _handleTitleSearchChanged(String text, TextChangedReason reason) {
    if (ref.read(tabIndexProvider) != Tabs.library) return;
    if (reason == TextChangedReason.suggestionChosen) return;
    final trimmed = text.trim();
    final filter = ref.read(libraryFilterProvider);
    if (filter.query == trimmed) return;
    filter.query = trimmed;
    _libSearchTimer?.cancel();
    if (trimmed.isEmpty || reason == TextChangedReason.cleared) {
      ref.read(libraryVersionProvider.notifier).state++;
    } else {
      _libSearchTimer = Timer(const Duration(milliseconds: 180), () {
        if (mounted) ref.read(libraryVersionProvider.notifier).state++;
      });
    }
  }

  void _jumpToLibraryQuery(String query) {
    final q = query.trim();
    final onLibrary = ref.read(tabIndexProvider) == Tabs.library;
    if (!onLibrary && q.isEmpty) return;
    _libSearchTimer?.cancel();
    ref.read(libraryFilterProvider).query = q;
    ref.read(libraryVersionProvider.notifier).state++;
    if (!onLibrary) {
      ref.read(tabIndexProvider.notifier).state = Tabs.library;
      _syncSearchCtrlText(q);
    }
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(tabIndexProvider, (prev, next) {
      if (next == Tabs.library) {
        _syncSearchCtrlText(ref.read(libraryFilterProvider).query);
      } else if (prev == Tabs.library) {
        _libSearchTimer?.cancel();
        _syncSearchCtrlText('');
      }
    });
    ref.listen<int>(libraryVersionProvider, (_, __) {
      if (ref.read(tabIndexProvider) != Tabs.library) return;
      final q = ref.read(libraryFilterProvider).query;
      if (q.isEmpty && _searchCtrl.text.isNotEmpty) {
        _syncSearchCtrlText('');
      } else if (!_searchFocusNode.hasFocus && _searchCtrl.text.trim() != q) {
        _syncSearchCtrlText(q);
      }
    });

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
    final games = ref.watch(allGamesProvider).valueOrNull ??
        ref.watch(gamesProvider).valueOrNull ??
        const <Game>[];
    final trackingId = ref.watch(trackingGameProvider);
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final fluent = FluentTheme.of(context);

    return NavigationView(
      titleBar: KisakiTitleBar(
        backButton: canPop
            ? Tooltip(
                message: '返回上一页',
                child: IconButton(
                  icon:
                      const Icon(FluentIcons.arrow_left_16_regular, size: 16),
                  onPressed: () => Navigator.maybeOf(context)?.maybePop(),
                ),
              )
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
                child: _KisakiEmblem(accent: fluent.accentInk),
              ),
        title: DragToMoveArea(
          child: Text(
            'KisakiGals',
            style: fluent.typography.bodyStrong?.copyWith(fontSize: 13),
          ),
        ),
        content: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 460),
              child: _GameQuickSearchBox(
                controller: _searchCtrl,
                focusNode: _searchFocusNode,
                games: games,
                isLibraryActive: tab == Tabs.library,
                onChanged: _handleTitleSearchChanged,
                onSelected: _openGameDetail,
                onFallbackSubmit: _jumpToLibraryQuery,
              ),
            ),
          ),
        ),
        endHeader: trackingId != null
            ? _ActiveTrackingPill(
                gameId: trackingId,
                games: games,
              )
            : null,
        captionControls: WindowCaptionButtons(
          enabled: widget.enableWindowHooks,
          isMaximized: _isMaximized,
          onToggleMaximize: _toggleMaximize,
          height: 48,
        ),
        onDragStarted:
            widget.enableWindowHooks ? windowManager.startDragging : null,
        onDoubleTap: widget.enableWindowHooks ? _toggleMaximize : null,
      ),
      pane: NavigationPane(
        displayMode: PaneDisplayMode.auto,
        size: const NavigationPaneSize(openWidth: 236),
        expandedModeThresholdWidth: 920,
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

/// Windows 11 原生比例 TitleBar：保证居中搜索栏拥有 360–460px 的充足空间，
/// 避免默认 `TitleBar` 均分三栏把搜索栏压扁。
class KisakiTitleBar extends TitleBar {
  const KisakiTitleBar({
    super.key,
    super.backButton,
    super.title,
    super.content,
    super.endHeader,
    super.captionControls,
    super.onDragStarted,
    super.onDoubleTap,
  }) : super(height: 48, isBackButtonVisible: true);

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasFluentTheme(context));
    final theme = FluentTheme.of(context);
    final view = NavigationView.dataOf(context);
    final isPaneToggleButtonVisible =
        view.toggleButtonPosition == PaneToggleButtonPosition.titleBar;

    return SafeArea(
      bottom: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => onDragStarted?.call(),
        onDoubleTap: onDoubleTap,
        child: SizedBox(
          height: 48 + MediaQuery.of(context).padding.top,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    if (backButton != null) backButton!,
                    if (isPaneToggleButtonVisible &&
                        view.pane?.toggleButton != null)
                      view.pane!.toggleButton!,
                    if (title != null)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 4,
                            end: 8,
                          ),
                          child: DefaultTextStyle.merge(
                            style: theme.typography.bodyStrong?.copyWith(
                              color: theme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: title!,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (content != null)
                Expanded(
                  flex: 4,
                  child: content!,
                ),
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const SizedBox(width: 8),
                    if (endHeader != null) Flexible(child: endHeader!),
                    if (captionControls != null) ...[
                      if (endHeader != null) const SizedBox(width: 6),
                      captionControls!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

class _GameQuickSearchBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Game> games;
  final bool isLibraryActive;
  final void Function(String text, TextChangedReason reason)? onChanged;
  final ValueChanged<Game> onSelected;
  final ValueChanged<String> onFallbackSubmit;

  const _GameQuickSearchBox({
    required this.controller,
    required this.focusNode,
    required this.games,
    this.isLibraryActive = false,
    this.onChanged,
    required this.onSelected,
    required this.onFallbackSubmit,
  });

  @override
  State<_GameQuickSearchBox> createState() => _GameQuickSearchBoxState();
}

class _GameQuickSearchBoxState extends State<_GameQuickSearchBox> {
  bool _selectedViaSuggestion = false;

  static bool _matches(Game g, String q) {
    return g.displayName.toLowerCase().contains(q) ||
        g.name.toLowerCase().contains(q) ||
        g.nameCn.toLowerCase().contains(q) ||
        g.developer.toLowerCase().contains(q) ||
        g.aliases.any((a) => a.toLowerCase().contains(q));
  }

  List<Game> _filterGames(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return widget.games.where((g) => _matches(g, q)).take(20).toList();
  }

  void _handleEnterFallback() {
    _selectedViaSuggestion = false;
    Future.microtask(() {
      if (!mounted || _selectedViaSuggestion) return;
      final raw = widget.controller.text.trim();
      if (widget.isLibraryActive) {
        widget.onFallbackSubmit(raw);
        return;
      }
      if (raw.isEmpty) return;
      final hits = _filterGames(raw);
      if (hits.isNotEmpty) {
        widget.onSelected(hits.first);
      } else {
        widget.onFallbackSubmit(raw);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final accent = theme.accentInk;
    final radius = BorderRadius.circular(6);

    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.focusNode]),
      builder: (context, _) {
        final hasText = widget.controller.text.isNotEmpty;
        final focused = widget.focusNode.hasFocus;

        return Focus(
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              _handleEnterFallback();
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            height: 34,
            child: AutoSuggestBox<Game>(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: widget.onChanged,
              placeholder: widget.isLibraryActive
                  ? '筛选当前游戏库：名称 / 别名 / 开发商...'
                  : '搜索库中作品、原名或开发商...',
              style: theme.typography.body?.copyWith(fontSize: 13),
              placeholderStyle: theme.typography.body?.copyWith(
                fontSize: 13,
                color: theme.textSecondary,
              ),
              decoration: WidgetStateProperty.resolveWith((states) {
                final fill = (states.isFocused || states.isPressed)
                    ? res.controlFillColorInputActive
                    : states.isHovered
                        ? res.controlFillColorSecondary
                        : res.controlFillColorDefault;
                return BoxDecoration(
                  color: fill,
                  borderRadius: radius,
                  border: Border.all(
                    color: states.isFocused
                        ? accent.withValues(alpha: 0.45)
                        : res.controlStrokeColorDefault,
                  ),
                );
              }),
              foregroundDecoration: WidgetStateProperty.resolveWith((states) {
                if (states.isFocused) {
                  return BoxDecoration(
                    borderRadius: radius,
                    border: Border(
                      bottom: BorderSide(color: accent, width: 2),
                    ),
                  );
                }
                return BoxDecoration(
                  borderRadius: radius,
                  border: Border(
                    bottom: BorderSide(
                      color: res.controlStrongStrokeColorDefault
                          .withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                );
              }),
              leadingIcon: Padding(
                padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
                child: Icon(
                  FluentIcons.search_16_regular,
                  size: 14,
                  color: focused ? accent : theme.textSecondary,
                ),
              ),
              trailingIcon: (!hasText && !focused)
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.surfaceCardSecondary,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: theme.surfaceStroke),
                        ),
                        child: Text(
                          widget.isLibraryActive ? 'Ctrl+F' : 'Ctrl+K',
                          style: theme.typography.caption?.copyWith(
                            fontSize: 10.5,
                            color: theme.textTertiary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    )
                  : null,
              noResultsFoundBuilder: (ctx) {
                final t = FluentTheme.of(ctx);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.search_16_regular,
                        size: 16,
                        color: t.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '未找到匹配作品，按 Enter 在游戏库中检索',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.typography.caption?.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              items: [
                for (final g in widget.games)
                  AutoSuggestBoxItem<Game>(
                    value: g,
                    label: g.displayName,
                    child: _QuickSearchSuggestionRow(game: g),
                  ),
              ],
              sorter: (text, items) {
                final q = text.trim().toLowerCase();
                if (q.isEmpty) return const [];
                return items
                    .where((item) {
                      final g = item.value;
                      return g != null && _matches(g, q);
                    })
                    .take(20)
                    .toList();
              },
              onSelected: (item) {
                final game = item.value;
                if (game != null) {
                  _selectedViaSuggestion = true;
                  widget.onSelected(game);
                }
              },
            ),
          ),
        );
      },
    );
  }
}

/// 控制在 38px 高度内，严格契合 `AutoSuggestBox` 固定 42px tile 高度。
class _QuickSearchSuggestionRow extends StatelessWidget {
  final Game game;

  const _QuickSearchSuggestionRow({required this.game});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final subtitleParts = <String>[
      if (game.developer.trim().isNotEmpty) game.developer.trim(),
      if (game.nameCn.trim().isNotEmpty &&
          game.name.trim().isNotEmpty &&
          game.name.trim() != game.nameCn.trim())
        game.name.trim(),
    ];
    final subtitle = subtitleParts.join(' · ');

    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            FluentCoverImage(
              pathOrUrl: game.coverPath,
              nsfw: game.nsfw,
              width: 22,
              height: 30,
              radius: 3,
              allowRevealOnHover: false,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.bodyStrong?.copyWith(
                      fontSize: 12.5,
                      height: 1.15,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption?.copyWith(
                        fontSize: 10.5,
                        height: 1.1,
                        color: theme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              game.playStatus.label,
              style: theme.typography.caption?.copyWith(
                fontSize: 11,
                color: theme.textTertiary,
              ),
            ),
          ],
        ),
      ),
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
    final accent = theme.accentInk;
    final game = _cachedGame;
    final title = game?.displayName ?? '正在游玩';

    return HoverButton(
      key: const ValueKey('active_tracking_pill'),
      cursor: game?.id == null ? MouseCursor.defer : SystemMouseCursors.click,
      onPressed: game?.id == null
          ? null
          : () {
              Navigator.of(context).push(
                FluentPageRoute<void>(
                  builder: (_) =>
                      GameDetailPage(gameId: game!.id!, initial: game),
                ),
              );
            },
      builder: (context, states) {
        return FocusBorder(
          focused: states.isFocused,
          renderOutside: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: states.isHovered ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: 0.38),
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
                        color: theme.textPrimary,
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
                Tooltip(
                  message: '停止当前游玩计时',
                  child: Semantics(
                    label: '停止当前游玩计时',
                    button: true,
                    child: IconButton(
                      key: const ValueKey('active_tracking_stop'),
                      icon: Icon(
                        FluentIcons.stop_16_filled,
                        size: 12,
                        color: accent,
                      ),
                      onPressed: () => stopActiveGameSession(ref),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
}
