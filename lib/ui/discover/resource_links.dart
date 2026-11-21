/// 全网资源检索与作品「下载资源」发布页链接聚合区（Fluent 2）。
///
/// 严格遵循产品红线：
/// - 仅提供各站点发布页 / 详情页外链，不托管直链、不解析网盘、不提供站内下载；
/// - 所有下载资源卡片与列表行**严禁**放置「入库 / 入库下载 / 一键入库」按钮。
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/settings_store.dart';
import '../../scraping/scraped_game.dart';
import '../../services/resource_search.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import '../library/game_actions.dart';
import 'discover_state.dart' show discoverLibraryKey;

/// 一次名字尝试里、每个来源最多保留的条目数。
const int kResourceMaxPerSource = 5;

/// 名字变体最多纳入几个（中文名 + 原名 + 若干别名）。
const int kResourceMaxCandidates = 6;

/// 一次自动加载最多自动换几个名字。
const int kResourceMaxAutoAttempts = 3;

/// 进程内缓存的作品数上限。
const int kResourceMaxCacheEntries = 32;

/// 流式资源搜索执行器签名（方便测试通过 Riverpod override 注入离线流）。
typedef ResourceSearchRunner = Stream<ResourceSearchUpdate> Function(
  String keyword,
);

/// 默认流式资源搜索执行器。
///
/// 若在独立 Widget 测试中未初始化 `AppServices`，安全返回已完成的空流。
final resourceSearchRunnerProvider = Provider<ResourceSearchRunner>((ref) {
  return (keyword) async* {
    final services = tryAppServices();
    if (services == null) {
      yield const ResourceSearchUpdate(completed: 0, total: 0, done: true);
      return;
    }
    final proxy = services.fetcher.proxy;
    final api = await services.settings
        .getString(SettingsStore.kSearchGalApi, '');
    final searcher = ResourceSearcher(proxy: proxy);
    try {
      yield* searcher.search(keyword, searchGalApi: api);
    } finally {
      searcher.dispose();
    }
  };
});

/// 搜索资源站时按顺序尝试的名字变体：**中文名 → 原名 → 别名**。
List<String> resourceNameCandidates(ScrapedGame g) {
  final out = <String>[];
  void add(String raw) {
    final t = raw.trim();
    if (t.isEmpty || out.contains(t)) return;
    out.add(t);
  }

  void addWithVariants(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    add(t);
    final compact = t.replaceAll(RegExp(r'[＊*・×]'), '').trim();
    if (compact.length >= 2 && compact != t) {
      add(compact);
    }
    final mainPart =
        t.split(RegExp(r'\s*[\-–—~～:：]\s*')).first.trim();
    if (mainPart.length >= 2 && mainPart != t) {
      add(mainPart);
    }
  }

  addWithVariants(g.nameCn);
  addWithVariants(g.name);
  for (final a in g.aliases) {
    if (out.length >= kResourceMaxCandidates) break;
    add(a);
  }
  return out.take(kResourceMaxCandidates).toList();
}

/// 一部作品的资源链接快照（不可变；故意不覆写 `==` 以支持同结构递增刷新）。
class ResourceLinkState {
  final List<String> candidates;
  final String name;
  final int attempt;
  final List<String> tried;
  final int nextIndex;
  final List<ResourceSourceResult> groups;
  final bool busy;
  final int completed;
  final int total;

  const ResourceLinkState({
    this.candidates = const [],
    this.name = '',
    this.attempt = 0,
    this.tried = const [],
    this.nextIndex = 0,
    this.groups = const [],
    this.busy = false,
    this.completed = 0,
    this.total = 0,
  });

  static const initial = ResourceLinkState();

  bool get started => attempt > 0;
  bool get hasItems => groups.any((g) => g.items.isNotEmpty);
  int get itemCount =>
      groups.fold<int>(0, (n, g) => n + g.items.length);
  List<ResourceSourceResult> get failures =>
      [for (final g in groups) if (g.error != null) g];
  String? get nextName =>
      nextIndex < candidates.length ? candidates[nextIndex] : null;

