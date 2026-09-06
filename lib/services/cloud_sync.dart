/// 云端记录同步：拉取 Bangumi / VNDB / Hikarinagi 的用户收藏与评分，
/// 按 game_sources 中已记录的平台 id 匹配本地游戏，
/// 同步游玩状态与评分（本地已有评分时不覆盖）。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../data/models.dart';

/// 平台 id → 本地游戏 解析器。
typedef GameResolver = Game? Function(String sourceId);

class SyncResult {
  final bool ok;
  final int matched; // 命中并更新的本地游戏数
  final int total; // 云端记录条数
  final String message;
  const SyncResult(this.ok, this.matched, this.total, this.message);
}

class CloudSyncService {
  final String? proxy;
  CloudSyncService({this.proxy});

  Dio _dio(Map<String, String> headers) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: headers,
    ));
    if (proxy != null) {
      dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy =
              (uri) => 'PROXY ${proxy!.replaceFirst(RegExp(r'^https?://'), '')}';
          client.badCertificateCallback = (_, __, ___) => true;
          return client;
        };
    }
    return dio;
  }

  /// 拉取并同步一个平台。[resolve] 把云端条目 id 解析为本地游戏。
  Future<SyncResult> sync({
    required String platform,
    required String token,
    required GameResolver resolve,
    required Future<void> Function(Game g, double? rating) onSave,
  }) async {
    try {
      switch (platform) {
        case KisakiSources.bangumi:
          return await _bgm(token, resolve, onSave);
        case KisakiSources.vndb:
          return await _vndb(token, resolve, onSave);
        case KisakiSources.hikarinagi:
          return await _hikarinagi(token, resolve, onSave);
        default:
          return const SyncResult(false, 0, 0, '该平台暂不支持同步');
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return const SyncResult(false, 0, 0, '鉴权失败：请检查账号 Token');
      }
      return SyncResult(false, 0, 0, '同步失败（HTTP $code）');
    } catch (e) {
      return SyncResult(false, 0, 0, '同步失败：$e');
    }
  }

  Future<SyncResult> _bgm(String token, GameResolver resolve,
      Future<void> Function(Game, double?) onSave) async {
    final dio = _dio({
      'Authorization': 'Bearer $token',
      'User-Agent': 'MusaLunar/KisakiGals/0.2.0 (Sync)',
    });
    final items = <Map<String, dynamic>>[];
    for (var offset = 0; offset < 1000; offset += 100) {
      final r = await dio.get('https://api.bgm.tv/v0/users/-/collections',
          queryParameters: {
            'subject_type': 4,
            'limit': 100,
            'offset': offset,
          },
          options: Options(validateStatus: (s) => s != null && s < 500));
      if (r.statusCode != 200) {
        return SyncResult(false, 0, 0, 'Bangumi 返回 ${r.statusCode}');
      }
      final m = Map<String, dynamic>.from(r.data as Map);
      final page = [for (final e in (m['data'] as List?) ?? []) Map<String, dynamic>.from(e as Map)];
      items.addAll(page);
      if (page.length < 100) break;
    }
    var matched = 0;
    for (final it in items) {
      final game = resolve('${it['subject_id']}');
      if (game == null) continue;
      // type: 1 想玩 2 玩过 3 在玩 4 搁置 5 抛弃
      final status = switch ((it['type'] ?? 0) as int) {
        1 => PlayStatus.wish,
        2 => PlayStatus.played,
        3 => PlayStatus.playing,
        4 => PlayStatus.onHold,
        5 => PlayStatus.dropped,
        _ => null,
      };
      final rate = ((it['rate'] ?? 0) as num).toDouble();
      if (status != null) game.playStatus = status;
      if (rate > 0 && game.userRating <= 0) game.userRating = normalizeRating(rate);
      await onSave(game, rate > 0 ? normalizeRating(rate) : null);
      matched++;
    }
    return SyncResult(true, matched, items.length,
        '云端 ${items.length} 条，匹配本地 $matched 部');
  }

  Future<SyncResult> _vndb(String token, GameResolver resolve,
      Future<void> Function(Game, double?) onSave) async {
    final dio = _dio({
      'Authorization': 'Token $token',
      'Content-Type': 'application/json',
    });
    final items = <Map<String, dynamic>>[];
    for (var page = 1; page <= 10; page++) {
      final r = await dio.post('https://api.vndb.org/kana/ulist',
          data: {
            'user': 'all',
            'fields': 'id, vote, labels{id, name}',
            'results': 100,
            'page': page,
          },
          options: Options(validateStatus: (s) => s != null && s < 500));
      if (r.statusCode != 200) {
        return SyncResult(false, 0, 0, 'VNDB 返回 ${r.statusCode}');
      }
      final m = Map<String, dynamic>.from(r.data as Map);
      final pageItems = [
        for (final e in (m['results'] as List?) ?? []) Map<String, dynamic>.from(e as Map)
      ];
      items.addAll(pageItems);
      if ((m['more'] ?? false) != true || pageItems.isEmpty) break;
    }
    var matched = 0;
    for (final it in items) {
      final vid = (it['id'] ?? '').toString(); // v123
      final game = resolve(vid);
      if (game == null) continue;
      // labels: 1 Playing 2 Finished 3 Stalled 4 Dropped 5 Wishlist
      final labels = [for (final l in (it['labels'] as List?) ?? []) (l as Map)['id'] as int];
      PlayStatus? status;
      if (labels.contains(1)) {
        status = PlayStatus.playing;
      } else if (labels.contains(2)) {
        status = PlayStatus.played;
      } else if (labels.contains(3)) {
        status = PlayStatus.onHold;
      } else if (labels.contains(4)) {
        status = PlayStatus.dropped;
      } else if (labels.contains(5)) {
        status = PlayStatus.wish;
      }
      final vote = ((it['vote'] ?? 0) as num).toDouble(); // 10-100
      if (status != null) game.playStatus = status;
      if (vote > 0 && game.userRating <= 0) game.userRating = vote / 10;
      await onSave(game, vote > 0 ? vote / 10 : null);
      matched++;
    }
    return SyncResult(true, matched, items.length,
        '云端 ${items.length} 条，匹配本地 $matched 部');
  }

  Future<SyncResult> _hikarinagi(String token, GameResolver resolve,
      Future<void> Function(Game, double?) onSave) async {
    final dio = _dio({
      'Authorization': 'Bearer $token',
      'User-Agent': 'MusaLunar/KisakiGals/0.2.0',
    });
    final items = <Map<String, dynamic>>[];
    for (var page = 1; page <= 10; page++) {
      final r = await dio.get(
          'https://api.hikarinagi.org/v3/user/me/rates/galgames',
          queryParameters: {'page': page, 'page_size': 50},
          options: Options(validateStatus: (s) => s != null && s < 500));
      if (r.statusCode != 200) {
        return SyncResult(false, 0, 0, 'Hikarinagi 返回 ${r.statusCode}');
      }
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['success'] != true) {
        return SyncResult(false, 0, 0, 'Hikarinagi：${m['message'] ?? '请求失败'}');
      }
      final data = Map<String, dynamic>.from((m['data'] ?? {}) as Map);
      final pageItems = [
        for (final e in (data['items'] as List?) ?? []) Map<String, dynamic>.from(e as Map)
      ];
      items.addAll(pageItems);
      if (pageItems.isEmpty || items.length >= ((data['total'] ?? 0) as num).toInt()) break;
    }
    var matched = 0;
    for (final it in items) {
      final gid = (it['galgame_id'] ?? it['id'] ?? '').toString();
      final game = resolve(gid);
      if (game == null) continue;
      final score = num.tryParse((it['rate'] ?? it['score'] ?? '').toString()) ?? 0;
      if (score > 0 && game.userRating <= 0) game.userRating = normalizeRating(score);
      await onSave(game, score > 0 ? normalizeRating(score) : null);
      matched++;
    }
    return SyncResult(true, matched, items.length,
        '云端 ${items.length} 条，匹配本地 $matched 部');
  }
}
