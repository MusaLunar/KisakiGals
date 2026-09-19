/// 媒体文件（封面/背景/存档）路径的跨设备可移植处理。
///
/// 这里是**纯 Dart** 实现（只依赖 dart:io / path / sqflite），
/// 不引入 path_provider 等 Flutter 依赖，方便被数据层与单元测试直接使用。
///
/// 背景：封面与背景图存放在数据目录的 covers/ 下。若把绝对路径写进数据库，
/// 换设备（数据目录不同）或换盘后就会全部失效——表现为「迁移后没有封面」。
/// 因此写入时尽量存**相对数据根目录**的路径，读取时解析回本机绝对路径，
/// 并对历史数据（绝对值且文件已不在）按文件名在当前目录下兜底找回。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MediaPaths {
  final String root;
  MediaPaths(this.root);

  static MediaPaths? _instance;

  /// 当前生效实例（应用启动时由 AppPaths.init 安装）。
  static MediaPaths get instance =>
      _instance ??= MediaPaths(p.join(Directory.current.path, 'data'));

  static void install(String root) => _instance = MediaPaths(root);

  /// 写入数据库时使用：位于数据目录内的文件存相对路径，外部文件保持绝对路径。
  String toStored(String path) {
    if (path.isEmpty) return '';
    final norm = p.normalize(path);
    final rootNorm = p.normalize(root);
    if (p.isWithin(rootNorm, norm)) {
      return p.relative(norm, from: rootNorm).replaceAll('\\', '/');
    }
    if (!p.isAbsolute(norm)) return norm.replaceAll('\\', '/');
    return path;
  }

  /// 读取数据库中的路径时使用：返回本机可用路径。
  /// 找不到时返回原值（由调用方的存在性检查决定是否回退占位图）。
  String resolveStored(String stored) {
    if (stored.isEmpty) return '';
    if (!p.isAbsolute(stored)) {
      final full = p.normalize(p.join(root, stored));
      if (File(full).existsSync() || Directory(full).existsSync()) return full;
      // 历史数据里可能存在「相对当前工作目录」的写法，保持其原有语义
      final cwd = p.normalize(p.join(Directory.current.path, stored));
      if (File(cwd).existsSync() || Directory(cwd).existsSync()) return cwd;
    } else if (File(stored).existsSync()) {
      return stored;
    }
    // 兜底：按文件名在当前数据目录（含 covers/ 子目录）里找回
    final name = p.basename(stored.replaceAll('/', Platform.pathSeparator));
    if (name.isEmpty) return stored;
    for (final candidate in [
      p.join(root, 'covers', name),
      p.join(root, 'saves', name),
      p.join(root, name),
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    final coversDir = Directory(p.join(root, 'covers'));
    if (coversDir.existsSync()) {
      try {
        for (final f in coversDir.listSync(recursive: true)) {
          if (f is File && p.basename(f.path) == name) return f.path;
        }
      } catch (_) {}
    }
    return stored;
  }

  /// 目录版本（存档目录等）。
  String resolveStoredDir(String stored) {
    if (stored.isEmpty) return '';
    if (p.isAbsolute(stored)) return stored;
    return p.normalize(p.join(root, stored));
  }

  /// 一次性修复历史遗留的「绝对路径且文件已不存在」的封面/背景地址：
  /// 按文件名在当前 covers/ 里找回并改存相对路径（换设备迁移后常见）。
  /// 返回修复的记录条数。
  Future<int> repairLegacyMediaPaths(Database db) async {
    var fixed = 0;
    try {
      final rows = await db.rawQuery(
          'SELECT id, cover_path, background_url FROM games '
          "WHERE (cover_path LIKE '%:%' OR background_url LIKE '%:%')");
      for (final r in rows) {
        final id = r['id'] as int;
        var cover = (r['cover_path'] ?? '') as String;
        var bg = (r['background_url'] ?? '') as String;
        var changed = false;

        if (cover.isNotEmpty &&
            p.isAbsolute(cover) &&
            !File(cover).existsSync()) {
          final found = resolveStored(cover);
          if (found != cover && File(found).existsSync()) {
            cover = toStored(found);
            changed = true;
          }
        }
        if (bg.isNotEmpty && p.isAbsolute(bg) && !File(bg).existsSync()) {
          final found = resolveStored(bg);
          if (found != bg && File(found).existsSync()) {
            bg = toStored(found);
            changed = true;
          }
        }
        if (changed) {
          await db.update('games', {'cover_path': cover, 'background_url': bg},
              where: 'id = ?', whereArgs: [id]);
          fixed++;
        }
      }
    } catch (_) {}
    return fixed;
  }
}
