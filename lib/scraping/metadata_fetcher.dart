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
        final candidates = [
          g.displayName,
          g.name,
          g.nameCn,
          ...g.aliases,
        ];
        for (final candidate in candidates) {
          score = bestMatchScore(kw, candidate);
          if (score > 0) break;
        }
        if (score > 0) hits.add(ScrapeHit(g, score));
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  /// 跨源搜索并按身份分组（同一游戏的各源条目归为一组，摘要级合并）。
  /// 选择列表直接展示组（一条=一个游戏，带多源徽章）。
  Future<List<ScrapeHitGroup>> searchGrouped(String kw,
      {List<String>? only}) async {
    final hits = await searchRanked(kw, only: only);
    final groups = <ScrapeHitGroup>[];
    for (final hit in hits) {
      ScrapeHitGroup? target;
      for (final g in groups) {
        // 与组内任一成员同身份即归入该组
        if (g.members.any((m) => _sameIdentity(m, hit.game))) {
          target = g;
          break;
        }
      }
      if (target == null) {
        groups.add(ScrapeHitGroup(hit.game, [hit.game], hit.score));
      } else {
        target.add(hit.game, hit.score);
      }
    }
    groups.sort((a, b) => b.bestScore.compareTo(a.bestScore));
    return groups;
  }

  bool _sameIdentity(ScrapedGame a, ScrapedGame b) {
    if (a.source == b.source && a.sourceId == b.sourceId) return true;
    final aKeys = _identityKeys(a);
    final bKeys = _identityKeys(b);
    return aKeys.intersection(bKeys).isNotEmpty;
  }

  /// 身份键：名称/别名的归一化形式 + 去空格压扁形式
  /// （「千恋 万花」与「千恋万花」视为同一身份）。
  Set<String> _identityKeys(ScrapedGame g) {
    final keys = <String>{
      normalizeForMatch(g.displayName),
      normalizeForMatch(g.name),
      ...g.aliases.map(normalizeForMatch),
    };
    final squashed = keys.map((k) => k.replaceAll(' ', '')).toSet();
    keys.addAll(squashed);
    keys.removeWhere((s) => s.isEmpty);
    return keys;
  }

  /// 组内合并：逐成员补全详情后融合为一条完整数据。
  /// 返回 [合并结果, 各源成员...]（供登记每源评分记录）。
  Future<List<ScrapedGame>> mergeGroup(ScrapeHitGroup group) async {
    final members = [...group.members];
    var merged = members.first;
    try {
      final full = await adapter(merged.source)?.fetchById(merged.sourceId);
      if (full != null) merged = _mergeFull(merged, full);
    } catch (_) {}
    for (final m in members.skip(1)) {
      try {
        final full = await adapter(m.source)?.fetchById(m.sourceId);
        merged = _mergeTwo(merged, full ?? m);
      } catch (_) {
        merged = _mergeTwo(merged, m);
      }
    }
    return [merged, ...members.skip(1)];
  }

  /// 以用户选中的条目为主体，合并其它源中同一游戏的数据。
  ///
  /// 同一性判断：归一化后的名称/别名词典相交（ReinaManager 式
  /// 多源整合——摘要、开发商、发售日、标签、截图取各源所长）。
  /// 返回 [合并后的条目, 各源原始条目...]，调用方可据后者登记
  /// 每个平台的评分记录（game_sources）。
  Future<List<ScrapedGame>> mergeAcrossSources(
    ScrapedGame picked, {
    String? kw,
    List<String>? only,
  }) async {
    var merged = picked;
    final matches = <ScrapedGame>[];
    // 尽量补全主体条目的详情（列表结果通常缺简介/截图）
    try {
      final full = await adapter(picked.source)?.fetchById(picked.sourceId);
      if (full != null) merged = _mergeFull(merged, full);
    } catch (_) {}

    final bySource = await searchAll(
        (kw != null && kw.trim().isNotEmpty) ? kw : merged.displayName,
        only: only);
    for (final entry in bySource.entries) {
      if (entry.key == picked.source) continue;
      ScrapedGame? match;
      for (final g in entry.value) {
        if (_sameIdentity(merged, g)) {
          match = g;
          break;
        }
      }
      if (match == null) continue;
      merged = _mergeTwo(merged, match);
      matches.add(match);
    }
    return [merged, ...matches];
  }

  /// 字段级合并：主体优先、空位补全；简介偏好含中文的一方；
  /// 别名/截图并集、标签按名称合并（保留较大权重）。
  ScrapedGame _mergeTwo(ScrapedGame a, ScrapedGame b) {
    String pick(String x, String y) => x.isNotEmpty ? x : y;
    var summary = a.summary.isNotEmpty ? a.summary : b.summary;
    if (summary.isNotEmpty && !_looksCjk(summary) && _looksCjk(b.summary)) {
      summary = b.summary;
    }
    final aliases = <String>{...a.aliases, ...b.aliases}.toList();
    final screenshots = <String>{...a.screenshots, ...b.screenshots}.toList();
    final tagByName = <String, ScrapedTag>{};
    for (final t in [...a.tags, ...b.tags]) {
      final key = normalizeForMatch(t.name);
      final old = tagByName[key];
      if (old == null || t.weight > old.weight) tagByName[key] = t;
    }
    final tags = tagByName.values.toList()
      ..sort((x, y) => y.weight.compareTo(x.weight));
    return ScrapedGame(
      source: a.source,
      sourceId: a.sourceId,
      name: pick(a.name, b.name),
      nameCn: pick(a.nameCn, b.nameCn),
      aliases: aliases,
      coverUrl: pick(a.coverUrl, b.coverUrl),
      developer: pick(a.developer, b.developer),
      releaseDate: pick(a.releaseDate, b.releaseDate),
      summary: summary,
      rating: a.rating > 0 ? a.rating : b.rating,
      voteCount: a.voteCount > 0 ? a.voteCount : b.voteCount,
      tags: tags.take(24).toList(),
      screenshots: screenshots,
      nsfw: a.nsfw || b.nsfw,
    );
  }

  static bool _looksCjk(String s) =>
      s.contains(RegExp(r'[\u3400-\u9FFF\u3040-\u30FF\uF900-\uFA6D]'));

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
  Future<String> downloadCover(ScrapedGame g, int gameId) =>
      downloadImage(g.coverUrl, 'game_$gameId');

  /// 下载任意图片到 covers 目录；[fileName] 不含扩展名。
  Future<String> downloadImage(String url, String fileName) async {
    if (url.isEmpty) return '';
    try {
      final dio = _probeDio ??= Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': 'MusaLunar/KisakiGals/0.2.0'},
      ));
      final ext = RegExp(r'\.(jpe?g|png|webp)', caseSensitive: false)
              .firstMatch(url)
              ?.group(0) ??
          '.jpg';
      final path = '$coversDir/$fileName$ext';
      final response = await dio.download(url, path);
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