  ResourceLinkState copyWith({
    List<String>? candidates,
    String? name,
    int? attempt,
    List<String>? tried,
    int? nextIndex,
    List<ResourceSourceResult>? groups,
    bool? busy,
    int? completed,
    int? total,
  }) =>
      ResourceLinkState(
        candidates: candidates ?? this.candidates,
        name: name ?? this.name,
        attempt: attempt ?? this.attempt,
        tried: tried ?? this.tried,
        nextIndex: nextIndex ?? this.nextIndex,
        groups: groups ?? this.groups,
        busy: busy ?? this.busy,
        completed: completed ?? this.completed,
        total: total ?? this.total,
      );
}

/// 作品资源链接进程内缓存 + 多候选词顺序探测调度器。
class ResourceLinkStore {
  ResourceLinkStore._();
  static final ResourceLinkStore instance = ResourceLinkStore._();

  final Map<String, ValueNotifier<ResourceLinkState>> _entries = {};
  final Set<String> _running = {};
  final Map<String, int> _gen = {};

  ValueNotifier<ResourceLinkState> entry(String key) => _entries.putIfAbsent(
        key,
        () => ValueNotifier<ResourceLinkState>(ResourceLinkState.initial),
      );

  void ensureLoaded(
    String key,
    List<String> candidates, {
    ResourceSearchRunner? runner,
  }) {
    if (candidates.isEmpty) return;
    if (_running.contains(key)) return;
    if (entry(key).value.started) return;
    _start(key, candidates, 0, reset: true, runner: runner);
  }

  void searchNext(String key, {ResourceSearchRunner? runner}) {
    if (_running.contains(key)) return;
    final s = entry(key).value;
    if (s.nextIndex >= s.candidates.length) return;
    _start(key, s.candidates, s.nextIndex, reset: false, runner: runner);
  }

  void restart(String key, {ResourceSearchRunner? runner}) {
    if (_running.contains(key)) return;
    _start(
      key,
      entry(key).value.candidates,
      0,
      reset: true,
      runner: runner,
    );
  }

  void _start(
    String key,
    List<String> candidates,
    int startIndex, {
    required bool reset,
    ResourceSearchRunner? runner,
  }) {
    if (candidates.isEmpty) return;
    final notifier = entry(key);
    final gen = (_gen[key] ?? 0) + 1;
    _gen[key] = gen;
    _running.add(key);
    final prev = notifier.value;
    notifier.value = ResourceLinkState(
      candidates: candidates,
      name: prev.name,
      attempt: reset ? 0 : prev.attempt,
      tried: reset ? const [] : prev.tried,
      nextIndex: startIndex,
      busy: true,
    );
    _evict();
    _walk(key, notifier, gen, candidates, startIndex, runner: runner)
        .whenComplete(() {
      if (_gen[key] == gen) _running.remove(key);
    }).catchError((Object e) {
      if (_gen[key] == gen) {
        final s = notifier.value;
        notifier.value = s.copyWith(
          busy: false,
          groups: [
            ...s.groups,
            ResourceSourceResult(site: '资源搜索', error: _friendly('$e')),
          ],
        );
      }
    });
  }

  Future<void> _walk(
    String key,
    ValueNotifier<ResourceLinkState> notifier,
    int gen,
    List<String> candidates,
    int startIndex, {
    ResourceSearchRunner? runner,
  }) async {
    var index = startIndex;
    var attempts = 0;
    try {
      while (index < candidates.length && attempts < kResourceMaxAutoAttempts) {
        if (_gen[key] != gen) return;
        final name = candidates[index];
        final s = notifier.value;
        final tried = [...s.tried];
        if (!tried.contains(name)) tried.add(name);
        notifier.value = s.copyWith(
          name: name,
          attempt: s.attempt + 1,
          tried: tried,
          nextIndex: index + 1,
          groups: const [],
          completed: 0,
          total: 0,
          busy: true,
        );
        final r = await _searchOnce(key, notifier, gen, name, runner: runner);
        if (_gen[key] != gen) return;
        index++;
        attempts++;
        if (r.hit || r.allFailed) break;
      }
    } catch (e) {
      if (_gen[key] == gen) {
        final s = notifier.value;
        notifier.value = s.copyWith(
          groups: [
            ...s.groups,
            ResourceSourceResult(site: '资源搜索', error: _friendly('$e')),
          ],
        );
      }
    } finally {
      if (_gen[key] == gen) {
        notifier.value = notifier.value.copyWith(busy: false, nextIndex: index);
      }
    }
  }

