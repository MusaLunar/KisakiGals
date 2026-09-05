/// Steam 适配器：storesearch → appdetails 两步。
library;


import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';

class SteamAdapter extends SourceAdapter {
  SteamAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.steam;

  @override
  bool get needsToken => false;

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final response = await limitedGet(
        'https://store.steampowered.com/api/storesearch/',
        query: {'term': kw, 'l': 'schinese', 'cc': 'CN'},
        headers: _headers);
    if (response.statusCode != 200) return [];
    final data = Map<String, dynamic>.from(response.data as Map);
    final items = (data['items'] as List?) ?? [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .take(10)
        .map((m) => ScrapedGame(
              source: KisakiSources.steam,
              sourceId: (m['id'] ?? 0).toString(),
              name: (m['name'] ?? '') as String,
              coverUrl: ((m['tiny_image'] ?? '') as String).replaceFirst(
                  'capsule_sm_120', 'library_600x900'),
            ))
        .toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet(
        'https://store.steampowered.com/api/appdetails',
        query: {'appids': id, 'l': 'schinese', 'cc': 'CN'},
        headers: _headers);
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final node = data[id];
    if (node is! Map) return null;
    final m = Map<String, dynamic>.from(node);
    if (m['success'] != true) return null;
    final d = Map<String, dynamic>.from((m['data'] ?? {}) as Map);

    final rating = Map<String, dynamic>.from((d['metacritic'] ?? {}) as Map);
    final release =
        Map<String, dynamic>.from((d['release_date'] ?? {}) as Map);

    final screenshots = ((d['screenshots'] as List?) ?? [])
        .whereType<Map>()
        .map((s) =>
            (Map<String, dynamic>.from(s)['path_full'] ?? '') as String)
        .take(6)
        .toList();

    final genres = ((d['genres'] as List?) ?? [])
        .whereType<Map>()
        .map((g) => (Map<String, dynamic>.from(g)['description'] ?? '')
            as String)
        .take(8)
        .toList();

    final developers = ((d['developers'] as List?) ?? [])
        .map((e) => e.toString())
        .take(3)
        .toList();

    return ScrapedGame(
      source: KisakiSources.steam,
      sourceId: id,
      name: (d['name'] ?? '') as String,
      coverUrl: (d['header_image'] ?? '') as String,
      developer: developers.join(', '),
      releaseDate: SourceAdapter.date(release['date']?.toString()),
      summary: _stripTags((d['short_description'] ?? '') as String),
      rating: normalizeRating((rating['score'] ?? 0) as num),
      voteCount: (rating['users_rating'] ?? 0) as int,
      tags: [
        for (var i = 0; i < genres.length; i++)
          ScrapedTag(genres[i], weight: 1.0 - i * 0.1),
      ],
      screenshots: screenshots,
    );
  }

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').trim();
}
