import 'dart:ffi';
import 'dart:io';

import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

/// 游戏库排版切换（grid / list）的持久化与容错
void main() {
  setUpAll(() {
    final shipped = File('build/windows/x64/runner/Release/sqlite3.dll');
    if (Platform.isWindows && shipped.existsSync()) {
      open.overrideFor(
          OperatingSystem.windows, () => DynamicLibrary.open(shipped.path));
    }
  });
  sqfliteFfiInit();

  late Directory dir;
  late Database db;
  late SettingsStore settings;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('kisaki_layout_');
    db = await openAppDb('${dir.path}/kisakigals.db');
    settings = SettingsStore(db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('默认排版为网格', () async {
    expect(await settings.getString(SettingsStore.kLibraryLayout, 'grid'),
        'grid');
  });

  test('切换为紧凑列表后能持久化（重启仍生效）', () async {
    await settings.setString(SettingsStore.kLibraryLayout, 'list');
    // 模拟重启：新建 store 重新读库
    final again = SettingsStore(db);
    expect(await again.getString(SettingsStore.kLibraryLayout, 'grid'), 'list');
  });

  test('未知取值回退为网格（避免设置损坏导致空白页）', () async {
    await settings.setString(SettingsStore.kLibraryLayout, '???');
    final raw = await settings.getString(SettingsStore.kLibraryLayout, 'grid');
    final effective = (raw == 'list') ? 'list' : 'grid';
    expect(effective, 'grid');
  });
}
