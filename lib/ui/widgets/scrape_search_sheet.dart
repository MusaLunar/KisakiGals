/// 刮削搜索选择器：关键词 → 分组结果（多源徽章）→ 选中 → 多源合并。
/// 返回 mergeGroup 结果（[0]=合并数据，其余为各源成员），取消返回 null。
///
/// 视觉全部走 kit：弹层本体是 `KCard(overlayShadow: true)`（顶部大圆角 +
/// 浮层重投影），进度态用 KLoading、空态用 KEmpty、按钮用 KPill、
/// 标题栏图标按钮用 KIconAction；结果条目 [ScrapeGroupTile] 由 KCard 承载
/// （hover 上浮 + 柔光阴影 + 1px 描边），不再有裸 Container / InkWell。
library;

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../scraping/scraped_game.dart';
import '../design.dart';
import '../kit.dart';
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
    // 底色透明：浮层外观（圆角 / 描边 / 阴影）全部交给内嵌的 KCard
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

  /// 结果列表滚动控制器（桌面端显示常驻滚动条）
  final ScrollController _listCtrl = ScrollController();
  _Stage _stage = _Stage.input;
  List<ScrapeHitGroup> _groups = const [];
  String _searchedKw = '';

  @override
  void dispose() {
    _query.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 输入法弹起时上抬（桌面端通常为 0，保留以兼容触摸屏）
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: KCard(
        overlayShadow: true,
        padding: EdgeInsets.zero,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: switch (_stage) {
            _Stage.input => _input(context),
            _Stage.searching => _loading(context, '正在从多个数据源搜刮…'),
            _Stage.choose => _choose(context),
            _Stage.merging => _loading(context, '正在整合所有数据源的元数据…'),
          },
        ),
      ),
    );
  }

  /// 进度态：KLoading + Type 文案（外层 Center 撑满弹层高度，与旧版一致）。
  Widget _loading(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // KLoading 内部是 Center：必须给定尺寸，否则会在宽松约束下撑满
          const SizedBox(width: 28, height: 28, child: KLoading(size: 28)),
          const SizedBox(height: Gap.lg),
          Text(message,
              textAlign: TextAlign.center,
              style: Type.body.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _input(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Gap.pageH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('刮削元数据', style: Type.title),
              const Spacer(),
              KIconAction(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  onTap: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: Gap.lg),
          TextField(
            controller: _query,
            autofocus: true,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
                labelText: '游戏名称（中文名 / 原名 / 别名均可）'),
          ),
          const SizedBox(height: Gap.lg),
          KPill(
              label: '开始搜刮',
              icon: Icons.travel_explore_rounded,
              onTap: _search),
          const SizedBox(height: Gap.sm),
        ],
      ),
    );
  }

  Widget _choose(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, 0),
      child: Column(
        children: [
          Row(
            children: [
              // Expanded + 省略号：关键词很长时不再溢出（旧版 Spacer 会溢出）
              Expanded(
                child: Text('「$_searchedKw」的搜索结果（${_groups.length}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.section),
              ),
              KIconAction(
                  icon: Icons.edit_rounded,
                  tooltip: '修改关键词',
                  onTap: () => setState(() => _stage = _Stage.input)),
              KIconAction(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  onTap: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: Gap.sm + 2),
          Expanded(
            child: _groups.isEmpty
                ? const KEmpty(
                    icon: Icons.search_off_rounded,
                    title: '没有找到匹配的游戏',
                    subtitle: '试试更换名称或数据源',
                  )
                : Scrollbar(
                    controller: _listCtrl,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _listCtrl,
                      padding: const EdgeInsets.only(bottom: Gap.xl),
                      itemCount: _groups.length,
                      itemBuilder: (context, i) => ScrapeGroupTile(
                        group: _groups[i],
                        onPick: () => _merge(_groups[i]),
                      ),
                    ),
                  ),
          ),
          if (_groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Text('选择一条以整合各平台元数据（简介 / 标签 / 评分 / 图片）',
                  style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
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

/// 分组结果条目：多源徽章 + 名称 + 评分/日期。
///
/// 结构走 [KCard]（点击卡片 = 选中该分组，hover 上浮 + 柔光阴影），
/// 封面用 common.dart 的 CoverImage，来源徽章沿用 SourceBadge
/// （与添加页 / 详情页的来源展示保持同一套配色）。
/// 注意：本组件同时被添加页的网格复用，行高与网格单元匹配（封面 64 高）。
class ScrapeGroupTile extends StatelessWidget {
  final ScrapeHitGroup group;
  final VoidCallback onPick;
  const ScrapeGroupTile({super.key, required this.group, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final g = group.merged;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // 条目间距留在组件内：列表与网格两种宿主都能拿到一致的呼吸感
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: KCard(
        onTap: onPick,
        borderRadius: BorderRadius.circular(Radii.md),
        padding: const EdgeInsets.all(Gap.sm + 2),
        // 比纯白卡再暖一档：让结果条目在弹层白卡上仍能一眼分辨
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: dark ? 0.07 : 0.035),
          dark ? KisakiColors.nightCard : Colors.white,
        ),
        child: Row(
          children: [
            CoverImage(
              path: '',
              networkUrl: g.coverUrl,
              nsfw: g.nsfw,
              width: 46,
              height: 64,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: dark
                              ? KisakiColors.nightInk
                              : KisakiColors.ink)),
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: 5,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final s in group.sources) SourceBadge(source: s),
                      if (g.rating > 0)
                        Text('${g.rating.toStringAsFixed(1)} · ${g.voteCount} 评',
                            style: Type.micro
                                .copyWith(color: scheme.onSurfaceVariant)),
                      if (g.releaseDate.isNotEmpty)
                        Text(g.releaseDate,
                            style: Type.micro
                                .copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
