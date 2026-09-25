/// 游玩期间「游戏往哪里写了文件」的写入监视器（Windows 专用）。
///
/// 为什么需要它：galgame 的存档位置极不规范 —— 可能叫 `savedata`，也可能是
/// `%APPDATA%\<厂商>\<游戏>\` 这种与标题毫无关系的层级，甚至是作者名的罗马音。
/// 纯关键词 / 名字匹配经常落空，而**游玩期间被写入的文件**几乎无法伪造：
/// 存档只可能由游戏在运行时写出来。因此这条线索在检测器里拿最高置信度（95）。
///
/// 生命周期：由 [PlaytimeTracker] 在开始跟踪时 `start()`、会话结束时 `stop()`；
/// 命中结果按 gameId 记在进程内的 [lastHits] 里（内存级、重启即失效），
/// 供检测器（save_dir_detector）与 UI 读取。
///
/// 性能与安全（监视器绝不能拖慢游戏）：
/// - 目录遍历一律走**异步 IO**，不阻塞 UI isolate；
/// - 每轮轮询都有「目录数 / stat 次数 / 时间预算」三重上限；
/// - 所有 IO 异常静默降级；监视器不抛异常、不写任何文件、不启子进程。
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/media_paths.dart';

/// 用户目录下的标准位置（Windows 惯例）+ 它的置信度基线。
///
/// 检测器与监视器**共用这一份清单**：两处各写一份的话后续很容易漂移
/// （比如只给检测器补了 LocalLow，监视器还在扫旧的根）。因此把
/// 「路径 + 中文说明 + 置信度」放在一起，检测器直接引用。
class SaveWatchRoot {
  /// 绝对路径（目录可能不存在）
  final String path;

  /// 中文来源说明，用于候选的 reason，如「AppData\Roaming」
  final String label;

  /// 目录名规范化后**等于**游戏名变体时的置信度
  final int exactConfidence;

  /// 目录名规范化后**包含**游戏名变体时的置信度（误匹配概率更高，故略低）
  final int partialConfidence;

  const SaveWatchRoot(
      this.path, this.label, this.exactConfidence, this.partialConfidence);
}

class SaveWriteWatcher {
  SaveWriteWatcher();

  /// 轮询间隔：存档写入是低频事件，25 秒足够，也避免长期占用磁盘。
  static const pollInterval = Duration(seconds: 25);

  /// 相对监视根最多下沉的层数（再深就属于「翻遍硬盘」，得不偿失）
  static const maxDepth = 3;

  // 每轮上限：宁可漏掉极端情况，也不能让轮询把磁盘/CPU 吃满。
  // 800 个目录 × 每目录一次目录项读取，实测在开发机上约 0.3~0.8 秒。
  static const _maxDirsPerPoll = 800;
  static const _maxStatsPerPoll = 8000;
  static const _pollBudget = Duration(milliseconds: 1200);
  static const _stopBudget = Duration(milliseconds: 600);

  int? _gameId;
  DateTime? _since;
  List<String> _roots = const [];
  Timer? _timer;

  /// 代际计数：start/stop 时自增，让「上一轮还在飞的扫描」立刻作废，
  /// 避免两次扫描并发写 _hits。
  int _gen = 0;
  bool _scanning = false;

  /// 目录 → 本轮命中的文件数（跨轮取最大值，同一次写入不会被重复计数）
  final Map<String, int> _hits = {};

  /// 最近一次会话的命中目录（进程内）。只在有命中时写入，
  /// 所以「这一轮没写文件」不会把上一轮的证据抹掉。
  static final Map<int, List<String>> _lastHits = {};

  /// 是否正在监视。
  bool get active => _timer != null;

  /// 正在监视的游戏 id（无则 null）。
  int? get watchedGameId => _gameId;

  /// 读取某个游戏最近一次会话的命中目录（按写入文件数降序，去重）。
  static List<String> lastHits(int gameId) =>
      List.unmodifiable(_lastHits[gameId] ?? const <String>[]);

  /// 清空全部会话记录（单测 / 诊断用）。
  static void clearAll() => _lastHits.clear();

