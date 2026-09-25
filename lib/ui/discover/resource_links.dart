/// 作品详情里的「资源下载」区：自动去资源站查这部作品的**发布页链接**。
///
/// 与改造前的「资源搜索」页/模式的关系：那时是用户自己敲关键词、在一整页
/// 结果里挑；现在流程是「在探索页找到作品 → 点开详情 → 资源链接自己出现」。
/// 作品名就是关键词，而且名字变体（中文名 / 原名 / 别名）由程序按命中率
/// 顺序去试，用户不需要再想「该用哪个名字搜」。
///
/// 因此本文件取代了 `resource_search_page.dart` 里的
/// `ResourceSearchPane` + `ResourceSearchSession`：
/// - 会话状态按**作品**缓存（[ResourceLinkStore]），而不是按关键词——
///   同一部作品第二次点开直接吃内存缓存，不重复打资源站；
/// - 结果按来源分组渲染，**每个来源的失败单独一行**（见 [_sourceBlock] /
///   [_outcomeCard]），一个站挂了不影响其它站的结果；
/// - 只提供链接，不解析直链、不托管资源（与旧实现同一条底线）。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../data/settings_store.dart';
import '../../scraping/scraped_game.dart';
import '../../services/resource_search.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/notifications.dart';
import 'discover_state.dart' show discoverLibraryKey;

/// 一次名字尝试里、**每个来源**最多保留多少条。
///
/// 同一个名字在资源站常常能搜到十几条（本体、FD、汉化版、整合包…），
/// 弹窗右栏只有 ~450px 宽，铺太多反而挑不出来；取相关度前 5 条已经覆盖
/// 「本体 + 常见版本」，再多的直接截掉（不额外请求，服务端本来也只回一页）。
const int kResourceMaxPerSource = 5;

/// 名字变体最多纳入几个（中文名 + 原名 + 若干别名）。
///
/// 别名里很大一部分是罗马音/拉丁转写与各平台副标题，命中率低，而**每个
/// 名字都要打 5 个资源站**，所以候选表必须封顶：留 6 个已经能在
/// 「中文名/原名都搜不到」时把常见别名试完。
const int kResourceMaxCandidates = 6;

/// 一次加载（含打开弹窗时的那次自动搜索）最多自动换几个名字。
///
/// 打开详情就无条件把所有候选刷一遍，最坏是 6 × 5 = 30 个请求，对资源站
/// 不礼貌、用户也要等很久。因此自动尝试封顶 3 个名字，剩下的交给空态里的
/// 「用「xxx」再搜一次」按钮——一次点击最多再 3 个名字，由用户决定要不要
/// 继续花这笔请求。
const int kResourceMaxAutoAttempts = 3;

/// 进程内缓存的作品数上限（超出后丢弃最早入库的条目，见 [_evict]）。
const int kResourceMaxCacheEntries = 32;

/// 搜索资源站时按顺序尝试的名字变体：**中文名 → 原名 → 别名**。
///
/// 顺序的理由：资源站（中文圈）的发布页标题绝大多数用中文译名，中文名命中
/// 率最高；原名（日文）其次，很多站的中文译名收录不全但日文原名一定有；
/// 别名放在最后且只取前几个（见 [kResourceMaxCandidates]）。
///
/// `ScrapedGame.displayName` 不单独加：它只可能是 nameCn 或 name 之一
/// （`nameCn.isNotEmpty ? nameCn : name`），不是独立的变体。
List<String> resourceNameCandidates(ScrapedGame g) {
  final out = <String>[];
  void add(String raw) {
    final t = raw.trim();
    if (t.isEmpty || out.contains(t)) return;
    out.add(t);
  }

  add(g.nameCn);
  add(g.name);
  for (final a in g.aliases) {
    if (out.length >= kResourceMaxCandidates) break;
    add(a);
  }
  return out;
}

/// 一部作品的资源链接快照（不可变）。
///
/// 刻意**不实现 `==`**：状态挂在 [ValueNotifier] 上，每次流式更新都构造一个
/// 新实例，靠「实例不同」触发重建；一旦按值比较，两次结构相同但来源不同的
/// 更新（例如某个来源从"等待"变成"没有结果"）就会被静默吞掉。
class ResourceLinkState {
  /// 名字变体（已 trim、去重）
  final List<String> candidates;

