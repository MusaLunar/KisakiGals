import 'dart:convert';
import 'dart:io';

import 'package:kisakigals/data/models.dart';
import 'package:path/path.dart' as p;
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/services/device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// 内存仓储替身
class _FakeRepo implements GameRepositoryLike {
  final List<Game> games;
  _FakeRepo(this.games);
  @override
  Future<List<Game>> allGames() async => games;
  @override
  Future<void> updateGame(Game g) async {}
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late SettingsStore settings;
  late Directory root; // 模拟「另一台电脑」的库根

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    settings = SettingsStore(db);
    root = Directory.systemTemp.createTempSync('kisaki_relocate_');
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('按相对路径把游戏重定位到新设备的库根', () async {
    // 新设备上的实际目录：<root>/Galgame/千恋万花/game.exe
    final gameDir = Directory('${root.path}/Galgame/千恋万花')
      ..createSync(recursive: true);
    File('${gameDir.path}/game.exe').writeAsStringSync('x');
    await settings.setString(SettingsStore.kLibraryRoots,
        jsonEncode(['${root.path}/Galgame']));

    // 旧设备记录：绝对路径已失效，但保留了相对路径
    final g = Game(
      id: 1,
      name: '千恋万花',
      directory: r'D:\Games\千恋万花',
      exePath: r'D:\Games\千恋万花\game.exe',
      relPath: '千恋万花',
      dirName: '千恋万花',
      deviceId: 'old-device',
    );
    final repo = _FakeRepo([g]);
    final result = await PathRelocator(settings, repo).relocateMissing();

    expect(result.relocated, ['千恋万花']);
    expect(p.normalize(g.directory), p.normalize(gameDir.path));
    expect(p.normalize(g.exePath), p.normalize(p.join(gameDir.path, 'game.exe')));
    expect(g.deviceId, isNot('old-device'), reason: '应更新为当前设备');
  });

  test('相对路径缺失时按目录名在库根下搜索（3 层内）', () async {
    final gameDir = Directory('${root.path}/a/b/ATRI')
      ..createSync(recursive: true);
    File('${gameDir.path}/atri.exe').writeAsStringSync('x');
    await settings.setString(
        SettingsStore.kLibraryRoots, jsonEncode([root.path]));

    final g = Game(
      id: 2,
      name: 'ATRI',
      directory: r'E:\Other\ATRI',
      exePath: r'E:\Other\ATRI\atri.exe',
      dirName: 'ATRI',
    );
    final result =
        await PathRelocator(settings, _FakeRepo([g])).relocateMissing();

    expect(result.relocated, ['ATRI']);
    expect(p.normalize(g.exePath), p.normalize(p.join(gameDir.path, 'atri.exe')));
  });

  test('找不到时归入 missing，且不改动原来的路径', () async {
    await settings.setString(
        SettingsStore.kLibraryRoots, jsonEncode([root.path]));
    final g = Game(
      id: 3,
      name: '不存在的游戏',
      directory: r'Z:\Nowhere\Ghost',
      exePath: r'Z:\Nowhere\Ghost\ghost.exe',
      dirName: 'Ghost',
    );
    final result =
        await PathRelocator(settings, _FakeRepo([g])).relocateMissing();

    expect(result.missing, ['不存在的游戏']);
    expect(g.exePath, r'Z:\Nowhere\Ghost\ghost.exe', reason: '路径应保持原样');
  });

  test('已在当前设备存在的游戏不会被改动', () async {
    final gameDir = Directory('${root.path}/Live')
      ..createSync(recursive: true);
    final exe = File('${gameDir.path}/live.exe')..writeAsStringSync('x');
    await settings.setString(
        SettingsStore.kLibraryRoots, jsonEncode([root.path]));

    final g = Game(id: 4, name: 'Live', directory: gameDir.path, exePath: exe.path);
    final result =
        await PathRelocator(settings, _FakeRepo([g])).relocateMissing();

    expect(result.relocated, isEmpty);
    expect(result.missing, isEmpty);
    expect(g.exePath, exe.path);
  });

  test('stamp 记录设备、目录名与相对路径', () async {
    final gameDir = Directory('${root.path}/Lib/GameA')..createSync(recursive: true);
    final repo = _FakeRepo([]);
    final g = Game(id: 5, name: 'GameA', directory: gameDir.path);
    await PathRelocator(settings, repo).stamp(g);

    expect(g.deviceId, isNotEmpty);
    expect(g.dirName, 'GameA');
    expect(g.relPath, 'GameA');
    final roots = await PathRelocator(settings, repo).roots();
    expect(roots, contains('${root.path}/Lib'));
  });
}
