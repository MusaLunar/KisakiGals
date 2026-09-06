/// TouchGal 适配器（developer.touchgal.com 开放 API，Bearer Token）。
///
/// 搜索：GET /games/search?keyword=&limit=&allowNsfw= → data.items[{name, uniqueId}]
/// 详情：GET /games/{uniqueId} → data{name, introduction, bannerUrl, tags,
///       companies, rating{average,count}, releaseDate, aliases}（多字段为字符串化的列表）。
library;

import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';

class TouchGalAdapter extends SourceAdapter {
  static const base = 'https://developer.touchgal.com/api/v1';
  // 开放 API 令牌（与 ChronoTide 同源的应用凭据）
  static const _token = 'tgal_live_nmnc-ZLyGctzGYQS7160Ruzff7UvaTcKen47wU8phkw';

  TouchGalAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.touchgal;

  @override
  bool get needsToken => false;

  Map<String, String> get _auth =>
      {'Authorization': 'Bearer $_token', 'Accept': 'application/json'};

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final response = await limitedGet('$base/games/search', query: {
      'keyword': kw,
      'page': 1,
      'limit': 10,
      'allowNsfw': 'true',
    }, headers: _auth);
    if (response.statusCode != 200) return [];
    final data = Map<String, dynamic>.from(response.data as Map);
    final payload = Map<String, dynamic>.from((data['data'] ?? {}) as Map);
    final list = (payload['items'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        // 搜索仅返回名称与 uniqueId，详情懒补
        .map((m) => ScrapedGame(
              source: KisakiSources.touchgal,
              sourceId: (m['uniqueId'] ?? '').toString(),
              name: (m['name'] ?? '') as String,
            ))
        .where((g) => g.sourceId.isNotEmpty)
        .toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet('$base/games/$id', headers: _auth);
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final g = data['data'];
    if (g is! Map) return null;
    return _parseDetail(Map<String, dynamic>.from(g));
  }

  static List<String> _stringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    // API 返回的是字符串化的列表：[‘a’, 'b']
    final s = (v ?? '').toString().trim();
    if (s.startsWith('[') && s.endsWith(']')) {
      return s
          .substring(1, s.length - 1)
          .split(RegExp("',\\s*'|\",\\s*\""))
          .map((e) => e.replaceAll(RegExp(r"^'|'$"), '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  ScrapedGame _parseDetail(Map<String, dynamic> m) {
    final companies = _stringList(m['companies']);
    String developer = '';
    for (final c in companies) {
      final name = RegExp(r"'name':\s*'([^']+)'").firstMatch(c)?.group(1) ??
          RegExp(r'"name":\s*"([^"]+)"').firstMatch(c)?.group(1);
      if (name != null && name.isNotEmpty) {
        developer = name;
        break;
      }
    }
    final ratingMap =
        (m['rating'] is Map) ? Map<String, dynamic>.from(m['rating'] as Map) : <String, dynamic>{};
    return ScrapedGame(
      source: KisakiSources.touchgal,
      sourceId: (m['uniqueId'] ?? '').toString(),
      name: (m['name'] ?? '') as String,
      aliases: _stringList(m['aliases']).take(6).toList(),
      coverUrl: (m['bannerUrl'] ?? '') as String,
      developer: developer,
      releaseDate: SourceAdapter.date(m['releaseDate']?.toString()),
      summary: ((m['introduction'] ?? '') ?? '') as String,
      rating: ((ratingMap['average'] ?? 0) as num).toDouble().clamp(0, 10).toDouble(),
      voteCount: (ratingMap['count'] ?? 0) as int,
      tags: _stringList(m['tags'])
          .take(10)
          .map(ScrapedTag.new)
          .toList(),
      nsfw: _stringList(m['type']).contains('adult'),
    );
  }
}
