/// 数据源适配器抽象与公共 HTTP 基础。
library;

import 'package:dio/dio.dart';

import '../core/constants.dart';
import 'rate_limiter.dart';
import 'scraped_game.dart';

abstract class SourceAdapter {
  String get id;
  String get label => KisakiSources.labels[id] ?? id;
  bool get needsToken;

  final Dio dio;
  final RateLimiters limiters;

  SourceAdapter(this.dio, this.limiters);

  /// 搜索（返回候选列表）。
  Future<List<ScrapedGame>> search(String kw);

  /// 按 id 拉取完整数据。
  Future<ScrapedGame?> fetchById(String id);

  /// 带限流、瞬态网络/握手异常重试与 429 退避的 GET。
  Future<Response> limitedGet(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    final limiter = limiters.forSource(id);
    // Uri.replace 的 queryParameters 只接受 String / List<String>
    final safeQuery = query?.map((k, v) {
      if (v is String || v is List) return MapEntry(k, v);
      return MapEntry(k, '$v');
    });
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      await limiter.acquire();
      try {
        final response = await dio.getUri(
          Uri.parse(url).replace(queryParameters: safeQuery),
          options: Options(
            headers: headers,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (response.statusCode == 429 && attempt < 2) {
          await Future.delayed(RateLimiter.backoff(attempt));
          continue;
        }
        return response;
      } catch (e) {
        lastError = e;
        if (attempt < 2 && _isRetryableError(e)) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('$id: 请求多次失败');
  }

  Future<Response> limitedPost(
    String url, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    final limiter = limiters.forSource(id);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      await limiter.acquire();
      try {
        final response = await dio.post(
          url,
          data: data,
          options: Options(
            headers: headers,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (response.statusCode == 429 && attempt < 2) {
          await Future.delayed(RateLimiter.backoff(attempt));
          continue;
        }
        return response;
      } catch (e) {
        lastError = e;
        if (attempt < 2 && _isRetryableError(e)) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('$id: 请求多次失败');
  }

  static bool _isRetryableError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('handshake') ||
        s.contains('connection terminated') ||
        s.contains('connection reset') ||
        s.contains('socketexception') ||
        s.contains('timed out');
  }

  /// 从字符串/数字安全取值。
  static String? s(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return null;
    return v.toString();
  }

  static int? i(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? d(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// 规范化日期：接受 YYYY-MM-DD 开头的字符串。
  static String date(String? raw) {
    if (raw == null) return '';
    final m = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(raw);
    if (m == null) return raw;
    String two(String n) => n.padLeft(2, '0');
    return '${m.group(1)}-${two(m.group(2)!)}-${two(m.group(3)!)}';
  }
}