  Future<({bool hit, bool allFailed})> _searchOnce(
    String key,
    ValueNotifier<ResourceLinkState> notifier,
    int gen,
    String name, {
    ResourceSearchRunner? runner,
  }) async {
    Stream<ResourceSearchUpdate> stream;
    ResourceSearcher? ownedSearcher;

    if (runner != null) {
      stream = runner(name);
    } else {
      final services = tryAppServices();
      if (services == null) {
        notifier.value = notifier.value.copyWith(
          completed: 0,
          total: 0,
          busy: false,
        );
        return (hit: false, allFailed: false);
      }
      final api = await services.settings
          .getString(SettingsStore.kSearchGalApi, '');
      if (_gen[key] != gen) return (hit: false, allFailed: false);
      ownedSearcher = ResourceSearcher(proxy: services.fetcher.proxy);
      stream = ownedSearcher.search(name, searchGalApi: api);
    }

    var hit = false;
    try {
      await for (final u in stream) {
        if (_gen[key] != gen) break;
        final s = notifier.value;
        final groups = [...s.groups];
        final r = u.result;
        if (r != null) {
          if (r.error != null) {
            groups.add(ResourceSourceResult(
              site: r.site,
              error: _friendly(r.error!),
              tags: r.tags,
            ));
          } else {
            final items = _rank(r.items, name);
            if (items.isNotEmpty) hit = true;
            groups.add(ResourceSourceResult(
              site: r.site,
              items: items,
              tags: r.tags,
            ));
          }
        }
        notifier.value = s.copyWith(
          groups: groups,
          completed: u.completed,
          total: u.total,
          busy: !u.done,
        );
      }
    } catch (e) {
      if (_gen[key] == gen) {
        final s = notifier.value;
        notifier.value = s.copyWith(groups: [
          ...s.groups,
          ResourceSourceResult(site: '资源搜索', error: _friendly('$e')),
        ]);
      }
    } finally {
      ownedSearcher?.dispose();
    }
    if (_gen[key] != gen) return (hit: false, allFailed: false);
    final groups = notifier.value.groups;
    return (
      hit: hit,
      allFailed: groups.isNotEmpty && groups.every((g) => g.error != null),
    );
  }

  static List<ResourceItem> _rank(List<ResourceItem> items, String name) {
    final sorted = items
        .where((it) => ResourceSearcher.relevance(it.title, name) > 0)
        .toList();
    sorted.sort((a, b) {
      final ra = ResourceSearcher.relevance(a.title, name);
      final rb = ResourceSearcher.relevance(b.title, name);
      if (ra != rb) return rb.compareTo(ra);
      if (a.title.length != b.title.length) {
        return a.title.length.compareTo(b.title.length);
      }
      return a.site.compareTo(b.site);
    });
    return sorted.take(kResourceMaxPerSource).toList();
  }

  void _evict() {
    if (_entries.length <= kResourceMaxCacheEntries) return;
    for (final k in _entries.keys.toList()) {
      if (_entries.length <= kResourceMaxCacheEntries) break;
      if (_running.contains(k)) continue;
      _entries.remove(k);
      _gen.remove(k);
    }
  }
}

String _short(Object e) {
  final s = '$e';
  return s.length > 100 ? '${s.substring(0, 100)}…' : s;
}

