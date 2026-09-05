/// 元数据调度器：并发查源、统一打分、磁盘缓存、封面下载、代理支持。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../data/metadata_cache.dart';
import 'rate_limiter.dart';
import 'scraped_game.dart';
import 'source_adapter.dart';
import 'sources/bangumi.dart';
import 'sources/cngal.dart';
import 'sources/dlsite.dart';
import 'sources/hikarinagi.dart';
import 'sources/kun.dart';
import 'sources/steam.dart';
import 'sources/touchgal.dart';
import 'sources/ymgal.dart';
import 'sources/vndb.dart';

/// 三级代理：应用设置 > Windows 系统代理（注册表）> 环境变量。
Future<String?> detectProxy({String? appProxy}) async {
  if (appProxy != null && appProxy.trim().isNotEmpty) return appProxy.trim();
  try {
    final result = Process.runSync('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyServer',
    ]);
    if (result.exitCode == 0) {
      final m = RegExp(r'ProxyServer\s+REG_SZ\s+(\S+)').firstMatch(result.stdout.toString());
      if (m != null) {
        var server = m.group(1)!;
        if (!server.contains('://')) server = 'http://$server';
        return server;
      }
    }
  } catch (_) {}
  return Platform.environment['HTTPS_PROXY'] ??
      Platform.environment['HTTP_PROXY'];
}

class MetadataFetcher {
  final Map<String, SourceAdapter> _adapters = {};
  final MetadataCache cache;
  final String coversDir;
  Dio? _probeDio;
  String? _proxy;

  MetadataFetcher({required this.cache, required this.coversDir});

