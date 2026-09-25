/// 智能识别游戏的存档读写目录：把多个来源的线索汇总成一份候选列表。
///
/// 背景：Galgame 的存档位置几乎无法用单一规则命中 ——
/// - 有的直接放在游戏目录里（`savedata` / `save` / `セーブ` / `存档`）；
/// - 有的按 Windows 惯例放到 `%APPDATA%\<厂商>\<游戏>\`（名字常是罗马音缩写）；
/// - 有的（Unity）落在 `%APPDATA%\..\LocalLow\<公司>\<产品名>`；
/// - 有的把路径写在注册表里，运行时才创建目录；
/// - 还有的用完全无关的目录名（如以作者名命名），只能靠「运行期间往哪写」判断。
///
/// 因此 [detect] 同时跑四类来源（游戏目录 / 用户目录标准位置 / 注册表 / 写入线索），
/// 去重后按置信度降序返回，交由用户选择（UI 见 save_dir_picker_dialog.dart）。
///
/// 设计约束：
/// - 每个来源都 try/catch 静默降级，一个来源失败不影响其它来源；
/// - 所有扫描都有上限，且整体时间预算 [ _budget ]（约 1.5 秒），超时即截断；
/// - 只读：不创建、不修改任何文件。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils.dart';
import '../data/models.dart';
import 'save_write_watcher.dart';

/// 一个「疑似存档目录」候选。
class SaveDirCandidate {
  /// 绝对路径
  final String path;

  /// 中文来源说明，例如「游戏目录内 savedata」「AppData 下与开发商同名」
  final String reason;

  /// 目录内文件数（递归，统计有上限）
  final int fileCount;

  /// 目录内最近的修改时间（无文件/不可读时为 null）
  final DateTime? lastModified;

  /// 0-100，用于排序与展示（阈值见 UI：≥90 高 / 70-89 中 / 其它 低）
  final int confidence;

  /// 路径当前是否存在。false 也要列出来（注册表/写入线索可能指向未创建的目录）
  final bool exists;

  const SaveDirCandidate({
    required this.path,
    required this.reason,
    this.fileCount = 0,
    this.lastModified,
    this.confidence = 0,
    this.exists = true,
  });

  /// 路径末两段（UI 主标题；完整路径放 Tooltip，避免长路径撑爆一行）
  String get shortPath {
    final parts =
        path.split(p.separator).where((e) => e.isNotEmpty).toList();
    if (parts.length <= 2) return path;
    return '…${p.separator}${parts[parts.length - 2]}${p.separator}${parts.last}';
  }

  /// 可信度档位（UI 徽标用）
  String get confidenceLevel =>
      confidence >= 90 ? '高' : (confidence >= 70 ? '中' : '低');
}

class SaveDirDetector {
  /// 整体时间预算：四个来源并发跑，谁跑完算谁，超时截断。
  /// 检测是在用户点按钮后同步等待的，超过 1.5 秒就该给结果了。
  static const _budget = Duration(milliseconds: 1500);

  /// 一个根目录下最多看多少个一级子目录
  static const _maxRootEntries = 500;

  /// 统计文件数时的上限
  static const _maxCountFiles = 2000;

  /// 取 mtime 时最多 stat 多少个文件。
  ///
  /// 列目录很便宜、逐个 stat 很贵：`%LOCALAPPDATA%\<大应用>` 这类目录动辄几千
  /// 个文件，十几个写入线索全量 stat 会直接吃满检测预算。存档目录通常只有几十
  /// 个文件，取前 [_maxStatFiles] 个足以反映「最近有没有被写过」。
  static const _maxStatFiles = 800;

  /// 写入线索目录专用的更小上限：它们的文件数往往很大，而置信度已经是最高档，
  /// mtime 只用于展示与加分，粗略取前 120 个即可。
  static const _maxStatFilesForHit = 120;

  /// 每个根目录最多对几个「命中名字」的目录再下沉一层
  static const _maxMatchedDirsPerRoot = 8;

  /// 下沉一层时最多看多少个子目录
  static const _maxChildEntries = 40;

