/// 月幕GAL (ymgal) 适配器：client_credentials 公共凭据。
library;

import 'package:dio/dio.dart';

import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';

class YmgalAdapter extends SourceAdapter {
  static const tokenUrl = 'https://www.ymgal.games/oauth/token';
  static const api = 'https://www.ymgal.games/open/archive';

  String? _cachedToken;
  DateTime? _expiresAt;

  YmgalAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.ymgal;

  @override
  bool get needsToken => false; // 使用内置公共凭据

  Future<String?> _token() async {
    if (_cachedToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!)) {
      return _cachedToken;
    }
    final response = await dio.getUri(
      Uri.parse(tokenUrl).replace(queryParameters: {
        'grant_type': 'client_credentials',
        'client_id': 'ymgal',
        'client_secret': 'luna0327',
        'scope': 'public',
      }),
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final token = data['access_token']?.toString();
    if (token == null || token.isEmpty) return null;
    _cachedToken = token;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 3600))
        .subtract(const Duration(seconds: 60));
    return token;
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'version': '1',
        'Accept': 'application/json;charset=utf-8',
      };

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final token = await _token();
    if (token == null) return [];
    final response = await limitedGet('$api/search-game',
        query: {'mode': 'accurate', 'keyword': kw, 'similarity': '70'},
        headers: _authHeaders(token));
    if (response.statusCode != 200) return [];
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['success'] != true) return [];
    final body = Map<String, dynamic>.from((data['data'] ?? {}) as Map);

    // 兼容两种返回：{game: {...}}（accurate 单结果）或 {games: [...]}
    final results = <ScrapedGame>[];
    final game = body['game'];
    if (game is Map) {
      results.add(_parse(Map<String, dynamic>.from(game)));
    }
    final games = body['games'];
    if (games is List) {
      for (final g in games) {
        if (g is Map) results.add(_parse(Map<String, dynamic>.from(g)));
      }
    }
    return results;
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final token = await _token();
    if (token == null) return null;
    final response = await limitedGet(api,
        query: {'gid': id}, headers: _authHeaders(token));
    if (response.statusCode != 200) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['success'] != true) return null;
    final body = Map<String, dynamic>.from((data['data'] ?? {}) as Map);
    final game = body['game'];
    if (game is! Map) return null;
    return _parse(Map<String, dynamic>.from(game));
  }

  ScrapedGame _parse(Map<String, dynamic> m) {
    final tags = ((m['tags'] as List?) ?? [])
        .take(10)
        .map((t) => t is Map
            ? ScrapedTag((t['name'] ?? '').toString())
            : ScrapedTag(t.toString()))
        .toList();

    String name = (m['chineseName'] ?? '') as String;
    if (name.isEmpty) name = (m['name'] ?? '') as String;
    String nameCn = (m['chineseName'] ?? '') as String;

    final aliases = <String>[];
    final ext = (m['extensionName'] as List?) ?? [];
    for (final e in ext) {
      if (e is Map && e['name'] != null) aliases.add(e['name'].toString());
    }

    return ScrapedGame(
      source: KisakiSources.ymgal,
      sourceId: (SourceAdapter.i(m, 'gid') ?? SourceAdapter.i(m, 'id') ?? 0)
          .toString(),
      name: name,
      nameCn: nameCn,
      aliases: aliases,
      coverUrl: ((m['mainImg'] ?? m['cover_url'] ?? m['image']) ?? '') as String,
      developer: ((m['brand_name'] ?? m['company'] ?? m['developer_name']) ?? '')
          as String,
      releaseDate: SourceAdapter.date(
          ((m['release_date'] ?? m['publish_date']) ?? '')?.toString()),
      summary: ((m['introduction'] ?? m['summary']) ?? '') as String,
      rating: normalizeRating((m['score'] ?? 0) as num),
      tags: tags,
      nsfw: (m['restricted'] ?? false).toString() == 'true',
    );
  }
}
