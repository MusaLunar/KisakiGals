/// 共享筛选边栏（游戏库 / 探索页共用）。
///
/// 为什么抽出来：游戏库右侧的筛选栏（排序 / 状态 / 收藏 / 来源 / 开发商 /
/// 标签）与探索页的筛选条件（来源 / 排序 / 评分 / 年份 / 标签 / R18）本质是
/// 同一种东西——「一列分组条件 + 置顶的清除操作」。此前游戏库是常驻侧栏、
/// 探索页是弹窗，同一个应用里同一种交互有两套长相。这里把**外壳与排版**
/// 统一：宽度、KCard 底色/描边/硬阴影、内边距、常驻滚动条、分组之间的
/// Divider 分隔、置顶的「清除全部筛选」。
///
/// 分组内容由调用方用 [FilterSection] 描述（内部统一 KChip 换行排版），
/// 因此新增一组条件只是多传一个 [FilterSection]，不需要再写一遍排版。
library;

import 'package:flutter/material.dart';

import '../design.dart';
import '../kit.dart';

/// 筛选边栏的标准宽度（234，两处页面共用；过窄会把「清除全部筛选」挤到换行）。
const double kFilterSidebarWidth = 234;

/// 筛选边栏外壳。
///
/// 用法参考 `library_page.dart` 与 `discover_page.dart`：
/// ```dart
/// FilterSidebar(
///   leading: filter.hasActive ? FilterClearButton(onTap: _clearAll) : null,
///   sections: [FilterSection(title: '排序', children: [...])],
/// )
/// ```
class FilterSidebar extends StatefulWidget {
  /// 可选顶部标题（一般不用：页面标题已经说明了这是筛选栏）
  final String? title;

  /// 置顶操作（通常传 [FilterClearButton]，仅在筛选生效时显示）
  final Widget? leading;

  /// 各分组（用 [FilterSection] 描述），分组之间自动插入 Divider
  final List<Widget> sections;

  /// 宽度（默认 [kFilterSidebarWidth]；超窄窗口下页面自行收窄）
  final double width;

  const FilterSidebar({
    super.key,
    this.title,
    this.leading,
    this.sections = const [],
    this.width = kFilterSidebarWidth,
  });

  @override
  State<FilterSidebar> createState() => _FilterSidebarState();
}

class _FilterSidebarState extends State<FilterSidebar> {
  /// 自己的 controller：常驻滚动条（thumbVisibility）要求 Scrollbar 与
  /// 滚动视图绑同一个 controller，否则 Flutter 直接抛断言。
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 装配顺序：标题 → 置顶操作（后接一档间距）→ 各分组（之间插 Divider）。
  /// 置顶操作后用的是间距而不是 Divider：它不是一个「条件分组」，
  /// 用分隔线会和下面的分组混在一起（游戏库原来就是这个节奏）。
  List<Widget> _children() {
    final out = <Widget>[];
    if (widget.title != null) out.add(KSectionTitle(widget.title!));
    if (widget.leading != null) {
      out
        ..add(widget.leading!)
        ..add(const SizedBox(height: Gap.md));
    }
    for (var i = 0; i < widget.sections.length; i++) {
      if (i > 0) out.add(const Divider(height: Gap.xxl));
      out.add(widget.sections[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: KCard(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.lg),
        child: Scrollbar(
          controller: _scroll,
          // 常驻滚动条：条件多到超出高度时，桌面端默认要滚一下才出现滚动条，
          // 用户不知道下面还有条件。
          thumbVisibility: true,
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.zero,
            children: _children(),
          ),
        ),
      ),
    );
  }
}

/// 「清除全部筛选」置顶按钮：两处的文案/图标/样式保持一致。
class FilterClearButton extends StatelessWidget {
  final VoidCallback onTap;
  const FilterClearButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => KPill(
        label: '清除全部筛选',
        icon: Icons.filter_alt_off_rounded,
        filled: false,
        onTap: onTap,
      );
}

/// 筛选分组：KSectionTitle 标题 + 一组自动换行的 KChip（+ 可选补充内容）。
class FilterSection extends StatelessWidget {
  final String title;

  /// 标题右侧的补充操作（例如标签组的「更多 / 收起」）
  final Widget? trailing;

  /// 分组内的控件，通常是若干 `KChip`：由本组件统一放进 Wrap 里换行，
  /// 间距与游戏库原实现一致（横向/纵向都是 6）。
  final List<Widget> children;

  /// chip 组**之前**的自定义控件（例如标签组的「过滤标签」输入框）。
  /// 它会被直接放进 Column，必须是能自行确定宽度的控件。
  final Widget? above;

  /// 需要自定义排版时追加在 [children] 之下（例如年份的手填区间输入行）。
  /// 同上：会被直接放进 Column，必须是能自行确定宽度的控件。
  final Widget? child;

  /// 标题下方的补充说明（例如「Bangumi 不支持标签筛选」的能力提示）
  final String? hint;

  const FilterSection({
    super.key,
    required this.title,
    this.trailing,
    this.children = const [],
    this.above,
    this.child,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KSectionTitle(title, trailing: trailing),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child:
                Text(hint!, style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
          ),
        if (above != null) ...[
          above!,
          if (children.isNotEmpty || child != null)
            const SizedBox(height: Gap.sm),
        ],
        if (children.isNotEmpty)
          Wrap(
            spacing: Gap.xs + 2,
            runSpacing: Gap.xs + 2,
            children: children,
          ),
        if (child != null) ...[
          if (children.isNotEmpty) const SizedBox(height: Gap.sm),
          child!,
        ],
      ],
    );
  }
}