  /// 初始化：构建 Dio（带代理）并注册适配器。
  /// [tokens]: vndb/bgm 用户 token；[enabledSources]: 启用源 id 列表。
  Future<void> init({
    String? appProxy,
    Map<String, String> tokens = const {},
  }) async {
    _proxy = await detectProxy(appProxy: appProxy);
    Dio buildDio() {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'User-Agent': 'MusaLunar/KisakiGals/0.1.0 (Metadata Scraper)'},
      ));
      if (_proxy != null) {
        dio.httpClientAdapter = IOHttpClientAdapter()
          ..createHttpClient = () {
            final client = HttpClient();
            client.findProxy = (uri) => 'PROXY ${_proxy!.replaceFirst(RegExp(r'^https?://'), '')}';
            client.badCertificateCallback = (_, __, ___) => true;
            return client;
          };
      }
      return dio;
    }

    final limiters = RateLimiters(defaults: {
      KisakiSources.vndb: RateLimiter(minInterval: const Duration(milliseconds: 200), maxPerWindow: 200),
      KisakiSources.bangumi: RateLimiter(minInterval: const Duration(milliseconds: 1000), maxPerWindow: 30),
      KisakiSources.steam: RateLimiter(minInterval: const Duration(milliseconds: 500), maxPerWindow: 100),
      KisakiSources.ymgal: RateLimiter(minInterval: const Duration(milliseconds: 500), maxPerWindow: 60),
      KisakiSources.hikarinagi: RateLimiter(minInterval: const Duration(milliseconds: 300), maxPerWindow: 100),
      KisakiSources.cngal: RateLimiter(minInterval: const Duration(milliseconds: 800), maxPerWindow: 60),
      KisakiSources.kun: RateLimiter(minInterval: const Duration(milliseconds: 400), maxPerWindow: 60),
      KisakiSources.touchgal: RateLimiter(minInterval: const Duration(milliseconds: 500), maxPerWindow: 60),
      KisakiSources.dlsite: RateLimiter(minInterval: const Duration(milliseconds: 800), maxPerWindow: 60),
    });

    _adapters[KisakiSources.vndb] =
        VndbAdapter(buildDio(), limiters, token: tokens[KisakiSources.vndb]);
    _adapters[KisakiSources.bangumi] =
        BangumiAdapter(buildDio(), limiters, token: tokens[KisakiSources.bangumi]);
    _adapters[KisakiSources.ymgal] = YmgalAdapter(buildDio(), limiters);
    _adapters[KisakiSources.hikarinagi] = HikarinagiAdapter(buildDio(), limiters);
    _adapters[KisakiSources.steam] = SteamAdapter(buildDio(), limiters);
    _adapters[KisakiSources.cngal] = CngalAdapter(buildDio(), limiters);
    _adapters[KisakiSources.kun] = KunAdapter(buildDio(), limiters);
    _adapters[KisakiSources.touchgal] = TouchGalAdapter(buildDio(), limiters);
    _adapters[KisakiSources.dlsite] = DlsiteAdapter(buildDio(), limiters);
  }

  String? get proxy => _proxy;

  SourceAdapter? adapter(String id) => _adapters[id];

  /// 并发搜索所有启用源（每源失败静默）。
  Future<Map<String, List<ScrapedGame>>> searchAll(String kw,
      {List<String>? only}) async {
    final ids = (only ?? KisakiSources.defaultEnabled)
        .where((id) => _adapters.containsKey(id))
        .toList();
    final results = <String, List<ScrapedGame>>{};
    await Future.wait(ids.map((id) async {
      try {
        results[id] = await _adapters[id]!.search(kw);
      } catch (_) {
        results[id] = const [];
      }
    }));
    return results;
  }

  /// 跨源搜索并按匹配度合并为候选列表（按源间评分优先）。
  Future<List<ScrapeHit>> searchRanked(String kw, {List<String>? only}) async {
    final bySource = await searchAll(kw, only: only);
    final hits = <ScrapeHit>[];
    for (final games in bySource.values) {
      for (final g in games) {
        var score = 0;
        for (final candidate in [g.displayName, g.name, g.nameCn]) {
          score = bestMatchScore(kw, candidate);
          if (score > 0) break;
        }
        if (score > 0) hits.add(ScrapeHit(g, score));
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  /// 取最佳单条结果（自动刮削用）。
  Future<ScrapedGame?> fetchBest(String kw, {List<String>? only}) async {
    final cacheKey = 'best:$kw';
    final cached = cache.get(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return ScrapedGame.fromJson(cached.first);
    }
    final hits = await searchRanked(kw, only: only);
    if (hits.isEmpty) return null;
    // 打分最高且 >0；同分时取有封面/有评分者
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final aScore = (a.game.coverUrl.isNotEmpty ? 2 : 0) +
          (a.game.rating > 0 ? 1 : 0);
      final bScore = (b.game.coverUrl.isNotEmpty ? 2 : 0) +
          (b.game.rating > 0 ? 1 : 0);
      return bScore.compareTo(aScore);
    });
    var best = hits.first.game;
    if (hits.first.score < 20) return null; // 相关度过低宁缺毋滥
    if (best.summary.isEmpty || best.coverUrl.isEmpty) {
      final full = await adapter(best.source)?.fetchById(best.sourceId);
      if (full != null) best = _mergeFull(best, full);
    }
    cache.put(cacheKey, [best.toJson()]);
    return best;
  }

  ScrapedGame _mergeFull(ScrapedGame summary, ScrapedGame full) => ScrapedGame(
        source: full.source,
        sourceId: full.sourceId,
        name: full.name.isNotEmpty ? full.name : summary.name,
        nameCn: full.nameCn.isNotEmpty ? full.nameCn : summary.nameCn,
        aliases: full.aliases.isNotEmpty ? full.aliases : summary.aliases,
        coverUrl: full.coverUrl.isNotEmpty ? full.coverUrl : summary.coverUrl,
        developer: full.developer.isNotEmpty ? full.developer : summary.developer,
        releaseDate: full.releaseDate.isNotEmpty ? full.releaseDate : summary.releaseDate,
        summary: full.summary.isNotEmpty ? full.summary : summary.summary,
        rating: full.rating,
        voteCount: full.voteCount,
        tags: full.tags.isNotEmpty ? full.tags : summary.tags,
        screenshots: full.screenshots,
        nsfw: full.nsfw || summary.nsfw,
      );

  /// 下载封面到本地，返回本地路径；失败返回空串。
  Future<String> downloadCover(ScrapedGame g, int gameId) async {
    if (g.coverUrl.isEmpty) return '';
    try {
      final dio = _probeDio ??= Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': 'MusaLunar/KisakiGals/0.1.0'},
      ));
      final ext = RegExp(r'\.(jpe?g|png|webp)', caseSensitive: false)
          .firstMatch(g.coverUrl)
          ?.group(0) ??
          '.jpg';
      final path = '$coversDir/game_$gameId$ext';
      final response = await dio.download(g.coverUrl, path);
      if (response.statusCode == 200 && File(path).lengthSync() > 1000) {
        return path;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 连通性测试（设置页「测试连接」）。
  Future<bool> testSource(String id) async {
    final a = _adapters[id];
    if (a == null) return false;
    try {
      final r = await a.search('atri');
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    for (final a in _adapters.values) {
      a.dio.close();
    }
    _adapters.clear();
  }
}