  /// 游戏目录二级扫描时最多下沉多少个一级子目录
  static const _maxGameDirDescend = 200;

  /// 注册表最多深入几个命中的一级键
  static const _maxRegistryKeys = 6;

  /// 汇总所有来源，去重 + 按 confidence 降序返回。
  ///
  /// [writeHits] 由 [SaveWriteWatcher] 提供（游戏运行期间有新文件写入的目录），
  /// [since] 为「最近一次运行开始时间」：晚于它被修改过的候选会获得小幅加分
  /// （上限 94，保证写入线索 95 永远排第一）。
  static Future<List<SaveDirCandidate>> detect(
    Game game, {
    List<String> writeHits = const [],
    DateTime? since,
  }) async {
    // 四个来源共用同一个截止时间：并发执行，总耗时 ≈ 最慢的那个
    final deadline = DateTime.now().add(_budget);
    final variants = nameVariants(game);
    final developers = _variantsOf([game.developer]);
    // 写入线索 = 调用方传入的 + 本进程内监视器记录的（游戏刚结束会话时后者非空）
    final hits = <String>{
      for (final h in writeHits)
        if (h.trim().isNotEmpty) h.trim(),
      ...SaveWriteWatcher.lastHits(game.id ?? -1),
    };

    final jobs = <Future<List<SaveDirCandidate>>>[
      _guard(() => _fromGameDir(game, deadline)),
      _guard(() => _fromUserDirs(variants, developers, deadline)),
      _guard(() => _fromRegistry(variants, developers, deadline)),
      _guard(() => _fromWriteHits(hits, deadline)),
    ];
    final all = <SaveDirCandidate>[];
    for (final job in jobs) {
      all.addAll(await job);
    }
    return _merge(all, since);
  }

  // ============================ 来源 1：游戏目录内 ============================

  /// 游戏目录内的一级 / 二级子目录关键词扫描（[SaveScanner] 的扩展版：
  /// 不只返回「最像的那个」，而是把所有命中都列出来，并排除程序目录）。
  static Future<List<SaveDirCandidate>> _fromGameDir(
      Game game, DateTime deadline) async {
    final root = game.directory.trim();
    if (root.isEmpty || !await Directory(root).exists()) return const [];
    final out = <SaveDirCandidate>[];
    var descended = 0;
    for (final dir in await _listDirs(root, _maxRootEntries)) {
      if (_expired(deadline) || descended >= _maxGameDirDescend) break;
      final name = p.basename(dir);
      // bin / plugin / patch / 汉化补丁 之类即使名字带 save 也不是存档目录
      if (_isProgramDir(name) || _nameExcluded(name)) continue;
      if (_saveKeywordOf(name) != null) {
        out.add(await _candidate(dir, 90, '游戏目录内 $name', deadline: deadline));
      }
      descended++;
      for (final sub in await _listDirs(dir, _maxChildEntries)) {
        if (_expired(deadline)) break;
        final subName = p.basename(sub);
        if (_isProgramDir(subName) || _nameExcluded(subName)) continue;
        if (_saveKeywordOf(subName) == null) continue;
        // 二级命中多一层间接（game/data/save），误判概率略高，故 90 → 87
        out.add(await _candidate(sub, 87, '游戏目录内 $name\\$subName',
            deadline: deadline));
      }
    }
    return out;
  }

  // ==================== 来源 2：用户目录标准位置（同名） ====================