String _friendly(String raw) {
  final code = RegExp(r'status code of (\d{3})').firstMatch(raw)?.group(1);
  if (code != null) {
    switch (code) {
      case '401':
        return '需要登录（HTTP 401）';
      case '403':
        return '被站点拒绝（HTTP 403，多半要登录或有区域限制）';
      case '404':
        return '站点接口地址已变（HTTP 404）';
      case '429':
        return '请求过于频繁（HTTP 429）';
    }
    if (code.startsWith('5')) return '站点暂时不可用（HTTP $code）';
    return '站点拒绝了这个请求（HTTP $code）';
  }
  final low = raw.toLowerCase();
  if (low.contains('timeout') || low.contains('timed out')) {
    return '连接超时（可能需要代理）';
  }
  if (low.contains('socketexception') ||
      low.contains('connection') ||
      low.contains('handshake')) {
    return '连不上站点（可能需要代理）';
  }
  return _short(raw);
}

String _shortName(String name) =>
    name.length > 12 ? '${name.substring(0, 12)}…' : name;

/// 使用系统默认浏览器打开探索页外部链接（站点发布页 / 商店 / 百科）。
Future<void> openExternalExploreUrl(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.hasScheme) {
    showNotice('链接地址无效：$rawUrl', error: true);
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      showNotice('无法调用系统浏览器打开链接', error: true);
    }
  } catch (e) {
    showNotice('无法打开链接：$e', error: true);
  }
}

// ==================== 作品详情内嵌「资源下载」区 ====================

/// 百科页「下载」Tab 内的自动资源站探测结果面板（零入库按钮）。
class ResourceLinkSection extends ConsumerStatefulWidget {
  final ScrapedGame game;
  final bool shrinkWrap;

  const ResourceLinkSection({
    super.key,
    required this.game,
    this.shrinkWrap = false,
  });

  @override
  ConsumerState<ResourceLinkSection> createState() =>
      _ResourceLinkSectionState();
}

