/// 插件系统：内置插件 + 外部清单导入（v1 外部插件仅元数据展示）。
library;

import 'dart:convert';
import 'dart:io';

import '../data/settings_store.dart';
import 'autostart.dart';
import 'playtime_tracker.dart';

/// 插件设置项描述。
class PluginSetting {
  final String key;
  final String label;
  final PluginSettingType type;
  final dynamic def;
  const PluginSetting(this.key, this.label, this.type, {this.def});
}

enum PluginSettingType { bool_, int_, string_ }

abstract class KisakiPlugin {
  String get id;
  String get name;
  String get description;
  String get version;
  String get author;
  List<PluginSetting> get settings => const [];

  bool enabled = false;
  Map<String, dynamic> config = {};

  Future<void> onInit(PluginContext ctx) async {}
  Future<void> onDispose() async {}
}

/// 插件可用的宿主能力。
class PluginContext {
  final SettingsStore settings;
  final String dataDir;
  final Stream<PlaySessionEnd> sessionStream;
  PluginContext(this.settings, this.dataDir, this.sessionStream);
}

/// 插件管理器。
class PluginManager {
  final List<KisakiPlugin> _plugins = [];
  final SettingsStore settings;
  final String pluginsDir;
  final List<Map<String, dynamic>> importedManifests = [];

  PluginManager(this.settings, this.pluginsDir);

  List<KisakiPlugin> get plugins => List.unmodifiable(_plugins);

  KisakiPlugin? byId(String id) {
    try {
      return _plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 注册内置插件并恢复持久化的开关/配置。
  Future<void> register(KisakiPlugin plugin, PluginContext ctx) async {
    plugin.enabled = await settings.getBool('plugin.${plugin.id}.enabled');
    plugin.config = {};
    for (final s in plugin.settings) {
      plugin.config[s.key] = switch (s.type) {
        PluginSettingType.bool_ => await settings.getBool(
            'plugin.${plugin.id}.${s.key}',
            def: (s.def ?? false) as bool),
        PluginSettingType.int_ => await settings.getInt(
            'plugin.${plugin.id}.${s.key}', (s.def ?? 0) as int),
        PluginSettingType.string_ =>
          await settings.getString('plugin.${plugin.id}.${s.key}',
              (s.def ?? '') as String),
      };
    }
    _plugins.add(plugin);
    if (plugin.enabled) {
      try {
        await plugin.onInit(ctx);
      } catch (_) {}
    }
  }

  Future<void> setEnabled(String id, bool enabled, PluginContext ctx) async {
    final p = byId(id);
    if (p == null) return;
    p.enabled = enabled;
    await settings.setBool('plugin.$id.enabled', enabled);
    if (enabled) {
      try {
        await p.onInit(ctx);
      } catch (_) {}
    } else {
      await p.onDispose();
    }
  }

  Future<void> setConfig(String id, String key, dynamic value) async {
    final p = byId(id);
    if (p == null) return;
    p.config[key] = value;
    await settings.setString('plugin.$id.$key', '$value');
  }

  /// 导入外部插件清单（仅元数据；v1 不加载外部代码）。
  Future<String?> importManifest(String manifestPath) async {
    try {
      final m = Map<String, dynamic>.from(
          jsonDecode(File(manifestPath).readAsStringSync()) as Map);
      if (m['id'] is! String || m['name'] is! String) {
        return '清单缺少 id/name 字段';
      }
      importedManifests.add(m);
      final target = File('$pluginsDir/${m['id']}.json');
      await target.writeAsString(jsonEncode(m));
      return null;
    } catch (e) {
      return '导入失败：$e';
    }
  }

  Future<void> loadImported() async {
    final dir = Directory(pluginsDir);
    if (!dir.existsSync()) return;
    for (final f in dir.listSync()) {
      if (f is File && f.path.endsWith('.json')) {
        try {
          importedManifests.add(
              Map<String, dynamic>.from(jsonDecode(f.readAsStringSync()) as Map));
        } catch (_) {}
      }
    }
  }
}

// ================= 内置插件 =================

/// 自动备份：启动时若距上次备份超过 24h 则备份并按保留数清理。
class AutoBackupPlugin extends KisakiPlugin {
  DateTime _lastCheck = DateTime.now();

  @override
  String get id => 'auto_backup';
  @override
  String get name => '自动备份';
  @override
  String get description => '每日自动备份数据库，并保留最近若干份';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'KisakiGals';

  @override
  List<PluginSetting> get settings => [
        const PluginSetting('keep', '保留备份数', PluginSettingType.int_, def: 10),
      ];

  @override
  Future<void> onInit(PluginContext ctx) async {
    final dir = '${ctx.dataDir}/backups';
    final svc = BackupService(
        dbFile: '${ctx.dataDir}/kisakigals.db', backupsDir: dir);
    final files = svc.list();
    if (files.isEmpty ||
        DateTime.now().difference(files.first.statSync().modified).inHours >= 24) {
      await svc.backup();
      await svc.prune((config['keep'] ?? 10) as int);
    }
    _lastCheck = DateTime.now();
  }

  DateTime get lastCheck => _lastCheck;
}

/// NSFW 封面保护：启用后强制模糊 NSFW 封面（读取此状态于封面组件）。
class NsfwGuardPlugin extends KisakiPlugin {
  @override
  String get id => 'nsfw_guard';
  @override
  String get name => 'NSFW 封面保护';
  @override
  String get description => '在游戏库与详情页模糊 NSFW 封面，防误触曝光';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'KisakiGals';

  @override
  List<PluginSetting> get settings => [
        const PluginSetting('blur', '模糊强度（0-20）', PluginSettingType.int_, def: 12),
      ];

  bool get active => enabled;
}

/// 久坐提醒：单次游玩超过设定分钟数时提醒休息。
class IdleReminderPlugin extends KisakiPlugin {
  @override
  String get id => 'idle_reminder';
  @override
  String get name => '久坐提醒';
  @override
  String get description => '单次连续游玩超过设定时长时提醒休息';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'KisakiGals';

  @override
  List<PluginSetting> get settings => [
        const PluginSetting('minutes', '提醒阈值（分钟）', PluginSettingType.int_, def: 90),
      ];

  bool _subscribed = false;

  @override
  Future<void> onInit(PluginContext ctx) async {
    if (_subscribed) return;
    _subscribed = true;
    ctx.sessionStream.listen((_) {});
  }

  /// 判断当前会话是否应提醒。
  bool shouldRemind(int seconds) =>
      enabled && seconds >= ((config['minutes'] ?? 90) as int) * 60;

  @override
  Future<void> onDispose() async {
    _subscribed = false;
  }
}
