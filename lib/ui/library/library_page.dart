/// Fluent 2 游戏库：DropTarget 拖拽入库 + 状态快捷筛选 + 统一分段布局切换 + 活动筛选胶囊 + FilterRail + 批量管理。
library;

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
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
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
  bool _batchBusy = false;
  bool _draggingOver = false;
  final Set<int> _selected = {};

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
    super.dispose();
  }

  void _refresh() => bumpLibrary(ref);

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarVisible = !_sidebarVisible);
    await tryAppServices()
        ?.settings
        .setBool(SettingsStore.kLibrarySidebar, _sidebarVisible);
  }

  Future<void> _setLayout(String next) async {
    if (ref.read(libraryLayoutProvider) == next) return;
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
    _refresh();
  }

  void _openAddGame({String initialQuery = '', String? initialDropPath}) {
    openAddGameTab(
      ref,
      initialQuery: initialQuery,
      initialDropPath: initialDropPath,
    );
  }

  void _handleDrop(DropDoneDetails details) {
    setState(() => _draggingOver = false);
    final paths = details.files.map((f) => f.path).toList();
    if (paths.isEmpty) return;

    if (paths.length > 1) {
      showNotice('已选取首个拖入项目进行识别，其余 ${paths.length - 1} 项已忽略');
    }

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
    _openAddGame(initialQuery: query, initialDropPath: paths.first);
  }

  int _activeFilterCount(LibraryFilter f) {
    var n = 0;
    if (f.status != null) n++;
    if (f.favoriteOnly) n++;
    if (f.developer != null && f.developer!.isNotEmpty) n++;
    if (f.source != null && f.source!.isNotEmpty) n++;
    if (f.tag != null && f.tag!.isNotEmpty) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);
    ref.watch(libraryVersionProvider);
    final games = ref.watch(gamesProvider);
    final allGames = ref.watch(allGamesProvider).valueOrNull;
    final layout = ref.watch(libraryLayoutProvider);

    if (ref.watch(librarySidebarProvider) && !_sidebarVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _sidebarVisible = true);
        tryAppServices()?.settings.setBool(SettingsStore.kLibrarySidebar, true);
        ref.read(librarySidebarProvider.notifier).state = false;
      });
    }

    // 当筛选改变时自动裁剪不可见的勾选 ID，防止批量删除误删隐藏作品
    final visibleIds = <int>{
      for (final g in games.valueOrNull ?? const <Game>[])
        if (g.id != null) g.id!,
    };
    if (_selected.isNotEmpty &&
        visibleIds.isNotEmpty &&
        !_selected.every(visibleIds.contains)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selected.retainAll(visibleIds));
      });
    }

    return ensureFluentTheme(
      context,
      Builder(
        builder: (ctx) => _buildScaffold(
          ctx,
          games,
          allGames?.length,
          layout,
          filter,
        ),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AsyncValue<List<Game>> games,
    int? totalCount,
    String layout,
    LibraryFilter filter,
  ) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final disableAnim = fluentAnimationsDisabled(context);
    final activeFilterN = _activeFilterCount(filter);

    final subtitle = games.when(
      skipLoadingOnReload: true,
      data: (list) => (filter.hasActive && totalCount != null)
          ? '显示 ${list.length} / 共 $totalCount 部作品'
          : '共 ${list.length} 部作品',
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
            padding: EdgeInsets.zero,
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
                          Text('游戏库', style: theme.typography.title),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.typography.caption?.copyWith(
                              color: theme.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: CommandBar(
                                overflowBehavior:
                                    CommandBarOverflowBehavior.dynamicOverflow,
                                mainAxisAlignment: MainAxisAlignment.end,
                                isCompact: false,
                                primaryItems: [
                                  CommandBarButton(
                                    icon: Icon(
                                      FluentIcons.add_16_regular,
                                      color: accent,
                                    ),
                                    label: Text(
                                      '添加游戏',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
                                      FluentIcons.filter_16_regular,
                                      color: (_sidebarVisible ||
                                              activeFilterN > 0)
                                          ? accent
                                          : null,
                                    ),
                                    label: Text(
                                      activeFilterN > 0
                                          ? '筛选栏 ($activeFilterN)'
                                          : '筛选栏',
                                    ),
                                    onPressed: _toggleSidebar,
                                  ),
                                  CommandBarButton(
                                    icon: Icon(
                                      FluentIcons.checkbox_checked_16_regular,
                                      color: _batchMode ? accent : null,
                                    ),
                                    label: Text(
                                      _batchMode ? '退出批量' : '批量管理',
                                    ),
                                    onPressed: _toggleBatchMode,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FluentSegmentedControl<String>(
                              compact: true,
                              selected: layout,
                              onChanged: _setLayout,
                              items: const [
                                FluentSegmentItem(
                                  value: 'grid',
                                  label: '网格视图',
                                  icon: FluentIcons.grid_16_regular,
                                  showLabel: false,
                                  tooltip: '网格视图',
                                ),
                                FluentSegmentItem(
                                  value: 'list',
                                  label: '列表视图',
                                  icon: FluentIcons.text_bullet_list_16_regular,
                                  showLabel: false,
                                  tooltip: '列表视图',
                                ),
                              ],
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
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _QuickFilterPill(
                                label: '全部状态',
                                selected: filter.status == null,
                                onTap: () {
                                  if (filter.status == null) return;
                                  ref.read(libraryFilterProvider).status = null;
                                  _refresh();
                                },
                              ),
                              for (final s in PlayStatus.values) ...[
                                const SizedBox(width: 6),
                                _QuickFilterPill(
                                  label: s.label,
                                  selected: filter.status == s,
                                  onTap: () {
                                    final next =
                                        filter.status == s ? null : s;
                                    ref.read(libraryFilterProvider).status =
                                        next;
                                    _refresh();
                                  },
                                ),
                              ],
                              const SizedBox(width: 10),
                              _QuickFilterPill(
                                icon: filter.favoriteOnly
                                    ? FluentIcons.heart_16_filled
                                    : FluentIcons.heart_16_regular,
                                label: '收藏',
                                selected: filter.favoriteOnly,
                                onTap: () {
                                  ref
                                      .read(libraryFilterProvider)
                                      .favoriteOnly = !filter.favoriteOnly;
                                  _refresh();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '排序',
                            style: theme.typography.caption?.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 162,
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
                  if (filter.hasActive) ...[
                    const SizedBox(height: 10),
                    _ActiveFilterChipsRow(
                      filter: filter,
                      onChanged: _refresh,
                      onClearAll: _clearAllFilters,
                    ),
                  ],
                ],
              ),
            ),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildBody(context, games, layout, filter),
                        ),
                        AnimatedContainer(
                          duration: disableAnim
                              ? Duration.zero
                              : FluentMotion.standard,
                          curve: FluentMotion.enterCurve,
                          width: _sidebarVisible ? 16 : 0,
                        ),
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
                      totalVisible: games.valueOrNull?.length ?? 0,
                      busy: _batchBusy,
                      onBusyChanged: (b) {
                        if (mounted) setState(() => _batchBusy = b);
                      },
                      onSelectAll: (all) => setState(() {
                        final list = ref.read(gamesProvider).valueOrNull ??
                            const <Game>[];
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
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_draggingOver,
              child: AnimatedOpacity(
                opacity: _draggingOver ? 1.0 : 0.0,
                duration: disableAnim ? Duration.zero : FluentMotion.fast,
                child: Container(
                  color: Colors.black.withValues(alpha: theme.isDark ? 0.45 : 0.25),
                  alignment: Alignment.center,
                  child: FluentAcrylicPanel(
                    radius: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 28,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
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
                            '释放鼠标以识别并入库',
                            style: theme.typography.subtitle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '支持拖入 .exe / .lnk / 游戏目录',
                            style: theme.typography.caption?.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
    return games.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (list) {
        if (list.isEmpty) {
          if (filter.hasActive) {
            return FluentEmptyState(
              icon: FluentIcons.search_24_regular,
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
                ),
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
                  mainAxisExtent: 344,
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
                      ),
                    );
                  },
                  childCount: list.length,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => layout == 'list'
          ? ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, __) => const FluentCardSkeleton(height: 92),
            )
          : GridView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                mainAxisExtent: 344,
              ),
              itemCount: 8,
              itemBuilder: (_, __) => const FluentCardSkeleton(height: 344),
            ),
      error: (_, __) => FluentEmptyState(
        icon: FluentIcons.error_circle_24_regular,
        title: '游戏库读取失败',
        message: '读取本地数据库时遇到异常，请尝试重新加载',
        action: Button(
          onPressed: _refresh,
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _QuickFilterPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _QuickFilterPill({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final disableAnim = fluentAnimationsDisabled(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: HoverButton(
        onPressed: onTap,
        builder: (context, states) {
          final bg = selected
              ? theme.accentTint
              : states.isHovered
                  ? theme.subtleHover
                  : theme.surfaceCardSecondary;
          final border = selected
              ? theme.accentInk.withValues(alpha: 0.55)
              : theme.surfaceStroke;
          final fg = selected ? theme.accentInk : theme.textPrimary;
          return FocusBorder(
            focused: states.isFocused,
            child: AnimatedContainer(
              duration: disableAnim ? Duration.zero : FluentMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 13, color: fg),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: theme.typography.caption?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActiveFilterChipsRow extends StatelessWidget {
  final LibraryFilter filter;
  final VoidCallback onChanged;
  final VoidCallback onClearAll;

  const _ActiveFilterChipsRow({
    required this.filter,
    required this.onChanged,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;

    Widget chip(String label, VoidCallback onRemove) => FluentBadge(
          text: '$label ×',
          foreground: accent,
          background: theme.accentTint,
          tooltip: '移除该筛选条件',
          onTap: () {
            onRemove();
            onChanged();
          },
        );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (filter.query.trim().isNotEmpty)
          chip('搜索: ${filter.query.trim()}', () => filter.query = ''),
        if (filter.status != null)
          chip('状态: ${filter.status!.label}', () => filter.status = null),
        if (filter.favoriteOnly)
          chip('仅看收藏', () => filter.favoriteOnly = false),
        if (filter.developer != null && filter.developer!.isNotEmpty)
          chip('开发商: ${filter.developer!}', () => filter.developer = null),
        if (filter.source != null && filter.source!.isNotEmpty)
          chip(
            '来源: ${KisakiSources.labels[filter.source!] ?? filter.source!}',
            () => filter.source = null,
          ),
        if (filter.tag != null && filter.tag!.isNotEmpty)
          chip('#${filter.tag!}', () => filter.tag = null),
        FluentBadge(
          text: '清除全部',
          foreground: theme.textSecondary,
          onTap: onClearAll,
        ),
      ],
    );
  }
}

class _BatchActionBar extends ConsumerWidget {
  final Set<int> selected;
  final int totalVisible;
  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onDone;

  const _BatchActionBar({
    required this.selected,
    required this.totalVisible,
    required this.busy,
    required this.onBusyChanged,
    required this.onSelectAll,
    required this.onDone,
  });

  Future<void> _applyBatchFavorite(
    BuildContext context,
    WidgetRef ref,
    bool fav,
  ) async {
    final ids = selected.toList();
    if (ids.isEmpty || busy) return;
    onBusyChanged(true);
    try {
      final repo = tryAppServices()?.repo;
      if (repo != null) {
        for (final id in ids) {
          final g = await repo.getGame(id);
          if (g != null && g.isFavorite != fav) {
            g.isFavorite = fav;
            await repo.updateGame(g);
          }
        }
      }
      if (!context.mounted) return;
      bumpLibrary(ref);
      showNotice(fav ? '已收藏 ${ids.length} 部游戏' : '已取消收藏 ${ids.length} 部游戏');
    } finally {
      onBusyChanged(false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final n = selected.length;
    final hasAny = n > 0 && !busy;

    return FluentAcrylicPanel(
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '已选 $n / $totalVisible 项',
                  style: theme.typography.bodyStrong?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (busy) const SizedBox(width: 14, height: 14, child: ProgressRing()),
                Button(
                  onPressed: busy || totalVisible == 0
                      ? null
                      : () => onSelectAll(true),
                  child: const Text('全选'),
                ),
                Button(
                  onPressed: hasAny ? () => onSelectAll(false) : null,
                  child: const Text('清空'),
                ),
                DropDownButton(
                  title: const Text('更改状态'),
                  disabled: !hasAny,
                  items: [
                    for (final s in PlayStatus.values)
                      MenuFlyoutItem(
                        text: Text('设为「${s.label}」'),
                        onPressed: () async {
                          final ids = selected.toList();
                          onBusyChanged(true);
                          try {
                            final repo = tryAppServices()?.repo;
                            if (repo != null) {
                              for (final id in ids) {
                                final g = await repo.getGame(id);
                                if (g != null) {
                                  g.playStatus = s;
                                  await repo.updateGame(g);
                                }
                              }
                            }
                            if (!context.mounted) return;
                            bumpLibrary(ref);
                            showNotice('已将 ${ids.length} 部游戏状态设为「${s.label}」');
                          } finally {
                            onBusyChanged(false);
                          }
                        },
                      ),
                  ],
                ),
                Button(
                  onPressed: hasAny
                      ? () => _applyBatchFavorite(context, ref, true)
                      : null,
                  child: const Text('批量收藏'),
                ),
                Button(
                  onPressed: hasAny
                      ? () => _applyBatchFavorite(context, ref, false)
                      : null,
                  child: const Text('取消收藏'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Button(
            onPressed: !hasAny
                ? null
                : () async {
                    final ids = selected.toList();
                    final ok = await confirmBatchDeleteGames(context, ids.length);
                    if (!ok) return;
                    onBusyChanged(true);
                    try {
                      final repo = tryAppServices()?.repo;
                      if (repo != null) {
                        for (final id in ids) {
                          await repo.deleteGame(id);
                        }
                      }
                      if (!context.mounted) return;
                      bumpLibrary(ref);
                      showNotice('已移出 ${ids.length} 部游戏');
                      onDone();
                    } finally {
                      onBusyChanged(false);
                    }
                  },
            child: Text(
              '批量移出',
              style: TextStyle(
                color: hasAny ? theme.dangerInk : theme.textDisabled,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy ? null : onDone,
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
