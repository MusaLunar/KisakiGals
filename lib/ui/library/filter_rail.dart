/// Fluent 2 游戏库可折叠右侧筛选栏（状态计数 / 收藏 / 开发商 / 来源 / 标签）。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';

const double kFilterRailWidth = 256.0;

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

  int _activeCount(LibraryFilter f) {
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
    ref.watch(libraryVersionProvider);
    final filter = ref.watch(libraryFilterProvider);
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final disableAnim = fluentAnimationsDisabled(context);

    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <TagItem>[];
    final devs = ref.watch(developersProvider).valueOrNull ?? const <String>[];
    final sources =
        ref.watch(usedSourcesProvider).valueOrNull ?? const <String>[];
    final allGames =
        ref.watch(allGamesProvider).valueOrNull ?? const <Game>[];

    final statusCounts = <PlayStatus, int>{
      for (final s in PlayStatus.values) s: 0,
    };
    for (final g in allGames) {
      statusCounts[g.playStatus] = (statusCounts[g.playStatus] ?? 0) + 1;
    }

    final devItems = <String>[
      ...devs,
      if (filter.developer != null &&
          filter.developer!.isNotEmpty &&
          !devs.contains(filter.developer))
        filter.developer!,
    ];
    final sourceItems = <String>[
      ...sources,
      if (filter.source != null &&
          filter.source!.isNotEmpty &&
          !sources.contains(filter.source))
        filter.source!,
    ];

    final currentDev = filter.developer ?? '';
    final currentSource = filter.source ?? '';
    final activeN = _activeCount(filter);

    final body = widget.visible
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
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '筛选条件',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.typography.bodyStrong,
                                ),
                              ),
                              if (activeN > 0) ...[
                                const SizedBox(width: 6),
                                FluentBadge(
                                  text: '$activeN',
                                  foreground: theme.onAccentInk,
                                  background: accent,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Button(
                          onPressed: filter.hasActive ? _clearFilters : null,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FluentIcons.filter_dismiss_16_regular,
                                size: 13,
                              ),
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
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '游玩状态',
                                style: theme.typography.caption?.copyWith(
                                  color: theme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _StatusSegmentItem(
                                label: '全部',
                                count: allGames.isEmpty ? null : allGames.length,
                                selected: filter.status == null,
                                accent: accent,
                                onTap: () {
                                  filter.status = null;
                                  _apply();
                                },
                              ),
                              for (final status in PlayStatus.values)
                                _StatusSegmentItem(
                                  label: status.label,
                                  count: allGames.isEmpty
                                      ? null
                                      : (statusCounts[status] ?? 0),
                                  selected: filter.status == status,
                                  accent: accent,
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
                                  color: theme.textSecondary,
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
                                  for (final d in devItems)
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
                                  color: theme.textSecondary,
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
                                  for (final src in sourceItems)
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
                                    color: theme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                FluentSearchBox(
                                  controller: _tagSearchCtrl,
                                  compact: true,
                                  placeholder: '过滤标签…',
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 8),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _tagSearchCtrl,
                                  builder: (context, val, _) {
                                    final q = val.text.trim().toLowerCase();
                                    final filtered = q.isEmpty
                                        ? tags
                                        : tags
                                            .where((t) =>
                                                t.name.toLowerCase().contains(q))
                                            .toList();
                                    if (filtered.isEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Text(
                                          '未找到匹配标签',
                                          style: theme.typography.caption
                                              ?.copyWith(
                                            color: theme.textTertiary,
                                          ),
                                        ),
                                      );
                                    }
                                    return Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final t in filtered)
                                          FluentBadge(
                                            icon: FluentIcons.tag_16_regular,
                                            text: t.name,
                                            selected: filter.tag == t.name,
                                            foreground: filter.tag == t.name
                                                ? theme.onAccentInk
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
                                    );
                                  },
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
        : const SizedBox.shrink();
    if (disableAnim) return body;
    return AnimatedSize(
      duration: FluentMotion.standard,
      curve: FluentMotion.enterCurve,
      alignment: Alignment.topRight,
      child: body,
    );
  }
}

class _StatusSegmentItem extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _StatusSegmentItem({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.count,
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
        cursor: SystemMouseCursors.click,
        onPressed: onTap,
        builder: (context, states) {
          final bg = selected
              ? accent.withValues(alpha: theme.isDark ? 0.20 : 0.12)
              : states.isPressed
                  ? theme.subtlePressed
                  : states.isHovered
                      ? theme.subtleHover
                      : Colors.transparent;

          return FocusBorder(
            focused: states.isFocused,
            renderOutside: false,
            child: AnimatedContainer(
              duration: disableAnim ? Duration.zero : FluentMotion.fast,
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: disableAnim ? Duration.zero : FluentMotion.fast,
                    width: 3,
                    height: selected ? 14 : 0,
                    decoration: BoxDecoration(
                      color: selected ? accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.typography.body?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? theme.textPrimary : theme.textSecondary,
                      ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      '$count',
                      style: theme.typography.caption?.copyWith(
                        color: selected ? accent : theme.textTertiary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
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
