/// KunGal (kungal.com / NextMoe) 适配器。
///
/// 鲲Gal已将作品目录与认证体系迁移至统一中台 NextMoe (`api.nextmoe.dev/v2/catalog/works`)，
/// 其中 `work.id` 与 `kungal.com/galgame/{id}` 完全等价：
/// - 搜索：GET https://api.nextmoe.dev/v2/catalog/works?q=... → items[]
/// - 详情：GET https://api.nextmoe.dev/v2/catalog/works/{id} → Work{...}
/// 支持匿名访问与 OAuth 2.0 Bearer Token 鉴权访问。
library;

import '../../core/constants.dart';
import '../../services/game_explore_service.dart';
import '../../services/kungal_oauth.dart';
import '../scraped_game.dart';
import '../source_adapter.dart';

class KunAdapter extends SourceAdapter {
  static const base = 'https://api.nextmoe.dev/v2';

  final String? token;

  KunAdapter(super.dio, super.limiters, {this.token});

  @override
  String get id => KisakiSources.kun;

  @override
  bool get needsToken => false;

  Future<Map<String, String>?> _authHeaders() async {
    try {
      final oauthToken = await KunOAuthService.instance.validAccessToken();
      if (oauthToken != null && oauthToken.isNotEmpty) {
        return {'Authorization': 'Bearer $oauthToken'};
      }
    } catch (_) {}
    final staticToken = (token ?? '').trim();
    if (staticToken.isNotEmpty) {
      return {'Authorization': 'Bearer $staticToken'};
    }
    return null;
  }

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final trimmed = kw.trim();
    if (trimmed.isEmpty) return const [];
    final headers = await _authHeaders();
    final response = await limitedGet(
      '$base/catalog/works',
      query: {
        'q': trimmed,
        'nsfw': 'true',
        'limit': 12,
        'include': 'titles,companies,ratings',
        'fields':
            'medium,display_name,latin,localized,olang,content_rating,content_limit,cover,companies,ratings',
      },
      headers: headers,
    );
    if (response.statusCode != 200 || response.data is! Map) return const [];
    final data = Map<String, dynamic>.from(response.data as Map);
    final topItems = data['items'];
    if (topItems is List) {
      return topItems
          .whereType<Map>()
          .map((e) => _parseWork(Map<String, dynamic>.from(e)))
          .toList();
    }
    final rawData = data['data'];
    if (rawData is List) {
      return rawData
          .whereType<Map>()
          .map((e) => _parseWork(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (rawData is Map) {
      final list = (rawData['items'] as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => _parseWork(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return null;
    final headers = await _authHeaders();
    final response = await limitedGet(
      '$base/catalog/works/$cleanId',
      query: {
        'include':
            'titles,refs,intros,companies,ratings,tags,playtimes,releases',
        'fields':
            'medium,display_name,latin,localized,olang,content_rating,content_limit,cover,titles,refs,intros,companies,ratings,tags,playtimes,releases',
        'nsfw': 'true',
        'spoiler': 'none',
      },
      headers: headers,
    );
    if (response.statusCode != 200 || response.data is! Map) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data.containsKey('id') || data.containsKey('display_name')) {
      return _parseWork(data);
    }
    final g = data['data'];
    if (g is Map) {
      return _parseWork(Map<String, dynamic>.from(g));
    }
    return null;
  }

  static String _extractLocalized(dynamic loc) {
    if (loc == null) return '';
    return GameExploreService.extractLocalizedText(loc);
  }

  /// 解析 NextMoe / KunGal 作品对象（兼容搜索摘要与详情结构）。
  ScrapedGame _parseWork(Map<String, dynamic> m) {
    final idStr = '${m['id'] ?? 0}';
    final displayName =
        (m['display_name'] ?? m['name_original'] ?? m['name'] ?? '')
            .toString()
            .trim();
    final localized = _extractLocalized(m['localized']);
    final latin = (m['latin'] ?? '').toString().trim();

    final aliases = <String>[];
    void addAlias(String s) {
      final t = s.trim();
      if (t.isNotEmpty && !aliases.contains(t)) aliases.add(t);
    }

    if (latin.isNotEmpty) addAlias(latin);
    if (m['localized'] is Map) {
      for (final v in (m['localized'] as Map).values) {
        if (v is Map && v['value'] != null) {
          addAlias('${v['value']}');
        }
      }
    }
    for (final t in (m['titles'] as List?) ?? const []) {
      if (t is Map) {
        addAlias('${t['title'] ?? t['value'] ?? t['display_name'] ?? ''}');
      } else if (t != null) {
        addAlias('$t');
      }
    }
    for (final t in (m['all_titles'] as List?) ?? const []) {
      if (t != null) addAlias('$t');
    }

    // 封面提取：NextMoe 为 cover.url / cover.original
    var coverUrl = '';
    final cover = m['cover'];
    if (cover is Map) {
      coverUrl = (cover['url'] ?? cover['original'] ?? cover['large'] ?? '')
          .toString()
          .trim();
    } else if (cover is String) {
      coverUrl = cover.trim();
    }
    if (coverUrl.isEmpty) {
      coverUrl = (m['effective_portrait_url'] ??
              m['effective_banner_url'] ??
              '')
          .toString()
          .trim();
    }

    // 开发商提取：companies 数组中优先 attribution_role / role == 'developer'
    var developer = '';
    final companies = (m['companies'] as List?) ?? const [];
    for (final c in companies) {
      if (c is! Map) continue;
      final cm = Map<String, dynamic>.from(c);
      final role =
          (cm['attribution_role'] ?? cm['role'] ?? '').toString().toLowerCase();
      final comp = cm['company'];
      final compMap = comp is Map ? Map<String, dynamic>.from(comp) : cm;
      final locName = _extractLocalized(compMap['localized']);
      final cName = locName.isNotEmpty
          ? locName
          : (compMap['display_name'] ?? compMap['name'] ?? '')
              .toString()
              .trim();
      if (cName.isEmpty) continue;
      if (role == 'developer') {
        developer = cName;
        break;
      }
      if (developer.isEmpty) developer = cName;
    }

    // 发售日提取：releases 数组中取最早合法日期（字段名 date 或 released_date）
    var releaseDate = SourceAdapter.date(m['release_date']?.toString());
    if (releaseDate.isEmpty) {
      final releases = (m['releases'] as List?) ?? const [];
      final dates = <String>[];
      for (final rel in releases) {
        if (rel is! Map) continue;
        final d = SourceAdapter.date(
            (rel['date'] ?? rel['released_date'])?.toString());
        if (d.isNotEmpty) dates.add(d);
      }
      if (dates.isNotEmpty) {
        dates.sort();
        releaseDate = dates.first;
      }
    }

    // 简介提取：NextMoe 为 intros[{lang, value/content}]，优先 zh-Hans / zh-Hant
    var summary = (m['intro_text'] ?? '').toString().trim();
    if (summary.isEmpty) {
      final intros = (m['intros'] as List?) ??
          (m['introduction'] as List?) ??
          const [];
      String? zhHans;
      String? zhHant;
      String? fallbackIntro;
      for (final item in intros) {
        if (item is! Map) continue;
        final im = Map<String, dynamic>.from(item);
        final text = (im['value'] ?? im['content'] ?? im['intro'] ?? '')
            .toString()
            .trim();
        if (text.isEmpty) continue;
        final lang = (im['lang'] ?? '').toString();
        if (lang == 'zh-Hans' || lang == 'zh-CN') {
          zhHans = text;
          break;
        } else if (lang == 'zh-Hant' || lang == 'zh-TW') {
          zhHant ??= text;
        } else {
          fallbackIntro ??= text;
        }
      }
      summary = zhHans ?? zhHant ?? fallbackIntro ?? '';
    }

    // 评分提取：NextMoe 为 ratings 数组 [{source, score, vote_count}]（优先 nextmoe，其次 vndb/bangumi）
    var rating = 0.0;
    var voteCount = 0;
    final ratings = m['ratings'];
    if (ratings is List && ratings.isNotEmpty) {
      Map<String, dynamic>? picked;
      for (final r in ratings) {
        if (r is! Map) continue;
        final rm = Map<String, dynamic>.from(r);
        final src = (rm['source'] ?? '').toString().toLowerCase();
        if (src == 'nextmoe' || src == 'kun' || src == 'kungal') {
          picked = rm;
          break;
        }
        picked ??= rm;
      }
      if (picked != null) {
        rating = normalizeRatingNum(picked['score'] ?? picked['average_score']);
        voteCount =
            ((picked['vote_count'] ?? picked['total_count'] ?? 0) as num)
                .toInt();
      }
    } else if (ratings is Map) {
      final rm = Map<String, dynamic>.from(ratings);
      rating = normalizeRatingNum(rm['average_score'] ?? rm['score']);
      voteCount = ((rm['total_count'] ?? rm['count'] ?? 0) as num).toInt();
    } else {
      rating = normalizeRatingNum(m['rating']);
      voteCount = ((m['rating_count'] ?? 0) as num).toInt();
    }

    // 标签提取：NextMoe 为 tags[{display_name, localized, weight}]
    final tags = <ScrapedTag>[];
    for (final rawTag in (m['tags'] as List?) ?? const []) {
      if (rawTag is! Map) continue;
      final tm = Map<String, dynamic>.from(rawTag);
      final inner = tm['tag'];
      String tagName = '';
      if (inner is Map) {
        final im = Map<String, dynamic>.from(inner);
        final loc = _extractLocalized(im['localized']);
        final disp = (im['display_name'] ?? '').toString().trim();
        tagName = loc.isNotEmpty ? loc : disp;
      } else {
        final loc = _extractLocalized(tm['localized']);
        tagName = loc.isNotEmpty
            ? loc
            : (tm['display_name'] ?? tm['name'] ?? '').toString().trim();
      }
      if (tagName.isEmpty) continue;
      final w = (tm['weight'] is num) ? (tm['weight'] as num).toDouble() : 1.0;
      tags.add(ScrapedTag(tagName, weight: w));
      if (tags.length >= 16) break;
    }

    // R18 判定：content_limit == 'nsfw' 或 content_rating == 'r18' / 'x'
    final contentLimit = (m['content_limit'] ?? '').toString().toLowerCase();
    final contentRating =
        (m['content_rating'] ?? m['age_limit'] ?? '').toString().toLowerCase();
    final nsfw = contentLimit == 'nsfw' ||
        contentRating == 'r18' ||
        contentRating == 'r18g' ||
        contentRating == 'x' ||
        contentRating == 'adult';

    final primaryName = displayName.isNotEmpty ? displayName : localized;
    final cnName = localized.isNotEmpty ? localized : displayName;

    return ScrapedGame(
      source: KisakiSources.kun,
      sourceId: idStr,
      name: primaryName,
      nameCn: cnName,
      aliases: aliases.take(15).toList(),
      coverUrl: coverUrl,
      developer: developer,
      releaseDate: releaseDate,
      summary: summary,
      rating: rating,
      voteCount: voteCount,
      tags: tags,
      nsfw: nsfw,
    );
  }

  static double normalizeRatingNum(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    if (n > 10 && n <= 100) return (n / 10).clamp(0, 10).toDouble();
    return n.clamp(0, 10).toDouble();
  }
}
