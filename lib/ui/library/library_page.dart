/// 游戏库：大封面网格 / 紧凑列表两种排版 + 右侧筛选边栏
/// （排序 / 状态 / 收藏 / 来源 / 开发商 / 标签）。
///
/// 页面骨架全部走 kit 原语：KPage 提供标题区与页面留白、KToolbar 承载工具栏、
/// KCard 承载筛选栏与批量操作栏、KEmpty / KLoading 承担空态与加载态；
/// 页面自身不再写标题栏、整页背景与手写卡片。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../add/add_game_page.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart' show kCoverAspect;
import '../widgets/filter_sidebar.dart';
import '../widgets/notifications.dart';
import 'game_card.dart';
import 'game_card_actions.dart';
import 'game_list_tile.dart';

/// 网格/列表的卡片间距（4/8px 栅格上的 16）。
const double _gridSpacing = Gap.lg;

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  bool _sidebarVisible = true;
  bool _batchMode = false;
  final _selected = <int>{};
  Timer? _searchTimer;

  /// 搜索框控制器：必须由 State 持有（放在 build 里会造成泄漏与光标跳动）
  late final TextEditingController _searchCtrl =
      TextEditingController(text: ref.read(libraryFilterProvider).query);

  @override
  void initState() {
    super.initState();
    // 从详情页跳转过来时，providers 会把 librarySidebarProvider 置 true，
    // build 中监听并展开筛选栏（见下方 build）
    AppServices.I.settings
        .getBool(SettingsStore.kLibrarySidebar, def: true)
        .then((v) {
      if (mounted) setState(() => _sidebarVisible = v);
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------- 状态操作 ----------------

  /// 库版本自增：通知 gamesProvider / 平台评分 / 筛选栏数据重新读取。
  void _refresh() => ref.read(libraryVersionProvider.notifier).state++;

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarVisible = !_sidebarVisible);
    await AppServices.I.settings
        .setBool(SettingsStore.kLibrarySidebar, _sidebarVisible);
  }

  /// 排版切换（网格 / 紧凑列表）并持久化到设置。
  Future<void> _toggleLayout() async {
    final next = ref.read(libraryLayoutProvider) == 'list' ? 'grid' : 'list';
    ref.read(libraryLayoutProvider.notifier).state = next;
    await AppServices.I.settings.setString(SettingsStore.kLibraryLayout, next);
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

  /// 清除全部筛选条件（空态按钮与筛选栏顶部按钮共用）。
  void _clearAllFilters() {
    final f = ref.read(libraryFilterProvider);
    f.status = null;
    f.tag = null;
    f.developer = null;
    f.source = null;
    f.favoriteOnly = false;
    f.query = '';
    _refresh();
  }

  Future<void> _openAddGame() async {
    await Navigator.of(context).push(
        FadeThroughRoute.builder(builder: (_) => const AddGamePage()));
    if (!mounted) return;
    _refresh();
  }

  /// 搜索防抖：250ms 内连续输入只刷新一次（避免每个字符都查库）。
  void _debouncedRefresh() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _refresh();
    });
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);
    final games = ref.watch(gamesProvider);
    final layout = ref.watch(libraryLayoutProvider);

    // 从详情页点开发商/标签跳转过来时自动展开筛选栏
    // （展开后把信号复位，避免用户手动收起又被强制打开）
    if (ref.watch(librarySidebarProvider) && !_sidebarVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _sidebarVisible = true);
        AppServices.I.settings.setBool(SettingsStore.kLibrarySidebar, true);
        ref.read(librarySidebarProvider.notifier).state = false;
      });
    }

    // 外部重置筛选（如「清除全部筛选」）时同步输入框
    if (_searchCtrl.text != filter.query) {
      _searchCtrl.value = TextEditingValue(
        text: filter.query,
        selection: TextSelection.collapsed(offset: filter.query.length),
      );
    }

    // 副标题展示当前筛选结果数量（重载时保留上一次的数字，不闪）
    final subtitle = games.when(
      skipLoadingOnReload: true,
      data: (list) => '共 ${list.length} 部作品',
      loading: () => '正在读取游戏库…',
      error: (e, _) => '游戏库读取失败',
    );

    return KPage(
      title: '游戏库',
      subtitle: subtitle,
      actions: [
        KPill(
          label: '添加游戏',
          icon: Icons.add_rounded,
          onTap: _openAddGame,
        ),
      ],
      child: Column(
        children: [
          KToolbar(
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: '搜索 名称 / 别名 / 开发商 / 标签',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    ref.read(libraryFilterProvider).query = v;
                    _debouncedRefresh();
                  },
                ),
              ),
              const Spacer(),
              KIconAction(
                icon: _sidebarVisible
                    ? Icons.filter_alt_rounded
                    : Icons.filter_alt_off_rounded,
                tooltip: _sidebarVisible ? '隐藏筛选栏' : '显示筛选栏',
                active: _sidebarVisible,
                onTap: _toggleSidebar,
              ),
              KIconAction(
                icon: layout == 'list'
                    ? Icons.grid_view_rounded
                    : Icons.view_list_rounded,
                tooltip: layout == 'list' ? '切换为大封面网格' : '切换为紧凑列表',
                onTap: _toggleLayout,
              ),
              KIconAction(
                icon: Icons.checklist_rounded,
                tooltip: _batchMode ? '退出批量管理' : '批量管理',
                active: _batchMode,
                onTap: _toggleBatchMode,
              ),
            ],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildBody(games, layout, filter)),
                if (_sidebarVisible) ...[
                  const SizedBox(width: Gap.lg),
                  _FilterSidebar(filter: filter, onClear: _clearAllFilters),
                ],
              ],
            ),
          ),
          // 批量操作栏：居中浮层，不挤压网格高度
          if (_batchMode)
            Padding(
              padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.lg),
              child: _BatchBar(
                selected: _selected,
                onSelectAll: (all) => setState(() {
                  final list = ref.read(gamesProvider).valueOrNull ?? const [];
                  _selected.clear();
                  if (all) {
                    for (final g in list) {
                      _selected.add(g.id!);
                    }
                  }
                }),
                onDone: _exitBatchMode,
              ),
            ),
        ],
      ),
    );
  }

  /// 内容区：网格 / 列表 / 空态 / 加载态。
  Widget _buildBody(
      AsyncValue<List<Game>> games, String layout, LibraryFilter filter) {
    return games.when(
      // 搜索与筛选触发的重载不显示 spinner（否则每次输入都闪一下）
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (list) => list.isEmpty
          // 空库与「筛选后为空」是两回事，文案与操作分开
          ? (filter.hasActive
              ? KEmpty(
                  icon: Icons.search_off_rounded,
                  title: '没有符合条件的游戏',
                  subtitle: '试试调整筛选条件，或清空搜索关键词',
                  actionLabel: '清除全部筛选',
                            actionIcon: Icons.filter_alt_off_rounded,
                  onAction: _clearAllFilters,
                )
              : const KEmpty(
                  icon: Icons.videogame_asset_off_rounded,
                  title: '游戏库还是空的',
                  subtitle: '点右上角「添加游戏」收录第一部作品吧',
                ))
          : LayoutBuilder(
              builder: (context, constraints) {
                // 平台评分角标数据：一次查询供整个网格共享（避免每张卡各查一次）
                final ratings =
                    ref.watch(platformRatingsProvider).valueOrNull ??
                        const <int, double>{};
                return layout == 'list'
                    ? _buildList(list, ratings, constraints)
                    : _buildGrid(list, ratings, constraints);
              },
            ),
      loading: () => const KLoading(size: 26),
      error: (e, _) => KEmpty(
        icon: Icons.error_outline_rounded,
        title: '游戏库读取失败',
        subtitle: '$e',
      ),
    );
  }

  /// 大封面网格：封面严格 2:3，单元高度由封面高度反推。
  Widget _buildGrid(
      List<Game> list, Map<int, double> ratings, BoxConstraints c) {
    final count = (c.maxWidth / 190).floor().clamp(2, 10);
    final cellW = (c.maxWidth - _gridSpacing * (count - 1)) / count;
    // 卡片有内边距，封面按**内容宽度**保持 2:3，再补上内边距与文字区
    final coverW = cellW - kGameCardPadding.horizontal;
    final cellH = coverW / kCoverAspect +
        kGameCardPadding.vertical +
        kGameCardMetaHeight;
    return GridView.builder(
      padding: const EdgeInsets.only(top: Gap.xs, bottom: Gap.xl),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count,
        mainAxisSpacing: _gridSpacing,
        crossAxisSpacing: _gridSpacing,
        childAspectRatio: cellW / cellH,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final g = list[i];
        // 首屏错落淡入（12 项之后不再延迟）
        return StaggeredFadeIn(
          index: i,
          child: GameCard(
            game: g,
            bestPlatformRating: ratings[g.id],
            selectionMode: _batchMode,
            selected: _selected.contains(g.id),
            onSelectionChanged: (sel) => _setSelected(g.id!, sel),
          ),
        );
      },
    );
  }

  /// 紧凑列表：左 2:3 小封面 + 右名称，多列自适应，一页容纳更多条目。
  Widget _buildList(
      List<Game> list, Map<int, double> ratings, BoxConstraints c) {
    const tileW = 320.0;
    final cols = (c.maxWidth / tileW).floor().clamp(1, 6);
    return GridView.builder(
      padding: const EdgeInsets.only(top: Gap.xs, bottom: Gap.xl),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: _gridSpacing,
        crossAxisSpacing: _gridSpacing,
        mainAxisExtent: 88,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final g = list[i];
        return StaggeredFadeIn(
          index: i,
          child: GameListTile(
            game: g,
            bestPlatformRating: ratings[g.id],
            selectionMode: _batchMode,
            selected: _selected.contains(g.id),
            onSelectionChanged: (sel) => _setSelected(g.id!, sel),
          ),
        );
      },
    );
  }
}

