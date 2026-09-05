/// KunGal (kungal.com) 适配器。
library;


import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';

class KunAdapter extends SourceAdapter {
  static const base = 'https://www.kungal.com/api';

  KunAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.kun;

  @override
  bool get needsToken => false;

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final response = await limitedGet('$base/search',
        query: {'keywords': kw, 'type': 'galgame', 'page': 1, 'limit': 10});
    if (response.statusCode != 200) return [];
    final data = Map<String, dynamic>.from(response.data as Map);
    final list = (data['galgames'] ?? data['data']) as List? ?? [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(_parseSummary)
        .toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet('$base/galgame/$id');
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final g = data['galgame'];
    if (g is! Map) return null;
    return _parseSummary(Map<String, dynamic>.from(g));
  }

  ScrapedGame _parseSummary(Map<String, dynamic> m) {
    final name = Map<String, dynamic>.from((m['name'] ?? {}) as Map? ?? {});
    final aliases = <String>[];
    for (final v in name.values) {
      if (v is String && v.isNotEmpty) aliases.add(v);
    }

    final tags = ((m['tags'] as List?) ?? [])
        .whereType<Map>()
        .map((t) => Map<String, dynamic>.from(t))
        .toList()
      ..sort((a, b) => ((b['galgame_count'] ?? 0) as num)
          .compareTo((a['galgame_count'] ?? 0) as num));

    final official = ((m['official'] as List?) ?? [])
        .whereType<Map>()
        .map((o) => (Map<String, dynamic>.from(o)['name'] ?? '').toString())
        .take(3)
        .toList();

    return ScrapedGame(
      source: KisakiSources.kun,
      sourceId: (m['id'] ?? 0).toString(),
      name: ((name['ja-jp'] ?? name['en-us']) ?? '') as String,
      nameCn: (name['zh-cn'] ?? '') as String,
      aliases: aliases.take(6).toList(),
      coverUrl: (m['effective_banner_url'] ?? '') as String,
      developer: official.join(', '),
      summary: ((m['summary'] ?? m['markdown']) ?? '') as String,
      tags: tags
          .take(10)
          .map((t) => ScrapedTag((t['name'] ?? '') as String))
          .toList(),
    );
  }
}
