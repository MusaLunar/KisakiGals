/// 纯 Dart 单元测试（dart test 运行，不依赖 flutter_tester）。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/core/utils.dart';
import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/game_repository.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/scraping/rate_limiter.dart';
import 'package:kisakigals/scraping/scraped_game.dart';

void main() {
  // Windows 测试环境：使用 System32 的 winsqlite3.dll
  open.overrideFor(OperatingSystem.windows, () {
    final testDll = File('test/dll/sqlite3.dll');
    return DynamicLibrary.open(testDll.existsSync()
        ? 'test/dll/sqlite3.dll'
        : 'sqlite3.dll');
  });

  sqfliteFfiInit();

  group('utils', () {
    test('normalizeRating 归一化', () {
      expect(normalizeRating(76.5), closeTo(7.65, 0.001));
      expect(normalizeRating(8.2), 8.2);
      expect(normalizeRating(0), 0);
      expect(normalizeRating(120), 10);
    });

    test('bestMatchScore 打分', () {
      expect(bestMatchScore('atri', 'ATRI'), 100);
      expect(bestMatchScore('atri', 'ATRI -My Dear Moments-'), 40);
      expect(bestMatchScore('dear', 'ATRI -My Dear Moments-'), 20);
      expect(bestMatchScore('xyz', 'ATRI'), 0);
      expect(bestMatchScore('千恋万花', '千恋＊万花'), greaterThan(0));
    });

    test('cleanExeName 清洗', () {
      expect(cleanExeName('ATRI -My Dear Moments-.exe'), contains('ATRI'));
      expect(cleanExeName('game_v1.0_final.exe'), isNot(contains('final')));
    });

    test('fmtDuration', () {
      expect(fmtDuration(0), '尚无记录');
      expect(fmtDuration(600), '10 分钟');
      expect(fmtDuration(45000), '12.5 小时');
    });

    test('PlayStatus 往返', () {
      for (final s in PlayStatus.values) {
        expect(PlayStatus.fromValue(s.value), s);
      }
    });
  });

  group('rate_limiter', () {
    test('限流间隔生效', () async {
      final limiter = RateLimiter(minInterval: const Duration(milliseconds: 60));
      final sw = Stopwatch()..start();
      await limiter.acquire();
      await limiter.acquire();
      await limiter.acquire();
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(110));
    });

    test('退避时长指数增长', () {
      expect(RateLimiter.backoff(0).inSeconds, 1);
      expect(RateLimiter.backoff(3).inSeconds, 8);
      expect(RateLimiter.backoff(10).inSeconds, 30);
    });
  });

  group('ScrapedGame JSON 往返', () {
    test('toJson/fromJson', () {
      final g = ScrapedGame(
        source: 'vndb',
        sourceId: 'v19073',
        name: 'Senren Banka',
        nameCn: '千恋＊万花',
        coverUrl: 'https://example.com/c.jpg',
        rating: 7.6,
        voteCount: 100,
        tags: const [ScrapedTag('纯爱', weight: 2.0)],
      );
      final restored = ScrapedGame.fromJson(g.toJson());
      expect(restored.nameCn, '千恋＊万花');
      expect(restored.rating, 7.6);
      expect(restored.tags.first.name, '纯爱');
    });
  });

  group('game_repository（内存 SQLite）', () {
    late Database db;
    late GameRepository repo;

    setUp(() async {
      final factory = databaseFactoryFfi;
      db = await factory.openDatabase(':memory:');
      for (final ddl in kCreateTables) {
        await db.execute(ddl);
      }
      repo = GameRepository(db);
    });

    tearDown(() => db.close());

    test('插入与读取', () async {
      final g = Game(name: 'ATRI', nameCn: 'ATRI', developer: 'ANIPLEX');
      final id = await repo.insertGame(g);
      final loaded = await repo.getGame(id);
      expect(loaded, isNotNull);
      expect(loaded!.displayName, 'ATRI');
      expect(loaded.developer, 'ANIPLEX');
    });

    test('会话落库同步聚合统计', () async {
      final g = Game(name: 'game1');
      final id = await repo.insertGame(g);
      final now = DateTime.now();
      await repo.addSession(GameSession(
        gameId: id,
        start: now.subtract(const Duration(hours: 2)),
        end: now.subtract(const Duration(hours: 1)),
        seconds: 3600,
      ));
      await repo.addSession(GameSession(
        gameId: id,
        start: now.subtract(const Duration(minutes: 30)),
        end: now,
        seconds: 1800,
      ));
      final loaded = await repo.getGame(id);
      expect(loaded!.totalSeconds, 5400);
      expect(loaded.lastPlayedAt, isNotNull);

      final stats = await repo.stats(period: StatsPeriod.all);
      expect(stats.totalSeconds, 5400);
      expect(stats.sessionCount, 2);
      expect(stats.activeDays, 1);
      expect(stats.byHour.reduce((a, b) => a + b), 5400);
      expect(stats.topGames.first.name, 'game1');
    });

    test('筛选/搜索/排序', () async {
      final a = Game(name: 'Alpha', nameCn: '阿爾法', developer: 'Dev1')
        ..playStatus = PlayStatus.played
        ..userRating = 8;
      final b = Game(name: 'Beta', nameCn: '貝塔', developer: 'Dev2')
        ..playStatus = PlayStatus.wish;
      final ia = await repo.insertGame(a);
      await repo.insertGame(b);
      await repo.setTags(ia, [TagItem(name: '纯爱'), TagItem(name: '催泪')]);

      expect((await repo.listGames(query: '阿爾法')).length, 1); // 中文名匹配
      expect((await repo.listGames(query: 'Alpha')).length, 1);
      expect((await repo.listGames(query: 'Dev1')).length, 1);
      expect((await repo.listGames(status: PlayStatus.wish)).length, 1);
      expect((await repo.listGames(tag: '纯爱')).map((g) => g.name), ['Alpha']);
      expect(
          (await repo.listGames(sort: GameSort.userRatingDesc)).first.name,
          'Alpha');
      expect((await repo.listGames(favorite: true)).length, 0);
    });

    test('upsertSource 与 sourcesOf', () async {
      final id = await repo.insertGame(Game(name: 'g'));
      await repo.upsertSource(id, SourceRecord(gameId: id, source: 'vndb', sourceId: 'v1', rating: 7));
      await repo.upsertSource(id, SourceRecord(gameId: id, source: 'vndb', sourceId: 'v1', rating: 8));
      final sources = await repo.sourcesOf(id);
      expect(sources.length, 1);
      expect(sources.first.rating, 8);
    });

    test('词云聚合', () async {
      final id = await repo.insertGame(Game(name: 'g'));
      await repo.setTags(id, [TagItem(name: '纯爱', weight: 3), TagItem(name: '催泪')]);
      final now = DateTime.now();
      await repo.addSession(GameSession(
          gameId: id, start: now, end: now, seconds: 60));
      final cloud = await repo.tagCloud(period: StatsPeriod.all);
      expect(cloud.first.name, '纯爱');
    });
  });
}
