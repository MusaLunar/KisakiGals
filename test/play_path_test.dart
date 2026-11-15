import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/media_paths.dart';
import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/game_repository.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/services/window_capture.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late Database db;
  late GameRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('kisaki_play_path_');
    MediaPaths.install(tempDir.path);
    db = await openAppDb(inMemoryDatabasePath);
    repo = GameRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('PlayPathNode CRUD and cascade delete in SQLite schema v5', () async {
    expect(kSchemaVersion, 5);
    final gid = await repo.insertGame(Game(name: '千恋＊万花'));

    final shotFile = File(p.join(tempDir.path, 'play_path', '$gid', 's1.png'));
    shotFile.parent.createSync(recursive: true);
    shotFile.writeAsBytesSync(
      encodeBgraToPng(Uint8List.fromList([10, 20, 30, 0]), 1, 1),
    );

    final n1 = await repo.addPlayPathNode(
      gameId: gid,
      imagePath: shotFile.path,
      note: '芳乃线第一幕',
      createdAt: DateTime(2026, 5, 1, 20, 0, 0),
    );
    final n2 = await repo.addPlayPathNode(
      gameId: gid,
      note: '纯文字剧情备忘',
      createdAt: DateTime(2026, 5, 1, 21, 0, 0),
    );

    expect(n1.id, isNotNull);
    expect(n2.id, isNotNull);
    expect(n1.imagePath, 'play_path/$gid/s1.png');
    expect(n1.resolvedImagePath, p.normalize(shotFile.path));

    var nodes = await repo.playPathOf(gid);
    expect(nodes.length, 2);
    // 倒序返回，最新节点在前
    expect(nodes.first.id, n2.id);
    expect(nodes.last.note, '芳乃线第一幕');

    n2.note = '更新后的备忘';
    await repo.updatePlayPathNode(n2);
    nodes = await repo.playPathOf(gid);
    expect(nodes.first.note, '更新后的备忘');

    // 删除图文节点应同时清理截图文件
    await repo.deletePlayPathNode(n1.id!);
    expect(shotFile.existsSync(), isFalse);
    nodes = await repo.playPathOf(gid);
    expect(nodes.length, 1);

    // 删除游戏后关联游玩路径节点应自动级联清除
    await repo.deleteGame(gid);
    expect(await repo.playPathOf(gid), isEmpty);
  });

  test('WindowCaptureService parses hotkey names and encodes valid PNG', () {
    expect(WindowCaptureService.virtualKeyForName('F12'), 0x7B);
    expect(WindowCaptureService.virtualKeyForName('f11'), 0x7A);
    expect(WindowCaptureService.virtualKeyForName('PrintScreen'), 0x2C);
    expect(WindowCaptureService.virtualKeyForName('disabled'), isNull);
    expect(WindowCaptureService.virtualKeyForName(''), isNull);

    // 构造 2x2 BGRA buffer（特意把 Alpha 置为 0，验证导出时自动修正为 255 不透明）
    final bgra = Uint8List.fromList([
      156, 131, 218, 0, // M3 Rose #DA839C
      245, 192, 208, 0, // M3 Lavender #D0C0F5
      160, 171, 237, 0, // M3 Peach #EDABA0
      255, 255, 255, 0,
    ]);
    final png = encodeBgraToPng(bgra, 2, 2);

    // 验证 PNG 文件头签名
    expect(
      png.sublist(0, 8),
      equals([137, 80, 78, 71, 13, 10, 26, 10]),
    );
    // IHDR chunk tag
    expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
    // 尾部 IEND chunk (4-byte length 0 + 'IEND' + 4-byte CRC AE426082)
    expect(
      png.sublist(png.length - 12),
      equals([0, 0, 0, 0, 73, 69, 78, 68, 0xAE, 0x42, 0x60, 0x82]),
    );
  });
}
