/// 刮削搜索选择器：关键词 → 分组结果（多源徽章）→ 选中 → 多源合并。
/// 返回 mergeGroup 结果（[0]=合并数据，其余为各源成员），取消返回 null。
library;

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../scraping/scraped_game.dart';
import '../theme.dart';
import 'common.dart';

Future<List<ScrapedGame>?> showScrapeSearchSheet(
  BuildContext context, {
  String initialQuery = '',
  List<String>? only,
}) {
  return showModalBottomSheet<List<ScrapedGame>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ScrapeSearchSheet(initialQuery: initialQuery, only: only),
  );
}

enum _Stage { input, searching, choose, merging }

class _ScrapeSearchSheet extends StatefulWidget {
  final String initialQuery;
  final List<String>? only;
  const _ScrapeSearchSheet({required this.initialQuery, this.only});

  @override
  State<_ScrapeSearchSheet> createState() => _ScrapeSearchSheetState();
}

class _ScrapeSearchSheetState extends State<_ScrapeSearchSheet> {
  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);
  _Stage _stage = _Stage.input;
  List<ScrapeHitGroup> _groups = const [];
  String _searchedKw = '';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: dark ? KisakiColors.nightCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: switch (_stage) {
          _Stage.input => _input(context),
          _Stage.searching => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在从多个数据源搜刮…'),
                ]),
              ),
            ),
          _Stage.choose => _choose(context),
          _Stage.merging => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在整合所有数据源的元数据…'),
                ]),
              ),
            ),
        },
      ),
    );
  }

  Widget _input(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('刮削元数据',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _query,
            autofocus: true,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
                labelText: '游戏名称（中文名 / 原名 / 别名均可）'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.travel_explore_rounded),
            label: const Text('开始搜刮'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _choose(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text('「$_searchedKw」的搜索结果（${_groups.length}）',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              IconButton(
                  onPressed: () => setState(() => _stage = _Stage.input),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  tooltip: '修改关键词'),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _groups.isEmpty
                ? EmptyState(
                    title: '没有找到匹配的游戏',
                    subtitle: '试试更换名称或数据源',
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      for (final g in _groups)
                        ScrapeGroupTile(
                          group: g,
                          onPick: () => _merge(g),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _search() async {
    final kw = _query.text.trim();
    if (kw.isEmpty) return;
    setState(() => _stage = _Stage.searching);
    try {
      final groups =
          await AppServices.I.fetcher.searchGrouped(kw, only: widget.only);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _searchedKw = kw;
        _stage = _Stage.choose;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _searchedKw = kw;
        _stage = _Stage.choose;
      });
    }
  }

  Future<void> _merge(ScrapeHitGroup group) async {
    setState(() => _stage = _Stage.merging);
    try {
      final all = await AppServices.I.fetcher.mergeGroup(group);
      if (!mounted) return;
      Navigator.pop(context, all);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context, [group.merged, ...group.members.skip(1)]);
    }
  }
}

/// 分组结果条目：多源徽章 + 名称 + 日期。
class ScrapeGroupTile extends StatelessWidget {
  final ScrapeHitGroup group;
  final VoidCallback onPick;
  const ScrapeGroupTile({super.key, required this.group, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final g = group.merged;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dark ? KisakiColors.nightBg.withValues(alpha: 0.5) : const Color(0xFFFDF6F1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CoverImage(
                  path: '',
                  networkUrl: g.coverUrl,
                  nsfw: g.nsfw,
                  width: 46,
                  height: 64,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13.5)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final s in group.sources)
                            SourceBadge(source: s),
                          if (g.rating > 0)
                            Text(
                                '${g.rating.toStringAsFixed(1)} · ${g.voteCount} 评',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          if (g.releaseDate.isNotEmpty)
                            Text(g.releaseDate,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
