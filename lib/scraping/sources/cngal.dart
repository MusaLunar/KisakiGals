/// CnGal 适配器（公开 API 不够稳定，默认关闭，失败静默）。
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
    // GetId 只支持精确名；失败即返回空
    final response = await limitedGet('$base/api/entries/GetId/${Uri.encodeComponent(kw)}');
    if (response.statusCode != 200) return [];
    final id = (response.data is int)
        ? response.data as int
        : int.tryParse(response.data.toString().trim());
    if (id == null) return [];
    final detail = await fetchById('$id');
    return detail == null ? [] : [detail];
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response =
        await limitedGet('$base/api/entries/GetEntryView/$id', query: {
      'renderMarkdown': 'false',
    });
    if (response.statusCode != 200) return null;
    final m = Map<String, dynamic>.from(response.data as Map);

    final tags = ((m['Tags'] as List?) ?? [])
        .whereType<Map>()
        .map((t) => Map<String, dynamic>.from(t))
        .map((t) => ScrapedTag((t['Name'] ?? '') as String))
        .where((t) => t.name.isNotEmpty)
        .take(10)
        .toList();

    return ScrapedGame(
      source: KisakiSources.cngal,
      sourceId: id,
      name: ((m['OriginalName'] ?? m['Name']) ?? '') as String,
      nameCn: ((m['ChineseName'] ?? '') ?? '') as String,
      coverUrl: ((m['MainImage'] ?? m['CoverImage']) ?? '') as String,
      developer: ((m['Developer'] ?? '') ?? '') as String,
      releaseDate: SourceAdapter.date(m['StartDate']?.toString()),
      summary: ((m['Introduction'] ?? '') ?? '') as String,
      tags: tags,
    );
  }
}
