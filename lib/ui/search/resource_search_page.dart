/// 资源搜索：聚合多个资源站搜索发布页，支持「打开下载页」与「入库」。
///
/// 参考 Moe-Sakura/SearchGal：不解析直链、不托管资源，只给出发布页链接；
/// 入库则复用既有的「添加游戏 → 搜刮」流程，用资源标题作为关键词自动补全元数据。
///
/// **信息架构变更**：本文件原先是独立的「资源搜索」页（侧栏第 4 项），现在
/// 侧栏只剩「探索」一项，资源搜索成为探索页里的**「资源」模式**。因此这里
/// 只导出可嵌入的 [ResourceSearchPane]（结果区）与它的会话
/// [ResourceSearchSession]：
/// - 页面外壳（KPage 标题区、KToolbar 工具条、关键词输入框、搜索按钮）
///   由探索页统一提供，两处共用同一套排版；
/// - 结果卡片、每源错误提示、相关度排序、打开下载页 / 入库留在本文件。
///
/// 结果状态放在 provider（而不是面板的 State）里：模式切换会让面板重建，
/// 挂在 State 上的流式结果会全部丢失（原本页面级的 State 没有这个问题，
/// 因为切页即销毁整页）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../services/resource_search.dart';
import '../add/add_game_page.dart';
import '../design.dart';
import '../kit.dart';
import '../shell/tabs.dart';
import '../theme.dart';
import '../widgets/notifications.dart';

/// 资源搜索会话快照（不可变）。
class ResourceSearchState {
  /// 本次搜索的关键词（相关度评分与「再搜一次」用；空串表示还没搜过）
  final String keyword;

  /// 已到达的结果（已按相关度重排）
  final List<ResourceItem> items;

  /// 每个失败来源的错误文案（来源名 → 原因）
  final Map<String, String> errors;

  /// 是否仍在流式接收（全部来源返回后为 false）
  final bool busy;

  /// 已完成的来源数 / 总来源数（流式进度）
  final int completed;
  final int total;

  const ResourceSearchState({
    this.keyword = '',
    this.items = const [],
    this.errors = const {},
    this.busy = false,
    this.completed = 0,
    this.total = 0,
  });

  /// 是否已经发起过搜索。
  bool get started => keyword.isNotEmpty;

  ResourceSearchState copyWith({
    String? keyword,
    List<ResourceItem>? items,
    Map<String, String>? errors,
    bool? busy,
    int? completed,
    int? total,
  }) =>
      ResourceSearchState(
        keyword: keyword ?? this.keyword,
        items: items ?? this.items,
        errors: errors ?? this.errors,
        busy: busy ?? this.busy,
        completed: completed ?? this.completed,
        total: total ?? this.total,
      );
}

/// 资源搜索会话：订阅各来源的流式结果、按相关度重排、累积结果与错误。
///
/// 与页面/面板解耦（不碰 BuildContext）：面板只负责渲染，探索页的工具条
/// 负责发起搜索（[start]）。
class ResourceSearchSession extends StateNotifier<ResourceSearchState> {
  ResourceSearchSession() : super(const ResourceSearchState());

  StreamSubscription<ResourceSearchUpdate>? _sub;
  ResourceSearcher? _searcher;

  /// 会话已销毁后不再写 state（StateNotifier 销毁后赋值会抛异常）
  bool _disposed = false;

  /// 代际计数：每次 start 自增。迟到的响应据此丢弃——否则「连点两次搜索，
  /// 第一次的慢响应后到」会把第二次的结果盖掉（与 discover_state.dart 里
  /// DiscoverFeed._gen 同一套做法）。
  int _gen = 0;

  /// 发起搜索（关键词为空时只提示，不打断上一次结果）。
  Future<void> start(String raw) async {
    final keyword = raw.trim();
    if (keyword.isEmpty) {
      showNotice('请输入要搜索的游戏名', error: true);
      return;
    }
    final gen = ++_gen;
    await _sub?.cancel();
    _searcher?.dispose();
    // 新会话：清空上一次的结果与错误，进度归零
    state = ResourceSearchState(keyword: keyword, busy: true);

    final proxy = AppServices.I.fetcher.proxy;
    final api =
        await AppServices.I.settings.getString(SettingsStore.kSearchGalApi, '');
    if (_disposed || gen != _gen) return;
    final searcher = ResourceSearcher(proxy: proxy);
    _searcher = searcher;

    _sub = searcher.search(keyword, searchGalApi: api).listen((u) {
      if (_disposed || gen != _gen) return;
      final items = [...state.items];
      final errors = {...state.errors};
      final r = u.result;
      if (r != null) {
        if (r.error != null) {
          // 单个来源失败不影响其它来源
          errors[r.site] = r.error!;
        } else {
          items.addAll(r.items);
          errors.remove(r.site);
        }
      }
      // 按相关度重排（不再按站点分组；同分时短标题优先）
      _sortByRelevance(items, keyword);
      state = ResourceSearchState(
        keyword: keyword,
        items: items,
        errors: errors,
        busy: !u.done,
        completed: u.completed,
        total: u.total,
      );
    }, onError: (e) {
      if (_disposed || gen != _gen) return;
      state = state.copyWith(
        busy: false,
        errors: {...state.errors, '搜索': '$e'},
      );
    });
  }

