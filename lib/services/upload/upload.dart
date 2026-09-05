/// 评价同步上传：Bangumi / VNDB / Hikarinagi。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../core/constants.dart';
import '../../data/models.dart';

class UploadResult {
  final bool ok;
  final String message;
  const UploadResult(this.ok, this.message);
}

class ReviewUploader {
  final String? proxy;
  ReviewUploader({this.proxy});

  Dio _dio(Map<String, String> headers) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: headers,
    ));
    if (proxy != null) {
      dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (uri) => 'PROXY ${proxy!.replaceFirst(RegExp(r'^https?://'), '')}';
          client.badCertificateCallback = (_, __, ___) => true;
          return client;
        };
    }
    return dio;
  }

  /// 向单个平台上传评分/评论。[rating] 为 0-10。
  Future<UploadResult> upload({
    required String platform,
    required String token,
    required SourceRecord source,
    required double rating,
    required String comment,
  }) async {
    try {
      switch (platform) {
        case KisakiSources.bangumi:
          return await _bgm(token, source, rating, comment);
        case KisakiSources.vndb:
          return await _vndb(token, source, rating, comment);
        case KisakiSources.hikarinagi:
          return await _hikarinagi(token, source, rating, comment);
        default:
          return const UploadResult(false, '该平台暂不支持上传');
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return const UploadResult(false, '鉴权失败：请检查账号 Token');
      }
      return UploadResult(false, '上传失败（HTTP $code）');
    } catch (e) {
      return UploadResult(false, '上传失败：$e');
    }
  }

  Future<UploadResult> _bgm(
      String token, SourceRecord source, double rating, String comment) async {
    final dio = _dio({
      'Authorization': 'Bearer $token',
      'User-Agent': 'MusaLunar/KisakiGals/0.1.0',
      'Content-Type': 'application/json',
    });
    final sid = int.tryParse(source.sourceId);
    if (sid == null) return const UploadResult(false, '缺少 Bangumi 条目 id');
    final body = <String, dynamic>{
      'type': 2, // 玩过
      'rate': rating.round().clamp(0, 10),
      if (comment.isNotEmpty) 'comment': comment,
    };
    final response = await dio.post(
        'https://api.bgm.tv/v0/users/-/collections/$sid',
        data: body,
        options: Options(validateStatus: (s) => s != null && s < 500));
    if (response.statusCode == 204 || response.statusCode == 200) {
      return const UploadResult(true, 'Bangumi 收藏/评分已同步');
    }
    return UploadResult(false, 'Bangumi 返回 ${response.statusCode}');
  }

  Future<UploadResult> _vndb(
      String token, SourceRecord source, double rating, String comment) async {
    final dio = _dio({
      'Authorization': 'Token $token',
      'Content-Type': 'application/json',
    });
    final vid = source.sourceId.startsWith('v')
        ? source.sourceId
        : 'v${source.sourceId}';
    if (rating <= 0 && comment.isEmpty) {
      return const UploadResult(false, '评分与评论均为空');
    }
    final body = <String, dynamic>{};
    if (rating > 0) {
      body['vote'] = (rating * 10).round().clamp(10, 100); // 10-100
    }
    if (comment.isNotEmpty) body['notes'] = comment;
    final response = await dio.patch('https://api.vndb.org/kana/ulist/$vid',
        data: body,
        options: Options(validateStatus: (s) => s != null && s < 500));
    if (response.statusCode == 200) {
      return const UploadResult(true, 'VNDB 投票已同步');
    }
    return UploadResult(false, 'VNDB 返回 ${response.statusCode}');
  }

  Future<UploadResult> _hikarinagi(
      String token, SourceRecord source, double rating, String comment) async {
    final dio = _dio({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
    final body = <String, dynamic>{
      'score': rating.toStringAsFixed(1),
      if (comment.isNotEmpty) 'comment': comment,
      'status': 'played',
    };
    final response = await dio.put(
        'https://api.hikarinagi.org/v3/user/me/rates/galgames/${source.sourceId}',
        data: body,
        options: Options(validateStatus: (s) => s != null && s < 500));
    if (response.statusCode == 200 || response.statusCode == 201) {
      return const UploadResult(true, 'Hikarinagi 评价已同步');
    }
    return UploadResult(false, 'Hikarinagi 返回 ${response.statusCode}');
  }

  /// 账号测试连接。
  Future<UploadResult> testAccount(String platform, String token) async {
    try {
      switch (platform) {
        case KisakiSources.bangumi:
          final dio = _dio({'Authorization': 'Bearer $token'});
          final r = await dio.get('https://api.bgm.tv/v0/me');
          final m = Map<String, dynamic>.from(r.data as Map);
          return UploadResult(true, '欢迎，${m['nickname'] ?? m['username'] ?? '用户'}');
        case KisakiSources.vndb:
          final dio = _dio({'Authorization': 'Token $token'});
          final r = await dio.get('https://api.vndb.org/kana/authinfo');
          final m = Map<String, dynamic>.from(r.data as Map);
          return UploadResult(true, '欢迎，${m['username'] ?? '用户'}');
        case KisakiSources.hikarinagi:
          final dio = _dio({'Authorization': 'Bearer $token'});
          final r = await dio.get('https://api.hikarinagi.org/v3/user/me');
          final m = Map<String, dynamic>.from(r.data as Map);
          final data = Map<String, dynamic>.from((m['data'] ?? m) as Map);
          return UploadResult(true, '欢迎，${data['nickname'] ?? data['name'] ?? '用户'}');
        default:
          return const UploadResult(false, '未知平台');
      }
    } on DioException catch (e) {
      return UploadResult(false, '连接失败（HTTP ${e.response?.statusCode}）');
    } catch (e) {
      return UploadResult(false, '连接失败：$e');
    }
  }
}

/// 平台评分展示辅助。
String fmtPlatformRating(double rating, int votes) =>
    rating <= 0 ? '暂无评分' : '${rating.toStringAsFixed(1)}（$votes 人评分）';
