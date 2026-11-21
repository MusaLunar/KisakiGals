/// 插件系统：声明式包管理（.zip / .js）、Manifest v1 规范校验与官方聚合插件市场。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../data/settings_store.dart';
import 'playtime_tracker.dart';
import 'update_checker.dart';

const int kPluginSchemaVersion = 1;
const int _kMaxPluginZipBytes = 32 * 1024 * 1024;
const int _kMaxPluginZipEntries = 512;

const String kLocaleEmulatorPluginId = 'locale-emulator';
const String kLocaleEmulatorProjectUrl =
    'https://github.com/xupefei/Locale-Emulator';

const Set<String> kAllowedPluginPermissions = {
  'notifications',
  'session.listen',
  'settings.storage',
  'network.http',
  'library.read',
  'process.launch',
};

const Map<String, String> kPluginPermissionLabels = {
  'notifications': '应用内通知提醒',
  'session.listen': '监听游玩会话生命周期',
  'settings.storage': '读写插件私有配置',
  'network.http': '发起外部 HTTP/API 请求',
  'library.read': '读取本地游戏库元数据',
  'process.launch': '联动外部工具进程',
};

typedef PluginNotifyCallback = void Function(String message, {bool error});
typedef PluginDownloadBytesFn = Future<List<int>> Function(String url);

enum PluginSettingType {
  bool_,
  int_,
  string_;

  String get wireName => switch (this) {
        PluginSettingType.bool_ => 'bool',
        PluginSettingType.int_ => 'int',
        PluginSettingType.string_ => 'string',
      };

  static PluginSettingType? fromWire(String raw) => switch (raw.trim()) {
        'bool' || 'bool_' => PluginSettingType.bool_,
        'int' || 'int_' => PluginSettingType.int_,
        'string' || 'string_' => PluginSettingType.string_,
        _ => null,
      };
}

/// 插件设置项描述。
class PluginSetting {
  final String key;
  final String label;
  final PluginSettingType type;
  final dynamic def;
  final num? min;
  final num? max;
  final String description;

  const PluginSetting(
    this.key,
    this.label,
    this.type, {
    this.def,
    this.min,
    this.max,
    this.description = '',
  });