  /// 本次尝试用的名字（空串 = 还没开始）
  final String name;

  /// 已经尝试过几次（0 = 还没开始）
  final int attempt;

  /// 已尝试过的名字（按顺序）：空态里如实告诉用户"都试过什么"
  final List<String> tried;

  /// 下一个还没试的候选下标（>= candidates.length 表示候选用完了）
  final int nextIndex;

  /// 最近一次尝试里各来源的结果/失败（按到达顺序，流式追加）
  final List<ResourceSourceResult> groups;

  /// 是否还在流式接收
  final bool busy;

  /// 已完成的来源数 / 总来源数（流式进度）
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

  /// 是否已经发起过搜索（决定空态文案：是"没搜过"还是"搜了没有"）
  bool get started => attempt > 0;

  /// 任何来源给了结果
  bool get hasItems => groups.any((g) => g.items.isNotEmpty);

  /// 结果总条数
  int get itemCount =>
      groups.fold<int>(0, (n, g) => n + g.items.length);

  /// 失败的来源（含具体原因，UI 里逐个显示）
  List<ResourceSourceResult> get failures =>
      [for (final g in groups) if (g.error != null) g];

  /// 下一个还没试过的名字（null = 没有更多候选）
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

/// 资源链接的内存缓存 + 加载器（进程内单例，按作品身份 key 索引）。
///
/// 缓存策略（对应"同一作品再次打开不重复请求、弹窗关闭不丢"）：
/// 1. **按作品缓存**：key 用 [discoverLibraryKey]（`vndb:123` / `bgm:45678`），
///    与"已在库"判定同一套 key，同一部作品在格子里点多少次都只有一次请求；
/// 2. **缓存里连"搜空了"也算数**：一部冷门作品搜不到资源是常态，若每次
///    打开都重打 5 个站，用户会看到弹窗每次都在转圈。想看新的结果有显式的
///    「重新搜索」按钮（[restart]）；
/// 3. **弹窗关闭不清缓存**：状态挂在常驻的 [ValueNotifier] 上，不随弹窗
///    销毁（这正是旧实现把它放 provider 而不是 State 的原因）；
/// 4. 条目数封顶 [kResourceMaxCacheEntries]，只**从表里摘掉**、不 dispose
///    （可能还有正开着的弹窗在监听它，dispose 会让那个弹窗收不到更新）。
class ResourceLinkStore {
  ResourceLinkStore._();
  static final ResourceLinkStore instance = ResourceLinkStore._();

  final Map<String, ValueNotifier<ResourceLinkState>> _entries = {};

  /// 正在跑的加载（同一作品同一时刻只跑一次，防重复点开造成双倍请求）
  final Set<String> _running = {};

  /// 代际计数：每次 [restart] / [searchNext] 自增。迟到的流式响应据此丢弃
  /// ——否则"点重新搜索 → 旧的那一轮慢慢返回"会把新结果覆盖掉
  /// （与 `ResourceSearchSession._gen`、`DiscoverFeed._gen` 同一套做法）。
  final Map<String, int> _gen = {};

  /// 取（必要时创建）某部作品的状态槽。
  ValueNotifier<ResourceLinkState> entry(String key) => _entries.putIfAbsent(
      key, () => ValueNotifier<ResourceLinkState>(ResourceLinkState.initial));

  /// 打开详情时调用：**缓存里没有才发起请求**（有缓存直接复用，见类注释）。
  void ensureLoaded(String key, List<String> candidates) {
    if (candidates.isEmpty) return;
    if (_running.contains(key)) return;
    if (entry(key).value.started) return;
    _start(key, candidates, 0, reset: true);
  }

  /// 空态里的「用「xxx」再搜一次」：从 [ResourceLinkState.nextIndex] 接着试。
  void searchNext(String key) {
    if (_running.contains(key)) return;
    final s = entry(key).value;
    if (s.nextIndex >= s.candidates.length) return;
    _start(key, s.candidates, s.nextIndex, reset: false);
  }

  /// 从头重搜（用户认为这次是网络抖动，或想再看一遍）。
  void restart(String key) {
    if (_running.contains(key)) return;
    _start(key, entry(key).value.candidates, 0, reset: true);
  }

