import 'dart:io';

import 'package:kisakigals/services/save_backup.dart';
import 'package:test/test.dart';

/// 存档目录探测（纯文件系统逻辑，不依赖 AppServices）
void main() {
  group('SaveScanner 存档目录探测', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('kisaki_save_test_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('识别 savedata / save / セーブ 目录', () {
      Directory('${root.path}/savedata').createSync();
      File('${root.path}/savedata/a.dat').writeAsStringSync('x');
      expect(SaveScanner.detectSaveDir(root.path, 'SomeGame'),
          contains('savedata'));
    });

    test('识别二级子目录（game/data/save）', () {
      Directory('${root.path}/data/save').createSync(recursive: true);
      File('${root.path}/data/save/s1.dat').writeAsStringSync('x');
      final found = SaveScanner.detectSaveDir(root.path, 'SomeGame');
      expect(found, isNotEmpty);
      expect(found, contains('save'));
    });

    test('忽略 screenshot / cache 目录', () {
      Directory('${root.path}/screenshot').createSync();
      Directory('${root.path}/cache').createSync();
      expect(SaveScanner.detectSaveDir(root.path, 'SomeGame'), isEmpty);
    });

    test('目录不存在时返回空串', () {
      expect(SaveScanner.detectSaveDir('${root.path}/not-exist', 'x'), isEmpty);
    });

    test('优先匹配以游戏名命名的存档目录', () {
      Directory('${root.path}/save').createSync();
      File('${root.path}/save/a.dat').writeAsStringSync('x');
      Directory('${root.path}/GameName_savedata').createSync();
      File('${root.path}/GameName_savedata/b.dat').writeAsStringSync('x');
      final found = SaveScanner.detectSaveDir(root.path, 'GameName');
      expect(found, contains('GameName_savedata'));
    });
  });

  group('SaveBackupService 备份与恢复', () {
    late Directory data;
    late Directory saves;
    late SaveBackupService svc;

    setUp(() {
      data = Directory.systemTemp.createTempSync('kisaki_data_');
      saves = Directory.systemTemp.createTempSync('kisaki_saves_');
      svc = SaveBackupService(data.path);
      File('${saves.path}/save01.dat').writeAsStringSync('v1');
      Directory('${saves.path}/sub').createSync();
      File('${saves.path}/sub/deep.dat').writeAsStringSync('deep');
    });

    tearDown(() {
      for (final d in [data, saves]) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });

    test('备份后列出，含文件数与大小', () async {
      final name = await svc.backup(1, saves.path);
      final list = svc.list(1);
      expect(list.length, 1);
      expect(list.first.name, name);
      expect(list.first.fileCount, 2);
      expect(list.first.totalBytes, greaterThan(0));
    });

    test('恢复覆盖改动过的存档', () async {
      final name = await svc.backup(1, saves.path);
      File('${saves.path}/save01.dat').writeAsStringSync('v2-changed');
      final (done, total) = await svc.restore(1, name, snapshot: false);
      expect(done, 2);
      expect(total, 2);
      expect(File('${saves.path}/save01.dat').readAsStringSync(), 'v1');
      expect(File('${saves.path}/sub/deep.dat').readAsStringSync(), 'deep');
    });

    test('恢复前快照会额外生成一份自动备份', () async {
      final name = await svc.backup(1, saves.path);
      File('${saves.path}/save01.dat').writeAsStringSync('changed');
      await svc.restore(1, name);
      final list = svc.list(1);
      expect(list.length, 2, reason: '恢复前应产生一份快照备份');
      expect(list.any((e) => e.auto), isTrue);
    });

    test('保留份数上限会裁剪最旧备份', () async {
      for (var i = 0; i < 3; i++) {
        await svc.backup(1, saves.path, keep: 2);
        await Future.delayed(const Duration(milliseconds: 1100));
      }
      expect(svc.list(1).length, lessThanOrEqualTo(2));
    });

    test('删除备份', () async {
      final name = await svc.backup(1, saves.path);
      svc.remove(1, name);
      expect(svc.list(1), isEmpty);
    });

    test('存档目录不存在时抛错而不是静默成功', () async {
      await expectLater(
          svc.backup(1, '${saves.path}/nope'), throwsA(isA<StateError>()));
    });
  });
}