  /// 在各用户目录标准位置下做**一级子目录名匹配**（性能考虑，不做深度递归）。
  ///
  /// 两级命中：
  /// - 目录名与游戏名变体相等 → 置信度高（见 [SaveWatchRoot.exactConfidence]）；
  ///   只「包含」变体（如 `ATRI_savedata`）略低；
  /// - 厂商名命中的目录再下沉一层（`%APPDATA%\<公司>\<游戏>` 这种层级极常见），
  ///   因为多了一次推断，置信度在基础上再降 4。
  static Future<List<SaveDirCandidate>> _fromUserDirs(
    Map<String, String> variants,
    Map<String, String> developers,
    DateTime deadline,
  ) async {
    if (variants.isEmpty && developers.isEmpty) return const [];
    final out = <SaveDirCandidate>[];
    for (final root in SaveWriteWatcher.standardUserRoots()) {
      if (_expired(deadline)) break;
      var matched = 0;
      for (final child in await _listDirs(root.path, _maxRootEntries)) {
        if (_expired(deadline) || matched >= _maxMatchedDirsPerRoot) break;
        final name = p.basename(child);
        if (_nameExcluded(name)) continue;
        final key = normKey(name);
        if (key.length < 3) continue;

        final tier = _matchTier(key, variants);
        if (tier > 0) {
          matched++;
          final base =
              tier == 2 ? root.exactConfidence : root.partialConfidence;
          out.add(await _candidate(
            child,
            base,
            tier == 2
                ? '${root.label} 下与游戏同名'
                : '${root.label} 下名称包含游戏名',
            deadline: deadline,
          ));
          // 再下沉一层：`%APPDATA%\游戏名\savedata` 这种「游戏名目录里套存档名」
          out.addAll(await _scanChildren(
            parent: child,
            label: '${root.label}\\$name',
            variants: variants,
            viaGameNameConfidence: base + 2,
            viaKeywordConfidence: base + 3,
            deadline: deadline,
          ));
          continue;
        }

        // 厂商目录：游戏名往往在下一层，只把「下一层命中的那个」当候选
        // （厂商目录本身几乎不会是存档目录，不该列出来干扰用户）
        if (developers.isEmpty || _matchTier(key, developers) == 0) continue;
        matched++;
        final base = (developers.containsKey(key)
                ? root.exactConfidence
                : root.partialConfidence) -
            4;
        out.addAll(await _scanChildren(
          parent: child,
          label: '${root.label}\\$name',
          variants: variants,
          viaGameNameConfidence: base,
          viaKeywordConfidence: base - 2,
          deadline: deadline,
        ));
      }
    }
    return out;
  }

  /// 在 [parent] 的一级子目录里找按「游戏名」或「存档关键词」命名的目录。
  static Future<List<SaveDirCandidate>> _scanChildren({
    required String parent,
    required String label,
    required Map<String, String> variants,
    required int viaGameNameConfidence,
    required int viaKeywordConfidence,
    required DateTime deadline,
  }) async {
    final out = <SaveDirCandidate>[];
    for (final sub in await _listDirs(parent, _maxChildEntries)) {
      if (_expired(deadline)) break;
      final name = p.basename(sub);
      if (_isProgramDir(name) || _nameExcluded(name)) continue;
      if (_matchTier(normKey(name), variants) > 0) {
        out.add(await _candidate(
            sub, viaGameNameConfidence, '$label 下与游戏同名',
            deadline: deadline));
      } else if (_saveKeywordOf(name) != null) {
        out.add(await _candidate(
            sub, viaKeywordConfidence, '$label 内的 $name',
            deadline: deadline));
      }
    }
    return out;
  }

  // ============================ 来源 3：注册表 ============================

