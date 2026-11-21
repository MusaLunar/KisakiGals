/// 纯 Dart 单元测试（dart test 运行，不依赖 flutter_tester）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/core/utils.dart';
import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/game_repository.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/scraping/rate_limiter.dart';
import 'package:kisakigals/scraping/scraped_game.dart';
import 'package:kisakigals/services/game_explore_service.dart';
import 'package:kisakigals/services/kungal_oauth.dart';
import 'package:kisakigals/services/playtime_tracker.dart';
import 'package:kisakigals/services/plugin_system.dart';
import 'package:kisakigals/services/update_checker.dart';

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
      expect(bestMatchScore('atri', 'ATRI -My Dear Moments-'), 55);
      expect(bestMatchScore('dear', 'ATRI -My Dear Moments-'), 55);
      expect(bestMatchScore('xyz', 'ATRI'), 0);
      expect(bestMatchScore('千恋万花', '千恋＊万花'), 95);
      // 符号归一化：×视作分隔，PURE×CONNECT 归一为 pure connect
      expect(bestMatchScore('pure connect', 'PURE×CONNECT'), 100);
      expect(bestMatchScore('pure x connect', 'PURE×CONNECT'), 25);
      expect(bestMatchScore('pure connect', 'Pure×Connect 特装版'), 55);
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

      // 符号穿透与繁简折叠搜索：「千恋万花」能匹配库内的「千恋＊万花」与「千戀＊萬花」
      await repo.insertGame(Game(name: 'Senren Banka', nameCn: '千恋＊万花'));
      expect((await repo.listGames(query: '千恋万花')).map((g) => g.nameCn),
          ['千恋＊万花']);
    });

    test('recentPlayedGames 返回最近游玩的 2 部游戏', () async {
      final g1 = await repo.insertGame(Game(name: 'G1', nameCn: '游戏一'));
      final g2 = await repo.insertGame(Game(name: 'G2', nameCn: '游戏二'));
      final g3 = await repo.insertGame(Game(name: 'G3', nameCn: '游戏三'));
      final now = DateTime.now();
      await repo.addSession(GameSession(
        gameId: g1,
        start: now.subtract(const Duration(hours: 3)),
        end: now.subtract(const Duration(hours: 2)),
        seconds: 600,
      ));
      await repo.addSession(GameSession(
        gameId: g3,
        start: now.subtract(const Duration(hours: 1)),
        end: now.subtract(const Duration(minutes: 30)),
        seconds: 1200,
      ));
      await repo.addSession(GameSession(
        gameId: g2,
        start: now.subtract(const Duration(minutes: 20)),
        end: now,
        seconds: 900,
      ));

      final recent = await repo.recentPlayedGames(limit: 2);
      expect(recent.length, 2);
      expect(recent[0].id, g2);
      expect(recent[1].id, g3);
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

    test('recentActivity JOIN 查询无 N+1 且顺序正确', () async {
      final id = await repo.insertGame(
          Game(name: 'Senren Banka', nameCn: '千恋＊万花', userRating: 8.5));
      final now = DateTime.now();
      await repo.addSession(GameSession(
          gameId: id, start: now, end: now, seconds: 120));
      final acts = await repo.recentActivity(limit: 10);
      expect(acts, isNotEmpty);
      expect(acts.every((a) => a.gameName == '千恋＊万花'), isTrue);
    });
  });

  group('GitHub 更新检测与 KunGal OAuth PKCE', () {
    test('AppInfo.version 为 1.1.0 且版本号比较正确', () {
      expect(AppInfo.version, '1.1.0');
      expect(GithubUpdateChecker.compareVersions('v1.1.0', '1.1.0'), 0);
      expect(GithubUpdateChecker.compareVersions('1.2.0', '1.1.0'), 1);
      expect(GithubUpdateChecker.compareVersions('1.0.1', '1.1.0'), -1);
      expect(GithubUpdateChecker.compareVersions('1.1.0', '1.1.0-beta.1'), 1);
    });

    test('KunOAuthService PKCE S256 生成符合 RFC 7636', () {
      final pkce = KunOAuthService.generatePkcePair();
      expect(pkce.verifier.length, greaterThanOrEqualTo(43));
      expect(pkce.challenge.length, 43);
      expect(pkce.verifier.contains('='), isFalse);
      expect(pkce.challenge.contains('='), isFalse);
    });
  });

  group('NextMoe 与游戏探索百科多语种解析', () {
    test('正确解析 NextMoe Map 字典中的本地化语言', () {
      final map = {
        'en': {'value': 'Mimi Wuhui', 'is_machine': false},
        'ja': {'value': '秘密舞会', 'is_machine': false},
        'zh-Hans': {'value': '秘密舞会', 'is_machine': false},
      };
      expect(GameExploreService.extractLocalizedText(map), '秘密舞会');
      expect(
        GameExploreService.extractLocalizedText(
          map,
          langPriority: ['en', 'zh-Hans'],
        ),
        'Mimi Wuhui',
      );
    });

    test('正确防御并提取 Stringified Map 文本（解决截图报错现象）', () {
      const rawStringified =
          '{en: {value: Mimi Wuhui, is_machine: false}, ja: {value: 秘密舞会, is_machine: false}, zh-Hans: {value: 秘密舞会, is_machine: false}}';
      expect(
        GameExploreService.extractLocalizedText(rawStringified),
        '秘密舞会',
      );
    });

    test('提取所有多语种别名', () {
      final map = {
        'en': {'value': 'Mimi Wuhui', 'is_machine': false},
        'ja': {'value': '秘密舞会', 'is_machine': false},
        'zh-Hans': {'value': '秘密舞会', 'is_machine': false},
      };
      final aliases = GameExploreService.extractAllLocalizedTexts(map);
      expect(aliases, contains('Mimi Wuhui'));
      expect(aliases, contains('秘密舞会'));
    });
  });

  group('插件系统：规范校验、ZIP 安装与插件市场', () {
    late Database db;
    late SettingsStore settings;
    late Directory tempRoot;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(':memory:');
      for (final ddl in kCreateTables) {
        await db.execute(ddl);
      }
      settings = SettingsStore(db);
      tempRoot = Directory.systemTemp.createTempSync('kisaki_plugin_test_');
    });

    tearDown(() async {
      await db.close();
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('Manifest v1 规范校验规则与权限白名单', () {
      final valid = PluginManifestValidator.validate({
        'schemaVersion': 1,
        'id': 'sample-hook-plugin',
        'name': '示例钩子插件',
        'version': '1.1.0',
        'author': 'Tester',
        'minAppVersion': '1.0.0',
        'permissions': ['notifications', 'session.listen'],
      });
      expect(valid.error, isNull);
      expect(valid.manifest?.id, 'sample-hook-plugin');

      expect(
        PluginManifestValidator.validate({
          'id': 'Invalid_ID!',
          'name': 'Bad',
          'version': '1.0.0',
        }).error,
        isNotNull,
      );
      expect(
        PluginManifestValidator.validate({
          'id': 'bad-ver',
          'name': 'BadVer',
          'version': 'v1',
        }).error,
        isNotNull,
      );
      expect(
        PluginManifestValidator.validate({
          'id': 'future-plugin',
          'name': 'Future',
          'version': '1.0.0',
          'minAppVersion': '99.0.0',
        }).error,
        isNotNull,
      );
      expect(
        PluginManifestValidator.validate({
          'id': 'evil-perm',
          'name': 'Evil',
          'version': '1.0.0',
          'permissions': ['root.shell'],
        }).error,
        isNotNull,
      );
    });

    test('默认无内置插件，支持 .zip 导入安装、防 Zip Slip、配置持久化、通知钩子与卸载', () async {
      final pluginsDir = p.join(tempRoot.path, 'plugins');
      final sessionCtrl = StreamController<PlaySessionEnd>.broadcast();
      final notices = <String>[];
      final ctx = PluginContext(
        settings,
        tempRoot.path,
        sessionCtrl.stream,
        onNotify: (msg, {bool error = false}) => notices.add(msg),
      );

      final manager = PluginManager(settings, pluginsDir);
      await manager.loadInstalled(ctx);
      expect(manager.plugins, isEmpty);

      final manifestMap = {
        'schemaVersion': 1,
        'id': 'sample-hook-plugin',
        'name': '示例钩子插件',
        'version': '1.1.0',
        'author': 'Community',
        'description': '示例通知钩子',
        'minAppVersion': '1.0.0',
        'entry': 'main.js',
        'permissions': ['notifications', 'session.listen', 'settings.storage'],
        'settings': [
          {'key': 'minutes', 'label': '阈值', 'type': 'int', 'default': 60},
        ],
        'hooks': [
          {
            'event': 'onSessionEnd',
            'action': 'notify',
            'message': '已游玩 {minutes} 分钟，注意休息',
          },
        ],
      };

      final zipBytes = PluginManager.buildPluginZipBytes(
        manifest: manifestMap,
        mainJs: 'module.exports = { id: "sample-hook-plugin" };',
        readme: '# Sample Hook Plugin\n',
      );
      final zipFile = File(p.join(tempRoot.path, 'sample-hook-plugin.zip'));
      await zipFile.writeAsBytes(zipBytes);

      // SHA-256 不匹配被拦截
      final badHashRes = await manager.installFromZip(
        zipFile.path,
        ctx: ctx,
        expectedSha256: '0000',
      );
      expect(badHashRes.ok, isFalse);

      // 合法 .zip 安装成功
      final actualHash = sha256.convert(zipBytes).toString();
      final res = await manager.installFromZip(
        zipFile.path,
        ctx: ctx,
        expectedSha256: actualHash,
      );
      expect(res.ok, isTrue);
      expect(res.plugin?.enabled, isTrue);
      expect(
        File(p.join(pluginsDir, 'sample-hook-plugin', 'manifest.json'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(pluginsDir, 'sample-hook-plugin', 'main.js')).existsSync(),
        isTrue,
      );

      // 修改配置并验证重启重加载恢复 + 钩子通知触发
      await manager.setConfig('sample-hook-plugin', 'minutes', 30);
      await res.plugin!.onDispose();

      final reloaded = PluginManager(settings, pluginsDir);
      await reloaded.loadInstalled(ctx);
      expect(reloaded.plugins.length, 1);
      expect(reloaded.byId('sample-hook-plugin')?.config['minutes'], 30);

      sessionCtrl.add(
        const PlaySessionEnd(session: null, elapsedSeconds: 35 * 60, gameId: 7),
      );
      await Future<void>.delayed(Duration.zero);
      expect(notices, contains('已游玩 35 分钟，注意休息'));

      // 防 Zip Slip 校验
      final slipArchive = Archive()
        ..addFile(ArchiveFile('../escape.txt', 3, utf8.encode('bad')));
      final slipRes = await reloaded.installFromZipBytes(
        ZipEncoder().encode(slipArchive),
        ctx: ctx,
      );
      expect(slipRes.ok, isFalse);
      expect(slipRes.message, contains('不安全路径'));

      // 卸载清理目录
      expect(await reloaded.uninstall('sample-hook-plugin'), isTrue);
      expect(reloaded.plugins, isEmpty);
      expect(
        Directory(p.join(pluginsDir, 'sample-hook-plugin')).existsSync(),
        isFalse,
      );
      await sessionCtrl.close();
    });

    test('插件市场镜像加速 URL 解析与 .zip / .js 远程索引安装', () async {
      const rawUrl =
          'https://raw.githubusercontent.com/MusaLunar/KisakiGals-Plugins/main/plugins/demo/main.js';
      const relUrl =
          'https://github.com/MusaLunar/KisakiGals-Plugins/releases/download/v1.0.0/demo.zip';

      expect(
        PluginMarketplaceService.resolveCandidateUrls(
          rawUrl,
          PluginMirrorMode.jsdelivr,
        ).first,
        'https://cdn.jsdelivr.net/gh/MusaLunar/KisakiGals-Plugins@main/plugins/demo/main.js',
      );
      expect(
        PluginMarketplaceService.resolveCandidateUrls(
          relUrl,
          PluginMirrorMode.ghfast,
        ).first,
        'https://ghfast.top/$relUrl',
      );
      expect(
        PluginMarketplaceService.resolveCandidateUrls(
          relUrl,
          PluginMirrorMode.ghproxy,
        ).first,
        'https://gh-proxy.com/$relUrl',
      );

      final zipBytes = PluginManager.buildPluginZipBytes(
        manifest: {
          'schemaVersion': 1,
          'id': 'zip-market-demo',
          'name': '市场压缩包示例',
          'version': '1.0.0',
          'author': 'Market',
          'description': 'Zip demo',
          'packageType': 'zip',
          'entry': 'main.js',
          'permissions': ['notifications'],
        },
        mainJs: '// zip entry\n',
      );
      final zipSha = sha256.convert(zipBytes).toString();
      final jsBytes = utf8.encode('// js plugin\n');
      final jsSha = sha256.convert(jsBytes).toString();

      final mockIndexJson = jsonEncode({
        'schemaVersion': 1,
        'generatedAt': '2026-11-21T00:00:00Z',
        'plugins': [
          {
            'schemaVersion': 1,
            'id': 'zip-market-demo',
            'name': '市场压缩包示例',
            'version': '1.0.0',
            'author': 'Market',
            'description': 'Zip demo',
            'packageType': 'zip',
            'entry': 'main.js',
            'permissions': ['notifications'],
            'downloadUrl': 'https://github.com/example/repo/releases/download/v1.0.0/zip-market-demo.zip',
            'sha256': zipSha,
            'verified': true,
          },
          {
            'schemaVersion': 1,
            'id': 'js-market-demo',
            'name': '市场脚本示例',
            'version': '1.2.0',
            'author': 'Market',
            'description': 'JS demo',
            'packageType': 'js',
            'entry': 'main.js',
            'permissions': ['session.listen'],
            'downloadUrl': 'https://raw.githubusercontent.com/example/repo/main/js-market-demo/main.js',
            'sha256': jsSha,
            'verified': true,
          },
        ],
      });

      final downloadedUrls = <String>[];
      final market = PluginMarketplaceService(
        downloader: (url) async {
          downloadedUrls.add(url);
          if (url.endsWith('index.json')) return utf8.encode(mockIndexJson);
          if (url.endsWith('.zip')) return zipBytes;
          if (url.endsWith('.js')) return jsBytes;
          throw StateError('404: $url');
        },
      );

      final indexRes = await market.fetchIndex(mirror: PluginMirrorMode.ghfast);
      expect(indexRes.ok, isTrue);
      expect(indexRes.entries.length, 2);
      expect(downloadedUrls.first, startsWith('https://ghfast.top/'));

      final pluginsDir = p.join(tempRoot.path, 'market_plugins');
      final manager = PluginManager(settings, pluginsDir);

      final zipInstall = await market.installEntry(
        indexRes.entries[0],
        manager: manager,
        mirror: PluginMirrorMode.ghfast,
      );
      expect(zipInstall.ok, isTrue);
      expect(zipInstall.plugin?.installSource, 'marketplace');
      expect(zipInstall.plugin?.hasEntryFile, isTrue);

      final jsInstall = await market.installEntry(
        indexRes.entries[1],
        manager: manager,
        mirror: PluginMirrorMode.jsdelivr,
      );
      expect(jsInstall.ok, isTrue);
      expect(jsInstall.plugin?.manifest.packageType, 'js');
      expect(
        File(p.join(pluginsDir, 'js-market-demo', 'main.js')).existsSync(),
        isTrue,
      );
      expect(
        downloadedUrls.last,
        startsWith('https://cdn.jsdelivr.net/gh/example/repo@main/'),
      );
    });

    test('官方精选目录仅保留 Locale Emulator 插件，支持启动解析与旧版路径迁移', () async {
      final ids = kCuratedMarketplaceEntries.map((e) => e.id).toList();
      expect(ids, [kLocaleEmulatorPluginId]);
      for (final removed in const [
        'idle-reminder',
        'playtime-milestone',
        'session-logger',
        'save-health-check',
      ]) {
        expect(ids, isNot(contains(removed)));
      }
      expect(
        kCuratedMarketplaceEntries.single.manifest.homepage,
        'https://github.com/xupefei/Locale-Emulator',
      );

      final fakeLeExe = File(p.join(tempRoot.path, 'LEProc.exe'))
        ..writeAsStringSync('stub');
      await settings.setString(SettingsStore.kLePath, fakeLeExe.path);

      final pluginsDir = p.join(tempRoot.path, 'le_plugins');
      final manager = PluginManager(settings, pluginsDir);

      // 未安装 LE 插件时：游戏未开启转区不受影响；开启转区则提示并回退普通启动
      final offRes = manager.resolveLaunchForGame(gameUseLocaleEmulator: false);
      expect(offRes.shouldUseLe, isFalse);
      expect(offRes.abortLaunch, isFalse);
      expect(offRes.notice, isNull);

      final missingRes =
          manager.resolveLaunchForGame(gameUseLocaleEmulator: true);
      expect(missingRes.shouldUseLe, isFalse);
      expect(missingRes.abortLaunch, isFalse);
      expect(missingRes.notice, contains('尚未安装或启用'));

      // 通过市场服务离线兜底安装 Locale Emulator 插件，并自动迁移旧版 kLePath
      final market = PluginMarketplaceService(
        downloader: (_) async => throw StateError('offline'),
      );
      final installRes = await market.installEntry(
        kCuratedMarketplaceEntries.single,
        manager: manager,
      );
      expect(installRes.ok, isTrue);
      expect(
        installRes.plugin?.config['le_path'],
        fakeLeExe.path,
      );

      final readyRes = manager.resolveLaunchForGame(gameUseLocaleEmulator: true);
      expect(readyRes.shouldUseLe, isTrue);
      expect(readyRes.lePath, fakeLeExe.path);
      expect(readyRes.abortLaunch, isFalse);
      expect(readyRes.notice, isNull);

      // 禁用 fallback_normal 且路径无效时，应中止启动
      await manager.setConfig(kLocaleEmulatorPluginId, 'fallback_normal', false);
      await manager.setConfig(
        kLocaleEmulatorPluginId,
        'le_path',
        p.join(tempRoot.path, 'MissingLE.exe'),
      );
      final abortRes = manager.resolveLaunchForGame(gameUseLocaleEmulator: true);
      expect(abortRes.shouldUseLe, isFalse);
      expect(abortRes.abortLaunch, isTrue);
      expect(abortRes.notice, contains('已中止启动'));
    });

    test('SettingsStore.kPerformanceMode 默认关闭并支持持久化读写', () async {
      expect(
        await settings.getBool(SettingsStore.kPerformanceMode, def: false),
        isFalse,
      );
      await settings.setBool(SettingsStore.kPerformanceMode, true);
      expect(
        await settings.getBool(SettingsStore.kPerformanceMode, def: false),
        isTrue,
      );
      await settings.setBool(SettingsStore.kPerformanceMode, false);
      expect(
        await settings.getBool(SettingsStore.kPerformanceMode, def: false),
        isFalse,
      );
    });

    test('仓库内置 plugins/index.json 与 locale-emulator-1.0.0.zip 制品哈希及安装校验通过',
        () async {
      final indexFile = File('plugins/index.json');
      final zipFile = File('plugins/dist/locale-emulator-1.0.0.zip');
      expect(indexFile.existsSync(), isTrue);
      expect(zipFile.existsSync(), isTrue);

      final parsed = PluginMarketplaceService.parseIndexJson(
        indexFile.readAsStringSync(),
      );
      expect(parsed.ok, isTrue);
      final entry = parsed.entries.singleWhere(
        (e) => e.id == kLocaleEmulatorPluginId,
      );
      expect(
        entry.downloadUrl,
        'https://raw.githubusercontent.com/MusaLunar/KisakiGals/main/plugins/dist/locale-emulator-1.0.0.zip',
      );
      expect(
        PluginMarketplaceService.defaultRegistryUrl,
        'https://raw.githubusercontent.com/MusaLunar/KisakiGals/main/plugins/index.json',
      );

      final zipBytes = zipFile.readAsBytesSync();
      final actualSha = sha256.convert(zipBytes).toString();
      expect(entry.sha256, actualSha);
      expect(entry.sizeBytes, zipBytes.length);

      final pluginsDir = p.join(tempRoot.path, 'dist_plugins');
      final manager = PluginManager(settings, pluginsDir);
      final res = await manager.installFromZipBytes(
        zipBytes,
        expectedSha256: entry.sha256,
        installSource: 'marketplace',
        downloadUrl: entry.downloadUrl,
      );
      expect(res.ok, isTrue);
      expect(res.plugin?.id, kLocaleEmulatorPluginId);
      expect(res.plugin?.manifest.homepage, kLocaleEmulatorProjectUrl);
    });
  });
}
