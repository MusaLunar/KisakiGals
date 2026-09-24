/// 资源搜索页：聚合多个资源站搜索发布页，支持「打开下载页」与「入库」。
///
/// 参考 Moe-Sakura/SearchGal：不解析直链、不托管资源，只给出发布页链接；
/// 入库则复用既有的「添加游戏 → 搜刮」流程，用资源标题作为关键词自动补全元数据。
///
/// 页面骨架走 KPage，结果卡片走 KCard / KBadge，流式结果错落淡入。
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
import '../theme.dart';
import '../widgets/notifications.dart';

class ResourceSearchPage extends ConsumerStatefulWidget {
  const ResourceSearchPage({super.key});

  @override
  ConsumerState<ResourceSearchPage> createState() => _ResourceSearchPageState();
}

class _ResourceSearchPageState extends ConsumerState<ResourceSearchPage> {
  final _ctrl = TextEditingController();
  final _items = <ResourceItem>[];
  final _errors = <String, String>{};
  StreamSubscription<ResourceSearchUpdate>? _sub;
  ResourceSearcher? _searcher;
  bool _busy = false;
  int _completed = 0;
  int _total = 0;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _ctrl.text = ref.read(resourceQueryProvider);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searcher?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final kw = _ctrl.text.trim();
    if (kw.isEmpty) {
      showNotice('请输入要搜索的游戏名', error: true);
      return;
    }
    await _sub?.cancel();
    _searcher?.dispose();
    setState(() {
      _items.clear();
      _errors.clear();
      _busy = true;
      _keyword = kw;
      _completed = 0;
      _total = 0;
    });
    ref.read(resourceQueryProvider.notifier).state = kw;

    final proxy = AppServices.I.fetcher.proxy;
    final api = await AppServices.I.settings
        .getString(SettingsStore.kSearchGalApi, '');
    final searcher = ResourceSearcher(proxy: proxy);
    _searcher = searcher;

    _sub = searcher.search(kw, searchGalApi: api).listen((u) {
      if (!mounted) return;
      setState(() {
        _completed = u.completed;
        _total = u.total;
        final r = u.result;
        if (r != null) {
          if (r.error != null) {
            _errors[r.site] = r.error!;
          } else {
            _items.addAll(r.items);
            _errors.remove(r.site);
          }
        }
        if (u.done) _busy = false;
        _resort();
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors['搜索'] = '$e';
      });
    });
  }

  /// 按相关度重排（不再按站点分组；同分时短标题优先）
  void _resort() {
    _items.sort((a, b) {
      final ra = ResourceSearcher.relevance(a.title, _keyword);
      final rb = ResourceSearcher.relevance(b.title, _keyword);
      if (ra != rb) return rb.compareTo(ra);
      if (a.title.length != b.title.length) {
        return a.title.length.compareTo(b.title.length);
      }
      return a.site.compareTo(b.site);
    });
  }

  Future<void> _openUrl(String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) showNotice('打开链接失败：$url', error: true);
  }

  /// 入库：已有同名游戏直接跳详情；否则带关键词进入「添加游戏（搜刮）」。
  Future<void> _addToLibrary(ResourceItem item) async {
    final existing = await AppServices.I.repo.findGameByTitle(item.title);
    if (!mounted) return;
    if (existing != null) {
      showNotice('「${existing.displayName}」已在库中，已为你打开游戏库');
      ref.read(libraryVersionProvider.notifier).state++;
      ref.read(tabIndexProvider.notifier).state = 1;
      return;
    }
    await Navigator.of(context).push(FadeThroughRoute.builder(
        builder: (_) => AddGamePage(initialQuery: item.title)));
    if (mounted) {
      ref.read(libraryVersionProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KPage(
      title: '资源搜索',
      subtitle: _items.isEmpty
          ? '聚合资源站发布页 · 只提供链接，不托管资源'
          : '共 ${_items.length} 条 · 按相关度排序',
      actions: [
        if (_busy)
          KBadge(text: '$_completed / $_total', color: scheme.primary),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索框 + 主操作
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _start(),
                  decoration: const InputDecoration(
                    hintText: '搜索游戏名（中文名效果最好，例如 千恋万花）',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              KPill(
                label: _busy ? '搜索中…' : '搜索',
                icon: _busy ? null : Icons.search_rounded,
                onTap: _busy ? null : _start,
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Expanded(child: _results(context)),
        ],
      ),
    );
  }

  Widget _results(BuildContext context) {
    if (_items.isEmpty && _errors.isEmpty && !_busy) {
      return KEmpty(
        icon: Icons.cloud_download_outlined,
        title: _keyword.isEmpty ? '输入游戏名开始搜索' : '未找到与「$_keyword」相关的资源',
        subtitle: '结果来自各资源站的发布页，可一键打开下载页或直接入库',
        actionLabel: _keyword.isEmpty ? null : '再搜一次',
        onAction: _keyword.isEmpty ? null : _start,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      children: [
        // 各源错误提示（不阻断其它源的结果）
        if (_errors.isNotEmpty)
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
                  for (final e in _errors.entries)
                    Text('${e.key}：${e.value}',
                        style: Type.caption.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        if (_items.isEmpty && _busy)
          const Padding(
            padding: EdgeInsets.only(top: Gap.huge),
            child: KLoading(),
          ),
        for (var i = 0; i < _items.length; i++)
          StaggeredFadeIn(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: _tile(context, _items[i]),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, ResourceItem it) {
    final scheme = Theme.of(context).colorScheme;
    final relevant = ResourceSearcher.relevance(it.title, _keyword);
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
                      child: Text(it.title,
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
                    KBadge(text: it.site, color: KisakiColors.lavender),
                    for (final t in it.tags.take(3))
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
            onPressed: () => _openUrl(it.url),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('下载页'),
          ),
          const SizedBox(width: Gap.xs),
          FilledButton.tonalIcon(
            onPressed: () => _addToLibrary(it),
            icon: const Icon(Icons.library_add_rounded, size: 16),
            label: const Text('入库'),
          ),
        ],
      ),
    );
  }
}