  /// 注册表线索（galgame 常把存档路径写在这里，也是唯一能拿到「明确路径」的来源）。
  ///
  /// 为什么不做 `reg query HKCU\Software /s /f <名字>`：全表递归搜索要几百毫秒
  /// 到数秒，期间还会刷出大量无关键。这里只查两层：
  /// ① `HKCU\Software` 的一级子键（= 厂商名 / 产品名），按厂商名或游戏名筛；
  /// ② 命中的键再查一次，拿它的子键与值：值里带路径的优先当候选，
  ///    只有键没有值时才按「同名目录」的惯例去用户目录里找。
  static Future<List<SaveDirCandidate>> _fromRegistry(
    Map<String, String> variants,
    Map<String, String> developers,
    DateTime deadline,
  ) async {
    if (!Platform.isWindows) return const [];
    final out = <SaveDirCandidate>[];
    final rootLines = await _regQuery(r'HKCU\Software');
    if (rootLines.isEmpty) return const [];

    final matched = <String>[];
    for (final sub in _subKeysOf(rootLines)) {
      if (matched.length >= _maxRegistryKeys) break;
      final key = normKey(sub);
      if (key.length < 3) continue;
      if (_matchTier(key, variants) > 0 || _matchTier(key, developers) > 0) {
        matched.add(sub);
      }
    }
    if (matched.isEmpty) return const [];

    // 并发查询：6 个 reg.exe 串行会吃满整个时间预算
    final results = await Future.wait([
      for (final key in matched) _regQuery('HKCU\\Software\\$key'),
    ]);

    for (var i = 0; i < matched.length; i++) {
      if (_expired(deadline)) break;
      final company = matched[i];
      final companyKey = 'HKCU\\Software\\$company';
      final lines = results[i];
      // ① 厂商键自己的值里可能直接写着存档路径
      out.addAll(await _valueCandidates(lines, companyKey, deadline));

      // ② 游戏名（或存档关键词）命中的子键
      for (final sub in _subKeysOf(lines)) {
        if (_expired(deadline)) break;
        if (sub.toLowerCase() == company.toLowerCase()) continue;
        final key = normKey(sub);
        if (key.length < 3) continue;
        if (_matchTier(key, variants) == 0 && _saveKeywordOf(sub) == null) {
          continue;
        }
        final gameKey = '$companyKey\\$sub';
        final subLines = await _regQuery('HKCU\\Software\\$company\\$sub');
        final found = await _valueCandidates(subLines, gameKey, deadline);
        if (found.isNotEmpty) {
          out.addAll(found);
        } else {
          out.add(await _deriveFromKey(gameKey, company, sub, deadline));
        }
      }
    }
    return out;
  }

  /// 从 `reg query` 输出里挑出「看起来是路径」的值，产出候选。
  /// 值名带 save/data/dir/path 的优先级更高（如 `SavePath`、`SaveDataDir`）。
  static Future<List<SaveDirCandidate>> _valueCandidates(
    List<String> lines,
    String keyPath,
    DateTime deadline,
  ) async {
    final ranked = <(int, String)>[];
    for (final line in lines) {
      final parsed = _parseValue(line);
      if (parsed == null) continue;
      final (name, data) = parsed;
      final dir = _asDirectory(data);
      if (dir == null) continue;
      final lower = name.toLowerCase();
      var score = 0;
      if (lower.contains('save')) score += 2;
      if (lower.contains('data') ||
          lower.contains('dir') ||
          lower.contains('path') ||
          lower.contains('folder')) {
        score += 1;
      }
      ranked.add((score, dir));
    }
    ranked.sort((a, b) => b.$1.compareTo(a.$1));

    final out = <SaveDirCandidate>[];
    var taken = 0;
    for (final (_, dir) in ranked) {
      if (_expired(deadline) || taken >= 2) break;
      taken++;
      final stat = await _statDir(dir, deadline: deadline);
      // 注册表里明确写着的路径：目录存在时很可信（88）；
      // 目录不存在说明游戏还没跑过（或需要在日文区下才创建），给中等分并说明
      out.add(_make(
        dir,
        stat.$1 ? 88 : 60,
        stat.$1
            ? '注册表 $keyPath 记录的路径'
            : '注册表 $keyPath（仅注册表存在，可能需要转区运行）',
        stat,
      ));
    }
    return out;
  }

  /// 注册表有键、但没有可用的路径值时的兜底：
  /// 按「目录名 = 厂商/游戏名」的惯例在用户目录标准位置下找同名目录，
  /// 存在才算数；都不存在则给出一条「仅注册表存在」的提示候选
  /// （对话框里会置灰、不可选，只让用户知道注册表里有这个游戏）。
  static Future<SaveDirCandidate> _deriveFromKey(
    String keyPath,
    String company,
    String sub,
    DateTime deadline,
  ) async {
    final roots = SaveWriteWatcher.standardUserRoots();
    for (final root in roots) {
      final guess = company.isEmpty
          ? p.join(root.path, sub)
          : p.join(root.path, company, sub);
      if (await Directory(guess).exists()) {
        return _candidate(guess, 84, '$keyPath 对应的目录（按注册表厂商/游戏名推断）',
            deadline: deadline);
      }
    }
    // 都不存在：退回 Roaming 下的「惯例路径」占位（roots 首项即 Roaming）
    final roaming = roots.isEmpty ? '' : roots.first.path;
    final fallback = company.isEmpty
        ? p.join(roaming, sub)
        : p.join(roaming, company, sub);
    return _candidate(
        fallback, 60, '注册表 $keyPath（仅注册表存在，可能需要转区运行）',
        deadline: deadline);
  }

