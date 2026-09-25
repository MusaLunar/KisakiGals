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
  Future<List<ScrapedGame>> browse({
    String sort = 'rank',
    int page = 1,
    int limit = 50,
    int? year,
    String? tag,
  }) async {
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
