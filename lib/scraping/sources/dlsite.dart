/// DLsite 适配器（HTML 简析，默认关闭）。
library;


import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';

class DlsiteAdapter extends SourceAdapter {
  DlsiteAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.dlsite;

  @override
  bool get needsToken => false;

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final url =
        'https://www.dlsite.com/maniax/fsr/=/language/jp/keyword/${Uri.encodeComponent(kw)}';
    final response = await limitedGet(url, headers: _headers);
    if (response.statusCode != 200) return [];
    final html = response.data.toString();

    // 搜索结果页：work_name 区块与 product id (VJ/RJ + 数字)
    final results = <ScrapedGame>[];
    final pattern = RegExp(r'(RJ|VJ)(\d{6,})');
    final names = RegExp(r'work_name[^>]*>([^<]+)<');
    final ids = pattern.allMatches(html).map((m) => '${m.group(1)}${m.group(2)}').toSet();
    final titleHits = names.allMatches(html).map((m) => m.group(1)!.trim()).toSet();
    final idList = ids.take(10).toList();
    for (var i = 0; i < idList.length; i++) {
      results.add(ScrapedGame(
        source: KisakiSources.dlsite,
        sourceId: idList[i],
        name: i < titleHits.length ? titleHits.elementAt(i) : idList[i],
        coverUrl: 'https://media.dlsite.com/archive/pc/${idList[i]}/psb.jpg',
      ));
    }
    return results;
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final response = await limitedGet(
        'https://www.dlsite.com/maniax/product/info/ajax?product_id=$id',
        headers: _headers);
    if (response.statusCode != 200) return null;
    try {
      final data = Map<String, dynamic>.from(response.data as Map);
      final node = data[id];
      if (node is! Map) return null;
      final m = Map<String, dynamic>.from(node);
      return ScrapedGame(
        source: KisakiSources.dlsite,
        sourceId: id,
        name: ((m['work_name'] ?? '') ?? '') as String,
        nameCn: ((m['work_name_cn'] ?? '') ?? '') as String,
        coverUrl: ((m['work_image'] ?? '') ?? '') as String,
        developer: ((m['maker_name'] ?? '') ?? '') as String,
        releaseDate: SourceAdapter.date(((m['regist_date'] ?? '') ?? '') as String),
        summary: ((m['description'] ?? '') ?? '') as String,
      );
    } catch (_) {
      return null;
    }
  }
}
