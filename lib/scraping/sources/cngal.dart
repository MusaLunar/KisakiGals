/// CnGal 适配器（公开 API；搜索走 /api/home/Search，默认关闭，失败静默）。
library;

import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';

class CngalAdapter extends SourceAdapter {
  static const base = 'https://api.cngal.org';

  CngalAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.cngal;

  @override
  bool get needsToken => false;

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    // 全站搜索 → 过滤「游戏」类型条目 → 逐条取详情（最多 3 条）
    final response = await limitedGet('$base/api/home/Search',
        query: {'Text': kw, 'Page': 1});
    if (response.statusCode != 200) return [];
    final data = Map<String, dynamic>.from(response.data as Map);
    final pr = Map<String, dynamic>.from((data['pagedResultDto'] ?? {}) as Map);
    final ids = <String>[];
    for (final item in (pr['data'] as List?) ?? []) {
      if (item is! Map) continue;
      final entry = item['entry'];
      if (entry is! Map) continue;
      final em = Map<String, dynamic>.from(entry);
      if ((em['type'] ?? '') == '游戏' && em['id'] != null) {
        ids.add('${em['id']}');
      }
      if (ids.length >= 3) break;
    }
    final results = <ScrapedGame>[];
    for (final id in ids) {
      final detail = await fetchById(id);
      if (detail != null && detail.name.isNotEmpty) results.add(detail);
    }
    return results;
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet('$base/api/entries/GetEntryView/$id',
        query: {'renderMarkdown': 'false'});
    if (response.statusCode != 200) return null;
    final m = Map<String, dynamic>.from(response.data as Map);

    final tags = ((m['tagState']?['tags'] as List?) ?? [])
        .whereType<Map>()
        .map((t) =>
            ScrapedTag(((Map<String, dynamic>.from(t))['Name'] ?? '') as String))
        .where((t) => t.name.isNotEmpty)
        .take(10)
        .toList();

    return ScrapedGame(
      source: KisakiSources.cngal,
      sourceId: id,
      name: ((m['name'] ?? m['originalName']) ?? '') as String,
      nameCn: ((m['anotherName'] ?? m['chineseName']) ?? '') as String,
      coverUrl: ((m['mainPicture'] ?? m['mainImage'] ?? m['thumbnail']) ?? '')
          as String,
      developer: ((m['developer'] ?? '') ?? '') as String,
      releaseDate: SourceAdapter.date(
          (m['startDate'] ?? m['releaseDate'])?.toString()),
      summary: ((m['briefIntroduction'] ?? m['introduction']) ?? '') as String,
      tags: tags,
    );
  }
}
