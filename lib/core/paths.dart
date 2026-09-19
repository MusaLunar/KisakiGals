/// 数据目录解析：便携式（exe 同目录/data）优先，不可写时回退系统应用目录。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_paths.dart';

class AppPaths {
  String root; // 数据根目录
  String dbFile; // kisakigals.db
  String covers; // 封面缓存
  String cache; // 元数据缓存
  String backups; // 备份
  String logs; // 日志
  String plugins; // 插件清单

  AppPaths._(this.root)
      : dbFile = p.join(root, 'kisakigals.db'),
        covers = p.join(root, 'covers'),
        cache = p.join(root, 'cache'),
        backups = p.join(root, 'backups'),
        logs = p.join(root, 'logs'),
        plugins = p.join(root, 'plugins');

  static AppPaths? _instance;

  static AppPaths get instance => _instance!;

  /// 初始化（应用启动时调用一次）。[customRoot] 来自设置中的自定义目录。
  static Future<AppPaths> init({String? customRoot}) async {
    final root = customRoot ?? await _resolveRoot();
    final paths = AppPaths._(root);
    for (final d in [
      root,
      paths.covers,
      paths.cache,
      paths.backups,
      paths.logs,
      paths.plugins
    ]) {
      Directory(d).createSync(recursive: true);
    }
    _instance = paths;
    // 媒体路径解析器与数据目录同步（供数据层/纯 Dart 代码使用）
    MediaPaths.install(root);
    return paths;
  }

  /// 便携目录：exe 同目录下 data/；不可写则回退 %APPDATA%/KisakiGals。
  static Future<String> _resolveRoot() async {
    String? portable;
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      portable = p.join(exeDir, 'data');
      final probe = File(p.join(portable, '.write_probe'));
      probe.parent.createSync(recursive: true);
      probe.writeAsStringSync('ok');
      probe.deleteSync();
    } catch (_) {
      portable = null;
    }
    if (portable != null) return portable;
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'KisakiGals');
  }

  // ---------- 媒体路径的跨设备可移植（实现见 core/media_paths.dart）----------

  /// 写入数据库时使用：数据目录内的文件存相对路径。
  String toStored(String path) => MediaPaths.instance.toStored(path);

  /// 读取数据库中的路径时使用：解析为本机可用路径。
  String resolveStored(String stored) => MediaPaths.instance.resolveStored(stored);

  /// 目录版本（存档目录等）。
  String resolveStoredDir(String stored) =>
      MediaPaths.instance.resolveStoredDir(stored);

  /// 修复历史遗留的封面/背景绝对路径。
  Future<int> repairLegacyMediaPaths(Database db) =>
      MediaPaths.instance.repairLegacyMediaPaths(db);
}
