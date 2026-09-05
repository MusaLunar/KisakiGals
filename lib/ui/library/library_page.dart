/// 游戏库：自适应网格 + 筛选 + 搜索 + 排序。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../add/add_game_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'game_card.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final games = ref.watch(gamesProvider);
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <TagItem>[];
    final devs = ref.watch(developersProvider).valueOrNull ?? const <String>[];
    final sources = ref.watch(usedSourcesProvider).valueOrNull ?? const <String>[];
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          // 顶栏
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
                width: 260,
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
              // 排序
              PopupMenuButton<GameSort>(
                tooltip: '排序',
                onSelected: (s) {
                  ref.read(libraryFilterProvider).sort = s;
                  ref.read(libraryVersionProvider.notifier).state++;
                },
                icon: const Icon(Icons.sort_rounded),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                itemBuilder: (_) => GameSort.values
                    .map((s) => PopupMenuItem(
                        value: s,
                        child: Row(
                          children: [
                            if (filter.sort == s)
                              const Icon(Icons.check_rounded, size: 18)
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 6),
                            Text(s.label),
                          ],
                        )))
                    .toList(),
              ),
              const SizedBox(width: 6),
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
          // 筛选栏
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // 状态
                for (final s in PlayStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.label),
                      selected: filter.status == s,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (sel) {
                        ref.read(libraryFilterProvider).status = sel ? s : null;
                        ref.read(libraryVersionProvider.notifier).state++;
                      },
                    ),
                  ),
                if (sources.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  for (final src in sources)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SourceBadgeSelectable(
                        source: src,
                        selected: filter.source == src,
                        onTap: () {
                          final f = ref.read(libraryFilterProvider);
                          f.source = f.source == src ? null : src;
                          ref.read(libraryVersionProvider.notifier).state++;
                        },
                      ),
                    ),
                ],
                // 收藏
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('收藏'),
                    selected: filter.favoriteOnly,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      filter.favoriteOnly
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 15,
                      color: KisakiColors.pink,
                    ),
                    onSelected: (sel) {
                      ref.read(libraryFilterProvider).favoriteOnly = sel;
                      ref.read(libraryVersionProvider.notifier).state++;
                    },
                  ),
                ),
                // 标签
                for (final t in tags.take(14))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(t.name),
                      selected: filter.tag == t.name,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (sel) {
                        ref.read(libraryFilterProvider).tag = sel ? t.name : null;
                        ref.read(libraryVersionProvider.notifier).state++;
                      },
                    ),
                  ),
                // 开发商
                if (devs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PopupMenuButton<String>(
                      tooltip: '开发商',
                      onSelected: (d) {
                        final f = ref.read(libraryFilterProvider);
                        f.developer = f.developer == d ? null : d;
                        ref.read(libraryVersionProvider.notifier).state++;
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: '', child: Text('全部开发商')),
                        ...devs.map((d) => PopupMenuItem(value: d, child: Text(d))),
                      ],
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black12),
                          color: filter.developer != null
                              ? (dark
                                  ? KisakiColors.lavender.withValues(alpha: 0.25)
                                  : KisakiColors.lavenderContainer)
                              : Colors.transparent,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(filter.developer ?? '开发商',
                                style: const TextStyle(fontSize: 12.5)),
                            const Icon(Icons.expand_more_rounded, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 清除
                if (filter.hasActive)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.close_rounded, size: 15),
                      label: const Text('清除筛选'),
                      onPressed: () {
                        final f = ref.read(libraryFilterProvider);
                        f.status = null;
                        f.tag = null;
                        f.developer = null;
                        f.source = null;
                        f.favoriteOnly = false;
                        f.query = '';
                        ref.read(libraryVersionProvider.notifier).state++;
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 网格
          Expanded(
            child: games.when(
              data: (list) => list.isEmpty
                  ? EmptyState(
                      title: '游戏库还是空的',
                      subtitle: '点击右上角「添加游戏」，或直接把游戏 exe 拖进来',
                      action: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AddGamePage())),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('添加第一款游戏'),
                      ),
                    )
                  : LayoutBuilder(builder: (context, constraints) {
                      const spacing = 18.0;
                      final count =
                          (constraints.maxWidth / 172).floor().clamp(2, 10);
                      return GridView(
                        padding: const EdgeInsets.only(bottom: 20, top: 4),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: 0.52,
                        ),
                        children: [
                          for (final g in list) GameCard(game: g),
                        ],
                      );
                    }),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(title: '加载失败', subtitle: '$e'),
            ),
          ),
        ],
      ),
    );
  }

  static void _debouncedRefresh(WidgetRef ref) {
    // 简易防抖：200ms 后刷新
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      ref.read(libraryVersionProvider.notifier).state++;
    });
  }
}

Timer? _searchTimer;

/// 可选中的来源徽标。
class SourceBadgeSelectable extends StatelessWidget {
  final String source;
  final bool selected;
  final VoidCallback onTap;
  const SourceBadgeSelectable(
      {super.key, required this.source, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? (dark
                  ? KisakiColors.pink.withValues(alpha: 0.25)
                  : KisakiColors.pinkContainer)
              : Colors.transparent,
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          source == 'custom' ? '自定义' : KisakiSources.labels[source] ?? source,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : null,
          ),
        ),
      ),
    );
  }
}