class _ResourceLinkSectionState extends ConsumerState<ResourceLinkSection> {
  late String _key;
  late List<String> _candidates;
  late ValueNotifier<ResourceLinkState> _notifier;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ResourceLinkSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = discoverLibraryKey(widget.game);
    if (nextKey != _key) {
      _bind();
    }
  }

  void _bind() {
    _key = discoverLibraryKey(widget.game);
    _candidates = resourceNameCandidates(widget.game);
    _notifier = ResourceLinkStore.instance.entry(_key);
    final runner = ref.read(resourceSearchRunnerProvider);
    Future.microtask(() {
      if (!mounted) return;
      ResourceLinkStore.instance.ensureLoaded(
        _key,
        _candidates,
        runner: runner,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ResourceLinkState>(
      valueListenable: _notifier,
      builder: (context, state, _) {
        final runner = ref.read(resourceSearchRunnerProvider);
        final header = _buildSectionHeader(context, state, runner);
        final body = _buildSectionBody(context, state, runner);

        if (widget.shrinkWrap) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 10),
              body,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 10),
            Expanded(child: SingleChildScrollView(child: body)),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    ResourceLinkState state,
    ResourceSearchRunner runner,
  ) {
    final theme = FluentTheme.of(context);
    final ratio = state.total > 0
        ? (state.completed / state.total * 100).clamp(0.0, 100.0)
        : null;

    return FluentSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.arrow_download_20_regular,
                size: 16,
                color: theme.accentInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.busy
                      ? '正在探测各资源站「${state.name.isEmpty ? widget.game.displayName : state.name}」'
                      : '站点发布页检索（${state.itemCount} 条链接）',
                  style: theme.typography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (state.nextName != null && !state.busy)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Button(
                    onPressed: () => ResourceLinkStore.instance
                        .searchNext(_key, runner: runner),
                    child: Text('改用「${_shortName(state.nextName!)}」'),
                  ),
                ),
              Button(
                onPressed: state.busy
                    ? null
                    : () => ResourceLinkStore.instance
                        .restart(_key, runner: runner),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.arrow_clockwise_16_regular, size: 14),
                    const SizedBox(width: 6),
                    const Text('重新检索'),
                  ],
                ),
              ),
            ],
          ),
          if (state.busy) ...[
            const SizedBox(height: 10),
            ProgressBar(value: ratio),
          ],
          const SizedBox(height: 6),
          Text(
            '仅跳转到资源站发布页，不提供直链解析或站内下载。',
            style: theme.typography.caption?.copyWith(
              color: theme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBody(
    BuildContext context,
    ResourceLinkState state,
    ResourceSearchRunner runner,
  ) {
    if (_candidates.isEmpty) {
      return const FluentEmptyState(
        icon: FluentIcons.search_24_regular,
        title: '缺少可用于检索的标题',
        message: '该条目暂未收录中文名或原名。',
      );
    }

    if (state.groups.isEmpty && state.busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              ProgressRing(),
              SizedBox(height: 10),
              Text('正在并行查询各资源站点…'),
            ],
          ),
        ),
      );
    }

    if (!state.hasItems && !state.busy) {
      final triedText = state.tried.isEmpty
          ? '未发起外部站点查询（或处于离线预览模式）'
          : '已尝试关键词：${state.tried.join(' / ')}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FluentEmptyState(
            icon: FluentIcons.search_24_regular,
            title: '暂未匹配到站点发布页',
            message: triedText,
            action: state.nextName != null
                ? FilledButton(
                    onPressed: () => ResourceLinkStore.instance
                        .searchNext(_key, runner: runner),
                    child: Text('改用「${_shortName(state.nextName!)}」再搜一次'),
                  )
                : null,
          ),
          if (state.failures.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...state.failures.map((f) => _FailureRow(group: f)),
          ],
        ],
      );
    }

    final okGroups = state.groups.where((g) => g.items.isNotEmpty).toList();
    final emptyGroups = state.groups
        .where((g) => g.error == null && g.items.isEmpty)
        .toList();
    final disableAnim = fluentAnimationsDisabled(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < okGroups.length; i++) ...[
          _SourceResultGroup(group: okGroups[i])
              .fluentEntrance(index: i, disable: disableAnim),
          const SizedBox(height: 10),
        ],
        if (state.failures.isNotEmpty) ...[
          for (final f in state.failures) ...[
            _FailureRow(group: f),
            const SizedBox(height: 8),
          ],
        ],
        if (emptyGroups.isNotEmpty)
          Text(
            '无命中站点：${emptyGroups.map((g) => g.site).join('、')}',
            style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).textSecondary,
                ),
          ),
      ],
    );
  }
}

// ==================== 探索页「资源检索」独立模式 ====================

enum _ResourceTagFilter {
  all('全部', null),
  noLogin('免登录', ResourceTag.noLogin),
  needMagic('需代理', ResourceTag.needMagic),
  needLogin('需登录', ResourceTag.needLogin);

  final String label;
  final String? tag;
  const _ResourceTagFilter(this.label, this.tag);
}

/// 探索页顶栏切到「资源检索」模式后的全网流式搜索面板（零入库按钮）。
class ResourceSearchPane extends ConsumerStatefulWidget {
  final String initialKeyword;
  final ValueChanged<String>? onKeywordSubmitted;

  const ResourceSearchPane({
    super.key,
    this.initialKeyword = '',
    this.onKeywordSubmitted,
  });

  @override
  ConsumerState<ResourceSearchPane> createState() => _ResourceSearchPaneState();
}

