/// 页面定位悬浮窗 (Floating Anchor Navigator).
///
/// 用于较长页面（如编辑信息页、探索百科页、作品规格页等）快速定位与段落跳转：
/// 1. **右侧微悬浮**：默认悬浮于页面右侧，支持在「展开导航栏」与「收起小胶囊」间平滑切换；
/// 2. **自动滚动与高亮**：点击条目平滑滚动至目标锚点（带物理减速曲线 `Motion.enter`）；
///    根据页面当前滚动位置，自动高亮当前所在章节；
/// 3. **极简半透明磨砂材质**：采用 `KisakiColors` 与光学校准排版，与桌面应用整体设计语言高度统一。
library;

import 'package:flutter/material.dart';

import '../design.dart';
import '../theme.dart';

class AnchorSectionItem {
  final String id;
  final String label;
  final IconData icon;
  final GlobalKey key;

  const AnchorSectionItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.key,
  });
}

class FloatingAnchorNav extends StatefulWidget {
  final ScrollController scrollController;
  final List<AnchorSectionItem> items;
  final bool initialExpanded;

  const FloatingAnchorNav({
    super.key,
    required this.scrollController,
    required this.items,
    this.initialExpanded = false,
  });

  @override
  State<FloatingAnchorNav> createState() => _FloatingAnchorNavState();
}

class _FloatingAnchorNavState extends State<FloatingAnchorNav> {
  late bool _expanded;
  String _activeId = '';

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
    if (widget.items.isNotEmpty) {
      _activeId = widget.items.first.id;
    }
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || widget.items.isEmpty) return;
    // 遍历锚点 context 寻找视口内最近的章节
    String bestId = widget.items.first.id;
    double minDistance = double.infinity;

    for (final item in widget.items) {
      final ctx = item.key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero);
      final dist = (pos.dy - 120).abs();
      if (pos.dy <= 300 && dist < minDistance) {
        minDistance = dist;
        bestId = item.id;
      }
    }

    if (bestId != _activeId) {
      setState(() {
        _activeId = bestId;
      });
    }
  }

  void _scrollTo(AnchorSectionItem item) {
    final ctx = item.key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Motion.enter,
        alignment: 0.06,
      );
    }
    setState(() {
      _activeId = item.id;
    });
  }

  void _scrollTop() {
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Motion.enter,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cyanInk = KisakiColors.temporalInk(dark);

    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.enter,
      decoration: BoxDecoration(
        color: (dark ? KisakiColors.nightCard : Colors.white)
            .withValues(alpha: dark ? 0.92 : 0.96),
        borderRadius: BorderRadius.circular(_expanded ? Radii.md : Radii.full),
        border: Border.all(
          color: Elev.border(dark),
          width: 1,
        ),
        boxShadow: Elev.overlay(dark),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_expanded ? Radii.md : Radii.full),
        child: AnimatedSize(
          duration: Motion.normal,
          curve: Motion.enter,
          alignment: Alignment.topRight,
          child: _expanded ? _buildExpanded(context, dark, scheme, cyanInk) : _buildCollapsed(context, dark, scheme),
        ),
      ),
    );
  }

  Widget _buildCollapsed(BuildContext context, bool dark, ColorScheme scheme) {
    return FluidPressable(
      onTap: () => setState(() => _expanded = true),
      scaleFactor: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.format_list_bulleted_rounded,
              size: 15,
              color: scheme.primary,
            ),
            const SizedBox(width: 5),
            Text(
              '定位',
              style: Type.micro.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(
    BuildContext context,
    bool dark,
    ColorScheme scheme,
    Color cyanInk,
  ) {
    return Container(
      width: 156,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 悬浮窗标题栏与收起按钮
          Row(
            children: [
              const SizedBox(width: 4),
              Icon(
                Icons.near_me_rounded,
                size: 13,
                color: scheme.primary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '项目定位',
                  style: Type.micro.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              FluidPressable(
                onTap: _scrollTop,
                scaleFactor: 0.92,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              FluidPressable(
                onTap: () => setState(() => _expanded = false),
                scaleFactor: 0.92,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(height: 1, thickness: 1, color: Elev.border(dark)),
          const SizedBox(height: 4),

          // 锚点列表
          for (final item in widget.items) ...[
            _AnchorRowTile(
              item: item,
              active: item.id == _activeId,
              onTap: () => _scrollTo(item),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnchorRowTile extends StatelessWidget {
  final AnchorSectionItem item;
  final bool active;
  final VoidCallback onTap;

  const _AnchorRowTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return FluidPressable(
      onTap: onTap,
      scaleFactor: 0.96,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.enter,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: dark ? 0.20 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: dark ? 0.45 : 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 13.5,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.caption.copyWith(
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active ? scheme.primary : scheme.onSurface,
                  fontSize: 11.5,
                ),
              ),
            ),
            if (active)
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
