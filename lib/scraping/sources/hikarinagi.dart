/// Hikarinagi 适配器：OIDC client_credentials（凭据与 ChronoTide 同源）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../source_adapter.dart';
import '../scraped_game.dart';
import '../../core/constants.dart';

class HikarinagiAdapter extends SourceAdapter {
  static const tokenUrl = 'https://id.hikarinagi.org/oidc/token';
  static const api = 'https://www.hikarinagi.org/api/v3/open';
  static const clientId = 'hkn_hCWLqY0zJzWwItBl';

  // client_secret（与 ChronoTide 同源的开发者凭据）
  static const _clientSecret =
      'hks_Z7bj68qCb7YjiEB31hJbcJUWdEmAM185csqqb9WdxEU';

  String? _cachedToken;
  DateTime? _expiresAt;

  HikarinagiAdapter(super.dio, super.limiters);

  @override
  String get id => KisakiSources.hikarinagi;

  @override
  bool get needsToken => false;

  Future<String?> _token() async {
    if (_cachedToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!)) {
      return _cachedToken;
    }
    final basic = base64Encode(utf8.encode('$clientId:$_clientSecret'));
    final response = await dio.post(
      tokenUrl,
      data: 'grant_type=client_credentials&scope=catalog:read',
      options: Options(
        headers: {
          'Authorization': 'Basic $basic',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        validateStatus: (s) => s != null && s < 500,
      ),
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

  @override
  Future<List<ScrapedGame>> search(String kw) async {
    final token = await _token();
    if (token == null) return [];
    final response = await limitedGet('$api/search',
        query: {'q': kw, 'types': 'galgame', 'page': 1, 'page_size': 10},
        headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode != 200) return [];
    final envelope = Map<String, dynamic>.from(response.data as Map);
    if (envelope['success'] != true) return [];
    final data = Map<String, dynamic>.from((envelope['data'] ?? {}) as Map);
    final items = (data['items'] as List?) ?? [];
    // 搜索结果仅含摘要，逐条补全会浪费请求；返回摘要形态（detail 懒补）
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => m['type'] == 'galgame')
        .map((m) => ScrapedGame(
              source: KisakiSources.hikarinagi,
              sourceId: (m['id'] ?? 0).toString(),
              name: (m['title'] ?? '') as String,
              developer: (m['developer'] ?? '') as String,
              coverUrl: (m['cover'] ?? '') as String,
            ))
        .toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final token = await _token();
    if (token == null) return null;
    final response = await limitedGet('$api/galgames/$id',
        headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode != 200) return null;
    final envelope = Map<String, dynamic>.from(response.data as Map);
    if (envelope['success'] != true) return null;
    final data = Map<String, dynamic>.from((envelope['data'] ?? {}) as Map);

    String name = (data['origin_title'] ?? '') as String;
    String nameCn = (data['trans_title'] ?? '') as String;

    // 封面：covers[] 按 votes 选最佳
    String cover = '';
    final covers = (data['covers'] as List?) ?? [];
    int bestVotes = -1;
    for (final c in covers) {
      if (c is! Map) continue;
      final cm = Map<String, dynamic>.from(c);
      final votes = (cm['votes'] ?? 0) as num;
      if (votes > bestVotes) {
        bestVotes = votes.toInt();
        cover = (cm['url'] ?? '') as String;
      }
    }

    String summary = (data['trans_intro'] ?? '') as String;
    if (summary.isEmpty) summary = (data['origin_intro'] ?? '') as String;

    final tags = ((data['tags'] as List?) ?? [])
        .whereType<Map>()
        .map((t) => Map<String, dynamic>.from(t))
        .toList()
      ..sort((a, b) =>
          ((b['likes'] ?? 0) as num).compareTo((a['likes'] ?? 0) as num));
    final maxLikes = tags.isEmpty
        ? 1
        : ((tags.first['likes'] ?? 1) as num).toDouble().clamp(1, double.infinity);

    return ScrapedGame(
      source: KisakiSources.hikarinagi,
      sourceId: id,
      name: name,
      nameCn: nameCn,
      coverUrl: cover,
      releaseDate: SourceAdapter.date(data['release_date']?.toString()),
      summary: summary,
      tags: tags
          .take(10)
          .map((t) => ScrapedTag(
                (t['name'] ?? '') as String,
                weight: (((t['likes'] ?? 0) as num) / maxLikes)
                    .clamp(0.1, 1.0)
                    .toDouble(),
              ))
          .toList(),
      nsfw: (data['nsfw'] ?? false).toString() == 'true',
    );
  }
}