/// 右侧筛选边栏：排序 / 状态 / 收藏 / 来源 / 开发商 / 标签。
///
/// 外壳（宽度、卡片、内边距、常驻滚动条、分组分隔、置顶的「清除全部筛选」）
/// 全部走共享组件 [FilterSidebar]（探索页用的是同一个），这里只描述分组内容；
/// 条件之间自动插入 Divider，条件项统一由 [FilterSection] 用 KChip 换行排版。
class _FilterSidebar extends ConsumerWidget {
  final LibraryFilter filter;

  /// 清除全部筛选（与空态按钮共用同一份逻辑，避免两处条件不一致）。
  final VoidCallback onClear;

  const _FilterSidebar({required this.filter, required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 筛选变化后本栏也要跟着重画（选中态）
    ref.watch(libraryVersionProvider);
    final scheme = Theme.of(context).colorScheme;
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <TagItem>[];
    final devs = ref.watch(developersProvider).valueOrNull ?? const <String>[];
    final sources = ref.watch(usedSourcesProvider).valueOrNull ?? const <String>[];

    void apply() => ref.read(libraryVersionProvider.notifier).state++;

    return FilterSidebar(
      // 「清除全部筛选」置顶（有筛选时才显示）
      leading: filter.hasActive ? FilterClearButton(onTap: onClear) : null,
      sections: [
        FilterSection(
          title: '排序',
          children: [
            for (final s in GameSort.values)
              KChip(
                label: s.label,
                selected: filter.sort == s,
                onTap: () {
                  ref.read(libraryFilterProvider).sort = s;
                  apply();
                },
              ),
          ],
        ),
        FilterSection(
          title: '游玩状态',
          children: [
            for (final s in PlayStatus.values)
              KChip(
                label: s.label,
                selected: filter.status == s,
                onTap: () {
                  filter.status = filter.status == s ? null : s;
                  apply();
                },
              ),
          ],
        ),
        FilterSection(
          title: '收藏',
          children: [
            KChip(
              label: '仅看收藏',
              color: KisakiColors.pink,
              selected: filter.favoriteOnly,
              onTap: () {
                filter.favoriteOnly = !filter.favoriteOnly;
                apply();
              },
            ),
          ],
        ),
        if (sources.isNotEmpty)
          FilterSection(
            title: '数据来源',
            children: [
              for (final src in sources)
                KChip(
                  label: KisakiSources.labels[src] ?? src,
                  selected: filter.source == src,
                  onTap: () {
                    filter.source = filter.source == src ? null : src;
                    apply();
                  },
                ),
            ],
          ),
        if (devs.isNotEmpty)
          FilterSection(
            title: '开发商',
            // 开发商数量可能很多，用「chip 触发 + 菜单选择」而不是铺满整屏 chip
            children: [
              PopupMenuButton<String>(
                tooltip: '选择开发商',
                onSelected: (d) {
                  filter.developer =
                      d.isEmpty || filter.developer == d ? null : d;
                  apply();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('全部开发商')),
                  for (final d in devs)
                    PopupMenuItem(value: d, height: 34, child: Text(d)),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KChip(
                      label: filter.developer ?? '全部开发商',
                      selected: filter.developer != null,
                      onTap: null,
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded,
                        size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ],
          ),
        if (tags.isNotEmpty)
          FilterSection(
            title: '标签',
            children: [
              for (final t in tags.take(40))
                KChip(
                  label: t.name,
                  selected: filter.tag == t.name,
                  onTap: () {
                    filter.tag = filter.tag == t.name ? null : t.name;
                    apply();
                  },
                ),
            ],
          ),
      ],
    );
  }
}

/// 批量管理操作栏：居中浮层（KCard + Elev.overlay），主按钮是实心药丸。
class _BatchBar extends ConsumerWidget {
  final Set<int> selected;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onDone;

  const _BatchBar({
    required this.selected,
    required this.onSelectAll,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final n = selected.length;

    return Center(
      // KCard 没有投影参数：这里只补一层浮层柔光（Elev.overlay），
      // 卡片自身的底色/描边/圆角仍然由 KCard 负责。
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: Radii.sheet,
          boxShadow: Elev.overlay(dark),
        ),
        child: KCard(
          borderRadius: Radii.sheet,
          padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg, vertical: Gap.sm + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('已选 $n 项', style: Type.section),
              const SizedBox(width: Gap.sm),
              TextButton(
                  onPressed: () => onSelectAll(true), child: const Text('全选')),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
                onPressed: () => onSelectAll(false),
                child: const Text('清除'),
              ),
              const SizedBox(width: Gap.lg),
              // 批量改状态
              PopupMenuButton<PlayStatus>(
                tooltip: '批量更改状态',
                onSelected: (s) async {
                  final repo = AppServices.I.repo;
                  for (final id in selected) {
                    final g = await repo.getGame(id);
                    if (g != null) {
                      g.playStatus = s;
                      await repo.updateGame(g);
                    }
                  }
                  if (!context.mounted) return;
                  ref.read(libraryVersionProvider.notifier).state++;
                  showNotice('已将 $n 部游戏状态设为「${s.label}」');
                },
                itemBuilder: (_) => [
                  for (final s in PlayStatus.values)
                    PopupMenuItem(
                        value: s, height: 34, child: Text('设为「${s.label}」')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: Gap.md, vertical: Gap.sm + 1),
                  child: Text('更改状态', style: Type.label),
                ),
              ),
              const SizedBox(width: Gap.xs),
              TextButton(
                onPressed: () async {
                  final repo = AppServices.I.repo;
                  for (final id in selected) {
                    final g = await repo.getGame(id);
                    if (g != null) {
                      g.isFavorite = true;
                      await repo.updateGame(g);
                    }
                  }
                  if (!context.mounted) return;
                  ref.read(libraryVersionProvider.notifier).state++;
                  showNotice('已收藏 $n 部游戏');
                },
                child: const Text('收藏'),
              ),
              const SizedBox(width: Gap.xs),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: KisakiColors.danger),
                onPressed: () async {
                  // 二次确认（与单条删除同一套对话框）
                  final ok = await GameCardActions.confirmBatchDelete(
                      context, n);
                  if (!ok) return;
                  final repo = AppServices.I.repo;
                  for (final id in selected) {
                    await repo.deleteGame(id);
                  }
                  ref.read(libraryVersionProvider.notifier).state++;
                  showNotice('已删除 $n 部游戏');
                  onDone();
                },
                child: const Text('删除'),
              ),
              const SizedBox(width: Gap.md),
              // 主操作：实心药丸，未选中时禁用
              KPill(
                label: '完成',
                icon: Icons.check_rounded,
                onTap: n == 0 ? null : onDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
