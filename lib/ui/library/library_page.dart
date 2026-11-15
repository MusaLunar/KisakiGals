/// Fluent 2 游戏库：DropTarget 拖拽入库 + CommandBar + 网格/列表切换 + FilterRail + 批量管理。
library;

import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../services/game_launcher.dart';
import '../add/add_game_page.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import 'filter_rail.dart';
import 'game_actions.dart';
import 'game_card.dart';
import 'game_list_tile.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  bool _sidebarVisible = false;
  bool _batchMode = false;
  bool _draggingOver = false;
  final Set<int> _selected = {};
  Timer? _searchTimer;

  late final TextEditingController _searchCtrl =
      TextEditingController(text: ref.read(libraryFilterProvider).query);

  @override
  void initState() {
    super.initState();
    final services = tryAppServices();
    if (services != null) {
      services.settings
          .getBool(SettingsStore.kLibrarySidebar, def: false)
          .then((v) {
        if (mounted) setState(() => _sidebarVisible = v);
      });
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() => bumpLibrary(ref);

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarVisible = !_sidebarVisible);
    await tryAppServices()
        ?.settings
        .setBool(SettingsStore.kLibrarySidebar, _sidebarVisible);
  }

  Future<void> _toggleLayout() async {
    final next = ref.read(libraryLayoutProvider) == 'list' ? 'grid' : 'list';
    ref.read(libraryLayoutProvider.notifier).state = next;
    await tryAppServices()?.settings.setString(SettingsStore.kLibraryLayout, next);
  }

  void _toggleBatchMode() => setState(() {
        _batchMode = !_batchMode;
        _selected.clear();
      });

  void _exitBatchMode() => setState(() {
        _batchMode = false;
        _selected.clear();
      });

  void _setSelected(int id, bool selected) => setState(() {
        if (selected) {
          _selected.add(id);
        } else {
          _selected.remove(id);
        }
      });

  void _clearAllFilters() {
    final f = ref.read(libraryFilterProvider);
    f
      ..status = null
      ..tag = null
      ..developer = null
      ..source = null
      ..favoriteOnly = false
      ..query = '';
    _searchCtrl.clear();
    _refresh();
  }

  Future<void> _openAddGame({String initialQuery = ''}) async {
    await pushFluentPage<void>(
      context,
      (_) => AddGamePage(initialQuery: initialQuery),
    );
    if (!mounted) return;
    _refresh();
  }

  void _handleDrop(DropDoneDetails details) {
    setState(() => _draggingOver = false);
    final paths = details.files.map((f) => f.path).toList();
    if (paths.isEmpty) return;

    String query = '';
    final exeOrLnk = paths.cast<String?>().firstWhere(
          (path) =>
              path != null &&
              (path.toLowerCase().endsWith('.exe') ||
                  path.toLowerCase().endsWith('.lnk')),
          orElse: () => null,
        );
    if (exeOrLnk != null) {
      query = cleanExeName(p.basenameWithoutExtension(exeOrLnk));
    } else {
      final dir = paths.firstWhere(
        (path) => Directory(path).existsSync(),
        orElse: () => '',
      );
      if (dir.isNotEmpty) {
        final detected = GameLauncher.detectExecutable(dir);
        query = detected.isNotEmpty
            ? cleanExeName(p.basenameWithoutExtension(detected))
            : cleanExeName(p.basename(dir));
      }
    }

    if (query.isEmpty) {
      query = cleanExeName(p.basenameWithoutExtension(paths.first));
    }
    _openAddGame(initialQuery: query);
  }

  void _debouncedRefresh() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);
    ref.watch(libraryVersionProvider);
    final games = ref.watch(gamesProvider);
    final layout = ref.watch(libraryLayoutProvider);

    if (ref.watch(librarySidebarProvider) && !_sidebarVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _sidebarVisible = true);
        tryAppServices()?.settings.setBool(SettingsStore.kLibrarySidebar, true);
        ref.read(librarySidebarProvider.notifier).state = false;
      });
    }

    if (_searchCtrl.text != filter.query) {
      _searchCtrl.value = TextEditingValue(
        text: filter.query,
        selection: TextSelection.collapsed(offset: filter.query.length),
      );
    }

    return ensureFluentTheme(
      context,
      Builder(
        builder: (ctx) => _buildScaffold(ctx, games, layout, filter),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AsyncValue<List<Game>> games,
    String layout,
    LibraryFilter filter,
  ) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final subtitle = games.when(
      skipLoadingOnReload: true,
      data: (list) => '共 ${list.length} 部作品',
      loading: () => '正在读取游戏库…',
      error: (_, __) => '游戏库读取失败',
    );

    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingOver = true),
      onDragExited: (_) => setState(() => _draggingOver = false),
      onDragDone: _handleDrop,
      child: Stack(
        children: [
          ScaffoldPage(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('游戏库', style: theme.typography.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.typography.caption?.copyWith(
                              color: theme.inactiveColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CommandBar(
                          overflowBehavior:
                              CommandBarOverflowBehavior.dynamicOverflow,
                          mainAxisAlignment: MainAxisAlignment.end,
                          isCompact: false,
                          primaryItems: [
                            CommandBarButton(
                              icon: const Icon(FluentIcons.add_16_regular),
                              label: const Text('添加游戏'),
                              onPressed: () => _openAddGame(),
                            ),
                            CommandBarButton(
                              icon: const Icon(
                                FluentIcons.arrow_clockwise_16_regular,
                              ),
                              label: const Text('刷新库'),
                              onPressed: _refresh,
                            ),
                            CommandBarButton(
                              icon: Icon(
                                _sidebarVisible
                                    ? FluentIcons.filter_16_regular
                                    : FluentIcons.filter_dismiss_16_regular,
                                color: _sidebarVisible ? accent : null,
                              ),
                              label: const Text('筛选栏'),
                              onPressed: _toggleSidebar,
                            ),
                            CommandBarButton(
                              icon: Icon(
                                layout == 'list'
                                    ? FluentIcons.grid_16_regular
                                    : FluentIcons.text_bullet_list_16_regular,
                              ),
                              label: Text(layout == 'list' ? '网格视图' : '列表视图'),
                              onPressed: _toggleLayout,
                            ),
                            CommandBarButton(
                              icon: Icon(
                                FluentIcons.checkbox_checked_16_regular,
                                color: _batchMode ? accent : null,
                              ),
                              label: Text(_batchMode ? '退出批量' : '批量管理'),
                              onPressed: _toggleBatchMode,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: TextBox(
                            controller: _searchCtrl,
                            placeholder: '搜索 名称 / 别名 / 开发商 / 标签',
                            prefix: const Padding(
                              padding: EdgeInsets.only(left: 10),
                              child: Icon(
                                FluentIcons.search_16_regular,
                                size: 15,
                              ),
                            ),
                            suffix: filter.query.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      FluentIcons.dismiss_16_regular,
                                      size: 13,
                                    ),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      ref.read(libraryFilterProvider).query = '';
                                      _refresh();
                                    },
                                  )
                                : null,
                            onChanged: (v) {
                              ref.read(libraryFilterProvider).query = v;
                              _debouncedRefresh();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 152,
                        child: ComboBox<GameSort>(
                          isExpanded: true,
                          value: filter.sort,
                          items: [
                            for (final s in GameSort.values)
                              ComboBoxItem<GameSort>(
                                value: s,
                                child: Text(s.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            ref.read(libraryFilterProvider).sort = v;
                            _refresh();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            content: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildBody(context, games, layout, filter)),
                      if (_sidebarVisible) const SizedBox(width: 16),
                      FilterRail(
                        visible: _sidebarVisible,
                        onClear: _clearAllFilters,
                      ),
                    ],
                  ),
                ),
                if (_batchMode) ...[
                  const SizedBox(height: 12),
                  _BatchActionBar(
                    selected: _selected,
                    onSelectAll: (all) => setState(() {
                      final list =
                          ref.read(gamesProvider).valueOrNull ?? const <Game>[];
                      _selected.clear();
                      if (all) {
                        for (final g in list) {
                          if (g.id != null) _selected.add(g.id!);
                        }
                      }
                    }),
                    onDone: _exitBatchMode,
                  ),
                ],
              ],
            ),
          ),
          if (_draggingOver)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                  alignment: Alignment.center,
                  child: FluentAcrylicPanel(
                    radius: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FluentIcons.folder_add_24_regular,
                          size: 42,
                          color: accent,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '拖入 .exe / .lnk / 游戏目录快速入库',
                          style: theme.typography.subtitle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<Game>> games,
    String layout,
    LibraryFilter filter,
  ) {
    final disableAnim = fluentAnimationsDisabled(context);
    return games.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (list) {
        if (list.isEmpty) {
          if (filter.hasActive) {
            return FluentEmptyState(
              icon: FluentIcons.search_16_regular,
              title: '没有符合条件的游戏',
              message: '试试调整筛选条件，或清空搜索关键词',
              action: Button(
                onPressed: _clearAllFilters,
                child: const Text('清除全部筛选'),
              ),
            );
          }
          return FluentEmptyState(
            icon: FluentIcons.games_24_regular,
            title: '游戏库还是空的',
            message: '点击「添加游戏」或直接拖入 .exe / 文件夹收录第一部作品',
            action: FilledButton(
              onPressed: () => _openAddGame(),
              child: const Text('添加游戏'),
            ),
          );
        }

        final ratings = ref.watch(platformRatingsProvider).valueOrNull ??
            const <int, double>{};

        if (layout == 'list') {
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final g = list[i];
              return RepaintBoundary(
                child: FluentGameListTile(
                  game: g,
                  bestPlatformRating: ratings[g.id],
                  selectionMode: _batchMode,
                  selected: g.id != null && _selected.contains(g.id),
                  onSelectionChanged: (sel) {
                    if (g.id != null) _setSelected(g.id!, sel);
                  },
                ).fluentEntrance(index: i, disable: disableAnim),
              );
            },
          );
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.56,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final g = list[i];
                    return RepaintBoundary(
                      child: FluentGameCard(
                        game: g,
                        bestPlatformRating: ratings[g.id],
                        selectionMode: _batchMode,
                        selected: g.id != null && _selected.contains(g.id),
                        onSelectionChanged: (sel) {
                          if (g.id != null) _setSelected(g.id!, sel);
                        },
                      ).fluentEntrance(index: i, disable: disableAnim),
                    );
                  },
                  childCount: list.length,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: ProgressRing()),
      error: (e, _) => FluentEmptyState(
        icon: FluentIcons.error_circle_24_regular,
        title: '游戏库读取失败',
        message: '$e',
        action: Button(
          onPressed: _refresh,
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _BatchActionBar extends ConsumerWidget {
  final Set<int> selected;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onDone;

  const _BatchActionBar({
    required this.selected,
    required this.onSelectAll,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final n = selected.length;
    final isDark = theme.brightness == Brightness.dark;
    final dangerColor =
        isDark ? const Color(0xFFFF99A4) : const Color(0xFFD13438);

    return FluentAcrylicPanel(
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('已选 $n 项', style: theme.typography.bodyStrong),
          Button(
            onPressed: () => onSelectAll(true),
            child: const Text('全选'),
          ),
          Button(
            onPressed: () => onSelectAll(false),
            child: const Text('清空'),
          ),
          DropDownButton(
            title: const Text('更改状态'),
            items: [
              for (final s in PlayStatus.values)
                MenuFlyoutItem(
                  text: Text('设为「${s.label}」'),
                  onPressed: n == 0
                      ? null
                      : () async {
                          final repo = tryAppServices()?.repo;
                          if (repo != null) {
                            for (final id in selected) {
                              final g = await repo.getGame(id);
                              if (g != null) {
                                g.playStatus = s;
                                await repo.updateGame(g);
                              }
                            }
                          }
                          if (!context.mounted) return;
                          bumpLibrary(ref);
                          showNotice('已将 $n 部游戏状态设为「${s.label}」');
                        },
                ),
            ],
          ),
          Button(
            onPressed: n == 0
                ? null
                : () async {
                    final repo = tryAppServices()?.repo;
                    if (repo != null) {
                      for (final id in selected) {
                        final g = await repo.getGame(id);
                        if (g != null) {
                          g.isFavorite = true;
                          await repo.updateGame(g);
                        }
                      }
                    }
                    if (!context.mounted) return;
                    bumpLibrary(ref);
                    showNotice('已收藏 $n 部游戏');
                  },
            child: const Text('批量收藏'),
          ),
          Button(
            onPressed: n == 0
                ? null
                : () async {
                    final ok = await confirmBatchDeleteGames(context, n);
                    if (!ok) return;
                    final repo = tryAppServices()?.repo;
                    if (repo != null) {
                      for (final id in selected) {
                        await repo.deleteGame(id);
                      }
                    }
                    if (!context.mounted) return;
                    bumpLibrary(ref);
                    showNotice('已移出 $n 部游戏');
                    onDone();
                  },
            child: Text('批量移出', style: TextStyle(color: dangerColor)),
          ),
          FilledButton(
            onPressed: onDone,
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
