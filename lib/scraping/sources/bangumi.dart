/// Bangumi (bgm.tv) 适配器。
library;


import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';

class BangumiAdapter extends SourceAdapter {
  static const base = 'https://api.bgm.tv';
  final String? token; // 个人访问令牌（PAT）

  BangumiAdapter(super.dio, super.limiters, {this.token});

  @override
  String get id => KisakiSources.bangumi;

  @override
  bool get needsToken => false;

  /// 最近一次 [browse] 之后是否还有下一页（由响应里的 `total` 推算）。
  bool lastBrowseHasMore = false;

  Map<String, String> get _headers => {
        'User-Agent': 'MusaLunar/KisakiGals/0.1.0 (Metadata Scraper)',
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final response = await limitedPost('$base/v0/search/subjects?limit=20',
        data: {
          'keyword': kw,
          'sort': 'rank',
          'filter': {'type': [4], 'nsfw': true},
        },
        headers: _headers);
    if (response.statusCode != 200) return [];
    final data = Map<String, dynamic>.from(response.data as Map);
    final list = (data['data'] as List?) ?? [];
    return list.map(_parse).toList();
  }

  /// 榜单浏览：GET /v0/subjects（type=4 游戏，sort=rank|date）。
  ///
  /// 为什么选 GET 浏览接口而不是 POST /v0/search/subjects：
  /// 1) 浏览榜单没有关键词，GET 的 sort/limit/offset/year 与「榜单 + 年份」
  ///    的语义一一对应；POST 搜索要自己拼 filter（{type, nsfw, ...}），
  ///    且无 keyword 的纯 filter 请求行为不稳定（不同时段/条目类型差异大）；
  /// 2) GET 会返回 `total`，可以直接推算「还有没有下一页」；
  /// 3) 实测（本机）GET 返回的是**完整 Subject**：date / platform / images /
  ///    summary / tags / infobox / rating{score,rank,total} / nsfw，
  ///    因此能直接复用 [_parse]，字段/评分口径与搜索、详情完全一致。
  ///
  /// [sort] 只支持 `rank`（按排名）与 `date`（按发售日，新→旧）；
  /// [year] 只接受**单一年份**（BGM 没有年份区间参数，区间筛选由 UI 侧在
  /// 客户端补筛）；[tag] 参数 BGM 浏览接口不支持，这里做客户端名称过滤，
  /// 仅作为兜底能力（探索页的标签选择是 VNDB 标签 id，BGM 下不会传）。
  ///
  /// [keyword] 非空时改用 `POST /v0/search/subjects`（见 [_searchBrowse]）：
  /// 浏览接口本身没有关键词参数，硬拼 filter 既不稳也不准。
  Future<List<ScrapedGame>> browse({
    String sort = 'rank',
    int page = 1,
    int limit = 50,
    int? year,
    String? tag,
    String? keyword,
  }) async {
    final kw = (keyword ?? '').trim();
    if (kw.isNotEmpty) return _searchBrowse(kw, page: page, limit: limit);
    final safeLimit = limit.clamp(1, 50);
    final safePage = page < 1 ? 1 : page;
    final offset = (safePage - 1) * safeLimit;
    final response = await limitedGet('$base/v0/subjects',
        query: {
          'type': 4, // 4 = 游戏
          'sort': sort == 'date' ? 'date' : 'rank',
          if (year != null && year > 0) 'year': year,
          'limit': safeLimit,
          'offset': offset,
        },
        headers: _headers);
    if (response.statusCode != 200) {
      lastBrowseHasMore = false;
      return [];
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final list = (data['data'] as List?) ?? const [];
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final realOffset = (data['offset'] as num?)?.toInt() ?? offset;
    // 分页依据：BGM 给的是 total（总条数），因此「当前位置 + 本页条数 < total」
    // 就是权威的「还有下一页」判断，不需要额外请求。
    lastBrowseHasMore = list.isNotEmpty && realOffset + list.length < total;
    var games = list.map(_parse).toList();
    final tagName = (tag ?? '').trim().toLowerCase();
    if (tagName.isNotEmpty) {
      games = games
          .where((g) =>
              g.tags.any((t) => t.name.toLowerCase().contains(tagName)))
          .toList();
    }
    return games;
  }

  /// 关键词浏览：`POST /v0/search/subjects` + 分页（探索页搜索框的入口）。
  ///
  /// 与 [search] 的区别只有两点：
  /// - 带上 `limit`/`offset`，返回的是「第 page 页」而不是固定的前 20 条；
  /// - 排序用 `match`（匹配程度）。BGM 的搜索排序只支持
  ///   match/heat/rank/score，其中只有 match 是「与关键词的相关度」，
  ///   与 VNDB 侧的 `searchrank` 对齐（探索页有关键词时排序条件不生效，
  ///   两个源都按各自的相关度排）。
  ///
  /// `filter` 里带 `nsfw: true`（与 [search] 一致）：R18 由客户端按
  /// 用户设置补筛，服务端先"都给"，避免把成人向作品静默藏掉。
  /// 年份区间同样是客户端补筛——探索页在关键词搜索时不做年份/评分补筛
  /// （见 `discover_state.dart` 的 `_passes`），因为那会把用户明确要找的
  /// 那部作品筛没（BGM 里新条目的 score 常为 0）。
  ///
  /// **每页上限 20**：实测这个接口无论 `limit` 传 20/30/50 都只回 20 条
  /// （浏览用的 GET 接口没这个限制）。`offset` 是按请求的 limit 步进的，
  /// 所以这里必须按 20 截断，否则「请求 30 拿到 20、下一页 offset=30」
  /// 每翻一页漏掉中间 10 条。
  Future<List<ScrapedGame>> _searchBrowse(
    String keyword, {
    required int page,
    required int limit,
  }) async {
    final safeLimit = limit.clamp(1, 20);
    final safePage = page < 1 ? 1 : page;
    final offset = (safePage - 1) * safeLimit;
    final response = await limitedPost(
        '$base/v0/search/subjects?limit=$safeLimit&offset=$offset',
        data: {
          'keyword': keyword,
          'sort': 'match',
          'filter': {'type': [4], 'nsfw': true},
        },
        headers: _headers);
    if (response.statusCode != 200) {
      lastBrowseHasMore = false;
      return const [];
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final list = (data['data'] as List?) ?? const [];
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final realOffset = (data['offset'] as num?)?.toInt() ?? offset;
    // 与浏览接口同一套判断：total 是权威的，位置 + 本页条数 < total 才有下一页
    lastBrowseHasMore = list.isNotEmpty && realOffset + list.length < total;
    return list.map(_parse).toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet('$base/v0/subjects/$id', headers: _headers);
    if (response.statusCode != 200) return null;
    return _parse(response.data);
  }

  ScrapedGame _parse(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);

    final images = Map<String, dynamic>.from((m['images'] ?? {}) as Map);
    String cover = (images['large'] ?? images['common'] ?? images['medium'] ?? '') as String;
    if (cover.startsWith('//')) {
      cover = 'https:$cover';
    } else if (cover.startsWith('/')) {
      cover = 'https://lain.bgm.tv$cover';
    }

    // infobox：别名、开发商
    String developer = '';
    final aliases = <String>[];
    final infobox = (m['infobox'] as List?) ?? [];
    for (final item in infobox) {
      final im = Map<String, dynamic>.from(item as Map);
      final key = (im['key'] ?? '') as String;
      if (key.contains('开发')) {
        final v = im['value'];
        if (v is List) {
          developer = v
              .map((e) => e is Map ? (e['v'] ?? '').toString() : e.toString())
              .take(3)
              .join(', ');
        } else {
          developer = (v ?? '').toString();
        }
      }
      if (key == '别名') {
        final v = im['value'];
        if (v is List) {
          for (final e in v) {
            if (e is Map && e['v'] != null) aliases.add(e['v'].toString());
          }
        }
      }
    }

    final rating = Map<String, dynamic>.from((m['rating'] ?? {}) as Map);

    final tags = ((m['tags'] as List?) ?? [])
        .map((t) => Map<String, dynamic>.from(t as Map))
        .where((t) => ((t['count'] ?? 0) as num) >= 3)
        .toList()
      ..sort((a, b) => ((b['count'] ?? 0) as num).compareTo((a['count'] ?? 0) as num));
    final maxCount = tags.isEmpty ? 1 : ((tags.first['count'] ?? 1) as num).toDouble();

    return ScrapedGame(
      source: KisakiSources.bangumi,
      sourceId: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '') as String,
      nameCn: (m['name_cn'] ?? '') as String,
      aliases: aliases.take(8).toList(),
      coverUrl: cover,
      developer: developer.replaceAll(RegExp(r'、|×'), ', '),
      releaseDate: SourceAdapter.date(m['date']?.toString()),
      summary: (m['summary'] ?? '') as String,
      rating: normalizeRating((rating['score'] ?? 0) as num),
      voteCount: (rating['total'] ?? 0) as int,
      tags: tags
          .take(10)
          .map((t) => ScrapedTag(
                (t['name'] ?? '') as String,
                weight: (((t['count'] ?? 0) as num) / maxCount).clamp(0.1, 1.0),
              ))
          .toList(),
      nsfw: (m['nsfw'] ?? false).toString() == 'true',
    );
  }
}
