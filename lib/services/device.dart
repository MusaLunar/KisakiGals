/// 设备识别与可移植路径。
///
/// 目标：把数据库拷到另一台电脑（或换盘符/换目录）后，**不改动用户手动
/// 指定的游戏路径**，而是自动按「库根 + 相对路径」或「目录名搜索」重新定位。
///
/// 识别方式：Windows 安装唯一标识 MachineGuid（注册表），失败则退化为
/// 数据目录里持久化的随机 UUID。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/models.dart';
import '../data/settings_store.dart';

class DeviceInfo {
  final String id;
  final String name;
  const DeviceInfo(this.id, this.name);
}

/// 当前设备标识（缓存）。
class DeviceIdentity {
  static DeviceInfo? _cached;

  static Future<DeviceInfo> current(SettingsStore settings) async {
    if (_cached != null) return _cached!;
    var id = '';
    try {
      final r = Process.runSync('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      if (r.exitCode == 0) {
        final m = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)')
            .firstMatch(r.stdout.toString());
        if (m != null) id = m.group(1)!.trim();
      }
    } catch (_) {}
    // 兜底：设置里持久化一个随机 ID（同一数据目录稳定）
    if (id.isEmpty) {
      id = await settings.getString(SettingsStore.kDeviceId, '');
      if (id.isEmpty) {
        id = 'dev-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
        await settings.setString(SettingsStore.kDeviceId, id);
      }
    }
    final name = Platform.localHostname;
    _cached = DeviceInfo(id, name);
    return _cached!;
  }
}

class RelocateResult {
  final List<String> relocated;
  final List<String> missing;
  const RelocateResult(this.relocated, this.missing);
}

/// 库根目录管理 + 缺失路径重定位。
class PathRelocator {
  final SettingsStore settings;
  final GameRepositoryLike repo;
  const PathRelocator(this.settings, this.repo);

  /// 已知库根（游戏目录的上级目录），存 settings 的 JSON 数组。
  /// 解析失败时退化为按换行分隔（容错历史/手工写入的格式）。
  Future<List<String>> roots() async {
    final raw = await settings.getString(SettingsStore.kLibraryRoots, '[]');
    if (raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return [
          for (final e in list)
            if (e.toString().trim().isNotEmpty) e.toString().trim()
        ];
      }
    } catch (_) {
      // 例如路径含未转义反斜杠：按分隔符容错解析
    }
    return [
      for (final part in raw.split(RegExp(r'[\r\n;]+')))
        if (part.replaceAll(RegExp(r'[\[\]"]'), '').trim().isNotEmpty)
          part.replaceAll(RegExp(r'[\[\]"]'), '').trim()
    ];
  }

  Future<void> rememberRoot(String gameDirectory) async {
    if (gameDirectory.isEmpty) return;
    final parent = p.dirname(gameDirectory);
    if (parent.isEmpty) return;
    final list = await roots();
    if (list.contains(parent)) return;
    list.add(parent);
    await settings.setString(
        SettingsStore.kLibraryRoots, jsonEncode(list.take(20).toList()));
  }

  /// 计算相对已知根的路径（找不到匹配根则返回空）。
  Future<String> relativeFor(String path) async {
    for (final root in await roots()) {
      if (path.toLowerCase().startsWith(root.toLowerCase())) {
        final rel = p.relative(path, from: root);
        if (!rel.startsWith('..')) return rel;
      }
    }
    return '';
  }

  /// 为一部游戏补齐设备/相对路径信息（添加或编辑保存时调用）。
  Future<Game> stamp(Game game) async {
    final info = await DeviceIdentity.current(settings);
    game.deviceId = info.id;
    game.dirName = game.directory.isEmpty ? '' : p.basename(game.directory);
    if (game.directory.isNotEmpty) {
      await rememberRoot(game.directory);
      game.relPath = await relativeFor(game.directory);
    }
    return game;
  }

  /// 重定位所有「可执行文件已不存在」的游戏。返回结果供 UI 提示。
  Future<RelocateResult> relocateMissing() async {
    final games = await repo.allGames();
    final rootsList = await roots();
    final info = await DeviceIdentity.current(settings);
    final relocated = <String>[];
    final missing = <String>[];

    for (final g in games) {
      if (g.exePath.isEmpty) continue;
      if (File(g.exePath).existsSync()) continue;

      final found = _resolve(g, rootsList);
      if (found == null) {
        missing.add(g.displayName);
        continue;
      }
      g.directory = found.$1;
      g.exePath = found.$2;
      g.deviceId = info.id;
      g.dirName = p.basename(found.$1);
      g.relPath = await relativeFor(found.$1);
      await repo.updateGame(g);
      relocated.add(g.displayName);
    }
    return RelocateResult(relocated, missing);
  }

  /// 定位策略：① 相对路径 + 已知根 ② 按目录名在已知根下搜索（≤3 层）
  /// ③ 按 exe 文件名在已知根下搜索。
  (String, String)? _resolve(Game g, List<String> rootsList) {
    final exeName = p.basename(g.exePath);
    final dirName = g.dirName.isNotEmpty
        ? g.dirName
        : (g.directory.isEmpty ? '' : p.basename(g.directory));

    // ① 相对路径
    if (g.relPath.isNotEmpty) {
      for (final root in rootsList) {
        final dir = p.normalize(p.join(root, g.relPath));
        final exe = p.normalize(p.join(dir, exeName));
        if (File(exe).existsSync()) return (dir, exe);
      }
    }
    // ②③ 按目录名 / exe 名搜索
    if (dirName.isEmpty && exeName.isEmpty) return null;
    for (final root in rootsList) {
      final hit = _searchUnder(p.normalize(root), dirName, exeName, 0);
      if (hit != null) return hit;
    }
    return null;
  }

  (String, String)? _searchUnder(
      String dir, String dirName, String exeName, int depth) {
    if (depth > 3) return null;
    final d = Directory(dir);
    if (!d.existsSync()) return null;
    if (dirName.isNotEmpty && p.basename(dir).toLowerCase() == dirName.toLowerCase()) {
      final exe = p.join(dir, exeName);
      if (File(exe).existsSync()) return (dir, exe);
      // 目录名匹配但 exe 名变了：尝试目录内同名或唯一 exe
      final alt = _pickExe(dir);
      if (alt.isNotEmpty) return (dir, alt);
    }
    try {
      for (final e in d.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (name.startsWith('.') || name == 'Windows' || name == r'$Recycle.Bin') {
          continue;
        }
        final hit = _searchUnder(e.path, dirName, exeName, depth + 1);
        if (hit != null) return hit;
      }
    } catch (_) {}
    return null;
  }

  String _pickExe(String dir) {
    try {
      final exes = Directory(dir)
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.exe'))
          .toList();
      if (exes.length == 1) return exes.first.path;
    } catch (_) {}
    return '';
  }
}

/// 供 [PathRelocator] 使用的最小仓储接口（便于测试替身）。
abstract class GameRepositoryLike {
  Future<List<Game>> allGames();
  Future<void> updateGame(Game g);
}