  /// 执行 `reg query <key>`；键不存在 / reg 被策略禁用 / 超时都返回空列表，
  /// 绝不抛异常 —— 少一个来源远好过整个检测失败。
  static Future<List<String>> _regQuery(String key) async {
    try {
      final result = await Process.run(_regExe, ['query', key])
          .timeout(const Duration(milliseconds: 900));
      if (result.exitCode != 0) return const [];
      // 中文 Windows 下 reg 输出是本地代码页，Process.run 默认按
      // systemEncoding（= 系统 ANSI 代码页）解码，中文键名才能正确还原
      return '${result.stdout}'.split(RegExp(r'\r?\n'));
    } catch (_) {
      return const [];
    }
  }

  /// reg.exe 绝对路径（不依赖 PATH；取不到时退回裸命令名交给系统解析）。
  static String get _regExe {
    final windir = (Platform.environment['SystemRoot'] ?? r'C:\Windows').trim();
    final full = p.join(windir, 'System32', 'reg.exe');
    return File(full).existsSync() ? full : 'reg';
  }

  /// 取 `reg query` 输出里的子键名（只看 HKEY_ 开头的行，取最后一段）。
  static List<String> _subKeysOf(List<String> lines) {
    final out = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (!line.toUpperCase().startsWith('HKEY_')) continue;
      final i = line.lastIndexOf('\\');
      final name = i >= 0 ? line.substring(i + 1) : line;
      if (name.isEmpty) continue;
      out.add(name);
      if (out.length >= 400) break; // HKCU\Software 正常几百个键，防御异常输出
    }
    return out;
  }

  /// 解析 `reg query` 的值行：`    SavePath    REG_SZ    D:\save`。
  /// 子键行（HKEY_ 开头）与空行返回 null。
  static (String, String)? _parseValue(String raw) {
    final line = raw.trim();
    if (line.isEmpty || line.toUpperCase().startsWith('HKEY_')) return null;
    // reg 用 4 个空格分列；值名与数据本身可能含空格，故按「4 个以上空格」切
    final parts = line.split(RegExp(r'\s{4,}'));
    if (parts.length < 3) return null;
    if (!parts[1].trim().toUpperCase().startsWith('REG_')) return null;
    return (parts[0].trim(), parts.sublist(2).join('    ').trim());
  }

  /// 把注册表里的值转成「目录」：展开 %VAR%、去引号、必要时取父目录。
  /// 不像绝对路径的一律返回 null（注册表里绝大多数值都不是路径）。
  static String? _asDirectory(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // %APPDATA%\Foo 这类写法在注册表里很常见，先展开
    s = s.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) {
      final v = Platform.environment[m.group(1)!];
      return v ?? m.group(0)!;
    });
    s = s.replaceAll('"', '').trim();
    final isAbsolute =
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(s) || s.startsWith(r'\\');
    if (!isAbsolute) return null;
    var dir = p.normalize(s);
    // 值指向文件时取父目录（存档路径常写成 ...\save.dat）
    if (_fileLikeExt.contains(p.extension(dir).toLowerCase())) {
      dir = p.dirname(dir);
    }
    return dir;
  }

  /// 像文件名的后缀（用于判断注册表里的值指向文件还是目录）
  static const _fileLikeExt = <String>{
    '.exe', '.dat', '.sav', '.ini', '.txt', '.json', '.bin', '.cfg', '.log',
    '.xml', '.db', '.dll', '.sys',
  };

  // ============================ 来源 4：写入线索 ============================

  /// 游玩期间有新文件写入的目录：几乎无法伪造的证据，置信度最高。
  static Future<List<SaveDirCandidate>> _fromWriteHits(
      Set<String> hits, DateTime deadline) async {
    final out = <SaveDirCandidate>[];
    for (final hit in hits) {
      if (_expired(deadline)) break;
      if (hit.trim().isEmpty) continue;
      // 命中的是缓存/日志目录时，只能说明游戏在写缓存，不是存档。
      // 只查「目录名 + 上一层目录名」两级：命中目录本身叫 cache 固然要排掉，
      // `<游戏目录>\cache\save` 这种「缓存里套了个 save」也要排掉；
      // 但不再往上追（否则游戏目录恰好叫 Temp\MyGame 时会把真线索一起丢掉）。
      if (isNoiseWriteHit(hit)) continue;
      out.add(await _candidate(
        hit,
        95,
        '游玩期间检测到文件写入',
        maxStatFiles: _maxStatFilesForHit,
        deadline: deadline,
      ));
    }
    return out;
  }

  /// 写入线索落在噪音目录里（自身或上一层是 cache/logs/temp 之类）。
  static bool isNoiseWriteHit(String path) {
    final norm = p.normalize(path.trim());
    if (SaveWriteWatcher.isNoiseDir(p.basename(norm))) return true;
    final parent = p.basename(p.dirname(norm));
    return parent.isNotEmpty && SaveWriteWatcher.isNoiseDir(parent);
  }

  // ============================ 合并与排序 ============================

  /// 去重（同一路径保留置信度最高的一条）+ 时间线加分 + 排序。
  static List<SaveDirCandidate> _merge(
      List<SaveDirCandidate> input, DateTime? since) {
    final byPath = <String, SaveDirCandidate>{};
    for (final raw in input) {
      final key = _dedupeKey(raw.path);
      if (key.isEmpty) continue;
      final c = _withRecency(raw, since);
      final old = byPath[key];
      if (old == null) {
        byPath[key] = c;
        continue;
      }
      byPath[key] = _combine(old, c);
    }
    final list = byPath.values.toList()
      ..sort((a, b) {
        if (a.confidence != b.confidence) return b.confidence - a.confidence;
        if (a.exists != b.exists) return a.exists ? -1 : 1;
        if (a.fileCount != b.fileCount) return b.fileCount - a.fileCount;
        return a.path.compareTo(b.path);
      });
    return list;
  }

  /// 同一路径的两个来源：置信度取最高，来源说明合并（让用户看到全部证据），
  /// 文件数/修改时间取更「有信息量」的那个，存在性取或。
  static SaveDirCandidate _combine(SaveDirCandidate a, SaveDirCandidate b) {
    final keep = b.confidence > a.confidence ? b : a;
    final other = identical(keep, b) ? a : b;
    var reason = keep.reason;
    if (other.reason.isNotEmpty &&
        !keep.reason.contains(other.reason) &&
        reason.length + other.reason.length <= 90) {
      reason = '$reason；${other.reason}';
    }
    final newest = _later(keep.lastModified, other.lastModified);
    return SaveDirCandidate(
      path: keep.path,
      reason: reason,
      fileCount: keep.fileCount > other.fileCount ? keep.fileCount : other.fileCount,
      lastModified: newest,
      confidence: keep.confidence,
      exists: keep.exists || other.exists,
    );
  }

  /// 时间线加分：晚于 [since] 被改动过的目录，说明最近一次运行确实在写它。
  /// 加分上限压到 94，保证「游玩期间检测到文件写入」（95）永远排在最前
  /// ——因此已经 ≥95 的候选直接原样返回，绝不因为封顶反而被降级。
  static SaveDirCandidate _withRecency(SaveDirCandidate c, DateTime? since) {
    final last = c.lastModified;
    if (since == null ||
        last == null ||
        !c.exists ||
        c.confidence >= 95 ||
        !last.isAfter(since)) {
      return c;
    }
    final boosted = c.confidence + 5;
    return SaveDirCandidate(
      path: c.path,
      reason: '${c.reason}（最近一次运行有改动）',
      fileCount: c.fileCount,
      lastModified: c.lastModified,
      confidence: boosted > 94 ? 94 : boosted,
      exists: c.exists,
    );
  }

  // ============================ 名称变体与匹配 ============================

  /// 名字变体表：规范化后的名字 → 原始标题（说明用）。
  ///
  /// 为什么要多变体：同一款游戏在库里可能同时有中文名、日文原名和刮削别名
  /// （`ATRI -My Dear Moments-` / `ATRI` / `ATRI～My Dear Moments～`），
  /// 而存档目录通常只用其中一种写法。
  static Map<String, String> nameVariants(Game game) =>
      _variantsOf(<String>[game.nameCn, game.name, ...game.aliases]);

  /// 一组标题 → 变体表。
  static Map<String, String> _variantsOf(List<String> titles) {
    final out = <String, String>{};
    for (final raw in titles) {
      final title = raw.trim();
      if (title.isEmpty) continue;
      for (final variant in _expandTitle(title)) {
        final key = normKey(variant);
        // 长度 ≥ 3 才收：'AI' / 'EF' 这种短名会到处误匹配
        if (key.length >= 3) out.putIfAbsent(key, () => title);
      }
    }
    return out;
  }

  /// 单个标题 → 多个写法。
  ///
  /// 依据：存档目录名常只保留主标题（副标题被省略）、去掉版本标注括号，
  /// 而规范化时又会把空格与符号全部去掉，于是
  /// `ATRI -My Dear Moments-` 与目录 `ATRI_MyDearMoments` 都能对上。
  static Iterable<String> _expandTitle(String title) sync* {
    yield title;
    // 去掉全角/半角括号及其内容：『（体験版）』『(FHD)』只是版本标注
    final noBracket =
        title.replaceAll(RegExp(r'[（(][^）)]*[）)]'), ' ').trim();
    if (noBracket.isNotEmpty) yield noBracket;
    // 按副标题分隔符取前段：『ATRI -My Dear Moments-』→『ATRI』
    for (final base in <String>{title, if (noBracket.isNotEmpty) noBracket}) {
      final cut = base.split(RegExp(r'[～~\-—–:：]+')).first.trim();
      if (cut.isNotEmpty && cut != base) yield cut;
    }
  }

  /// 名称规范化：小写 + 全角折半角 + 去掉空格/标点/符号，只留字母数字与 CJK。
  ///
  /// 直接复用刮削匹配用的 [normalizeForMatch]（同一套口径，避免出现
  /// 「搜索能匹配、存档目录却匹配不上」这种不一致），再去掉词间空格。
  static String normKey(String s) => normalizeForMatch(s).replaceAll(' ', '');

  /// 名称匹配等级：2 = 规范化后完全相等（可信）；1 = 包含（可信度略低）；
  /// 0 = 不匹配。
  static int _matchTier(String key, Map<String, String> variants) {
    if (variants.isEmpty || key.length < 3) return 0;
    if (variants.containsKey(key)) return 2;
    for (final v in variants.keys) {
      if (key.contains(v)) return 1;
    }
    return 0;
  }

  // ============================ 存档目录关键词 ============================

  /// 存档目录关键词（与 [SaveScanner] 保持一致的判断口径，并补上几个常见写法）。
  static const _saveKeywords = <String>[
    'savedata', 'save_data', 'savedir', 'savegame', 'save',
    'セーブ', 'セーブデータ', '存档', '存檔', '数据',
  ];

  /// 命中并存档关键词则返回它，否则 null。
  static String? _saveKeywordOf(String name) {
    final lower = name.toLowerCase();
    for (final k in _saveKeywords) {
      if (lower.contains(k)) return k;
    }
    return null;
  }

  /// 明显不该被当成存档目录的名字：截图、缓存（沿用 SaveScanner 的排除项）
  /// 与本监视器的噪音名单。
  static bool _nameExcluded(String name) {
    final lower = name.toLowerCase();
    if (SaveWriteWatcher.isNoiseDir(lower)) return true;
    for (final k in const ['screenshot', 'screen', 'screensaver']) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  /// 明显的程序 / 补丁目录：即使名字里带 save 也不是存档目录（如 `patch\save`）。
  static const _programDirNames = <String>[
    'bin', 'bin32', 'bin64', 'plugin', 'plugins', 'patch', 'patches',
    'redist', '_redist', 'commonredist', 'directx', 'vcredist', 'd3d', 'dx',
    'tools', 'tool', 'driver', 'drivers', 'dotnet', 'sys', 'engine',
    'crashreportclient', 'installer', 'setup', 'update', 'updater', 'steam',
  ];

  /// 名字里含这些片段的多半是补丁 / 破解 / 汉化目录
  static const _programDirHints = <String>[
    '补丁', '汉化', 'crack', 'nocd', 'keygen', 'repack',
  ];

  static bool _isProgramDir(String name) {
    final key = name.toLowerCase().trim();
    if (key.isEmpty) return true;
    for (final n in _programDirNames) {
      if (key == n ||
          key.startsWith('${n}_') ||
          key.startsWith('$n-') ||
          key.startsWith('$n ')) {
        return true;
      }
    }
    for (final h in _programDirHints) {
      if (key.contains(h)) return true;
    }
    return false;
  }

  // ============================ 工具 ============================

  /// 来源级 try/catch：任何来源抛异常都只当它没结果。
  static Future<List<SaveDirCandidate>> _guard(
      Future<List<SaveDirCandidate>> Function() job) async {
    try {
      return await job();
    } catch (_) {
      return const [];
    }
  }

  static bool _expired(DateTime deadline) => DateTime.now().isAfter(deadline);

  /// 列出目录的一级子目录（上限 [max] 个：异常目录里可能有几十万项）。
  static Future<List<String>> _listDirs(String path, int max) async {
    final out = <String>[];
    try {
      await for (final e in Directory(path).list(followLinks: false)) {
        if (e is! Directory) continue;
        out.add(e.path);
        if (out.length >= max) break;
      }
    } catch (_) {}
    return out;
  }

  /// 统计目录信息：文件数（递归，上限 [_maxCountFiles]）+ 最近的修改时间。
  /// 存档目录通常只有几十个文件，撞上限说明它多半不是存档目录。
  ///
  /// [maxStatFiles] 限制取 mtime 时 stat 的文件数；[deadline] 传入时每 128 个
  /// 文件检查一次总预算，保证单个大目录不会吃光整个检测窗口。
  static Future<(bool, int, DateTime?)> _statDir(
    String path, {
    int maxStatFiles = _maxStatFiles,
    DateTime? deadline,
  }) async {
    final dir = Directory(path);
    var exists = false;
    try {
      exists = await dir.exists();
    } catch (_) {}
    if (!exists) return (false, 0, null);
    var count = 0;
    var inspected = 0;
    DateTime? last;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        count++;
        if (inspected < maxStatFiles) {
          inspected++;
          try {
            final st = await e.stat();
            if (last == null || st.modified.isAfter(last)) last = st.modified;
          } catch (_) {}
        }
        if (count >= _maxCountFiles) break;
        if (deadline != null && count % 128 == 0 && _expired(deadline)) break;
      }
    } catch (_) {}
    if (last == null) {
      // 空目录：退回目录本身的修改时间，至少能反映它被创建/改动过
      try {
        last = (await dir.stat()).modified;
      } catch (_) {}
    }
    return (true, count, last);
  }

  static SaveDirCandidate _make(
    String path,
    int confidence,
    String reason,
    (bool, int, DateTime?) stat,
  ) =>
      SaveDirCandidate(
        path: p.normalize(path),
        reason: reason,
        fileCount: stat.$2,
        lastModified: stat.$3,
        confidence: confidence,
        exists: stat.$1,
      );

  static Future<SaveDirCandidate> _candidate(
    String path,
    int confidence,
    String reason, {
    int maxStatFiles = _maxStatFiles,
    DateTime? deadline,
  }) async =>
      _make(
        path,
        confidence,
        reason,
        await _statDir(path, maxStatFiles: maxStatFiles, deadline: deadline),
      );

  /// 去重键：Windows 路径大小写不敏感，末尾分隔符也忽略。
  static String _dedupeKey(String path) {
    var s = p.normalize(path.trim());
    while (s.length > 3 && (s.endsWith(p.separator) || s.endsWith('/'))) {
      s = s.substring(0, s.length - 1);
    }
    return s.toLowerCase();
  }

  static DateTime? _later(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}
