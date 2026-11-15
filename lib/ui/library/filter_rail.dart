/// Fluent 2 游戏库可折叠右侧筛选栏（状态 / 收藏 / 开发商 / 来源 / 标签）。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_surfaces.dart';

const double kFilterRailWidth = 250.0;

class FilterRail extends ConsumerStatefulWidget {
  final bool visible;
  final double width;
  final VoidCallback? onClear;

  const FilterRail({
    super.key,
    this.visible = true,
    this.width = kFilterRailWidth,
    this.onClear,
  });

  @override
  ConsumerState<FilterRail> createState() => _FilterRailState();
}

class _FilterRailState extends ConsumerState<FilterRail> {
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _tagSearchCtrl = TextEditingController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _tagSearchCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    bumpLibrary(ref);
    setState(() {});
  }

  void _clearFilters() {
    if (widget.onClear != null) {
      widget.onClear!.call();
      _tagSearchCtrl.clear();
      setState(() {});
      return;
    }
    final f = ref.read(libraryFilterProvider);
    f
      ..status = null
      ..tag = null
      ..developer = null
      ..source = null
      ..favoriteOnly = false
      ..query = '';
    _tagSearchCtrl.clear();
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(libraryVersionProvider);
    final filter = ref.watch(libraryFilterProvider);
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final isDark = theme.brightness == Brightness.dark;

    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <TagItem>[];
    final devs = ref.watch(developersProvider).valueOrNull ?? const <String>[];
    final sources =
        ref.watch(usedSourcesProvider).valueOrNull ?? const <String>[];

    final tagQuery = _tagSearchCtrl.text.trim().toLowerCase();
    final filteredTags = tagQuery.isEmpty
        ? tags
        : tags
            .where((t) => t.name.toLowerCase().contains(tagQuery))
            .toList();

    final currentDev =
        (filter.developer != null && devs.contains(filter.developer))
            ? filter.developer!
            : '';
    final currentSource =
        (filter.source != null && sources.contains(filter.source))
            ? filter.source!
            : '';

    return AnimatedSize(
      duration: FluentMotion.standard,
      curve: FluentMotion.enterCurve,
      alignment: Alignment.topRight,
      child: widget.visible
          ? SizedBox(
              width: widget.width,
              child: FluentSurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FluentIcons.filter_16_regular,
                          size: 16,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '筛选条件',
                            style: theme.typography.bodyStrong,
                          ),
                        ),
                        Button(
                          onPressed: filter.hasActive ? _clearFilters : null,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.filter_dismiss_16_regular,
                                  size: 13),
                              SizedBox(width: 4),
                              Text('清除筛选'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollCtrl,
                        child: SingleChildScrollView(
                          controller: _scrollCtrl,
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            Text(
                              '游玩状态',
                              style: theme.typography.caption?.copyWith(
                                color: theme.inactiveColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _StatusSegmentItem(
                              label: '全部',
                              selected: filter.status == null,
                              accent: accent,
                              isDark: isDark,
                              onTap: () {
                                filter.status = null;
                                _apply();
                              },
                            ),
                            for (final status in PlayStatus.values)
                              _StatusSegmentItem(
                                label: status.label,
                                selected: filter.status == status,
                                accent: accent,
                                isDark: isDark,
                                onTap: () {
                                  filter.status =
                                      filter.status == status ? null : status;
                                  _apply();
                                },
                              ),
                            const SizedBox(height: 8),
                            const Divider(),
                            const SizedBox(height: 8),
                            ToggleSwitch(
                              checked: filter.favoriteOnly,
                              content: const Text('仅看收藏'),
                              onChanged: (v) {
                                filter.favoriteOnly = v;
                                _apply();
                              },
                            ),
                            const SizedBox(height: 8),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              '开发商',
                              style: theme.typography.caption?.copyWith(
                                color: theme.inactiveColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ComboBox<String>(
                              isExpanded: true,
                              value: currentDev,
                              items: [
                                const ComboBoxItem<String>(
                                  value: '',
                                  child: Text('全部开发商'),
                                ),
                                for (final d in devs)
                                  ComboBoxItem<String>(
                                    value: d,
                                    child: Text(
                                      d,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                filter.developer =
                                    (v == null || v.isEmpty) ? null : v;
                                _apply();
                              },
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '数据来源',
                              style: theme.typography.caption?.copyWith(
                                color: theme.inactiveColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ComboBox<String>(
                              isExpanded: true,
                              value: currentSource,
                              items: [
                                const ComboBoxItem<String>(
                                  value: '',
                                  child: Text('全部来源'),
                                ),
                                for (final src in sources)
                                  ComboBoxItem<String>(
                                    value: src,
                                    child: Text(
                                      KisakiSources.labels[src] ?? src,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                filter.source =
                                    (v == null || v.isEmpty) ? null : v;
                                _apply();
                              },
                            ),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Divider(),
                              const SizedBox(height: 8),
                              Text(
                                '标签',
                                style: theme.typography.caption?.copyWith(
                                  color: theme.inactiveColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextBox(
                                controller: _tagSearchCtrl,
                                placeholder: '过滤标签…',
                                prefix: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(
                                    FluentIcons.search_16_regular,
                                    size: 14,
                                  ),
                                ),
                                suffix: tagQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          FluentIcons.dismiss_16_regular,
                                          size: 12,
                                        ),
                                        onPressed: () =>
                                            setState(_tagSearchCtrl.clear),
                                      )
                                    : null,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final t in filteredTags)
                                    FluentBadge(
                                      icon: FluentIcons.tag_16_regular,
                                      text: t.name,
                                      foreground: filter.tag == t.name
                                          ? Colors.white
                                          : null,
                                      background: filter.tag == t.name
                                          ? accent
                                          : null,
                                      onTap: () {
                                        filter.tag = filter.tag == t.name
                                            ? null
                                            : t.name;
                                        _apply();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _StatusSegmentItem extends StatefulWidget {
  final String label;
  final bool selected;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _StatusSegmentItem({
    required this.label,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_StatusSegmentItem> createState() => _StatusSegmentItemState();
}

class _StatusSegmentItemState extends State<_StatusSegmentItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bg = widget.selected
        ? widget.accent.withValues(alpha: widget.isDark ? 0.22 : 0.12)
        : (_hovered
            ? (widget.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04))
            : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: FluentMotion.fast,
                width: 3,
                height: widget.selected ? 14 : 0,
                decoration: BoxDecoration(
                  color: widget.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: widget.selected ? 8 : 0),
              Expanded(
                child: Text(
                  widget.label,
                  style: theme.typography.body?.copyWith(
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                    color: widget.selected ? widget.accent : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
