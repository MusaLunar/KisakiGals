import 'dart:ffi';
import 'dart:io';

import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/game_repository.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

/// 全新数据库上的回归测试。
///
/// 背景：打包版在**全新库**上报过
/// `no such column: " ... should this be a string literal in single-quotes?`
/// —— SQL 里用双引号当字符串字面量，遇到关闭 DQS 的 SQLite 构建就会失败。
/// 随包发布的 `sqlite3.dll` 正是 **SQLite 3.52.0 + DQS=0**，而开发环境常见的
/// SQLite 多为 DQS=1，所以这个缺陷在开发机上不会暴露。
/// 因此这里**强制加载随包 DLL** 再跑全部仓储查询，让同类问题能被复现与拦住。
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
  late GameRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('kisaki_fresh_');
    db = await openAppDb('${dir.path}/kisakigals.db');
    repo = GameRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<Game> seedGame({String name = '千恋＊万花', String nameCn = '千恋万花'}) async {
    final g = Game(
      name: name,
      nameCn: nameCn,
      developer: 'ゆずソフト',
      directory: 'C:\\Games\\Senren',
      exePath: 'C:\\Games\\Senren\\senren.exe',
      totalSeconds: 3600,
    );
    final id = await repo.insertGame(g);
    g.id = id;
    final now = DateTime.now();
    await repo.addSession(GameSession(
      gameId: id,
      start: now.subtract(const Duration(minutes: 30)),
      end: now,
      seconds: 1800,
    ));
    await repo.setTags(id, [
      TagItem(name: '纯爱', weight: 5),
      TagItem(name: '和风', weight: 3),
    ]);
    await repo.upsertSource(
        id,
        SourceRecord(
      gameId: id,
      source: 'vndb',
      sourceId: 'v123',
      rating: 8.2,
      voteCount: 100,
    ));
    return g;
  }

  test('全新库的 schema 版本为最新', () async {
    final v = await db.getVersion();
    expect(v, kSchemaVersion);
  });

  test('主页聚合查询在全新库（无数据）上可用', () async {
    for (final p in StatsPeriod.values) {
      final s = await repo.stats(period: p);
      expect(s.totalSeconds, 0);
      expect(s.topGames, isEmpty);
    }
    expect(await repo.recentActivity(limit: 20), isEmpty);
    expect(await repo.gameCount(), 0);
    expect(await repo.tagCloud(period: StatsPeriod.all), isEmpty);
  });

  test('主页聚合查询在有数据时可用（topGames 使用 NULLIF 判断中文名）', () async {
    await seedGame();
    for (final p in StatsPeriod.values) {
      final s = await repo.stats(period: p);
      expect(s.topGames, isNotEmpty, reason: 'period=$p 应能统计到游玩记录');
      expect(s.topGames.first.name, '千恋万花', reason: '应优先取中文名');
    }
  });

  test('中文名为空时 topGames 回退到原始名称', () async {
    await seedGame(name: 'ATRI -My Dear Moments-', nameCn: '');
    final s = await repo.stats(period: StatsPeriod.all);
    expect(s.topGames.first.name, 'ATRI -My Dear Moments-');
  });

  test('全部排序方式的列表查询都可用', () async {
    await seedGame();
    for (final sort in GameSort.values) {
      final list = await repo.listGames(sort: sort);
      expect(list, isNotEmpty, reason: 'sort=$sort 应返回结果');
    }
  });

  test('筛选查询（关键词/状态/标签/开发商/收藏）都可用', () async {
    final g = await seedGame();
    expect(await repo.listGames(query: '千恋万花'), isNotEmpty);
    expect(await repo.listGames(query: '千恋'), isNotEmpty);
    expect(await repo.listGames(query: 'ゆずソフト'), isNotEmpty);
    expect(await repo.listGames(query: '纯爱'), isNotEmpty, reason: '标签命中');
    // 状态筛选：任意状态查询都应正常返回（不抛异常即可）
    for (final s in PlayStatus.values) {
      await repo.listGames(status: s);
    }
    expect(await repo.listGames(tag: '纯爱'), isNotEmpty);
    expect(await repo.listGames(developer: 'ゆずソフト'), isNotEmpty);
    await repo.listGames(favorite: true);
    await repo.listGames(favorite: false);
    expect(await repo.getGame(g.id!), isNotNull);
  });

  test('来源、标签、开发商、平台评分等查询都可用', () async {
    final g = await seedGame();
    await repo.insertGame(Game(name: '另一部', developer: 'Key'));
    expect(await repo.sourcesOf(g.id!), hasLength(1));
    expect(await repo.tagsOf(g.id!), hasLength(2));
    expect(await repo.allTags(), isNotEmpty);
    expect(await repo.developers(), contains('ゆずソフト'));
    expect(await repo.usedSources(), contains('vndb'));
    expect(await repo.bestPlatformRatings(), isNotEmpty);
    expect(await repo.findGameByTitle('千恋万花'), isNotNull);
    expect(await repo.allGames(), hasLength(2));
  });

  test('设置存储可读写（安装后首次启动路径）', () async {
    final s = SettingsStore(db);
    expect(await s.getString('any.key', 'def'), 'def');
    await s.setString('any.key', '值');
    expect(await s.getString('any.key', ''), '值');
  });
}
