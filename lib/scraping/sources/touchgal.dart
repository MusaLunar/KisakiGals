/// TouchGal 适配器（developer.touchgal.com 开放 API）。
library;


import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';

class TouchGalAdapter extends SourceAdapter {
  static const base = 'https://developer.touchgal.com/api/v1';

  TouchGalAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.touchgal;

  @override
  bool get needsToken => false;

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final response = await limitedGet('$base/games/search', query: {
      'keyword': kw,
      'limit': '10',
      'allowNsfw': 'true',
    });
    if (response.statusCode != 200) return [];
    final data = Map<String, dynamic>.from(response.data as Map);
    final list = (data['games'] ?? data['data']) as List? ?? [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(_parse)
        .toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet('$base/games/$id');
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final g = data['game'] ?? data['data'];
    if (g is! Map) return null;
    return _parse(Map<String, dynamic>.from(g));
  }

  ScrapedGame _parse(Map<String, dynamic> m) {
    final tags = ((m['tags'] as List?) ?? [])
        .map((t) => t is Map
            ? ScrapedTag((t['name'] ?? '').toString())
            : ScrapedTag(t.toString()))
        .where((t) => t.name.isNotEmpty)
        .take(10)
        .toList();

    return ScrapedGame(
      source: KisakiSources.touchgal,
      sourceId: ((m['uniqueId'] ?? m['id']) ?? 0).toString(),
      name: ((m['title'] ?? m['name'] ?? m['originTitle']) ?? '') as String,
      nameCn: ((m['chineseTitle'] ?? m['transTitle']) ?? '') as String,
      coverUrl: ((m['cover'] ?? m['mainImg'] ?? m['image']) ?? '') as String,
      developer: ((m['developer'] ?? m['brand']) ?? '') as String,
      releaseDate: SourceAdapter.date(m['releaseDate']?.toString()),
      summary: ((m['introduction'] ?? m['intro']) ?? '') as String,
      tags: tags,
      nsfw: (m['nsfw'] ?? m['restricted'] ?? false).toString() == 'true',
    );
  }
}
