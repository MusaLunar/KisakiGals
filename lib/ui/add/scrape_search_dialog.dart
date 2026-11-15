/// Fluent 2 刮削搜索与重新匹配元数据对话框。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';

/// 打开刮削搜索对话框为 [game] 匹配并应用多源元数据，成功应用返回 true，否则 false。
Future<bool> showScrapeSearchDialog(
  BuildContext context,
  WidgetRef ref,
  Game game, {
  String? initialQuery,
  Future<List<ScrapeHitGroup>> Function(String query, List<String> only)?
      onSearch,
  Future<List<ScrapedGame>> Function(ScrapeHitGroup group)? onMergeGroup,
  Future<void> Function(Game game, List<ScrapedGame> all)? onApply,
}) async {
  final applied = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ScrapeSearchDialog(
      ref: ref,
      game: game,
      initialQuery: initialQuery ??
          (game.displayName.isNotEmpty ? game.displayName : game.name),
      onSearch: onSearch,
      onMergeGroup: onMergeGroup,
      onApply: onApply,
    ),
  );
  return applied == true;
}

class _ScrapeSearchDialog extends StatefulWidget {
  final WidgetRef ref;
  final Game game;
  final String initialQuery;
  final Future<List<ScrapeHitGroup>> Function(String query, List<String> only)?
      onSearch;
  final Future<List<ScrapedGame>> Function(ScrapeHitGroup group)? onMergeGroup;
  final Future<void> Function(Game game, List<ScrapedGame> all)? onApply;

  const _ScrapeSearchDialog({
    required this.ref,
    required this.game,
    required this.initialQuery,
    this.onSearch,
    this.onMergeGroup,
    this.onApply,
  });

  @override
  State<_ScrapeSearchDialog> createState() => _ScrapeSearchDialogState();
}

class _ScrapeSearchDialogState extends State<_ScrapeSearchDialog> {
  late final TextEditingController _queryCtrl =
      TextEditingController(text: widget.initialQuery);
  final Set<String> _selectedSources = {...KisakiSources.defaultEnabled};

  bool _searching = false;
  bool _applying = false;
  bool _hasSearched = false;
  List<ScrapeHitGroup> _groups = const [];

  static Iterable<MapEntry<String, String>> get _filterableSources =>
      KisakiSources.labels.entries
          .where((e) => e.key != KisakiSources.custom);

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _toggleSource(String sourceId, bool checked) {
    setState(() {
      if (checked) {
        _selectedSources.add(sourceId);
      } else {
        _selectedSources.remove(sourceId);
      }
    });
  }

