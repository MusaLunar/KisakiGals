/// 资源搜索页：聚合多个资源站搜索发布页，支持「打开下载页」与「入库」。
///
/// 参考 Moe-Sakura/SearchGal：不解析直链、不托管资源，只给出发布页链接；
/// 入库则复用既有的「添加游戏 → 搜刮」流程，用资源标题作为关键词自动补全元数据。
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
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors['搜索'] = '$e';
      });
    });
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok) showNotice('打开链接失败：$url', error: true);
  }

  /// 入库：已有同名游戏直接跳详情；否则带关键词进入「添加游戏（搜刮）」。
  Future<void> _addToLibrary(ResourceItem item) async {
    final existing = await AppServices.I.repo.findGameByTitle(item.title);
    if (!mounted) return;
    if (existing != null) {
      showNotice('「${existing.displayName}」已在库中，已为你打开详情');
      ref.read(libraryVersionProvider.notifier).state++;
      ref.read(tabIndexProvider.notifier).state = 1;
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AddGamePage(initialQuery: item.title)));
    if (mounted) {
      ref.read(libraryVersionProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.travel_explore_rounded,
                size: 22, color: KisakiColors.pink),
            const SizedBox(width: 8),
            Text('资源搜索',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink)),
            const SizedBox(width: 10),
            Text('聚合资源站发布页',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const Spacer(),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text('$_completed / $_total',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
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
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(_busy ? '搜索中…' : '搜索'),
            ),
          ]),
          const SizedBox(height: 14),
          if (_items.isEmpty && _errors.isEmpty && !_busy)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_download_outlined,
                        size: 44, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(_keyword.isEmpty ? '输入游戏名开始搜索' : '未找到与「$_keyword」相关的资源',
                        style: TextStyle(
                            fontSize: 14, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text('结果来自各资源站的发布页，可一键打开下载页或直接入库',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  if (_errors.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KisakiColors.pink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: KisakiColors.pink.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _errors.entries)
                            Text('${e.key}：${e.value}',
                                style: const TextStyle(fontSize: 11.5)),
                        ],
                      ),
                    ),
                  if (_items.isEmpty && _busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  for (final it in _items) _tile(context, it),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ResourceItem it) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: dark ? KisakiColors.nightCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Row(children: [
                _chip(it.site, KisakiColors.lavender),
                const SizedBox(width: 6),
                for (final t in it.tags.take(3)) ...[
                  _chip(t, t == ResourceTag.noLogin
                      ? const Color(0xFF7EC8C3)
                      : (t == ResourceTag.needMagic
                          ? const Color(0xFFE0B060)
                          : scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                ],
              ]),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => _openUrl(it.url),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('下载页'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _addToLibrary(it),
          icon: const Icon(Icons.library_add_rounded, size: 16),
          label: const Text('入库'),
        ),
        const SizedBox(width: 6),
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      );
}
