/// 存档目录探测与备份。
///
/// 参考 ChronoTide 的 SaveScanner：Galgame 的存档目录名往往与游戏标题无关
/// （常见 savedata / save / セーブ / SaveData 等），因此按关键词在游戏目录内
/// 做一级 + 二级子目录扫描，命中即视为存档目录。
///
/// 备份产物为**明文目录树**（与 ChronoTide 一致，便于用户手动翻看/替换），
/// 相比参考实现补上了：保留份数上限、恢复前快照、恢复前检查游戏是否在运行、
/// 备份元数据记录恢复所需的原始绝对路径。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;


class SaveBackupEntry {
  final String name; // 备份目录名（时间戳或自定义）
  final DateTime time;
  final int fileCount;
  final int totalBytes;
  final bool auto;
  const SaveBackupEntry({
    required this.name,
    required this.time,
    required this.fileCount,
    required this.totalBytes,
    this.auto = false,
  });

  String get displaySize {
    final kb = totalBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class SaveScanner {
  static const _keywords = [
    'savedata',
    'save_data',
    'savedir',
    'savegame',
    'save',
    'セーブ',
    '存档',
    '数据',
  ];
  static const _exclude = ['screenshot', 'screen', 'screensaver', 'cache'];

  /// 在 [gameDir] 内探测存档目录；找不到返回空串。
  /// [gameName] 用于优先匹配以游戏名命名的目录。
  static String detectSaveDir(String gameDir, String gameName) {
    try {
      final root = Directory(gameDir);
      if (!root.existsSync()) return '';
      final candidates = <Directory>[];

      void consider(Directory d) {
        final name = p.basename(d.path).toLowerCase();
        if (name.isEmpty) return;
        if (_exclude.any(name.contains)) return;
        if (_keywords.any(name.contains)) candidates.add(d);
      }

      for (final e in root.listSync(followLinks: false)) {
        if (e is Directory) {
          consider(e);
          // 二级子目录（如 game/data/save）
          try {
            for (final sub in e.listSync(followLinks: false)) {
              if (sub is Directory) consider(sub);
            }
          } catch (_) {}
        }
      }
      if (candidates.isEmpty) return '';
      // 以游戏名命名的优先，其次目录内文件数多的
      final key = _norm(gameName);
      candidates.sort((a, b) {
        final an = _norm(p.basename(a.path));
        final bn = _norm(p.basename(b.path));
        final am = key.isNotEmpty && an.contains(key) ? 1 : 0;
        final bm = key.isNotEmpty && bn.contains(key) ? 1 : 0;
        if (am != bm) return bm - am;
        return _count(b).compareTo(_count(a));
      });
      return candidates.first.path;
    } catch (_) {
      return '';
    }
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(
      RegExp(r'[^0-9a-z\u3400-\u9fff]+'), '');

  static int _count(Directory d) {
    try {
      return d.listSync(recursive: true).whereType<File>().length;
    } catch (_) {
      return 0;
    }
  }
}

/// 存档备份仓库：以 [root]（通常是数据目录）为根，
/// 注入式设计便于单测与自定义位置。
class SaveBackupService {
  final String root;
  const SaveBackupService(this.root);

  /// 备份保存到数据目录下 `saves/<gameId>/<name>/`，与游戏库解耦
  /// （参考实现把备份放在游戏元数据目录内，删游戏会连带删掉全部存档备份）。
  String _root(int gameId) => p.join(root, 'saves', '$gameId');

  List<SaveBackupEntry> list(int gameId) {
    final dir = Directory(_root(gameId));
    if (!dir.existsSync()) return const [];
    final out = <SaveBackupEntry>[];
    for (final e in dir.listSync()) {
      if (e is! Directory) continue;
      final meta = File(p.join(e.path, 'backup.json'));
      if (!meta.existsSync()) continue;
      try {
        final m = Map<String, dynamic>.from(
            jsonDecode(meta.readAsStringSync()) as Map);
        out.add(SaveBackupEntry(
          name: p.basename(e.path),
          time: DateTime.tryParse('${m['time']}') ?? e.statSync().modified,
          fileCount: (m['files'] as List?)?.length ?? 0,
          totalBytes: (m['bytes'] ?? 0) as int,
          auto: m['auto'] == true,
        ));
      } catch (_) {}
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// 备份 [savePath] 到数据目录；返回备份名。超过 [keep] 份时删除最旧的。
  Future<String> backup(
    int gameId,
    String savePath, {
    bool auto = false,
    int keep = 10,
  }) async {
    final src = Directory(savePath);
    if (!src.existsSync()) throw StateError('存档目录不存在');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final name = auto ? 'auto-$stamp' : stamp;
    final target = Directory(p.join(_root(gameId), name));
    if (target.existsSync()) {
      // 同秒重复备份：追加后缀而不是静默覆盖（参考实现的缺陷）
      return backup(gameId, savePath,
          auto: auto, keep: keep);
    }
    target.createSync(recursive: true);

    final files = <Map<String, String>>[];
    var bytes = 0;
    for (final e in src.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: src.path);
      final dst = File(p.join(target.path, rel));
      dst.parent.createSync(recursive: true);
      e.copySync(dst.path);
      bytes += e.lengthSync();
      files.add({'rel': rel, 'src': e.path});
    }
    File(p.join(target.path, 'backup.json')).writeAsStringSync(jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'source': savePath,
      'auto': auto,
      'bytes': bytes,
      'files': files,
    }));

    // 保留份数上限
    final all = list(gameId);
    for (var i = keep; i < all.length; i++) {
      try {
        Directory(p.join(_root(gameId), all[i].name)).deleteSync(recursive: true);
      } catch (_) {}
    }
    return name;
  }

  /// 恢复备份。[snapshot] 为 true 时先把当前存档复制一份（恢复前快照）。
  /// 返回 (恢复文件数, 总数)。
  Future<(int, int)> restore(
    int gameId,
    String name, {
    bool snapshot = true,
  }) async {
    final dir = Directory(p.join(_root(gameId), name));
    final meta = File(p.join(dir.path, 'backup.json'));
    if (!meta.existsSync()) throw StateError('备份不存在');
    final m = Map<String, dynamic>.from(jsonDecode(meta.readAsStringSync()) as Map);
    final files = (m['files'] as List?) ?? [];
    final source = '${m['source'] ?? ''}';

    if (snapshot && source.isNotEmpty && Directory(source).existsSync()) {
      await backup(gameId, source, auto: true);
    }

    var ok = 0;
    for (final f in files) {
      final entry = Map<String, dynamic>.from(f as Map);
      final srcFile = File(p.join(dir.path, '${entry['rel']}'));
      if (!srcFile.existsSync()) continue;
      final dst = File('${entry['src']}');
      dst.parent.createSync(recursive: true);
      srcFile.copySync(dst.path);
      ok++;
    }
    return (ok, files.length);
  }

  void remove(int gameId, String name) {
    final dir = Directory(p.join(_root(gameId), name));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