  /// 相关度排序：分数高的在前；同分时标题更短（更「正」）的在前。
  static void _sortByRelevance(List<ResourceItem> items, String keyword) {
    items.sort((a, b) {
      final ra = ResourceSearcher.relevance(a.title, keyword);
      final rb = ResourceSearcher.relevance(b.title, keyword);
      if (ra != rb) return rb.compareTo(ra);
      if (a.title.length != b.title.length) {
        return a.title.length.compareTo(b.title.length);
      }
      return a.site.compareTo(b.site);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _searcher?.dispose();
    super.dispose();
  }
}

/// 资源搜索会话（不放 autoDispose：切模式/切页回来结果还在）。
///
/// 不额外 `ref.onDispose(session.dispose)`：riverpod 在 provider 销毁时
/// 已经会调用 notifier 的 `dispose`，再调一次会撞上 StateNotifier
/// 「已销毁」的断言。
final resourceSearchSessionProvider =
    StateNotifierProvider<ResourceSearchSession, ResourceSearchState>(
        (ref) => ResourceSearchSession());

/// 可嵌入的资源搜索结果面板（探索页 → 「资源」模式）。
///
/// 工具栏的搜索框与「搜索」按钮由探索页提供（[onRerun] 就是那条回程路），
/// 这里只负责渲染结果、错误与空态。
class ResourceSearchPane extends ConsumerWidget {
  /// 「再搜一次」：交给外壳处理——它掌握工具栏输入框，能把关键词同步回去，
  /// 避免「输入框显示 A、结果却是 B」。为空时退化为直接用会话里的关键词重跑。
  final void Function(String keyword)? onRerun;

  const ResourceSearchPane({super.key, this.onRerun});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(resourceSearchSessionProvider);

    // 还没搜过：说明入口在工具条上（探索页的搜索框与「搜索」按钮）
    if (!s.started) {
      return const KEmpty(
        icon: Icons.cloud_download_outlined,
        title: '输入游戏名开始搜索',
        subtitle: '结果来自各资源站的发布页，可一键打开下载页或直接入库',
      );
    }
    // 搜索完成但一条结果也没有、也没有报错：数据源确实没有匹配项
    if (s.items.isEmpty && s.errors.isEmpty && !s.busy) {
      return KEmpty(
        icon: Icons.search_off_rounded,
        title: '未找到与「${s.keyword}」相关的资源',
        subtitle: '试试用中文名，或换一个更短的关键词',
        actionLabel: '再搜一次',
        actionIcon: Icons.refresh_rounded,
        onAction: () => _rerun(ref, s.keyword),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      children: [
        // 各源错误提示（不阻断其它源的结果；失败时展示具体原因而不是「没有结果」）
        if (s.errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: KCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg, vertical: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 16, color: KisakiColors.danger),
                      const SizedBox(width: Gap.sm),
                      Text('部分数据源不可用',
                          style: Type.section
                              .copyWith(color: KisakiColors.danger)),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  for (final e in s.errors.entries)
                    Text('${e.key}：${e.value}',
                        style: Type.caption.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        // 首个结果到达前显示加载态（之后结果流式追加，不再遮挡内容）
        if (s.items.isEmpty && s.busy)
          const Padding(
            padding: EdgeInsets.only(top: Gap.huge),
            child: KLoading(size: 26),
          ),
        for (var i = 0; i < s.items.length; i++)
          StaggeredFadeIn(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: _ResourceTile(
                item: s.items[i],
                keyword: s.keyword,
              ),
            ),
          ),
      ],
    );
  }

  /// 「再搜一次」：优先交给外壳（顺带同步工具栏输入框）。
  void _rerun(WidgetRef ref, String keyword) {
    final rerun = onRerun;
    if (rerun != null) {
      rerun(keyword);
      return;
    }
    ref.read(resourceSearchSessionProvider.notifier).start(keyword);
  }
}

/// 单条资源：标题 + 来源/标签徽标 + 「下载页 / 入库」操作。
class _ResourceTile extends ConsumerWidget {
  final ResourceItem item;
  final String keyword;

  const _ResourceTile({required this.item, required this.keyword});

  Future<void> _openUrl(String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) showNotice('打开链接失败：$url', error: true);
  }

  /// 入库：已有同名游戏直接跳详情；否则带关键词进入「添加游戏（搜刮）」。
  Future<void> _addToLibrary(BuildContext context, WidgetRef ref) async {
    final existing = await AppServices.I.repo.findGameByTitle(item.title);
    if (!context.mounted) return;
    if (existing != null) {
      showNotice('「${existing.displayName}」已在库中，已为你打开游戏库');
      ref.read(libraryVersionProvider.notifier).state++;
      ref.read(tabIndexProvider.notifier).state = Tabs.library;
      return;
    }
    await Navigator.of(context).push(FadeThroughRoute.builder(
        builder: (_) => AddGamePage(initialQuery: item.title)));
    if (context.mounted) {
      ref.read(libraryVersionProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final relevant = ResourceSearcher.relevance(item.title, keyword);
    return KCard(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Type.body.copyWith(
                              fontWeight: FontWeight.w600)),
                    ),
                    if (relevant >= 850) ...[
                      const SizedBox(width: Gap.sm),
                      const KBadge(
                          text: '高度相关', color: Color(0xFF3F9E97)),
                    ],
                  ],
                ),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    KBadge(text: item.site, color: KisakiColors.lavender),
                    for (final t in item.tags.take(3))
                      KBadge(
                        text: t,
                        color: t == ResourceTag.noLogin
                            ? const Color(0xFF7EC8C3)
                            : (t == ResourceTag.needMagic
                                ? KisakiColors.warning
                                : scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          TextButton.icon(
            onPressed: () => _openUrl(item.url),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('下载页'),
          ),
          const SizedBox(width: Gap.xs),
          FilledButton.tonalIcon(
            onPressed: () => _addToLibrary(context, ref),
            icon: const Icon(Icons.library_add_rounded, size: 16),
            label: const Text('入库'),
          ),
        ],
      ),
    );
  }
}
