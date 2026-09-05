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
