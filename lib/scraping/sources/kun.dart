/// KunGal (kungal.com) 适配器。
///
/// 搜索：GET /api/search?keywords=&type=galgame → data.items[]
/// 详情：GET /api/galgame/{id} → data{...}（含 vndb_id、多语言简介）。
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
    final payload = Map<String, dynamic>.from((data['data'] ?? {}) as Map);
    final list = (payload['items'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => _parseSummary(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet('$base/galgame/$id');
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final g = data['data'];
    if (g is! Map) return null;
    return _parseDetail(Map<String, dynamic>.from(g));
  }

  /// 搜索摘要条目：name/rating 为标量，封面用竖版 portrait。
  ScrapedGame _parseSummary(Map<String, dynamic> m) => ScrapedGame(
        source: KisakiSources.kun,
        sourceId: (m['id'] ?? 0).toString(),
        name: ((m['name_original'] ?? m['name']) ?? '') as String,
        nameCn: (m['name'] ?? '') as String,
        coverUrl: (m['effective_portrait_url'] ??
                m['effective_banner_url'] ??
                '') as String,
        releaseDate: SourceAdapter.date(m['release_date']?.toString()),
        rating: normalizeRatingNum(m['rating']),
        voteCount: (m['rating_count'] ?? 0) as int,
      );

  /// 详情条目：name 标量 + name_original，introduction 为多语言数组。
  ScrapedGame _parseDetail(Map<String, dynamic> m) {
    String summary = '';
    for (final lang in (m['introduction'] as List?) ?? []) {
      if (lang is! Map) continue;
      final lm = Map<String, dynamic>.from(lang);
      final text = (lm['intro'] ?? '').toString();
      if (text.isEmpty) continue;
      summary = text;
      if (lm['lang'] == 'zh-Hans') break;
    }
    final tags = ((m['tags'] as List?) ?? [])
        .whereType<Map>()
        .map((t) => ScrapedTag(
            ((Map<String, dynamic>.from(t))['name'] ?? '') as String))
        .where((t) => t.name.isNotEmpty)
        .take(10)
        .toList();
    return ScrapedGame(
      source: KisakiSources.kun,
      sourceId: (m['id'] ?? 0).toString(),
      name: ((m['name_original'] ?? m['name']) ?? '') as String,
      nameCn: (m['name'] ?? '') as String,
      aliases: [
        if ((m['vndb_id'] ?? '') is String && (m['vndb_id'] ?? '') != '')
          (m['vndb_id'] ?? '').toString(),
      ],
      coverUrl: (m['effective_portrait_url'] ??
              m['effective_banner_url'] ??
              '') as String,
      releaseDate: SourceAdapter.date(m['release_date']?.toString()),
      summary: summary,
      rating: normalizeRatingNum(m['rating']),
      voteCount: (m['rating_count'] ?? 0) as int,
      tags: tags,
    );
  }

  static double normalizeRatingNum(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n.clamp(0, 10).toDouble();
  }
}
