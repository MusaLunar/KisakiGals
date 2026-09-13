/// VNDB kana API 适配器。
library;


import '../source_adapter.dart';
import '../scraped_game.dart';
import '../tag_translator.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';

class VndbAdapter extends SourceAdapter {
  static const base = 'https://api.vndb.org/kana';
  final String? token;

  VndbAdapter(super.dio, super.limiters, {this.token});

  @override
  String get id => KisakiSources.vndb;

  @override
  bool get needsToken => false;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Token $token',
      };

  static const _fields = 'id, title, titles{lang, title, latin, official, main}, '
      'image{url}, screenshots{url}, description, rating, votecount, released, '
      'developers{name}, tags{name, rating, spoiler, lie}, length_minutes';

  Future<List<dynamic>?> _query(Object filters) async {
    final response = await limitedPost('$base/vn',
        data: {'filters': filters, 'fields': _fields, 'sort': 'searchrank', 'results': 20},
        headers: _headers);
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['results'] as List?;
  }

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final results = await _query(['search', '=', kw]);
    if (results == null) return [];
    return results.map(_parse).toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final vid = id.startsWith('v') ? id : 'v$id';
    final results = await _query(['id', '=', vid]);
    if (results == null || results.isEmpty) return null;
    return _parse(results.first);
  }

  ScrapedGame _parse(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);

    // 标题：zh-hans > zh-hant > zh > 主标题 > 任意 official
    String title = (m['title'] ?? '') as String;
    String nameCn = '';
    final titles = (m['titles'] as List?) ?? [];
    // 收集全部标题变体（日文/英文/罗马音/其它语言）作为别名，
    // 这样跨源搜索时「Shiny Sisters」与「シャイニー・シスターズ」能被认成同一部作品
    final aliases = <String>{};
    for (final t in titles) {
      final tm = Map<String, dynamic>.from(t as Map);
      final lang = (tm['lang'] ?? '') as String;
      final tTitle = (tm['title'] ?? '').toString().trim();
      final latin = (tm['latin'] ?? '').toString().trim();
      if (lang == 'zh-Hans' && nameCn.isEmpty) {
        nameCn = tTitle;
      } else if (lang == 'zh-Hant' && nameCn.isEmpty) {
        nameCn = tTitle;
      }
      if (tTitle.isNotEmpty) aliases.add(tTitle);
      if (latin.isNotEmpty) aliases.add(latin);
    }
    if (nameCn.isEmpty) {
      for (final t in titles) {
        final tm = Map<String, dynamic>.from(t as Map);
        if ((tm['lang'] ?? '') == 'zh') {
          nameCn = (tm['title'] ?? '') as String;
          break;
        }
      }
    }

    final image = Map<String, dynamic>.from((m['image'] ?? {}) as Map);
    final cover = (image['url'] ?? '') as String;

    final screenshots = ((m['screenshots'] as List?) ?? [])
        .map((s) => (Map<String, dynamic>.from(s as Map)['url'] ?? '') as String)
        .where((u) => u.isNotEmpty)
        .take(6)
        .toList();

    final developers = ((m['developers'] as List?) ?? [])
        .map((d) => (Map<String, dynamic>.from(d as Map)['name'] ?? '') as String)
        .where((n) => n.isNotEmpty)
        .take(5)
        .toList();

    final tags = ((m['tags'] as List?) ?? [])
        .map((t) => Map<String, dynamic>.from(t as Map))
        .where((t) {
          final rating = (t['rating'] ?? 0) as num;
          final spoiler = (t['spoiler'] ?? 0) as num;
          return rating >= 1.5 && spoiler < 2 && t['lie'] != true;
        })
        .map((t) => ScrapedTag(
              TagTranslator.instance.translate((t['name'] ?? '') as String),
              weight: ((t['rating'] as num) / 3).clamp(0.1, 10).toDouble(),
            ))
        .take(10)
        .toList();

    return ScrapedGame(
      source: KisakiSources.vndb,
      sourceId: (m['id'] ?? '').toString(),
      name: title,
      nameCn: nameCn,
      aliases: aliases
          .where((a) => a != title && a != nameCn)
          .take(12)
          .toList(),
      coverUrl: cover,
      developer: developers.join(', '),
      releaseDate: SourceAdapter.date(m['released']?.toString()),
      summary: _stripSp((m['description'] ?? '') as String),
      rating: normalizeRating((m['rating'] ?? 0) as num),
      voteCount: (m['votecount'] ?? 0) as int,
      tags: tags,
      screenshots: screenshots,
    );
  }

  static String _stripSp(String s) => s
      .replaceAll(RegExp(r'\[url=[^\]]*\]'), '')
      .replaceAll('[/url]', '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .trim();
}