class _ResourceSearchPaneState extends ConsumerState<ResourceSearchPane> {
  late final TextEditingController _ctrl;
  StreamSubscription<ResourceSearchUpdate>? _sub;
  int _gen = 0;
  bool _searching = false;
  int _completed = 0;
  int _total = 0;
  String _activeKeyword = '';
  _ResourceTagFilter _tagFilter = _ResourceTagFilter.all;
  final List<ResourceSourceResult> _groups = [];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialKeyword);
    if (widget.initialKeyword.trim().isNotEmpty) {
      Future.microtask(() {
        if (mounted) _startSearch(widget.initialKeyword);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ResourceSearchPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKw = widget.initialKeyword.trim();
    if (nextKw.isNotEmpty && nextKw != oldWidget.initialKeyword.trim()) {
      _ctrl.text = nextKw;
      _startSearch(nextKw);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _stopSearch() {
    _sub?.cancel();
    _sub = null;
    _gen++;
    if (mounted) {
      setState(() => _searching = false);
    }
  }

  void _startSearch([String? raw]) {
    if (_searching) return;
    final kw = (raw ?? _ctrl.text).trim();
    if (kw.isEmpty) {
      showNotice('请输入游戏名称或关键字');
      return;
    }
    widget.onKeywordSubmitted?.call(kw);
    _sub?.cancel();
    final gen = ++_gen;
    setState(() {
      _searching = true;
      _completed = 0;
      _total = 0;
      _activeKeyword = kw;
      _groups.clear();
    });

    final runner = ref.read(resourceSearchRunnerProvider);
    _sub = runner(kw).listen(
      (update) {
        if (!mounted || gen != _gen) return;
        setState(() {
          if (update.result != null) {
            _groups.add(update.result!);
          }
          _completed = update.completed;
          _total = update.total;
          if (update.done) {
            _searching = false;
          }
        });
      },
      onError: (Object err) {
        if (!mounted || gen != _gen) return;
        setState(() {
          _searching = false;
          _groups.add(
            ResourceSourceResult(site: '资源搜索', error: _friendly('$err')),
          );
        });
      },
      onDone: () {
        if (!mounted || gen != _gen) return;
        setState(() => _searching = false);
      },
    );
  }

  List<ResourceSourceResult> get _filteredGroups {
    final tag = _tagFilter.tag;
    if (tag == null) return _groups;
    return [
      for (final g in _groups)
        if (g.tags.contains(tag) ||
            g.items.any((it) => it.tags.contains(tag)))
          g,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final filtered = _filteredGroups;
    final totalLinks = filtered.fold<int>(0, (n, g) => n + g.items.length);
    final progressValue =
        _total > 0 ? (_completed / _total * 100).clamp(0.0, 100.0) : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FluentSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FluentSearchBox(
                        controller: _ctrl,
                        compact: true,
                        placeholder: '输入作品中文名 / 日文原名 / 别名进行资源站检索…',
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (!_searching) _startSearch();
                        },
                        onCleared: () {
                          _ctrl.clear();
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_searching)
                      Button(
                        onPressed: _stopSearch,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              FluentIcons.stop_16_regular,
                              size: 14,
                              color: theme.dangerInk,
                            ),
                            const SizedBox(width: 6),
                            const Text('停止检索'),
                          ],
                        ),
                      )
                    else
                      FilledButton(
                        onPressed: () => _startSearch(),
                        child: const Text('检索'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final f in _ResourceTagFilter.values)
                      _FilterPill(
                        label: f.label,
                        selected: _tagFilter == f,
                        onTap: () => setState(() => _tagFilter = f),
                      ),
                    if (_activeKeyword.isNotEmpty)
                      Text(
                        _searching
                            ? '正在检索「$_activeKeyword」($_completed/$_total)…'
                            : '关键词「$_activeKeyword」共 $totalLinks 条外链',
                        style: theme.typography.caption?.copyWith(
                          color: theme.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '仅跳转到资源站发布页，不提供直链解析或站内下载。',
                  style: theme.typography.caption?.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
                if (_searching) ...[
                  const SizedBox(height: 10),
                  ProgressBar(value: progressValue),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _buildResultsList(context, filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    List<ResourceSourceResult> filtered,
  ) {
    final theme = FluentTheme.of(context);
    if (_activeKeyword.isEmpty && _groups.isEmpty) {
      return const FluentEmptyState(
        icon: FluentIcons.search_24_regular,
        title: '全网 Galgame 资源站流式检索',
        message: '输入游戏标题并点击「检索」，结果将按站点实时返回发布页链接。',
      );
    }
    if (filtered.isEmpty && _searching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            ProgressRing(),
            SizedBox(height: 12),
            Text('正在等待首个站点响应…'),
          ],
        ),
      );
    }

    final nonEmpty = filtered
        .where((g) => g.error != null || g.items.isNotEmpty)
        .toList();
    final emptyGroups = filtered
        .where((g) => g.error == null && g.items.isEmpty)
        .toList();

    if (nonEmpty.isEmpty && !_searching) {
      return FluentEmptyState(
        icon: FluentIcons.search_24_regular,
        title: '未找到匹配的资源发布页',
        message: '可尝试换用日文原名、去除副标题或切换上方站点标签筛选。',
        action: _tagFilter != _ResourceTagFilter.all
            ? Button(
                onPressed: () =>
                    setState(() => _tagFilter = _ResourceTagFilter.all),
                child: const Text('查看全部站点'),
              )
            : null,
      );
    }

    final itemCount = nonEmpty.length + (emptyGroups.isNotEmpty ? 1 : 0);
    return ListView.separated(
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= nonEmpty.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '无命中站点：${emptyGroups.map((g) => g.site).join('、')}',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
          );
        }
        final group = nonEmpty[index];
        if (group.error != null) {
          return _FailureRow(group: group);
        }
        return _SourceResultGroup(group: group);
      },
    );
  }
}