  Future<void> _search() async {
    final kw = _queryCtrl.text.trim();
    if (kw.isEmpty) {
      showNotice('请输入搜索关键词', error: true);
      return;
    }
    if (_selectedSources.isEmpty) {
      showNotice('请至少选择一个数据源', error: true);
      return;
    }
    setState(() {
      _searching = true;
      _hasSearched = true;
    });
    try {
      final only = _selectedSources.toList();
      final groups = widget.onSearch != null
          ? await widget.onSearch!(kw, only)
          : await AppServices.I.fetcher.searchGrouped(kw, only: only);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _searching = false;
      });
      showNotice('搜索失败：$e', error: true);
    }
  }

  Future<void> _applyGroup(ScrapeHitGroup group) async {
    setState(() => _applying = true);
    try {
      List<ScrapedGame> all;
      try {
        all = widget.onMergeGroup != null
            ? await widget.onMergeGroup!(group)
            : await AppServices.I.fetcher.mergeGroup(group);
      } catch (_) {
        all = [group.merged, ...group.members.skip(1)];
      }
      if (widget.onApply != null) {
        await widget.onApply!(widget.game, all);
      } else {
        await ScrapeApplier(AppServices.I.repo, AppServices.I.fetcher)
            .apply(widget.game, all);
      }
      bumpLibrary(widget.ref);
      showNotice('已重新刮削：${all.first.displayName}（${all.length} 个数据源）');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      showNotice('应用元数据失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final busy = _searching || _applying;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 780, maxHeight: 680),
      title: Row(
        children: [
          const Icon(FluentIcons.search_20_regular, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '刮削元数据 · ${widget.game.displayName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 732,
        height: 510,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _queryCtrl,
                    enabled: !busy,
                    placeholder: '输入游戏名称（中文名 / 原名 / 别名均可）',
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _search,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.search_20_regular, size: 16),
                      SizedBox(width: 6),
                      Text('搜索'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in _filterableSources)
                  ToggleButton(
                    checked: _selectedSources.contains(entry.key),
                    onChanged:
                        busy ? null : (v) => _toggleSource(entry.key, v),
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _applying ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildBody(FluentThemeData theme) {
    if (_searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(),
            SizedBox(height: 12),
            Text('正在从多个数据源搜索…'),
          ],
        ),
      );
    }
    if (_applying) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(),
            SizedBox(height: 12),
            Text('正在整合元数据并应用到当前作品…'),
          ],
        ),
      );
    }
    if (!_hasSearched) {
      return const FluentEmptyState(
        icon: FluentIcons.search_24_regular,
        title: '输入关键词并搜索',
        message: '可按需筛选上方数据源，点击「搜索」获取跨平台分组候选',
      );
    }
    if (_groups.isEmpty) {
      return const FluentEmptyState(
        icon: FluentIcons.search_24_regular,
        title: '没有找到匹配的作品',
        message: '试试更换中文名、原名，或勾选更多数据源后再次搜索',
      );
    }

    return ListView.separated(
      itemCount: _groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final group = _groups[index];
        return _ScrapeGroupExpander(
          group: group,
          initiallyExpanded: index == 0,
          applying: _applying,
          onApply: () => _applyGroup(group),
        );
      },
    );
  }
}

class _ScrapeGroupExpander extends StatelessWidget {
  final ScrapeHitGroup group;
  final bool initiallyExpanded;
  final bool applying;
  final VoidCallback onApply;

  const _ScrapeGroupExpander({
    required this.group,
    required this.initiallyExpanded,
    required this.applying,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final g = group.merged;
    final scoreText = g.rating > 0 ? g.rating.toStringAsFixed(1) : null;
    final voteText = g.voteCount > 0 ? '${g.voteCount} 票' : null;

    return Expander(
      initiallyExpanded: initiallyExpanded,
      leading: FluentCoverImage(
        pathOrUrl: g.coverUrl,
        nsfw: g.nsfw,
        width: 36,
        height: 52,
        radius: 4,
        allowRevealOnHover: false,
      ),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 4),
          FluentR18ScoreRow(
            nsfw: g.nsfw,
            scoreText: scoreText,
            voteText: voteText,
            trailing: [
              for (final s in group.sources)
                FluentBadge(text: KisakiSources.labels[s] ?? s),
              if (g.releaseDate.isNotEmpty) FluentBadge(text: g.releaseDate),
            ],
          ),
        ],
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentCoverImage(
            pathOrUrl: g.coverUrl,
            nsfw: g.nsfw,
            width: 84,
            height: 120,
            radius: 6,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (g.name.isNotEmpty && g.name != g.displayName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '原名：${g.name}',
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                    ),
                  ),
                if (g.developer.isNotEmpty || g.releaseDate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      [
                        if (g.developer.isNotEmpty) '开发商：${g.developer}',
                        if (g.releaseDate.isNotEmpty) '发售：${g.releaseDate}',
                      ].join(' · '),
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                    ),
                  ),
                if (g.summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      g.summary,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body,
                    ),
                  ),
                if (g.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in g.tags.take(8))
                          FluentBadge(text: '#${t.name}'),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: applying ? null : onApply,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.arrow_download_20_regular, size: 16),
                        SizedBox(width: 6),
                        Text('应用到当前作品'),
                      ],
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
}
