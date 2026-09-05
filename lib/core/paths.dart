/// 数据目录解析：便携式（exe 同目录/data）优先，不可写时回退系统应用目录。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
}