class _SourceResultGroup extends StatelessWidget {
  final ResourceSourceResult group;
  const _SourceResultGroup({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.globe_16_regular,
                size: 16,
                color: theme.accentInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(group.site, style: theme.typography.bodyStrong),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in group.tags) FluentBadge(text: tag),
                  FluentBadge(
                    text: '${group.items.length} 条',
                    foreground: theme.accentInk,
                    background: theme.accentTint,
                  ),
                ],
              ),
            ],
          ),
          if (group.items.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '该站点暂无匹配条目',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            for (var i = 0; i < group.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _ResourceLinkRow(item: group.items[i]),
            ],
          ],
        ],
      ),
    );
  }
}

class _ResourceLinkRow extends StatelessWidget {
  final ResourceItem item;
  const _ResourceLinkRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final host = Uri.tryParse(item.url)?.host ?? item.url;
    return Semantics(
      button: true,
      label: '${item.title} 打开链接',
      child: HoverButton(
        onPressed: () => openExternalExploreUrl(item.url),
        builder: (context, states) => FocusBorder(
          focused: states.isFocused,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: states.isHovered
                  ? theme.subtleHover
                  : theme.surfaceCardSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerHairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.typography.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (host.isNotEmpty)
                            Text(
                              host,
                              style: theme.typography.caption?.copyWith(
                                color: theme.textSecondary,
                              ),
                            ),
                          for (final tag in item.tags) FluentBadge(text: tag),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Button(
                  onPressed: () => openExternalExploreUrl(item.url),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.open_16_regular, size: 14),
                      SizedBox(width: 6),
                      Text('打开链接'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FailureRow extends StatelessWidget {
  final ResourceSourceResult group;
  const _FailureRow({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            FluentIcons.warning_16_regular,
            size: 16,
            color: theme.warningInk,
          ),
          const SizedBox(width: 8),
          Text('${group.site}：', style: theme.typography.bodyStrong),
          Expanded(
            child: Text(
              group.error ?? '请求未成功',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (group.tags.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                for (final tag in group.tags) FluentBadge(text: tag),
              ],
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
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
        onPressed: onTap,
        builder: (context, states) {
          final bg = selected
              ? theme.accentTint
              : states.isHovered
                  ? theme.subtleHover
                  : theme.surfaceCardSecondary;
          final border = selected
              ? theme.accentInk.withValues(alpha: 0.55)
              : theme.surfaceStroke;
          return FocusBorder(
            focused: states.isFocused,
            child: AnimatedContainer(
              duration: disableAnim ? Duration.zero : FluentMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Text(
                label,
                style: theme.typography.caption?.copyWith(
                  color: selected ? theme.accentInk : theme.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