  /// 开始监视。[since] 为本次会话开始时间，只把 mtime 晚于它的文件算作写入。
  void start(int gameId, {required String gameDir, required DateTime since}) {
    _teardown(); // 上一段会话（若未正常 stop）直接丢弃
    _gameId = gameId;
    _since = since;
    _roots = watchRoots(gameDir: gameDir);
    _hits.clear();
    // 启动瞬间游戏还没写任何东西，立即扫一轮纯属浪费；
    // 第一个轮询周期后再开始，启动阶段零开销。
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_sweep()));
  }

  /// 结束监视：补最后一轮扫描（抓住会话末尾写下的存档），
  /// 返回命中目录（去重、按写入文件数降序）并记入 [lastHits]。
  Future<List<String>> stop() async {
    if (_timer == null && _gameId == null) return const <String>[];
    final id = _gameId;
    // 先记下「结束这一刻」的命中：下面的补扫要 await，期间如果用户又启动了
    // 另一个游戏（start 会清空 _hits），这份快照就是本次会话的最终结果
    final snapshot = _sortedHits();
    _teardown();
    final gen = _gen;
    // 等在飞的扫描退出（它已被代际判定为过期），避免两个扫描并发写 _hits
    for (var i = 0; i < 30 && _scanning; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    try {
      await _scanOverRoots(gen: gen, budget: _stopBudget);
    } catch (_) {}
    final sameSession = gen == _gen;
    final hits = sameSession ? _sortedHits() : snapshot;
    if (id != null && hits.isNotEmpty) _lastHits[id] = hits;
    // 期间已有新会话开始的话，状态归它所有，这里不能重置
    if (sameSession) _reset();
    return hits;
  }

  /// 一次性扫描（不进会话记录、不启定时器）。
  ///
  /// 兜底用途：用户没经过一次完整会话（或应用刚重启、内存记录已丢）就直接点
  /// 「智能识别存档目录」时，用「当前会话开始 / 最近 30 分钟」当窗口扫一遍，
  /// 仍然能拿到写入线索。
  static Future<List<String>> scanNow({
    String? gameDir,
    required DateTime since,
    Duration budget = const Duration(milliseconds: 1200),
  }) async {
    final w = SaveWriteWatcher()
      .._since = since
      .._roots = watchRoots(gameDir: gameDir);
    try {
      await w._scanOverRoots(gen: w._gen, budget: budget);
    } catch (_) {}
    return w._sortedHits();
  }

  // ============================ 路径清单 ============================

  /// 用户目录下的标准位置（按「最可能存放存档」排序，置信度见字段注释）。
  ///
  /// 名字变体匹配只在这些根下做**一级子目录**匹配（检测器），写入监视则
  /// 在这些根下下沉 [maxDepth] 层 —— 两条线索的覆盖范围必须一致，
  /// 否则会出现「监视器发现了某目录，检测器却因为不在根清单里而忽略」。
  static List<SaveWatchRoot> standardUserRoots() {
    final env = Platform.environment;
    String v(String key) => (env[key] ?? '').trim();
    final roaming = v('APPDATA'); // %APPDATA% = AppData\Roaming
    final local = v('LOCALAPPDATA');
    final profile = v('USERPROFILE');
    final docs = profile.isEmpty ? '' : p.join(profile, 'Documents');
    String under(String base, String name) =>
        base.isEmpty ? '' : p.join(base, name);

    return <SaveWatchRoot>[
      // Roaming 是存档最常见的去处（大多数日文游戏、RPG Maker、Kirikiri）
      if (roaming.isNotEmpty)
        SaveWatchRoot(roaming, r'AppData\Roaming', 85, 80),
      if (local.isNotEmpty) SaveWatchRoot(local, r'AppData\Local', 82, 76),
      // Unity 游戏（PlayerPrefs / 用户数据）默认落在 LocalLow
      if (profile.isNotEmpty)
        SaveWatchRoot(
            under(under(profile, 'AppData'), 'LocalLow'), r'AppData\LocalLow', 83, 77),
      // 欧美游戏与部分日厂用「我的文档\My Games」
      if (docs.isNotEmpty) SaveWatchRoot(docs, '文档', 74, 70),
      if (docs.isNotEmpty)
        SaveWatchRoot(under(docs, 'My Games'), r'文档\My Games', 84, 79),
      if (profile.isNotEmpty)
        SaveWatchRoot(under(profile, 'Saved Games'), 'Saved Games', 83, 78),
      if (docs.isNotEmpty)
        SaveWatchRoot(under(docs, 'Saved Games'), r'文档\Saved Games', 83, 78),
    ].where((r) => r.path.isNotEmpty).toList();
  }

  /// 监视根 = 游戏目录 + 用户目录标准位置。
  ///
  /// `%TEMP%` 不在清单里；它通常位于 `%LOCALAPPDATA%\Temp` 之下，
  /// 而 `temp` 已进 [isNoiseDir] 黑名单，因此不会被扫到。
  static List<String> watchRoots({String? gameDir}) {
    final raw = <String>[
      if (gameDir != null && gameDir.trim().isNotEmpty) gameDir.trim(),
      for (final r in standardUserRoots()) r.path,
    ];
    final appRoot = _appDataRoot();
    final seen = <String>{};
    final kept = <String>[];
    for (final r in raw) {
      final norm = p.normalize(r);
      final lower = norm.toLowerCase();
      if (!seen.add(lower)) continue;
      // 本应用自己的数据目录（db / 封面缓存 / 日志）在游玩期间必然有写入，
      // 如果被当成「游戏写入」会凭空多出一个高置信度的错误候选
      if (appRoot.isNotEmpty &&
          (p.equals(norm, appRoot) || p.isWithin(appRoot, norm))) {
        continue;
      }
      // 已被更浅的根覆盖（如 文档\My Games 在 文档 之内）就丢掉，
      // 省下的配额留给别的根
      if (kept.any((k) => p.equals(k, norm) || p.isWithin(k, norm))) continue;
      kept.add(norm);
    }
    return kept;
  }

  /// 本应用的数据根目录（便携模式为 exe 同目录 data/，否则应用支持目录）。
  static String _appDataRoot() {
    try {
      return p.normalize(MediaPaths.instance.root);
    } catch (_) {
      return '';
    }
  }

  // ============================ 噪音过滤 ============================

  /// 明显与存档无关的目录名（小写比较）：缓存、日志、崩溃转储、浏览器内核等。
  ///
  /// 检测器也复用这个判断 —— 一条命中线索如果落在 GPUCache / Crashpad 里，
  /// 那只能是误报。
  static const _noiseDirs = <String>{
    // 缓存 / 渲染缓存
    'cache', 'caches', 'gpucache', 'code cache', 'gpu cache', 'dawncache',
    'dawn webgpu cache', 'shadercache', 'grshadercache', 'd3dscache',
    'htmlcache', 'webcache', 'blob_storage', 'indexeddb', 'local storage',
    'session storage', 'service worker', 'leveldb',
    // 日志 / 崩溃
    'crashpad', 'crashdumps', 'logs', 'log', 'temp', 'tmp',
    // 浏览器内核 / 常见运行时（体量巨大且与存档无关）
    'chrome', 'chromium', 'google', 'mozilla', 'firefox', 'edge',
    'brave-browser', 'vivaldi', 'opera', 'opera software', 'cef', 'electron',
    'webview2', 'packages', 'microsoft', 'nvidia', 'intel', 'amd', 'dotnet',
    'nuget', 'npm', 'pip', 'pub', 'steam', 'steamapps',
    // 开发工具链
    'node_modules', '.git', '.svn', '.gradle', '.cache',
    // 本应用自己的数据目录（db / 封面缓存会在游玩期间被写入）
    'kisakigals',
  };

  /// 噪音文件后缀（小写）：日志、临时文件、转储 —— 游戏写这些不代表是存档。
  static const _noiseExt = <String>[
    '.log', '.tmp', '.dmp', '.etl', '.pid', '.lock', '.part', '.crdownload',
  ];

  /// 目录名是否属于明显噪音（检测器与监视器共用）。
  static bool isNoiseDir(String name) =>
      _noiseDirs.contains(name.trim().toLowerCase());

  /// 文件名是否属于明显噪音。
  static bool isNoiseFile(String name) {
    final lower = name.toLowerCase();
    for (final ext in _noiseExt) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  // ============================ 扫描实现 ============================

  void _teardown() {
    _timer?.cancel();
    _timer = null;
    _gen++; // 在飞的扫描看到代际变化会自行退出
  }

  void _reset() {
    _gameId = null;
    _since = null;
    _roots = const [];
    _hits.clear();
    _gen++;
  }

  /// 定时轮询入口：上一轮没结束就跳过（磁盘慢时不会堆积任务）。
  Future<void> _sweep() async {
    if (_scanning) return;
    _scanning = true;
    final gen = _gen;
    try {
      await _scanOverRoots(gen: gen, budget: _pollBudget);
    } catch (_) {
      // 监视失败绝不冒泡：游戏该照常运行
    } finally {
      _scanning = false;
      _publish();
    }
  }

  /// 把当前命中同步到 [lastHits]：游戏还在跑时用户就能打开编辑页看到线索。
  void _publish() {
    final id = _gameId;
    if (id == null) return;
    final hits = _sortedHits();
    if (hits.isEmpty) return;
    _lastHits[id] = hits;
  }

  Future<void> _scanOverRoots({
    required int gen,
    required Duration budget,
  }) async {
    final since = _since;
    if (since == null || _roots.isEmpty) return;
    final limit = _WalkBudget(budget);
    // 本轮局部计数，扫完再与历史取最大值合并：
    // 同一个文件在后续轮询里会被反复看到，直接累加会越滚越大
    final local = <String, int>{};
    for (final root in _roots) {
      if (gen != _gen || limit.expired) break;
      await _walk(root, since: since, gen: gen, limit: limit, hit: local);
    }
    // 期间会话已切换（start/stop）：本轮结果作废，绝不能写进新会话的 _hits
    if (gen != _gen) return;
    local.forEach((dir, count) {
      final old = _hits[dir] ?? 0;
      if (count > old) _hits[dir] = count;
    });
  }

  /// 广度优先遍历一个根，记录「mtime > since 的文件」所在的目录。
  Future<void> _walk(
    String root, {
    required DateTime since,
    required int gen,
    required _WalkBudget limit,
    required Map<String, int> hit,
  }) async {
    final queue = <(String, int)>[(root, 0)];
    while (queue.isNotEmpty) {
      if (gen != _gen || limit.expired) return;
      final (dir, depth) = queue.removeAt(0);
      limit.dirs++;
      List<FileSystemEntity> entries;
      try {
        // 异步列目录：不阻塞 UI isolate；followLinks=false 让符号链接
        // 以 Link 形式出现（下面直接忽略），避免环状递归
        entries = await Directory(dir).list(followLinks: false).toList();
      } catch (_) {
        continue; // 权限不足 / 目录被占用：跳过
      }
      for (final e in entries) {
        if (e is Directory) {
          if (depth + 1 > maxDepth) continue;
          if (isNoiseDir(p.basename(e.path))) continue;
          queue.add((e.path, depth + 1));
        } else if (e is File) {
          final name = p.basename(e.path);
          if (isNoiseFile(name)) continue;
          if (++limit.stats > _maxStatsPerPoll) return;
          try {
            final st = await e.stat();
            // 存档是「写入」出来的：新建或覆盖都会刷新 mtime
            if (st.modified.isAfter(since)) {
              hit.update(dir, (v) => v + 1, ifAbsent: () => 1);
            }
          } catch (_) {
            // 扫描期间文件被删除 / 被独占：忽略
          }
        }
      }
    }
  }

  /// 命中目录：按写入文件数降序，同数按路径排序（结果稳定，便于测试）。
  List<String> _sortedHits() {
    final entries = _hits.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [for (final e in entries) e.key];
  }
}

/// 单轮扫描的预算：目录数 / stat 次数 / 时间三重上限，任一触顶即停止。
class _WalkBudget {
  final DateTime deadline;
  int dirs = 0;
  int stats = 0;

  _WalkBudget(Duration budget) : deadline = DateTime.now().add(budget);

  bool get expired =>
      dirs >= SaveWriteWatcher._maxDirsPerPoll ||
      stats >= SaveWriteWatcher._maxStatsPerPoll ||
      DateTime.now().isAfter(deadline);
}
