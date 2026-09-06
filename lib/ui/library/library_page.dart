/// 游戏库：自适应网格 + 右侧筛选边栏（排序/状态/收藏/来源/标签/开发商）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../add/add_game_page.dart';
import '../theme.dart';
import '../widgets/notifications.dart';
import 'game_card.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  bool _sidebarVisible = true;
  bool _batchMode = false;
  final _selected = <int>{};

  @override
  void initState() {
    super.initState();
    AppServices.I.settings
        .getBool('library.sidebar', def: false)
        .then((v) {
      if (mounted) setState(() => _sidebarVisible = v);
    });
  }

  Future<void> _toggleSidebar() async {
    setState(() => _sidebarVisible = !_sidebarVisible);
    await AppServices.I.settings.setBool('library.sidebar', _sidebarVisible);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final filter = ref.watch(libraryFilterProvider);
    final games = ref.watch(gamesProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          // 顶栏：标题 + 计数 + 搜索 + 添加
          Row(
            children: [
              Text('游戏库',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              games.maybeWhen(
                data: (list) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: dark
                        ? KisakiColors.pink.withValues(alpha: 0.18)
                        : KisakiColors.pinkContainer,
                  ),
                  child: Text('${list.length}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: dark ? KisakiColors.pinkSoft : KisakiColors.pink)),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const Spacer(),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: TextEditingController(text: filter.query)
                    ..selection = TextSelection.collapsed(offset: filter.query.length),
                  decoration: const InputDecoration(
                    hintText: '搜索 名称 / 别名 / 开发商 / 标签',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    ref.read(libraryFilterProvider).query = v;
                    _debouncedRefresh(ref);
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: _sidebarVisible ? '隐藏筛选栏' : '显示筛选栏',
                onPressed: _toggleSidebar,
                icon: Icon(
                  _sidebarVisible
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_off_rounded,
                  size: 22,
                  color: _sidebarVisible
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '批量管理',
                onPressed: () {
                  setState(() {
                    _batchMode = !_batchMode;
                    _selected.clear();
                  });
                },
                icon: Icon(
                  Icons.checklist_rounded,
                  size: 22,
                  color: _batchMode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddGamePage()));
                  ref.read(libraryVersionProvider.notifier).state++;
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('添加游戏'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: games.when(
                    data: (list) => list.isEmpty
                        ? const Center(child: Text('没有符合条件的游戏'))
                        : LayoutBuilder(builder: (context, constraints) {
                            const spacing = 18.0;
                            final count = (constraints.maxWidth / 172)
                                .floor()
                                .clamp(2, 10);
                            return GridView(
                              padding:
                                  const EdgeInsets.only(bottom: 20, top: 4),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: count,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                childAspectRatio: 0.52,
                              ),
                              children: [
                                for (final g in list)
                                  GameCard(
                                    game: g,
                                    selectionMode: _batchMode,
                                    selected: _selected.contains(g.id),
                                    onSelectionChanged: (sel) {
                                      setState(() {
                                        if (sel) {
                                          _selected.add(g.id!);
                                        } else {
                                          _selected.remove(g.id);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            );
                          }),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('加载失败：$e')),
                  ),
                ),
                    if (_sidebarVisible) ...[
                      const SizedBox(width: 14),
                      _FilterSidebar(filter: filter),
                    ],
                  ],
                ),
              ),
              if (_batchMode)
                _BatchBar(
                  selected: _selected,
                  onSelectAll: (all) {
                    setState(() {
                      final list = ref.read(gamesProvider).valueOrNull ?? [];
                      _selected.clear();
                      if (all) {
                        for (final g in list) {
                          _selected.add(g.id!);
                        }
                      }
                    });
                  },
                  onDone: () => setState(() {
                    _batchMode = false;
                    _selected.clear();
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _debouncedRefresh(WidgetRef ref) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      ref.read(libraryVersionProvider.notifier).state++;
    });
  }
}

Timer? _searchTimer;

/// 右侧筛选边栏：按类别整理全部筛选/排序项，外观统一。
class _FilterSidebar extends ConsumerWidget {
  final LibraryFilter filter;
  const _FilterSidebar({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <TagItem>[];
    final devs = ref.watch(developersProvider).valueOrNull ?? const <String>[];
    final sources = ref.watch(usedSourcesProvider).valueOrNull ?? const <String>[];
    final dark = Theme.of(context).brightness == Brightness.dark;

    void apply() => ref.read(libraryVersionProvider.notifier).state++;

    return SizedBox(
      width: 234,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? KisakiColors.nightCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
          children: [
            _sectionLabel(context, '排序'),
            for (final s in GameSort.values)
              _sortRow(context, s, apply),
            const Divider(height: 22),
            _sectionLabel(context, '游玩状态'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in PlayStatus.values)
                  _SideChip(
                    label: s.label,
                    selected: filter.status == s,
                    onTap: () {
                      filter.status = filter.status == s ? null : s;
                      apply();
                    },
                  ),
              ],
            ),
            const Divider(height: 22),
            _sectionLabel(context, '收藏'),
            _SideChip(
              label: '仅看收藏',
              icon: filter.favoriteOnly
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              selected: filter.favoriteOnly,
              onTap: () {
                filter.favoriteOnly = !filter.favoriteOnly;
                apply();
              },
            ),
            if (sources.isNotEmpty) ...[
              const Divider(height: 22),
              _sectionLabel(context, '数据来源'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final src in sources)
                    _SideChip(
                      label: KisakiSources.labels[src] ?? src,
                      selected: filter.source == src,
                      onTap: () {
                        filter.source = filter.source == src ? null : src;
                        apply();
                      },
                    ),
                ],
              ),
            ],
            if (devs.isNotEmpty) ...[
              const Divider(height: 22),
              _sectionLabel(context, '开发商'),
              PopupMenuButton<String>(
                onSelected: (d) {
                  filter.developer = filter.developer == d ? null : d;
                  apply();
                },
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('全部开发商')),
                  ...devs.map((d) => PopupMenuItem(value: d, child: Text(d))),
                ],
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: filter.developer != null
                        ? (dark
                            ? KisakiColors.pink.withValues(alpha: 0.2)
                            : KisakiColors.pinkContainer)
                        : (dark ? Colors.white10 : const Color(0xFFFDF3EE)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          filter.developer ?? '全部开发商',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: filter.developer != null
                                  ? FontWeight.w700
                                  : FontWeight.w500),
                        ),
                      ),
                      const Icon(Icons.expand_more_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const Divider(height: 22),
              _sectionLabel(context, '标签'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in tags.take(40))
                    _SideChip(
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
            if (filter.hasActive) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  final f = ref.read(libraryFilterProvider);
                  f.status = null;
                  f.tag = null;
                  f.developer = null;
                  f.source = null;
                  f.favoriteOnly = false;
                  f.query = '';
                  apply();
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text('清除全部筛选'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Text(text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _sortRow(BuildContext context, GameSort s, VoidCallback apply) =>
      Consumer(builder: (context, ref, _) {
        final current = ref.watch(libraryFilterProvider).sort;
        final selected = current == s;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            ref.read(libraryFilterProvider).sort = s;
            apply();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 16,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(s.label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500)),
              ],
            ),
          ),
        );
      });
}

/// 边栏统一胶囊筛选块（状态/来源/标签/收藏共用一种外观）。
class _SideChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const _SideChip(
      {required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: selected
              ? (dark ? KisakiColors.pink.withValues(alpha: 0.25) : KisakiColors.pinkContainer)
              : (dark ? Colors.white10 : const Color(0xFFFDF3EE)),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 13,
                  color: selected
                      ? scheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? (dark ? KisakiColors.pinkSoft : KisakiColors.pink)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 批量管理操作栏。
class _BatchBar extends ConsumerWidget {
  final Set<int> selected;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onDone;
  const _BatchBar(
      {required this.selected, required this.onSelectAll, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final n = selected.length;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? KisakiColors.nightCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text('已选 $n 项',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          TextButton(
              onPressed: () => onSelectAll(true), child: const Text('全选')),
          TextButton(
              onPressed: () => onSelectAll(false), child: const Text('清除')),
          const Spacer(),
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
              ref.read(libraryVersionProvider.notifier).state++;
              showNotice(ref, '已将 $n 部游戏状态设为「${s.label}」');
            },
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            itemBuilder: (_) => [
              for (final s in PlayStatus.values)
                PopupMenuItem(value: s, child: Text('设为「${s.label}」')),
            ],
            child: const Text('更改状态',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
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
                ref.read(libraryVersionProvider.notifier).state++;
                showNotice(ref, '已收藏 $n 部游戏');
              },
              child: const Text('收藏')),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('批量删除'),
                  content: Text('确定要删除选中的 $n 部游戏吗？\n游玩记录与统计将一并删除。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('删除')),
                  ],
                ),
              );
              if (ok != true) return;
              final repo = AppServices.I.repo;
              for (final id in selected) {
                await repo.deleteGame(id);
              }
              ref.read(libraryVersionProvider.notifier).state++;
              showNotice(ref, '已删除 $n 部游戏');
              onDone();
            },
            child: const Text('删除'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: onDone, child: const Text('完成')),
        ],
      ),
    );
  }
}