  void _start(
    String key,
    List<String> candidates,
    int startIndex, {
    required bool reset,
  }) {
    if (candidates.isEmpty) return;
    final notifier = entry(key);
    final gen = (_gen[key] ?? 0) + 1;
    _gen[key] = gen;
    _running.add(key);
    final prev = notifier.value;
    // 换名字重搜：结果与进度清空，但保留"已试过哪些名字"（空态要如实说）
    notifier.value = ResourceLinkState(
      candidates: candidates,
      name: prev.name,
      attempt: reset ? 0 : prev.attempt,
      tried: reset ? const [] : prev.tried,
      nextIndex: startIndex,
      busy: true,
    );
    _evict();
    // 不 await：结果经 ValueNotifier 流式推给 UI
    _walk(key, notifier, gen, candidates, startIndex).whenComplete(() {
      // 只有还是自己这一代才释放锁（否则会把新那一轮放跑成"可并发"）
      if (_gen[key] == gen) _running.remove(key);
    }).catchError((Object e) {
      // 兜底：_walk 内部已经 try/catch，这里再兜一层，免得将来改动引入的
      // 异常变成一条没人接管的异步报错、进度条永远转下去
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

  /// 依次尝试候选名字，**命中即停**（第一个有结果的名字就够用）。
  ///
  /// 什么时候继续试下一个名字：
  /// - 这个名字在当前来源里**零结果**：这正是名字变体存在的意义；
  /// 什么时候停：
  /// - 有结果（命中即停，再试只会拿到重复条目）；
  /// - **所有来源都失败**：没有任何站回应，多半是网络/代理问题，换个名字
  ///   不会有帮助，只会让用户多等一个超时；此时把错误原样交给用户
  ///   （每个来源的原因都显示在该来源那一行里，不吞掉）。
  ///   单个/部分来源失败不算"全失败"——否则 KunGal 这类需要登录的站会让
  ///   流程每次都卡在第一个名字上。
  Future<void> _walk(
    String key,
    ValueNotifier<ResourceLinkState> notifier,
    int gen,
    List<String> candidates,
    int startIndex,
  ) async {
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
        final r = await _searchOnce(key, notifier, gen, name);
        if (_gen[key] != gen) return;
        index++;
        attempts++;
        if (r.hit) break;
        if (r.allFailed) break;
      }
    } catch (e) {
      // 兜底：任何意外都要把进度收掉并把原因写出来，否则进度条会一直转
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

  /// 用 [name] 打一轮全部资源站，边到边写状态。
  /// 返回「是否至少有一条结果」与「是否所有来源都失败」（见 [_walk]）。
  Future<({bool hit, bool allFailed})> _searchOnce(
    String key,
    ValueNotifier<ResourceLinkState> notifier,
    int gen,
    String name,
  ) async {
    final proxy = AppServices.I.fetcher.proxy;
    final api =
        await AppServices.I.settings.getString(SettingsStore.kSearchGalApi, '');
    if (_gen[key] != gen) return (hit: false, allFailed: false);
    final searcher = ResourceSearcher(proxy: proxy);
    var hit = false;
    try {
      // 流里每个来源单独一条更新：谁先返回谁先显示；单站失败在服务层已转成
      // 带 error 的结果（不会中断整条流），所以这里不需要 try/catch 包单站。
      await for (final u in searcher.search(name, searchGalApi: api)) {
        if (_gen[key] != gen) break;
        final s = notifier.value;
        final groups = [...s.groups];
        final r = u.result;
        if (r != null) {
          if (r.error != null) {
            // 失败的来源也占一行：用户要看到"这个站问不通/需要登录"，
            // 而不是"这个站没有结果"（原因经 _friendly 翻译成人话，
            // 但 HTTP 状态码原样保留）
            groups.add(ResourceSourceResult(
                site: r.site, error: _friendly(r.error!), tags: r.tags));
          } else {
            final items = _rank(r.items, name);
            if (items.isNotEmpty) hit = true;
            groups.add(ResourceSourceResult(
                site: r.site, items: items, tags: r.tags));
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
      searcher.dispose();
    }
    if (_gen[key] != gen) return (hit: false, allFailed: false);
    final groups = notifier.value.groups;
    return (
      hit: hit,
      allFailed: groups.isNotEmpty && groups.every((g) => g.error != null),
    );
  }

  /// 相关度排序 + 截断到 [kResourceMaxPerSource] 条。
  ///
  /// 复用服务层的 [ResourceSearcher.relevance]（与旧「资源搜索」页同一套
  /// 打分：完全匹配 > 前缀 > 中间命中 > 分词命中），因此"本体"总能排在
  /// 一堆带后缀的整合包前面。
  static List<ResourceItem> _rank(List<ResourceItem> items, String name) {
    final sorted = [...items];
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

  /// 缓存淘汰：只摘表、不 dispose（见类注释第 4 条）。
  void _evict() {
    if (_entries.length <= kResourceMaxCacheEntries) return;
    for (final k in _entries.keys.toList()) {
      if (_entries.length <= kResourceMaxCacheEntries) break;
      if (_running.contains(k)) continue;
      _entries.remove(k);
    }
  }
}

/// 长错误/异常文本截断（弹窗里放不下几百字符的 Dio 报错）。
String _short(Object e) {
  final s = '$e';
  return s.length > 100 ? '${s.substring(0, 100)}…' : s;
}

/// 把服务层的原始错误文本**翻译**成用户看得懂的一句话。
///
/// 服务层刻意给的是原样原因（`DioException … status code of 401 …`）——排障
/// 需要它，但直接铺在弹窗里又长又吓人，用户只想知道"这个站为什么没结果"。
/// 这里只做翻译，**不改写事实**：HTTP 状态码一定保留在括号里，认不出的原文
/// 一字不动地留着（宁可难看，也不替站点编一个原因）。
///
/// 实测（本机 2024 版各站）：鲲Galgame 现在一律回 401（要登录），因此这条
/// 翻译在真实环境里是常态而不是边角情况。
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

/// 名字太长的候选在按钮上的显示（避免按钮被撑到换行）。
String _shortName(String name) =>
    name.length > 12 ? '${name.substring(0, 12)}…' : name;

// ==================== 资源下载区（详情弹窗右栏） ====================

/// 详情弹窗里的「资源下载」区。
///
/// 只做三件事：一进来就查（缓存命中则不发请求）、把结果按来源分组列出、
/// 每个来源的失败单独展示。行内两个动作：
/// - **下载页**：`url_launcher` 外部浏览器打开发布页（失败给通知，不静默）；
/// - **入库**：与弹窗底部的入库是同一个动作——把**当前这部作品的元数据**
///   写进库（资源行只是链接，本身没有元数据），入库成功后按钮变「已在库」。
class ResourceLinkSection extends StatefulWidget {
  final ScrapedGame game;

  /// 入库链路（由详情弹窗提供，内部会查重 → insertGame → ScrapeApplier.apply）
  final Future<void> Function() onAdd;

  /// 当前作品是否已在库
  final bool inLibrary;

  /// 正在入库（显示进度并禁用按钮）
  final bool adding;

  const ResourceLinkSection({
    super.key,
    required this.game,
    required this.onAdd,
    required this.inLibrary,
    required this.adding,
  });

  @override
  State<ResourceLinkSection> createState() => _ResourceLinkSectionState();
}

class _ResourceLinkSectionState extends State<ResourceLinkSection> {
  late final String _key;
  late ValueNotifier<ResourceLinkState> _state;

  @override
  void initState() {
    super.initState();
    _key = discoverLibraryKey(widget.game);
    _state = ResourceLinkStore.instance.entry(_key);
    // 只在这里"发起"：不写 provider、也不 setState，因此不会撞上
    // Riverpod「不能在 initState 改 provider」/ 构建期改状态那两条断言；
    // 结果通过 ValueNotifier 流式回填。
    ResourceLinkStore.instance
        .ensureLoaded(_key, resourceNameCandidates(widget.game));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ResourceLinkState>(
      valueListenable: _state,
      builder: (context, s, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KSectionTitle('资源下载', trailing: _header(s)),
          Expanded(
            child: KScrollArea(
              // 常驻滚动条（KScrollArea 自带），但不要底部渐隐：渐隐用的是
              // 页面底色，在弹窗卡片的底色上会露出一条色差。
              bottomFade: false,
              padding: const EdgeInsets.only(right: Gap.sm, bottom: Gap.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _body(s),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 标题右侧：进度/计数徽标 + 重新搜索。
  Widget _header(ResourceLinkState s) {
    final Widget badge;
    if (s.busy) {
      badge = KBadge(
        text: s.total > 0 ? '${s.completed} / ${s.total}' : '搜索中',
        icon: Icons.cloud_download_outlined,
      );
    } else if (s.hasItems) {
      badge = KBadge(
        text: '共 ${s.itemCount} 条',
        icon: Icons.link_rounded,
        color: KisakiColors.lavender,
      );
    } else if (s.started) {
      badge = const KBadge(
        text: '没有结果',
        icon: Icons.search_off_rounded,
        color: KisakiColors.warning,
      );
    } else {
      badge = const KBadge(
        text: '准备中',
        icon: Icons.hourglass_empty_rounded,
        color: KisakiColors.info,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        KIconAction(
          icon: Icons.refresh_rounded,
          tooltip: '重新搜索资源站（从第一个名字重查一遍）',
          onTap: s.busy ? null : () => ResourceLinkStore.instance.restart(_key),
        ),
      ],
    );
  }

  List<Widget> _body(ResourceLinkState s) {
    final blocks = <Widget>[];
    if (s.busy) blocks.add(_progress(s));

    // 有结果的来源：每个来源一块（来源徽标 + 该来源的条目）
    for (final g in s.groups) {
      if (g.items.isNotEmpty) blocks.add(_sourceBlock(g));
    }

    if (s.hasItems) {
      // 有结果时：只把失败的来源单独收一张卡（说明"还有站没问到"）
      final failures = s.failures;
      if (failures.isNotEmpty) blocks.add(_failureCard(failures));
      return blocks;
    }

    // 没有任何结果：
    // 1) 先如实列出每个来源的结局（没有结果 / 具体错误），
    // 2) 再给空态与"换名字再搜"的出口。
    if (s.started) blocks.add(_outcomeCard(s));
    if (!s.busy) blocks.add(_empty(s));
    return blocks;
  }

  /// 加载态：进度文案（要求的「正在搜索资源站…」+ 已完成的来源数）+ 当前名字。
  Widget _progress(ResourceLinkState s) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 20, height: 20, child: KLoading(size: 16)),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.total > 0
                      ? '正在搜索资源站…（已完成 ${s.completed} / ${s.total}）'
                      : '正在搜索资源站…',
                  style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (s.name.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('正在用「${s.name}」搜索',
                      style:
                          Type.micro.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 某个来源有结果：来源徽标 + 条数 + 条目行。
  Widget _sourceBlock(ResourceSourceResult g) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KBadge(text: g.site, color: KisakiColors.lavender),
              const SizedBox(width: Gap.sm),
              Text('${g.items.length} 条',
                  style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: Gap.xs + 2),
          for (final it in g.items)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: _ResourceRow(
                item: it,
                inLibrary: widget.inLibrary,
                adding: widget.adding,
                onAdd: widget.onAdd,
              ),
            ),
        ],
      ),
    );
  }

  /// 有结果时：把失败的来源收成一张卡（**每个来源一行**，附具体原因）。
  Widget _failureCard(List<ResourceSourceResult> failures) {
    return KCard(
      flat: true,
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm + 2, Gap.md, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 15, color: KisakiColors.danger),
              const SizedBox(width: Gap.xs + 2),
              Text(
                '${failures.length} 个来源没问到结果',
                style: Type.caption.copyWith(color: KisakiColors.danger),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          for (final f in failures) _sourceStatusRow(f.site, f.error!),
        ],
      ),
    );
  }

  /// 一条结果都没有时：列出**所有**来源的结局（含"没有结果"与具体错误）。
  Widget _outcomeCard(ResourceLinkState s) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: KCard(
        flat: true,
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm + 2, Gap.md, Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.name.isEmpty ? '各来源结果' : '各来源结果（按「${s.name}」搜索）',
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gap.xs),
            for (final g in s.groups)
              _sourceStatusRow(g.site, g.error ?? '没有结果',
                  isError: g.error != null),
          ],
        ),
      ),
    );
  }

  /// 单个来源的结局行：`站名：原因`（失败用危险色，其余弱化）。
  Widget _sourceStatusRow(String site, String detail,
      {bool isError = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xxs),
      child: Text(
        '$site：$detail',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Type.micro.copyWith(
          color: isError ? KisakiColors.danger : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 空态：说清"试过哪些名字"，并给出换名字/重搜的出口。
  Widget _empty(ResourceLinkState s) {
    // 名字表为空（元数据里既没有原名也没有别名）：没有可靠的搜索入口，
    // 直接说明，而不是给一个点了没反应的按钮。
    if (!s.started) {
      return const KEmpty(
        icon: Icons.help_outline_rounded,
        title: '没有可用于搜索的作品名',
        subtitle: '这条元数据没有中文名/原名，无法自动去资源站搜索',
        compact: true,
      );
    }
    final next = s.nextName;
    final tried = s.tried.map((t) => '「$t」').join('、');
    final failed = s.failures.length;
    final notes = <String>[
      if (tried.isNotEmpty) '已用$tried搜过',
      if (failed > 0) '其中 $failed 个来源没能问通（见上）',
      next != null ? '可以换用另一个名字再试一次' : '可以点右上角的刷新按钮重搜',
    ];
    return KEmpty(
      icon: Icons.search_off_rounded,
      title: '没有找到资源链接',
      subtitle: notes.join('；'),
      actionLabel:
          next == null ? '重新搜索' : '用「${_shortName(next)}」再搜一次',
      actionIcon:
          next == null ? Icons.refresh_rounded : Icons.translate_rounded,
      onAction: () => next == null
          ? ResourceLinkStore.instance.restart(_key)
          : ResourceLinkStore.instance.searchNext(_key),
      compact: true,
    );
  }
}

/// 单条资源：标题 + 标签徽标 + 「下载页 / 入库」。
///
/// 说明：服务层的 [ResourceItem] 只有 站点/标题/链接/标签 四个字段（没有
/// 发布日期与大小——发布页上的这些信息在搜索结果里拿不到），因此这里不显示
/// 日期与体积，只显示站点（在分组标题上）与标签（免登录/需登录/需代理/补丁站）。
class _ResourceRow extends StatelessWidget {
  final ResourceItem item;
  final bool inLibrary;
  final bool adding;
  final Future<void> Function() onAdd;

  const _ResourceRow({
    required this.item,
    required this.inLibrary,
    required this.adding,
    required this.onAdd,
  });

  /// 打开下载页：外部浏览器；打不开要如实提示（链接失效是常态）。
  Future<void> _open() async {
    final uri = Uri.tryParse(item.url);
    if (uri == null || uri.host.isEmpty) {
      showNotice('链接不可用：${item.url}', error: true);
      return;
    }
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) showNotice('打开链接失败：${item.url}', error: true);
    } catch (e) {
      showNotice('打开链接失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KCard(
      // 嵌在弹窗卡片里：用 flat（只描边不投影），避免硬阴影叠加显脏
      flat: true,
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm + 2, Gap.sm, Gap.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: Gap.xs + 2,
                    runSpacing: Gap.xs,
                    children: [
                      for (final t in item.tags)
                        KBadge(text: t, color: _tagColor(t, scheme)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          KPill(
            label: '下载页',
            icon: Icons.open_in_new_rounded,
            filled: false,
            onTap: _open,
          ),
          const SizedBox(width: Gap.xs + 2),
          if (adding)
            const SizedBox(width: 72, height: 36, child: KLoading(size: 16))
          else
            KPill(
              label: inLibrary ? '已在库' : '入库',
              icon: inLibrary
                  ? Icons.check_rounded
                  : Icons.library_add_rounded,
              onTap: inLibrary ? null : () => onAdd(),
            ),
        ],
      ),
    );
  }

  /// 标签配色（沿用旧「资源搜索」页的语义色）：免登录=清爽的青（最省事），
  /// 需代理=警告色（要挂代理才打得开），需登录=淡紫（要账号，但不是错误），
  /// 其余（补丁站等）弱化。
  static Color _tagColor(String tag, ColorScheme scheme) {
    if (tag == ResourceTag.noLogin) return const Color(0xFF3F9E97);
    if (tag == ResourceTag.needMagic) return KisakiColors.warning;
    if (tag == ResourceTag.needLogin) return KisakiColors.lavender;
    return scheme.onSurfaceVariant;
  }
}
