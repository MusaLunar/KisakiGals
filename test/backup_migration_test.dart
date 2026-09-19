import 'dart:ffi';
import 'dart:io';

import 'package:kisakigals/core/media_paths.dart';
import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/game_repository.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/services/autostart.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

/// 备份/迁移：封面与背景必须跟着走，且换设备后路径仍能定位。
void main() {
  setUpAll(() {
    final shipped = File('build/windows/x64/runner/Release/sqlite3.dll');
    if (Platform.isWindows && shipped.existsSync()) {
      open.overrideFor(
          OperatingSystem.windows, () => DynamicLibrary.open(shipped.path));
    }
  });
  sqfliteFfiInit();

  late Directory srcRoot; // 原设备数据目录
  late Directory backupDir;
  late Database db;
  late GameRepository repo;

  setUp(() async {
    srcRoot = Directory.systemTemp.createTempSync('kisaki_src_');
    backupDir = Directory.systemTemp.createTempSync('kisaki_bak_');
    Directory(p.join(srcRoot.path, 'covers')).createSync(recursive: true);
    // 模拟应用启动时的安装（数据层通过全局实例换算相对路径）
    MediaPaths.install(srcRoot.path);
    db = await openAppDb(p.join(srcRoot.path, 'kisakigals.db'));
    repo = GameRepository(db);
  });

  tearDown(() async {
    await db.close();
    for (final d in [srcRoot, backupDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<Game> seedWithCover() async {
    final cover = File(p.join(srcRoot.path, 'covers', 'game_1.jpg'));
    cover.writeAsBytesSync(List<int>.filled(2048, 7));
    final bg = File(p.join(srcRoot.path, 'covers', 'bg_1.jpg'));
    bg.writeAsBytesSync(List<int>.filled(2048, 9));
    final g = Game(
      name: '千恋＊万花',
      nameCn: '千恋万花',
      coverPath: cover.path, // 绝对路径（旧行为）
      backgroundUrl: bg.path,
      directory: r'D:\Games\Senren',
      exePath: r'D:\Games\Senren\senren.exe',
      relPath: 'Senren',
      dirName: 'Senren',
    );
    await repo.insertGame(g);
    return (await repo.getGame(g.id!))!;
  }

  test('写入数据库时封面/背景转为相对数据目录的路径', () async {
    final g = await seedWithCover();
    expect(g.coverPath, 'covers/game_1.jpg');
    expect(g.backgroundUrl, 'covers/bg_1.jpg');
  });

  test('备份包含封面与背景（不是只有数据库）', () async {
    await seedWithCover();
    final svc = BackupService(
      dbFile: p.join(srcRoot.path, 'kisakigals.db'),
      backupsDir: backupDir.path,
      dataRoot: srcRoot.path,
    );
    final path = await svc.backup(checkpointDb: db);
    expect(path, endsWith(BackupService.ext));
    expect(BackupService.looksLikeArchive(path), isTrue,
        reason: '备份应为打包文件（含媒体）');
    expect(BackupService.looksLikeSqlite(path), isFalse);

    // 用另一个服务实例恢复到一个全新目录，模拟「另一台设备」
    final dstRoot = Directory.systemTemp.createTempSync('kisaki_dst_');
    addTearDown(() {
      if (dstRoot.existsSync()) dstRoot.deleteSync(recursive: true);
    });
    final restored = BackupService(
      dbFile: p.join(dstRoot.path, 'kisakigals.db'),
      backupsDir: p.join(dstRoot.path, 'backups'),
      dataRoot: dstRoot.path,
    );
    final media = await restored.restore(path);
    expect(media, greaterThanOrEqualTo(2), reason: '封面与背景都应被还原');
    expect(File(p.join(dstRoot.path, 'covers', 'game_1.jpg')).existsSync(),
        isTrue);
    expect(File(p.join(dstRoot.path, 'covers', 'bg_1.jpg')).existsSync(), isTrue);

    // 新设备上：数据库里的相对路径应解析到新位置的封面
    final paths = MediaPaths(dstRoot.path);
    expect(paths.resolveStored('covers/game_1.jpg'),
        p.normalize(p.join(dstRoot.path, 'covers', 'game_1.jpg')));
  });

  test('兼容旧版纯 .db 备份', () async {
    await seedWithCover();
    final legacy = p.join(backupDir.path, 'legacy.db');
    File(p.join(srcRoot.path, 'kisakigals.db')).copySync(legacy);
    expect(BackupService.looksLikeSqlite(legacy), isTrue);

    final dstRoot = Directory.systemTemp.createTempSync('kisaki_dst2_');
    addTearDown(() {
      if (dstRoot.existsSync()) dstRoot.deleteSync(recursive: true);
    });
    final media = await BackupService(
      dbFile: p.join(dstRoot.path, 'kisakigals.db'),
      backupsDir: p.join(dstRoot.path, 'backups'),
      dataRoot: dstRoot.path,
    ).restore(legacy);
    expect(media, 0);
    expect(File(p.join(dstRoot.path, 'kisakigals.db')).existsSync(), isTrue);
  });

  test('修复历史数据：绝对路径失效时按文件名在 covers/ 找回', () async {
    await seedWithCover();
    // 手工写回旧式绝对路径（模拟迁移前的库），并把它指向不存在的旧位置
    await db.update(
        'games',
        {
          'cover_path': r'D:\OldPC\KisakiGals\data\covers\game_1.jpg',
          'background_url': r'D:\OldPC\KisakiGals\data\covers\bg_1.jpg',
        },
        where: 'id = ?',
        whereArgs: [1]);

    final paths = MediaPaths(srcRoot.path);
    final fixed = await paths.repairLegacyMediaPaths(db);
    expect(fixed, 1, reason: '应修复 1 条记录');

    final g = await repo.getGame(1);
    expect(g!.coverPath, 'covers/game_1.jpg');
    expect(g.backgroundUrl, 'covers/bg_1.jpg');
    // 解析后确实指向本机存在的文件
    expect(File(paths.resolveStored(g.coverPath)).existsSync(), isTrue);
  });

  test('备份文件可被 prune 清理（含新旧两种格式）', () async {
    await seedWithCover();
    final svc = BackupService(
      dbFile: p.join(srcRoot.path, 'kisakigals.db'),
      backupsDir: backupDir.path,
      dataRoot: srcRoot.path,
    );
    for (var i = 0; i < 3; i++) {
      await svc.backup(checkpointDb: db);
      await Future.delayed(const Duration(milliseconds: 1100));
    }
    File(p.join(backupDir.path, 'old.db')).writeAsStringSync('x');
    expect(svc.list().length, 4);
    await svc.prune(2);
    expect(svc.list().length, 2);
  });
}
