/// 应用服务单例：初始化目录/数据库/存储/刮削/监控/插件。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/paths.dart';
import 'data/db.dart';
import 'data/game_repository.dart';
import 'data/metadata_cache.dart';
import 'data/settings_store.dart';
import 'scraping/metadata_fetcher.dart';
import 'scraping/tag_translator.dart';
import 'services/autostart.dart';
import 'services/device.dart';
import 'services/ai_service.dart';
import 'services/playtime_tracker.dart';
import 'services/plugin_system.dart';

/// 修复历史版本的数据库路径双层嵌套：
/// 旧版把文件路径再拼一层，得到 `<root>/kisakigals.db/kisakigals.db`。
/// 若发现该目录，则把其中的库文件（含 WAL）上移到正确位置并删除目录。
/// 先复制到临时名，全部成功后才删除目录，任何一步失败都保留原状。
Future<void> _flattenLegacyDbDir(String dbFile) async {
  final legacyDir = Directory(dbFile);
  if (!legacyDir.existsSync()) return;
  final inner = '$dbFile/kisakigals.db';
  if (!File(inner).existsSync()) {
    legacyDir.deleteSync(recursive: true);
    return;
  }
  final staged = <String, String>{};
  try {
    staged[inner] = '$dbFile.migrating';
    File(inner).copySync('$dbFile.migrating');
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$inner$suffix');
      if (f.existsSync()) {
        staged['$inner$suffix'] = '$dbFile$suffix';
        f.copySync('$dbFile$suffix');
      }
    }
    legacyDir.deleteSync(recursive: true);
    File('$dbFile.migrating').renameSync(dbFile);
  } catch (_) {
    // 失败回滚：移除已落地的副本，目录保持原样
    for (final target in staged.values) {
      final f = File(target);
      if (f.existsSync()) f.deleteSync();
    }
    return;
  }
}

/// 最近一次启动时的重定位结果（UI 提示用）。
RelocateResult? lastRelocateResult;

class AppServices {
  static AppServices? _i;
  static AppServices get I => _i!;

  late AppPaths paths;
  late Database db;
  late GameRepository repo;
  late SettingsStore settings;
  late AccountStore accounts;
  late MetadataFetcher fetcher;
  late PlaytimeTracker tracker;
  late PluginManager plugins;
  late AutostartService autostart;
  late AiService ai;
  late PathRelocator relocator;
  PluginContext? pluginContext;

  bool get ready => _ready;
  bool _ready = false;

  AppServices._();

  static Future<AppServices> init() async {
    if (_i?._ready == true) return _i!;
    // SQLite FFI 初始化（Windows 桌面必需）
    sqfliteFfiInit();

    final s = AppServices._();
    s.paths = await AppPaths.init();
    await _flattenLegacyDbDir(s.paths.dbFile);
    s.db = await openAppDb(s.paths.dbFile);
    s.settings = SettingsStore(s.db);
    s.accounts = AccountStore(s.db);
    s.tracker = PlaytimeTracker();

    // 用户自定义数据目录（影响 covers/cache/backups 位置）
    final customDir = await s.settings.getString(SettingsStore.kDataDir, '');
    if (customDir.isNotEmpty && Directory(customDir).existsSync()) {
      final targetDb = p.join(customDir, 'kisakigals.db');
      final currentRoot = p.normalize(s.paths.root);
      final targetRoot = p.normalize(customDir);
      if (targetRoot != currentRoot) {
        // 数据库也一并迁移，避免「库在一处、封面缓存在另一处」
        if (!File(targetDb).existsSync() && File(s.paths.dbFile).existsSync()) {
          try {
            await s.db.close(); // 关闭前 sqflite 会把 WAL 合并回主库
            File(s.paths.dbFile).copySync(targetDb);
            for (final suffix in ['-wal', '-shm']) {
              final src = File('${s.paths.dbFile}$suffix');
              if (src.existsSync()) src.copySync('$targetDb$suffix');
            }
            // 旧库改名留档，避免下次启动又被当作主库
            File(s.paths.dbFile).renameSync('${s.paths.dbFile}.moved');
          } catch (_) {
            // 迁移失败则继续使用原位置
          }
        }
        s.paths = await AppPaths.init(customRoot: customDir);
        s.db = await openAppDb(s.paths.dbFile);
      }
    }
    s.repo = GameRepository(s.db);
    s.settings = SettingsStore(s.db);
    s.accounts = AccountStore(s.db);
    s.tracker = PlaytimeTracker();

    // 标签翻译资源
    try {
      final raw = await rootBundle.loadString('assets/data/vndb_tags_zh_cn.json');
      TagTranslator.init(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}

    // 元数据刮削
    s.fetcher = MetadataFetcher(
        cache: MetadataCache(s.paths.cache), coversDir: s.paths.covers);
    await s.fetcher.init(tokens: {
      'vndb': await s.accounts.token('vndb') ?? '',
      'bgm': await s.accounts.token('bgm') ?? '',
      'hikarinagi': await s.accounts.token('hikarinagi') ?? '',
    });

    // 插件（精简后仅保留久坐提醒；自动备份/NSFW 已集成为应用功能）
    s.plugins = PluginManager(s.settings, s.paths.plugins);
    await s.plugins.loadImported();
    final ctx = PluginContext(s.settings, s.paths.root, s.tracker.onSessionEnd);
    s.pluginContext = ctx;
    await s.plugins.register(IdleReminderPlugin(), ctx);

    // 自动备份（每日一次，可在设置-数据中关闭）
    if (await s.settings.getBool(SettingsStore.kAutoBackup, def: true)) {
      try {
        final svc = BackupService(
            dbFile: s.paths.dbFile, backupsDir: s.paths.backups);
        final files = svc.list();
        if (files.isEmpty ||
            DateTime.now()
                    .difference(files.first.statSync().modified)
                    .inHours >=
                24) {
          await svc.backup(checkpointDb: s.db);
          await svc.prune(
              await s.settings.getInt(SettingsStore.kBackupKeep, 10));
        }
      } catch (_) {}
    }

    // 设备识别与路径重定位（换机/换盘导入数据库后自动找回游戏目录）
    s.relocator = PathRelocator(s.settings, s.repo);
    s.autostart = AutostartService();
    s.ai = AiService(proxy: s.fetcher.proxy);

    // 启动时尝试重定位缺失的游戏路径（失败静默，由 UI 侧另行提示）
    try {
      final r = await s.relocator.relocateMissing();
      lastRelocateResult = r;
    } catch (_) {}

    s._ready = true;
    _i = s;
    return s;
  }

  Future<void> dispose() async {
    tracker.stopTracking(saveSession: true);
    fetcher.dispose();
    await db.close();
  }
}
