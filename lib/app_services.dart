/// 应用服务单例：初始化目录/数据库/存储/刮削/监控/插件。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/paths.dart';
import 'data/db.dart';
import 'data/game_repository.dart';
import 'data/metadata_cache.dart';
import 'data/settings_store.dart';
import 'scraping/metadata_fetcher.dart';
import 'scraping/tag_translator.dart';
import 'services/autostart.dart';
import 'services/playtime_tracker.dart';
import 'services/plugin_system.dart';

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
  PluginContext? pluginContext;

  bool get ready => _ready;
  bool _ready = false;

  AppServices._();

  /// NSFW 封面显示模式：blur / placeholder / show（封面组件直接读取）。
  String nsfwMode = 'blur';

  static Future<AppServices> init() async {
    if (_i?._ready == true) return _i!;
    // SQLite FFI 初始化（Windows 桌面必需）
    sqfliteFfiInit();

    final s = AppServices._();
    s.paths = await AppPaths.init();
    s.db = await openAppDb(s.paths.dbFile);
    s.repo = GameRepository(s.db);
    s.settings = SettingsStore(s.db);
    s.accounts = AccountStore(s.db);
    s.tracker = PlaytimeTracker();

    // 用户自定义数据目录（影响 covers/cache/backups 位置）
    final customDir = await s.settings.getString(SettingsStore.kDataDir, '');
    if (customDir.isNotEmpty && Directory(customDir).existsSync()) {
      s.paths = await AppPaths.init(customRoot: customDir);
    }

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

    // 插件
    s.plugins = PluginManager(s.settings, s.paths.plugins);
    await s.plugins.loadImported();
    final ctx = PluginContext(s.settings, s.paths.root, s.tracker.onSessionEnd);
    s.pluginContext = ctx;
    for (final plugin in [
      AutoBackupPlugin(),
      NsfwGuardPlugin(),
      IdleReminderPlugin(),
    ]) {
      await s.plugins.register(plugin, ctx);
    }

    s.autostart = AutostartService();

    // NSFW 显示模式
    s.nsfwMode = await s.settings.getString(SettingsStore.kNsfwMode, 'blur');

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