  factory PluginSetting.fromJson(Map<String, dynamic> raw) {
    final typeRaw = (raw['type'] ?? 'string').toString();
    final type = PluginSettingType.fromWire(typeRaw) ?? PluginSettingType.string_;
    final defVal = raw.containsKey('default') ? raw['default'] : raw['def'];
    return PluginSetting(
      (raw['key'] ?? '').toString().trim(),
      (raw['label'] ?? '').toString().trim(),
      type,
      def: defVal,
      min: raw['min'] is num ? raw['min'] as num : null,
      max: raw['max'] is num ? raw['max'] as num : null,
      description: (raw['description'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.wireName,
        if (def != null) 'default': def,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (description.isNotEmpty) 'description': description,
      };
}

/// 声明式插件事件钩子规则（便于零原生代码插件执行轻量化通知/记录）。
class PluginHookRule {
  final String event; // onSessionEnd | onSessionTick | onGameLaunch | onScreenshotCaptured
  final String action; // notify | log
  final String message;
  final int? thresholdMinutes;

  const PluginHookRule({
    required this.event,
    required this.action,
    this.message = '',
    this.thresholdMinutes,
  });

  static const Set<String> allowedEvents = {
    'onSessionEnd',
    'onSessionTick',
    'onGameLaunch',
    'onScreenshotCaptured',
  };

  static const Set<String> allowedActions = {'notify', 'log'};

  factory PluginHookRule.fromJson(Map<String, dynamic> raw) {
    return PluginHookRule(
      event: (raw['event'] ?? '').toString().trim(),
      action: (raw['action'] ?? 'log').toString().trim(),
      message: (raw['message'] ?? '').toString().trim(),
      thresholdMinutes: raw['thresholdMinutes'] is num
          ? (raw['thresholdMinutes'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'event': event,
        'action': action,
        if (message.isNotEmpty) 'message': message,
        if (thresholdMinutes != null) 'thresholdMinutes': thresholdMinutes,
      };
}

/// `manifest.json` 完整 Schema v1 模型。
class PluginManifest {
  final int schemaVersion;
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String homepage;
  final String repository;
  final String license;
  final String minAppVersion;
  final String entry;
  final String packageType; // 'zip' | 'js'
  final String category;
  final List<String> tags;
  final List<String> permissions;
  final List<PluginSetting> settings;
  final List<PluginHookRule> hooks;
  final String? downloadUrl;
  final String? sha256;
  final String installSource; // 'zip' | 'marketplace'
  final String? installedAt;

  const PluginManifest({
    this.schemaVersion = kPluginSchemaVersion,
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.author = 'Unknown',
    this.description = '',
    this.homepage = '',
    this.repository = '',
    this.license = 'MIT',
    this.minAppVersion = '1.0.0',
    this.entry = 'main.js',
    this.packageType = 'zip',
    this.category = '效率工具',
    this.tags = const [],
    this.permissions = const [],
    this.settings = const [],
    this.hooks = const [],
    this.downloadUrl,
    this.sha256,
    this.installSource = 'zip',
    this.installedAt,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> raw) {
    List<String> strList(Object? value) {
      if (value is! List) return const [];
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final rawSettings = raw['settings'];
    final settings = <PluginSetting>[
      if (rawSettings is List)
        for (final item in rawSettings)
          if (item is Map)
            PluginSetting.fromJson(Map<String, dynamic>.from(item)),
    ];

    final rawHooks = raw['hooks'];
    final hooks = <PluginHookRule>[
      if (rawHooks is List)
        for (final item in rawHooks)
          if (item is Map)
            PluginHookRule.fromJson(Map<String, dynamic>.from(item)),
    ];

    final sv = raw['schemaVersion'];
    final schemaVersion = sv is num ? sv.toInt() : kPluginSchemaVersion;

    return PluginManifest(
      schemaVersion: schemaVersion,
      id: (raw['id'] ?? '').toString().trim(),
      name: (raw['name'] ?? '').toString().trim(),
      version: (raw['version'] ?? '1.0.0').toString().trim(),
      author: (raw['author'] ?? 'Unknown').toString().trim(),
      description: (raw['description'] ?? '').toString().trim(),
      homepage: (raw['homepage'] ?? '').toString().trim(),
      repository: (raw['repository'] ?? '').toString().trim(),
      license: (raw['license'] ?? 'MIT').toString().trim(),
      minAppVersion: (raw['minAppVersion'] ?? '1.0.0').toString().trim(),
      entry: (raw['entry'] ?? 'main.js').toString().trim(),
      packageType: (raw['packageType'] ?? 'zip').toString().trim().toLowerCase(),
      category: (raw['category'] ?? '效率工具').toString().trim(),
      tags: strList(raw['tags']),
      permissions: strList(raw['permissions']),
      settings: settings,
      hooks: hooks,
      downloadUrl: raw['downloadUrl']?.toString().trim(),
      sha256: raw['sha256']?.toString().trim(),
      installSource:
          (raw['installSource'] ?? 'zip').toString().trim().toLowerCase(),
      installedAt: raw['installedAt']?.toString().trim(),
    );
  }

  PluginManifest copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? version,
    String? author,
    String? description,
    String? homepage,
    String? repository,
    String? license,
    String? minAppVersion,
    String? entry,
    String? packageType,
    String? category,
    List<String>? tags,
    List<String>? permissions,
    List<PluginSetting>? settings,
    List<PluginHookRule>? hooks,
    String? downloadUrl,
    String? sha256,
    String? installSource,
    String? installedAt,
  }) {
    return PluginManifest(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      homepage: homepage ?? this.homepage,
      repository: repository ?? this.repository,
      license: license ?? this.license,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      entry: entry ?? this.entry,
      packageType: packageType ?? this.packageType,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      permissions: permissions ?? this.permissions,
      settings: settings ?? this.settings,
      hooks: hooks ?? this.hooks,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      sha256: sha256 ?? this.sha256,
      installSource: installSource ?? this.installSource,
      installedAt: installedAt ?? this.installedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        if (homepage.isNotEmpty) 'homepage': homepage,
        if (repository.isNotEmpty) 'repository': repository,
        if (license.isNotEmpty) 'license': license,
        'minAppVersion': minAppVersion,
        'entry': entry,
        'packageType': packageType,
        'category': category,
        if (tags.isNotEmpty) 'tags': tags,
        'permissions': permissions,
        'settings': [for (final s in settings) s.toJson()],
        if (hooks.isNotEmpty) 'hooks': [for (final h in hooks) h.toJson()],
        if (downloadUrl != null && downloadUrl!.isNotEmpty)
          'downloadUrl': downloadUrl,
        if (sha256 != null && sha256!.isNotEmpty) 'sha256': sha256,
        'installSource': installSource,
        if (installedAt != null && installedAt!.isNotEmpty)
          'installedAt': installedAt,
      };
}

/// 插件规范校验器。
class PluginManifestValidator {
  static final RegExp idPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{1,63}$');
  static final RegExp semverPattern = RegExp(
    r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$',
  );

  static bool isSafeRelativePath(String rawPath) {
    final normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains(':')) {
      return false;
    }
    final parts = normalized.split('/');
    for (final seg in parts) {
      if (seg == '..') return false;
    }
    return true;
  }

  static ({PluginManifest? manifest, String? error}) validate(
    Map<String, dynamic> raw, {
    String currentAppVersion = AppInfo.version,
  }) {
    if (raw['schemaVersion'] != null) {
      final sv = raw['schemaVersion'];
      if (sv is! num || sv < 1 || sv > kPluginSchemaVersion) {
        return (
          manifest: null,
          error: '不支持的插件协议版本 schemaVersion=$sv（当前支持 1..$kPluginSchemaVersion）',
        );
      }
    }

    final idRaw = raw['id'];
    if (idRaw is! String || !idPattern.hasMatch(idRaw.trim())) {
      return (
        manifest: null,
        error: '插件 id 无效：仅支持 2-64 位小写字母、数字及 ._-（须以字母或数字开头）',
      );
    }

    final nameRaw = raw['name'];
    if (nameRaw is! String || nameRaw.trim().isEmpty) {
      return (manifest: null, error: '插件缺少有效的 name 字段');
    }

    final versionRaw = (raw['version'] ?? '1.0.0').toString().trim();
    if (!semverPattern.hasMatch(versionRaw)) {
      return (
        manifest: null,
        error: '插件版本号 "$versionRaw" 不符合 SemVer 规范（如 1.0.0）',
      );
    }

    final minAppRaw = (raw['minAppVersion'] ?? '').toString().trim();
    if (minAppRaw.isNotEmpty) {
      if (!semverPattern.hasMatch(minAppRaw)) {
        return (
          manifest: null,
          error: 'minAppVersion "$minAppRaw" 不符合 SemVer 规范',
        );
      }
      if (GithubUpdateChecker.compareVersions(minAppRaw, currentAppVersion) > 0) {
        return (
          manifest: null,
          error: '该插件要求宿主版本 >= v$minAppRaw（当前 v$currentAppVersion）',
        );
      }
    }

    final manifest = PluginManifest.fromJson(raw);

    if (manifest.packageType != 'zip' && manifest.packageType != 'js') {
      return (
        manifest: null,
        error: '不支持的插件包类型 packageType=${manifest.packageType}',
      );
    }
    if (!isSafeRelativePath(manifest.entry)) {
      return (
        manifest: null,
        error: '入口文件路径 "${manifest.entry}" 不合法（禁止绝对路径与目录穿越）',
      );
    }

    for (final perm in manifest.permissions) {
      if (!kAllowedPluginPermissions.contains(perm)) {
        return (manifest: null, error: '声明了未授权权限 "$perm"');
      }
    }

    for (final s in manifest.settings) {
      if (s.key.isEmpty || s.label.isEmpty) {
        return (manifest: null, error: 'settings 存在缺少 key 或 label 的配置项');
      }
    }

    for (final h in manifest.hooks) {
      if (!PluginHookRule.allowedEvents.contains(h.event)) {
        return (manifest: null, error: '不支持的钩子事件 "${h.event}"');
      }
      if (!PluginHookRule.allowedActions.contains(h.action)) {
        return (manifest: null, error: '不支持的钩子动作 "${h.action}"');
      }
    }

    return (manifest: manifest, error: null);
  }
}

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
  final PluginNotifyCallback? onNotify;

  PluginContext(
    this.settings,
    this.dataDir,
    this.sessionStream, {
    this.onNotify,
  });

  void notify(String message, {bool error = false}) =>
      onNotify?.call(message, error: error);
}

/// 已安装的外部插件（通过市场或本地 `.zip` 包导入）。
class InstalledPlugin extends KisakiPlugin {
  PluginManifest manifest;
  final String installDir;
  StreamSubscription<PlaySessionEnd>? _sessionSub;

  InstalledPlugin({
    required this.manifest,
    required this.installDir,
  });

  @override
  String get id => manifest.id;
  @override
  String get name => manifest.name;
  @override
  String get description => manifest.description;
  @override
  String get version => manifest.version;
  @override
  String get author => manifest.author;
  @override
  List<PluginSetting> get settings => manifest.settings;

  String get installSource => manifest.installSource;
  List<String> get permissions => manifest.permissions;

  bool get hasEntryFile {
    if (!PluginManifestValidator.isSafeRelativePath(manifest.entry)) {
      return false;
    }
    return File(p.join(installDir, manifest.entry)).existsSync();
  }

  @override
  Future<void> onInit(PluginContext ctx) async {
    await onDispose();
    final endHooks =
        manifest.hooks.where((h) => h.event == 'onSessionEnd').toList();
    if (endHooks.isEmpty) return;

    _sessionSub = ctx.sessionStream.listen((event) {
      final secs = event.session?.seconds ?? event.elapsedSeconds;
      final mins = (secs / 60).floor();
      for (final hook in endHooks) {
        final cfgMins = config['minutes'];
        final threshold = hook.thresholdMinutes ??
            (cfgMins is num
                ? cfgMins.toInt()
                : int.tryParse('$cfgMins') ?? 0);
        if (threshold > 0 && mins < threshold) continue;
        if (hook.action == 'notify' &&
            manifest.permissions.contains('notifications')) {
          final rawMsg = hook.message.isNotEmpty
              ? hook.message
              : '「${manifest.name}」会话结束：本次已游玩 $mins 分钟';
          final rendered = rawMsg
              .replaceAll('{minutes}', '$mins')
              .replaceAll('{gameId}', '${event.gameId}');
          ctx.notify(rendered);
        }
      }
    });
  }

  @override
  Future<void> onDispose() async {
    await _sessionSub?.cancel();
    _sessionSub = null;
  }
}

class PluginInstallResult {
  final bool ok;
  final InstalledPlugin? plugin;
  final String message;
  final bool isUpdate;

  const PluginInstallResult({
    required this.ok,
    this.plugin,
    required this.message,
    this.isUpdate = false,
  });
}

/// 插件管理器：负责本地 `.zip` / `.js` 安装、持久化加载、启用与卸载。
class PluginManager {
  final List<InstalledPlugin> _plugins = [];
  final SettingsStore settings;
  final String pluginsDir;

  /// 兼容旧界面字段（保留为无效文件或未迁移条目列表）。
  final List<Map<String, dynamic>> importedManifests = [];

  PluginManager(this.settings, this.pluginsDir);

  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  InstalledPlugin? byId(String id) {
    for (final p in _plugins) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 根据「Locale Emulator 转区启动」插件状态与配置解析游戏启动参数。
  ({
    bool shouldUseLe,
    String lePath,
    bool abortLaunch,
    String? notice,
    bool noticeIsError,
  }) resolveLaunchForGame({required bool gameUseLocaleEmulator}) {
    if (!gameUseLocaleEmulator) {
      return (
        shouldUseLe: false,
        lePath: '',
        abortLaunch: false,
        notice: null,
        noticeIsError: false,
      );
    }

    final plugin = byId(kLocaleEmulatorPluginId);
    if (plugin == null || !plugin.enabled) {
      return (
        shouldUseLe: false,
        lePath: '',
        abortLaunch: false,
        notice:
            '已开启 LE 转区启动，但尚未安装或启用「Locale Emulator 转区启动」插件，本次按普通方式启动',
        noticeIsError: true,
      );
    }

    final lePath = (plugin.config['le_path'] ?? '').toString().trim();
    final fallbackNormal = plugin.config['fallback_normal'] != false;
    if (lePath.isEmpty || !File(lePath).existsSync()) {
      if (fallbackNormal) {
        return (
          shouldUseLe: false,
          lePath: '',
          abortLaunch: false,
          notice:
              'Locale Emulator 插件未配置有效的 LEProc.exe 路径，本次按普通方式启动（可能显示乱码）',
          noticeIsError: true,
        );
      }
      return (
        shouldUseLe: false,
        lePath: '',
        abortLaunch: true,
        notice: 'Locale Emulator 插件未配置有效的 LEProc.exe 路径，已中止启动',
        noticeIsError: true,
      );
    }

    return (
      shouldUseLe: true,
      lePath: lePath,
      abortLaunch: false,
      notice: null,
      noticeIsError: false,
    );
  }

  /// 构建标准 `.zip` 插件压缩包字节（可用于打包测试包或离线示例）。
  static List<int> buildPluginZipBytes({
    required Map<String, dynamic> manifest,
    String mainJs = '// KisakiGals plugin entrypoint\n',
    String? readme,
  }) {
    final archive = Archive();
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    final entry = (manifest['entry'] ?? 'main.js').toString().trim();
    if (entry.isNotEmpty && PluginManifestValidator.isSafeRelativePath(entry)) {
      final jsBytes = utf8.encode(mainJs);
      archive.addFile(ArchiveFile(entry, jsBytes.length, jsBytes));
    }
    if (readme != null && readme.isNotEmpty) {
      final rmBytes = utf8.encode(readme);
      archive.addFile(ArchiveFile('README.md', rmBytes.length, rmBytes));
    }
    return ZipEncoder().encode(archive);
  }

  Future<void> _restoreAndRegister(
    InstalledPlugin plugin,
    PluginContext? ctx, {
    bool? forceEnabled,
  }) async {
    if (forceEnabled != null) {
      await settings.setBool('plugin.${plugin.id}.enabled', forceEnabled);
    }
    plugin.enabled = await settings.getBool('plugin.${plugin.id}.enabled');
    plugin.config = {};
    for (final s in plugin.settings) {
      switch (s.type) {
        case PluginSettingType.bool_:
          plugin.config[s.key] = await settings.getBool(
            'plugin.${plugin.id}.${s.key}',
            def: s.def is bool ? s.def as bool : false,
          );
        case PluginSettingType.int_:
          plugin.config[s.key] = await settings.getInt(
            'plugin.${plugin.id}.${s.key}',
            s.def is num ? (s.def as num).toInt() : 0,
          );
        case PluginSettingType.string_:
          var val = await settings.getString(
            'plugin.${plugin.id}.${s.key}',
            s.def?.toString() ?? '',
          );
          if (plugin.id == kLocaleEmulatorPluginId &&
              s.key == 'le_path' &&
              val.trim().isEmpty) {
            final legacy =
                (await settings.getString(SettingsStore.kLePath, '')).trim();
            if (legacy.isNotEmpty) {
              val = legacy;
              await settings.setString('plugin.${plugin.id}.le_path', val);
            }
          }
          plugin.config[s.key] = val;
      }
    }

    final existingIdx = _plugins.indexWhere((e) => e.id == plugin.id);
    if (existingIdx >= 0) {
      await _plugins[existingIdx].onDispose();
      _plugins[existingIdx] = plugin;
    } else {
      _plugins.add(plugin);
    }

    if (plugin.enabled && ctx != null) {
      try {
        await plugin.onInit(ctx);
      } catch (_) {}
    }
  }

  Future<void> loadInstalled([PluginContext? ctx]) async {
    final dir = Directory(pluginsDir);
    if (!dir.existsSync()) return;

    // 1) 兼容迁移旧版顶层 `<id>.json` 到 `<id>/manifest.json`
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        final raw = Map<String, dynamic>.from(
          jsonDecode(f.readAsStringSync()) as Map,
        );
        final res = PluginManifestValidator.validate(raw);
        if (res.manifest != null) {
          final m = res.manifest!;
          final targetDir = Directory(p.join(pluginsDir, m.id));
          if (!targetDir.existsSync()) {
            targetDir.createSync(recursive: true);
          }
          final targetManifest = File(p.join(targetDir.path, 'manifest.json'));
          if (!targetManifest.existsSync()) {
            await targetManifest.writeAsString(
              const JsonEncoder.withIndent('  ').convert(m.toJson()),
            );
          }
          await f.delete();
        }
      } catch (_) {}
    }

    // 2) 扫描已安装插件子目录
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final manifestFile = File(p.join(entity.path, 'manifest.json'));
      if (!manifestFile.existsSync()) continue;
      try {
        final raw = Map<String, dynamic>.from(
          jsonDecode(manifestFile.readAsStringSync()) as Map,
        );
        final res = PluginManifestValidator.validate(raw);
        if (res.manifest == null) continue;
        final plugin = InstalledPlugin(
          manifest: res.manifest!,
          installDir: entity.path,
        );
        await _restoreAndRegister(plugin, ctx);
      } catch (_) {}
    }
  }

  /// 向后兼容旧调用名。
  Future<void> loadImported([PluginContext? ctx]) => loadInstalled(ctx);

  Future<void> setEnabled(String id, bool enabled, PluginContext? ctx) async {
    final p = byId(id);
    if (p == null) return;
    p.enabled = enabled;
    await settings.setBool('plugin.$id.enabled', enabled);
    if (enabled && ctx != null) {
      try {
        await p.onInit(ctx);
      } catch (_) {}
    } else {
      await p.onDispose();
    }
  }

  Future<void> setConfig(String id, String key, dynamic value) async {
    final plugin = byId(id);
    if (plugin == null) return;
    plugin.config[key] = value;
    if (value is bool) {
      await settings.setBool('plugin.$id.$key', value);
    } else if (value is int) {
      await settings.setInt('plugin.$id.$key', value);
    } else {
      await settings.setString('plugin.$id.$key', '$value');
    }
  }

  Future<PluginInstallResult> installFromZip(
    String zipPath, {
    PluginContext? ctx,
    String installSource = 'zip',
    String? expectedSha256,
  }) async {
    final file = File(zipPath);
    if (!file.existsSync()) {
      return const PluginInstallResult(ok: false, message: '找不到所选 .zip 插件文件');
    }
    try {
      final bytes = await file.readAsBytes();
      return await installFromZipBytes(
        bytes,
        ctx: ctx,
        installSource: installSource,
        expectedSha256: expectedSha256,
      );
    } catch (e) {
      return PluginInstallResult(ok: false, message: '读取插件包失败：$e');
    }
  }

  Future<PluginInstallResult> installFromZipBytes(
    List<int> bytes, {
    PluginContext? ctx,
    String installSource = 'zip',
    String? expectedSha256,
    String? downloadUrl,
  }) async {
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final actual = sha256.convert(bytes).toString().toLowerCase();
      final want = expectedSha256.trim().toLowerCase();
      if (actual != want) {
        return PluginInstallResult(
          ok: false,
          message: 'SHA-256 校验失败（期望 ${want.substring(0, want.length.clamp(0, 12))}…）',
        );
      }
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (e) {
      return PluginInstallResult(ok: false, message: '无效的 .zip 压缩包：$e');
    }

    final fileEntries = archive.files.where((f) => f.isFile).toList();
    if (fileEntries.isEmpty) {
      return const PluginInstallResult(ok: false, message: '插件压缩包为空');
    }
    if (fileEntries.length > _kMaxPluginZipEntries) {
      return const PluginInstallResult(
        ok: false,
        message: '插件包内文件数量超过上限（最多 $_kMaxPluginZipEntries 个）',
      );
    }

    var totalBytes = 0;
    final normalizedEntries = <({String relPath, List<int> data})>[];
    for (final entry in fileEntries) {
      final rawName = entry.name.replaceAll('\\', '/');
      if (!PluginManifestValidator.isSafeRelativePath(rawName)) {
        return PluginInstallResult(
          ok: false,
          message: '检测到不安全路径 "${entry.name}"，已拒绝解压',
        );
      }
      final data = entry.content as List<int>;
      totalBytes += data.length;
      if (totalBytes > _kMaxPluginZipBytes) {
        return const PluginInstallResult(
          ok: false,
          message: '插件包解压后体积超过 32 MB 限制',
        );
      }
      normalizedEntries.add((relPath: rawName, data: data));
    }

    // 支持根目录下直接放 manifest.json，或打包时多一层同名顶层目录（如 my-plugin/manifest.json）
    String? commonPrefix;
    final directManifest = normalizedEntries
        .where((e) => e.relPath == 'manifest.json')
        .firstOrNull;
    if (directManifest == null) {
      final nestedManifests = normalizedEntries
          .where((e) => e.relPath.endsWith('/manifest.json'))
          .toList();
      if (nestedManifests.length == 1 &&
          nestedManifests.first.relPath.split('/').length == 2) {
        final candidatePrefix =
            '${nestedManifests.first.relPath.split('/').first}/';
        if (normalizedEntries.every((e) => e.relPath.startsWith(candidatePrefix))) {
          commonPrefix = candidatePrefix;
        }
      }
    }

    final resolvedEntries = <({String relPath, List<int> data})>[
      for (final e in normalizedEntries)
        (
          relPath: commonPrefix == null
              ? e.relPath
              : e.relPath.substring(commonPrefix.length),
          data: e.data,
        ),
    ];

    final manifestEntry = resolvedEntries
        .where((e) => e.relPath == 'manifest.json')
        .firstOrNull;
    if (manifestEntry == null) {
      return const PluginInstallResult(
        ok: false,
        message: '插件包根目录缺少 manifest.json',
      );
    }

    Map<String, dynamic> rawManifest;
    try {
      rawManifest = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(manifestEntry.data)) as Map,
      );
    } catch (e) {
      return PluginInstallResult(ok: false, message: 'manifest.json 解析失败：$e');
    }

    final checked = PluginManifestValidator.validate(rawManifest);
    if (checked.manifest == null) {
      return PluginInstallResult(
        ok: false,
        message: checked.error ?? 'manifest.json 校验失败',
      );
    }

    final enriched = checked.manifest!.copyWith(
      packageType: 'zip',
      installSource: installSource,
      downloadUrl: downloadUrl ?? checked.manifest!.downloadUrl,
      sha256: expectedSha256 ?? sha256.convert(bytes).toString(),
      installedAt: DateTime.now().toIso8601String(),
    );

    final isUpdate = byId(enriched.id) != null;
    final targetDir = Directory(p.join(pluginsDir, enriched.id));
    final normTarget = p.normalize(p.absolute(targetDir.path));
    if (targetDir.existsSync()) {
      await byId(enriched.id)?.onDispose();
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);

    for (final e in resolvedEntries) {
      if (e.relPath.isEmpty || e.relPath == 'manifest.json') continue;
      final dstPath = p.normalize(
        p.join(normTarget, e.relPath.replaceAll('/', Platform.pathSeparator)),
      );
      if (!p.isWithin(normTarget, dstPath)) {
        return const PluginInstallResult(ok: false, message: '检测到目录穿越路径');
      }
      final dst = File(dstPath);
      dst.parent.createSync(recursive: true);
      await dst.writeAsBytes(e.data, flush: true);
    }

    await File(p.join(normTarget, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(enriched.toJson()),
      flush: true,
    );

    final installed = InstalledPlugin(
      manifest: enriched,
      installDir: normTarget,
    );
    await _restoreAndRegister(
      installed,
      ctx,
      forceEnabled: isUpdate ? null : true,
    );

    return PluginInstallResult(
      ok: true,
      plugin: installed,
      isUpdate: isUpdate,
      message:
          '${isUpdate ? '已更新' : '已安装'}插件「${enriched.name}」v${enriched.version}',
    );
  }

  Future<PluginInstallResult> installFromJsBytes(
    List<int> jsBytes, {
    required PluginManifest manifest,
    PluginContext? ctx,
    String? expectedSha256,
    String installSource = 'marketplace',
  }) async {
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final actual = sha256.convert(jsBytes).toString().toLowerCase();
      final want = expectedSha256.trim().toLowerCase();
      if (actual != want) {
        return PluginInstallResult(
          ok: false,
          message: 'JS 插件 SHA-256 校验失败',
        );
      }
    }

    final checked = PluginManifestValidator.validate(manifest.toJson());
    if (checked.manifest == null) {
      return PluginInstallResult(
        ok: false,
        message: checked.error ?? '清单校验失败',
      );
    }

    final enriched = checked.manifest!.copyWith(
      packageType: 'js',
      entry: checked.manifest!.entry.isEmpty ? 'main.js' : checked.manifest!.entry,
      installSource: installSource,
      sha256: expectedSha256 ?? sha256.convert(jsBytes).toString(),
      installedAt: DateTime.now().toIso8601String(),
    );

    final isUpdate = byId(enriched.id) != null;
    final targetDir = Directory(p.join(pluginsDir, enriched.id));
    final normTarget = p.normalize(p.absolute(targetDir.path));
    if (targetDir.existsSync()) {
      await byId(enriched.id)?.onDispose();
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);

    final entryDstPath = p.normalize(
      p.join(normTarget, enriched.entry.replaceAll('/', Platform.pathSeparator)),
    );
    if (!p.isWithin(normTarget, entryDstPath)) {
      return const PluginInstallResult(ok: false, message: '入口脚本路径不安全');
    }
    final entryFile = File(entryDstPath);
    entryFile.parent.createSync(recursive: true);
    await entryFile.writeAsBytes(jsBytes, flush: true);

    await File(p.join(normTarget, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(enriched.toJson()),
      flush: true,
    );

    final installed = InstalledPlugin(
      manifest: enriched,
      installDir: normTarget,
    );
    await _restoreAndRegister(
      installed,
      ctx,
      forceEnabled: isUpdate ? null : true,
    );

    return PluginInstallResult(
      ok: true,
      plugin: installed,
      isUpdate: isUpdate,
      message:
          '${isUpdate ? '已更新' : '已安装'}脚本插件「${enriched.name}」v${enriched.version}',
    );
  }

  Future<bool> uninstall(String id) async {
    final existing = byId(id);
    if (existing != null) {
      await existing.onDispose();
      _plugins.removeWhere((p) => p.id == id);
    }
    final dir = Directory(p.join(pluginsDir, id));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    final legacyJson = File(p.join(pluginsDir, '$id.json'));
    if (legacyJson.existsSync()) {
      legacyJson.deleteSync();
    }
    await settings.setBool('plugin.$id.enabled', false);
    return true;
  }
}

// ================= 插件市场与 GitHub 加速下载 =================

enum PluginMirrorMode {
  auto('auto', '智能优选（直连 + 加速站）'),
  direct('direct', 'GitHub 直连'),
  ghfast('ghfast', 'ghfast.top 加速'),
  ghproxy('ghproxy', 'gh-proxy.com 加速'),
  jsdelivr('jsdelivr', 'jsDelivr CDN');

  final String id;
  final String label;
  const PluginMirrorMode(this.id, this.label);

  static PluginMirrorMode fromId(String raw) =>
      PluginMirrorMode.values.firstWhere(
        (m) => m.id == raw.trim(),
        orElse: () => PluginMirrorMode.auto,
      );
}

enum MarketplaceInstallState {
  notInstalled,
  installed,
  updateAvailable,
  incompatible,
}

class MarketplacePluginEntry {
  final PluginManifest manifest;
  final String downloadUrl;
  final String packageType; // 'zip' | 'js'
  final String sha256;
  final int sizeBytes;
  final int downloads;
  final String updatedAt;
  final bool verified;
  final String changelog;

  const MarketplacePluginEntry({
    required this.manifest,
    required this.downloadUrl,
    this.packageType = 'zip',
    this.sha256 = '',
    this.sizeBytes = 0,
    this.downloads = 0,
    this.updatedAt = '',
    this.verified = false,
    this.changelog = '',
  });

  String get id => manifest.id;
  String get name => manifest.name;
  String get version => manifest.version;
  String get author => manifest.author;
  String get description => manifest.description;
  String get category => manifest.category;

  MarketplaceInstallState checkState(
    InstalledPlugin? installed, {
    String currentAppVersion = AppInfo.version,
  }) {
    if (manifest.minAppVersion.isNotEmpty &&
        GithubUpdateChecker.compareVersions(
              manifest.minAppVersion,
              currentAppVersion,
            ) >
            0) {
      return MarketplaceInstallState.incompatible;
    }
    if (installed == null) return MarketplaceInstallState.notInstalled;
    if (GithubUpdateChecker.compareVersions(version, installed.version) > 0) {
      return MarketplaceInstallState.updateAvailable;
    }
    return MarketplaceInstallState.installed;
  }

  factory MarketplacePluginEntry.fromJson(Map<String, dynamic> raw) {
    final manifestMap = raw['manifest'] is Map
        ? Map<String, dynamic>.from(raw['manifest'] as Map)
        : raw;
    final manifest = PluginManifest.fromJson(manifestMap);
    final packageType =
        (raw['packageType'] ?? manifest.packageType).toString().toLowerCase();
    final downloadUrl =
        (raw['downloadUrl'] ?? manifest.downloadUrl ?? '').toString().trim();
    final sha = (raw['sha256'] ?? manifest.sha256 ?? '').toString().trim();
    return MarketplacePluginEntry(
      manifest: manifest.copyWith(
        packageType: packageType,
        downloadUrl: downloadUrl,
        sha256: sha,
        installSource: 'marketplace',
      ),
      downloadUrl: downloadUrl,
      packageType: packageType,
      sha256: sha,
      sizeBytes: raw['sizeBytes'] is num ? (raw['sizeBytes'] as num).toInt() : 0,
      downloads: raw['downloads'] is num ? (raw['downloads'] as num).toInt() : 0,
      updatedAt: (raw['updatedAt'] ?? '').toString().trim(),
      verified: raw['verified'] == true,
      changelog: (raw['changelog'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        ...manifest.toJson(),
        'downloadUrl': downloadUrl,
        'packageType': packageType,
        if (sha256.isNotEmpty) 'sha256': sha256,
        if (sizeBytes > 0) 'sizeBytes': sizeBytes,
        if (downloads > 0) 'downloads': downloads,
        if (updatedAt.isNotEmpty) 'updatedAt': updatedAt,
        'verified': verified,
        if (changelog.isNotEmpty) 'changelog': changelog,
      };
}

class MarketplaceIndexResult {
  final bool ok;
  final List<MarketplacePluginEntry> entries;
  final String generatedAt;
  final String sourceLabel;
  final bool fromFallback;
  final String message;

  const MarketplaceIndexResult({
    required this.ok,
    required this.entries,
    this.generatedAt = '',
    this.sourceLabel = '',
    this.fromFallback = false,
    this.message = '',
  });
}

/// 官方内置精选目录（远程聚合仓库不可达或离线环境下仍可供浏览与按需安装）。
final List<MarketplacePluginEntry> kCuratedMarketplaceEntries = [
  MarketplacePluginEntry(
    manifest: const PluginManifest(
      id: kLocaleEmulatorPluginId,
      name: 'Locale Emulator 转区启动',
      version: '1.0.0',
      author: 'xupefei / KisakiGals',
      description:
          '基于 Locale Emulator (LEProc.exe) 的日文及非 Unicode 游戏转区启动插件；可在游戏详情界面「…」菜单内按作品开启转区开关',
      homepage: kLocaleEmulatorProjectUrl,
      repository: kLocaleEmulatorProjectUrl,
      license: 'LGPL-3.0',
      minAppVersion: '1.1.0',
      entry: 'main.js',
      packageType: 'zip',
      category: '启动与转区',
      tags: ['Locale Emulator', 'LE', '转区', '日文', 'LEProc'],
      permissions: [
        'process.launch',
        'settings.storage',
        'library.read',
        'notifications',
      ],
      settings: [
        PluginSetting(
          'le_path',
          'LEProc.exe 路径',
          PluginSettingType.string_,
          def: '',
          description:
              '指向 Locale Emulator 安装目录中的 LEProc.exe（原项目：$kLocaleEmulatorProjectUrl）',
        ),
        PluginSetting(
          'fallback_normal',
          '路径缺失时回退普通启动',
          PluginSettingType.bool_,
          def: true,
          description: '未配置有效 LEProc.exe 时提示并回退普通启动',
        ),
      ],
      hooks: [
        PluginHookRule(
          event: 'onGameLaunch',
          action: 'log',
          message: '通过 Locale Emulator (LEProc.exe) 转区启动游戏 #{gameId}',
        ),
      ],
    ),
    downloadUrl:
        'https://raw.githubusercontent.com/MusaLunar/KisakiGals/main/plugins/dist/locale-emulator-1.0.0.zip',
    packageType: 'zip',
    updatedAt: '2026-11-21',
    verified: true,
    changelog: '将原有的内置 LE 转区功能独立为插件，支持在游戏详情页「…」菜单内按作品独立开关',
  ),
];

/// 插件市场客户端服务：拉取静态 `index.json`、解析加速地址、校验并安装 `.zip`/`.js`。
class PluginMarketplaceService {
  static const String defaultRegistryUrl =
      'https://raw.githubusercontent.com/MusaLunar/KisakiGals/main/plugins/index.json';

  final String? proxy;
  final PluginDownloadBytesFn? _customDownloader;

  PluginMarketplaceService({
    this.proxy,
    PluginDownloadBytesFn? downloader,
  }) : _customDownloader = downloader;

  /// 根据镜像模式生成有序候选地址，支持 GitHub Raw 与 Release 文件自动加速。
  static List<String> resolveCandidateUrls(
    String rawUrl,
    PluginMirrorMode mode,
  ) {
    final url = rawUrl.trim();
    if (url.isEmpty) return const [];
    final jsd = _toJsDelivr(url);

    final candidates = switch (mode) {
      PluginMirrorMode.direct => [url],
      PluginMirrorMode.ghfast => ['https://ghfast.top/$url', url],
      PluginMirrorMode.ghproxy => ['https://gh-proxy.com/$url', url],
      PluginMirrorMode.jsdelivr => [
          if (jsd != null) jsd else 'https://ghfast.top/$url',
          url,
        ],
      PluginMirrorMode.auto => [
          if (jsd != null) jsd,
          url,
          'https://ghfast.top/$url',
          'https://gh-proxy.com/$url',
        ],
    };

    final seen = <String>{};
    return [
      for (final c in candidates)
        if (seen.add(c)) c,
    ];
  }

  static String? _toJsDelivr(String url) {
    final rawMatch = RegExp(
      r'^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)$',
    ).firstMatch(url);
    if (rawMatch != null) {
      final owner = rawMatch.group(1)!;
      final repo = rawMatch.group(2)!;
      final branch = rawMatch.group(3)!;
      final filePath = rawMatch.group(4)!;
      return 'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$filePath';
    }
    final ghRawMatch = RegExp(
      r'^https://github\.com/([^/]+)/([^/]+)/raw/([^/]+)/(.+)$',
    ).firstMatch(url);
    if (ghRawMatch != null) {
      final owner = ghRawMatch.group(1)!;
      final repo = ghRawMatch.group(2)!;
      final branch = ghRawMatch.group(3)!;
      final filePath = ghRawMatch.group(4)!;
      return 'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$filePath';
    }
    return null;
  }

  Dio _buildDio({required bool useProxy}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json, application/octet-stream, */*',
        'User-Agent': 'MusaLunar/${AppInfo.name}/${AppInfo.version}',
      },
      responseType: ResponseType.bytes,
      validateStatus: (s) => s != null && s >= 200 && s < 400,
    ));
    if (useProxy && proxy != null && proxy!.trim().isNotEmpty) {
      dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          final cleaned = proxy!.trim().replaceFirst(RegExp(r'^https?://'), '');
          client.findProxy = (_) => 'PROXY $cleaned';
          return client;
        };
    }
    return dio;
  }

  Future<List<int>> _downloadBytesWithFallback(
    String rawUrl,
    PluginMirrorMode mode,
  ) async {
    final urls = resolveCandidateUrls(rawUrl, mode);
    if (urls.isEmpty) {
      throw const FormatException('下载地址为空');
    }
    Object? lastError;
    for (final url in urls) {
      if (_customDownloader != null) {
        try {
          return await _customDownloader(url);
        } catch (e) {
          lastError = e;
          continue;
        }
      }
      if (Platform.environment['FLUTTER_TEST'] == 'true') {
        throw StateError('flutter test offline');
      }
      final hasProxy = proxy != null && proxy!.trim().isNotEmpty;
      for (final useProxy in [if (hasProxy) true, false]) {
        final dio = _buildDio(useProxy: useProxy);
        try {
          final resp = await dio.get<List<int>>(url);
          final data = resp.data;
          if (data != null && data.isNotEmpty) {
            return data;
          }
        } catch (e) {
          lastError = e;
        } finally {
          dio.close(force: true);
        }
      }
    }
    throw lastError ?? StateError('所有下载源均失败');
  }

  /// 解析聚合索引 `index.json` 字符串。
  static MarketplaceIndexResult parseIndexJson(
    String rawJson, {
    String sourceLabel = '远程聚合索引',
  }) {
    final decoded = jsonDecode(rawJson);
    final rawList = switch (decoded) {
      List list => list,
      Map map when map['plugins'] is List => map['plugins'] as List,
      _ => const <dynamic>[],
    };
    final generatedAt = decoded is Map
        ? (decoded['generatedAt'] ?? '').toString().trim()
        : '';

    final entries = <MarketplacePluginEntry>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final entry = MarketplacePluginEntry.fromJson(map);
      if (entry.id.isNotEmpty && entry.name.isNotEmpty) {
        entries.add(entry);
      }
    }

    return MarketplaceIndexResult(
      ok: true,
      entries: entries,
      generatedAt: generatedAt,
      sourceLabel: sourceLabel,
      message: '已加载 ${entries.length} 个市场插件',
    );
  }

  /// 拉取官方聚合仓库发布的 `index.json`；若离线或仓库尚未发布，安全回退内置精选目录。
  Future<MarketplaceIndexResult> fetchIndex({
    String? customRegistryUrl,
    PluginMirrorMode mirror = PluginMirrorMode.auto,
  }) async {
    final url = (customRegistryUrl != null && customRegistryUrl.trim().isNotEmpty)
        ? customRegistryUrl.trim()
        : defaultRegistryUrl;
    try {
      final bytes = await _downloadBytesWithFallback(url, mirror);
      final parsed = parseIndexJson(
        utf8.decode(bytes),
        sourceLabel: url,
      );
      if (parsed.entries.isNotEmpty) {
        return parsed;
      }
    } catch (_) {}

    return MarketplaceIndexResult(
      ok: true,
      entries: kCuratedMarketplaceEntries,
      sourceLabel: '官方精选目录（离线/缓存）',
      fromFallback: true,
      message: '远程聚合索引暂不可达，已展示内置精选插件目录（${kCuratedMarketplaceEntries.length} 项）',
    );
  }

  /// 下载、校验并安装市场插件（支持 `.zip` 压缩包与 `.js` 单脚本，自动支持加速镜像）。
  Future<PluginInstallResult> installEntry(
    MarketplacePluginEntry entry, {
    required PluginManager manager,
    PluginContext? ctx,
    PluginMirrorMode mirror = PluginMirrorMode.auto,
  }) async {
    final validation = PluginManifestValidator.validate(entry.manifest.toJson());
    if (validation.manifest == null) {
      return PluginInstallResult(
        ok: false,
        message: validation.error ?? '插件清单不符合规范',
      );
    }

    final expectedSha = entry.sha256.trim().isEmpty ? null : entry.sha256.trim();
    List<int>? downloaded;
    Object? downloadErr;
    if (entry.downloadUrl.isNotEmpty) {
      try {
        downloaded = await _downloadBytesWithFallback(entry.downloadUrl, mirror);
      } catch (e) {
        downloadErr = e;
      }
    }

    // 远程包尚未发布且属于官方精选插件时，构造合规精选包供按需安装
    if (downloaded == null) {
      final isOfficialCurated = entry.downloadUrl.startsWith(
            'https://raw.githubusercontent.com/MusaLunar/KisakiGals/',
          ) ||
          entry.downloadUrl.startsWith(
            'https://github.com/MusaLunar/KisakiGals/',
          ) ||
          entry.downloadUrl.startsWith(
            'https://github.com/MusaLunar/KisakiGals-Plugins/',
          ) ||
          entry.downloadUrl.startsWith(
            'https://raw.githubusercontent.com/MusaLunar/KisakiGals-Plugins/',
          );
      final curatedMatch =
          kCuratedMarketplaceEntries.any((e) => e.id == entry.id);
      if (isOfficialCurated && curatedMatch && expectedSha == null) {
        final fallbackJs = '''// ${entry.name} (${entry.id}) v${entry.version}
module.exports = {
  id: '${entry.id}',
  onInit(ctx) {
    ctx.settings.get('${entry.id}');
  }
};
''';
        if (entry.packageType == 'js') {
          return manager.installFromJsBytes(
            utf8.encode(fallbackJs),
            manifest: entry.manifest,
            ctx: ctx,
            installSource: 'marketplace',
          );
        }
        final zipBytes = PluginManager.buildPluginZipBytes(
          manifest: entry.manifest.toJson(),
          mainJs: fallbackJs,
          readme: '# ${entry.name}\n\n${entry.description}\n',
        );
        return manager.installFromZipBytes(
          zipBytes,
          ctx: ctx,
          installSource: 'marketplace',
          downloadUrl: entry.downloadUrl,
        );
      }
      return PluginInstallResult(
        ok: false,
        message: '下载插件包失败：${downloadErr ?? '未提供有效下载地址'}',
      );
    }

    if (entry.packageType == 'js' ||
        entry.downloadUrl.toLowerCase().endsWith('.js')) {
      return manager.installFromJsBytes(
        downloaded,
        manifest: entry.manifest,
        ctx: ctx,
        expectedSha256: expectedSha,
        installSource: 'marketplace',
      );
    }

    return manager.installFromZipBytes(
      downloaded,
      ctx: ctx,
      installSource: 'marketplace',
      expectedSha256: expectedSha,
      downloadUrl: entry.downloadUrl,
    );
  }
}
