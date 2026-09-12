/// 设置与账号存储（settings / accounts 表的类型化封装）。
library;

import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/constants.dart';

class SettingsStore {
  final Database db;
  final Map<String, String> _cache = {};

  SettingsStore(this.db);

  Future<void> _load() async {
    if (_cache.isNotEmpty) return;
    final rows = await db.query('settings');
    for (final r in rows) {
      _cache[r['key'] as String] = (r['value'] ?? '') as String;
    }
  }

  Future<String> getString(String key, String def) async {
    await _load();
    return _cache[key] ?? def;
  }

  Future<void> setString(String key, String value) async {
    await _load();
    _cache[key] = value;
    await db.insert(
        'settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getBool(String key, {bool def = false}) async =>
      (await getString(key, def ? '1' : '0')) == '1';

  Future<void> setBool(String key, bool v) => setString(key, v ? '1' : '0');

  Future<int> getInt(String key, int def) async =>
      int.tryParse(await getString(key, '$def')) ?? def;

  Future<void> setInt(String key, int v) => setString(key, '$v');

  Future<double> getDouble(String key, double def) async =>
      double.tryParse(await getString(key, '$def')) ?? def;

  Future<void> setDouble(String key, double v) => setString(key, '$v');

  Future<List<String>> getStringList(String key, List<String> def) async {
    final s = await getString(key, '');
    if (s.isEmpty) return def;
    try {
      return List<String>.from(jsonDecode(s) as List);
    } catch (_) {
      return def;
    }
  }

  Future<void> setStringList(String key, List<String> v) =>
      setString(key, jsonEncode(v));

  // ---------- 常用设置项 ----------

  static const kThemeMode = 'theme.mode'; // system/light/dark
  static const kTrackingMode = 'tracking.mode'; // foreground/elapsed
  static const kAutostart = 'system.autostart';
  static const kAfterLaunch = 'system.after_launch'; // none/minimize
  static const kCloseBehavior = 'system.close'; // exit/minimize_tray
  static const kNsfwMode = 'nsfw.mode'; // blur/placeholder/show
  static const kEnabledSources = 'sources.enabled';
  static const kSourceOrder = 'sources.order';
  static const kDataDir = 'data.dir';
  static const kAutoBackup = 'plugin.auto_backup';
  static const kBackupKeep = 'plugin.backup_keep';
  static const kIdleReminder = 'plugin.idle_reminder';
  static const kIdleMinutes = 'plugin.idle_minutes';

  // AI 助手（OpenAI 兼容端点）
  static const kAiBaseUrl = 'ai.baseUrl';
  static const kAiApiKey = 'ai.apiKey';
  static const kAiModel = 'ai.model';

  /// Locale Emulator 的 LEProc.exe 路径（日文游戏转区启动用）
  static const kLePath = 'runtime.le_path';

  /// 存档备份保留份数 / 自动备份阈值（分钟）
  static const kSaveBackupKeep = 'save.backup_keep';
  static const kSaveAutoMinutes = 'save.auto_minutes';

  Future<ThemeModePref> themeMode() async {
    final s = await getString(kThemeMode, 'system');
    return ThemeModePref.values.firstWhere((e) => e.id == s,
        orElse: () => ThemeModePref.system);
  }

  Future<TimeTrackingMode> trackingMode() async {
    final s = await getString(kTrackingMode, 'foreground');
    return s == 'elapsed'
        ? TimeTrackingMode.elapsed
        : TimeTrackingMode.foreground;
  }
}

enum ThemeModePref { system, light, dark }

extension ThemeModePrefId on ThemeModePref {
  String get id => switch (this) {
        ThemeModePref.system => 'system',
        ThemeModePref.light => 'light',
        ThemeModePref.dark => 'dark',
      };
}

class AccountStore {
  final Database db;
  AccountStore(this.db);

  Future<String?> token(String platform) async {
    final rows = await db.query('accounts',
        where: 'platform = ?', whereArgs: [platform], limit: 1);
    if (rows.isEmpty) return null;
    final t = (rows.first['token'] ?? '') as String;
    return t.isEmpty ? null : t;
  }

  Future<void> setToken(String platform, String? token,
      {Map<String, dynamic> extra = const {}}) async {
    await db.insert(
        'accounts',
        {
          'platform': platform,
          'token': token ?? '',
          'extra': jsonEncode(extra),
          'verified_at': token == null ? '' : DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>> info(String platform) async {
    final rows = await db.query('accounts',
        where: 'platform = ?', whereArgs: [platform], limit: 1);
    if (rows.isEmpty) return {};
    final s = (rows.first['extra'] ?? '') as String;
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return {};
    }
  }
}
