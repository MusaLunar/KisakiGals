/// 资源搜索（参考 Moe-Sakura/SearchGal 的聚合思路）。
///
/// 两类来源：
/// 1. **内置适配器**：直接解析各资源站的搜索接口（鲲Galgame、GAL图书馆…），
///    实测在本机网络可达，无需额外部署。
/// 2. **SearchGal 兼容聚合接口**（可选）：SearchGal 用 Cloudflare Workers
///    聚合 27+ 站点并以 SSE 流式返回，可填自建地址获得最全覆盖。
///
/// 只提供**发布页/详情页链接**，不解析直链、不托管资源。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/constants.dart';

/// 资源站标签（对齐 SearchGal 的标注语义）
class ResourceTag {
  static const noLogin = '免登录';
  static const needLogin = '需登录';
  static const needMagic = '需代理';
  static const patch = '补丁站';
}

class ResourceItem {
  final String site; // 站点名
  final String title; // 资源标题
  final String url; // 发布页/详情页
  final List<String> tags;
  const ResourceItem({
    required this.site,
    required this.title,
    required this.url,
    this.tags = const [],
  });
}

/// 单个来源的搜索结果（或错误）
class ResourceSourceResult {
  final String site;
  final List<ResourceItem> items;
  final String? error;
  final List<String> tags;
  const ResourceSourceResult({
    required this.site,
    this.items = const [],
    this.error,
    this.tags = const [],
  });
}

/// 搜索进度/结果更新（流式，边出边显示）
class ResourceSearchUpdate {
  final int completed;
  final int total;
  final ResourceSourceResult? result;
  final bool done;
  const ResourceSearchUpdate({
    this.completed = 0,
    this.total = 0,
    this.result,
    this.done = false,
  });
}

/// 内置适配器接口
abstract class ResourceAdapter {
  String get site;
  List<String> get tags;
  Future<List<ResourceItem>> search(Dio dio, String keyword);
}

/// 鲲Galgame（元数据 + 资源发布页，实测可达）
class KunResourceAdapter implements ResourceAdapter {
  @override
  String get site => '鲲Galgame';
  @override
  List<String> get tags => const [ResourceTag.noLogin];

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final r = await dio.get('https://www.kungal.com/api/search',
        queryParameters: {
          'keywords': keyword,
          'type': 'galgame',
          'page': 1,
          'limit': 20,
        });
    final data = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
    final items = (data?['data'] is Map)
        ? ((data!['data'] as Map)['items'] as List? ?? [])
        : <dynamic>[];
    final out = <ResourceItem>[];
    for (final it in items) {
      final m = Map<String, dynamic>.from(it as Map);
      final id = m['id'];
      final name = m['name'];
      var title = '';
      if (name is Map) {
        title = (name['zh-cn'] ?? name['ja-jp'] ?? '').toString();
      } else {
        title = (name ?? '').toString();
      }
      final original = (m['name_original'] ?? '').toString();
      if (title.isEmpty && original.isEmpty) continue;
      out.add(ResourceItem(
        site: site,
        title: title.isEmpty ? original : title,
        url: 'https://www.kungal.com/zh-cn/galgame/$id',
        tags: tags,
      ));
    }
    return out;
  }
}

/// GAL图书馆（实测可达）
class GalLibraryAdapter implements ResourceAdapter {
  @override
  String get site => 'GAL图书馆';
  @override
  List<String> get tags => const [ResourceTag.noLogin];

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final r = await dio.get('https://gallibrary.pw/galgame/game/manyGame',
        queryParameters: {
          'page': 1,
          'type': 1,
          'count': 60,
          'keyWord': keyword,
        });
    final data = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
    if (data == null || data['code'] != 200) return const [];
    final list = (data['data'] as List?) ?? [];
    final out = <ResourceItem>[];
    for (final it in list) {
      final m = Map<String, dynamic>.from(it as Map);
      final texts = (m['listGameText'] as List?) ?? [];
      String title = '';
      if (texts.length > 1) {
        final t = Map<String, dynamic>.from(texts[1] as Map);
        title = (t['data'] ?? '').toString();
      }
      title = title.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (title.isEmpty) continue;
      out.add(ResourceItem(
        site: site,
        title: title,
        url: 'https://gallibrary.pw/game.html?id=${m['id']}',
        tags: tags,
      ));
    }
    return out;
  }
}

/// TouchGal（官方元数据 API，需 Bearer token；主站有 Cloudflare 质询，
/// 因此搜索走 developer.touchgal.com，链接仍指向主站条目页）
class TouchGalResourceAdapter implements ResourceAdapter {
  static const _base = 'https://developer.touchgal.com/api/v1';
  // 与元数据刮削共用同一把官方 token（内置，免配置）
  static const _token = 'tgal_live_nmnc-ZLyGctzGYQS7160Ruzff7UvaTcKen47wU8phkw';

  @override
  String get site => 'TouchGal';
  @override
  List<String> get tags => const [ResourceTag.noLogin];

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final kw = keyword.trim();
    // 官方接口限制关键词 3-100 字符
    if (kw.length < 3 || kw.length > 100) return const [];
    final r = await dio.get('$_base/games/search',
        queryParameters: {
          'keyword': kw,
          'page': 1,
          'limit': 20,
          'allowNsfw': 'true',
        },
        options: Options(headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        }));
    final data = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
    final items = (data?['data'] is Map)
        ? ((data!['data'] as Map)['items'] as List? ?? [])
        : <dynamic>[];
    final out = <ResourceItem>[];
    for (final it in items) {
      final m = Map<String, dynamic>.from(it as Map);
      final uid = (m['uniqueId'] ?? '').toString();
      if (uid.isEmpty) continue;
      out.add(ResourceItem(
        site: site,
        title: (m['name'] ?? '').toString(),
        url: 'https://www.touchgal.ink/$uid',
        tags: tags,
      ));
    }
    return out;
  }
}

/// 量子ACG（HTML 搜索页解析）
class LiangZiAcgAdapter implements ResourceAdapter {
  @override
  String get site => '量子ACG';
  @override
  List<String> get tags => const [ResourceTag.noLogin, '自建盘'];

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final r = await dio.get('https://lzacg.org/',
        queryParameters: {'s': keyword},
        options: Options(responseType: ResponseType.plain));
    final html = r.data.toString();
    final re = RegExp(
        r'<h2 class="item-heading"><a[^>]*href="([^"]+)"[^>]*>(.*?)</a></h2>',
        dotAll: true,
        caseSensitive: false);
    final out = <ResourceItem>[];
    for (final m in re.allMatches(html)) {
      final url = m.group(1)!.trim();
      final name = m
          .group(2)!
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&#8211;', '–')
          .trim();
      if (url.isEmpty || name.isEmpty) continue;
      out.add(ResourceItem(site: site, title: name, url: url, tags: tags));
      if (out.length >= 30) break;
    }
    return out;
  }
}

/// 真红小站（部分网络不可达，失败会以错误形式显示）
class ShinnkuAdapter implements ResourceAdapter {
  @override
  String get site => '真红小站';
  @override
  List<String> get tags => const [ResourceTag.noLogin];

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final r = await dio.get('https://www.shinnku.com/search',
        queryParameters: {'q': keyword},
        options: Options(responseType: ResponseType.plain));
    final html = r.data.toString();
    final re = RegExp(r'hover:underline"\s+href="([^"]+)"[^>]*>\s*([^<]+?)\s*</a>',
        dotAll: true, caseSensitive: false);
    final out = <ResourceItem>[];
    for (final m in re.allMatches(html)) {
      var url = m.group(1)!.trim();
      final name = m.group(2)!.trim();
      if (url.isEmpty || name.isEmpty) continue;
      if (!url.startsWith('http')) url = 'https://www.shinnku.com$url';
      out.add(ResourceItem(
          site: site, title: name, url: url, tags: tags));
      if (out.length >= 30) break;
    }
    return out;
  }
}

class ResourceSearcher {
  final Dio _dio;
  ResourceSearcher({String? proxy})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'User-Agent': 'MusaLunar/${AppInfo.name}/${AppInfo.version} '
                '(Gal Resource Search)',
          },
        )) {
    if (proxy != null && proxy.trim().isNotEmpty) {
      _dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy =
              (uri) => 'PROXY ${proxy.replaceFirst(RegExp(r'^https?://'), '')}';
          return client;
        };
    }
  }

  /// 底层 HTTP 客户端（测试/扩展适配器用）
  Dio get dio => _dio;

  List<ResourceAdapter> get builtinAdapters => [
        KunResourceAdapter(),
        GalLibraryAdapter(),
        TouchGalResourceAdapter(),
        LiangZiAcgAdapter(),
        ShinnkuAdapter(),
      ];

  /// 相关度评分（0-1000）：与关键词越接近越高。
  /// 归一化会去掉空格/全角符号（Senren＊Banka 与 senren banka 视为同一串），
  /// 并支持「标题包含关键词但更短者优先」——资源站的标题常带一堆后缀。
  static double relevance(String title, String keyword) {
    final t = _norm(title);
    final k = _norm(keyword);
    if (t.isEmpty || k.isEmpty) return 0;
    if (t == k) return 1000;
    if (t.startsWith(k)) {
      // 前缀命中：越短越精确
      return 900 - (t.length - k.length).clamp(0, 200) * 1.0;
    }
    final idx = t.indexOf(k);
    if (idx >= 0) {
      return 800 - idx * 2.0 - (t.length - k.length).clamp(0, 200) * 0.5;
    }
    // 关键词被空格/符号切成多段时，按命中段数给分
    final parts = keyword
        .split(RegExp(r'[\s　\-–—:：・,，。!！?？~～＊*]+'))
        .map(_norm)
        .where((p) => p.length >= 2)
        .toList();
    if (parts.isEmpty) return 0;
    var hit = 0;
    for (final p in parts) {
      if (t.contains(p)) hit++;
    }
    if (hit == 0) return 0;
    return 400.0 * hit / parts.length - (t.length - k.length).clamp(0, 200) * 0.3;
  }

  /// 归一化：小写、去空白与装饰符号、全角转半角。
  static const _punct =
      " \t\r\n-_–—_・,，。.:：;；!！?？~～＊*★☆「」『』[]()（）'\"“”";

  static String _norm(String s) {
    final buf = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      // 全角字母数字 → 半角
      if (r >= 0xFF01 && r <= 0xFF5E) {
        final half = r - 0xFEE0;
        final c = String.fromCharCode(half);
        if (!_punct.contains(c)) buf.write(c);
        continue;
      }
      if (r == 0x3000) continue; // 全角空格
      final c = String.fromCharCode(r);
      if (_punct.contains(c)) continue;
      buf.write(c);
    }
    return buf.toString();
  }

  /// 并发搜索全部来源，流式返回每个来源的结果。
  Stream<ResourceSearchUpdate> search(
    String keyword, {
    String? searchGalApi,
    List<ResourceAdapter>? only,
  }) async* {
    final adapters = only ?? builtinAdapters;
    final useAggregator = searchGalApi != null && searchGalApi.trim().isNotEmpty;
    final total = adapters.length + (useAggregator ? 1 : 0);
    var completed = 0;
    yield ResourceSearchUpdate(completed: 0, total: total);

    final tasks = <Future<ResourceSourceResult>>[
      for (final a in adapters)
        () async {
          try {
            final items = await a.search(_dio, keyword);
            return ResourceSourceResult(
                site: a.site, items: items, tags: a.tags);
          } catch (e) {
            return ResourceSourceResult(
                site: a.site, error: _short(e), tags: a.tags);
          }
        }(),
      if (useAggregator)
        () async {
          try {
            final items = await _searchSearchGal(searchGalApi, keyword);
            return ResourceSourceResult(site: 'SearchGal 聚合', items: items);
          } catch (e) {
            return ResourceSourceResult(
                site: 'SearchGal 聚合', error: _short(e));
          }
        }(),
    ];

    // 谁先返回先展示（SearchGal 的 SSE 体验）
    final pending = tasks.toSet();
    while (pending.isNotEmpty) {
      final finished = await Future.any(pending.map((f) async {
        final r = await f;
        return MapEntry(f, r);
      }));
      pending.remove(finished.key);
      completed++;
      yield ResourceSearchUpdate(
          completed: completed, total: total, result: finished.value);
    }
    yield ResourceSearchUpdate(completed: total, total: total, done: true);
  }

  /// 调用 SearchGal 兼容接口（SSE：total / progress+result / done）。
  Future<List<ResourceItem>> _searchSearchGal(String api, String keyword) async {
    final form = FormData.fromMap({'game': keyword});
    final r = await _dio.post(api,
        data: form,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          followRedirects: true,
        ));
    final stream = (r.data as ResponseBody).stream;
    final out = <ResourceItem>[];
    await for (final chunk in stream) {
      final text = utf8.decode(chunk, allowMalformed: true);
      for (final line in text.split('\n')) {
        final s = line.trim();
        if (s.isEmpty || !s.startsWith('{')) continue;
        try {
          final m = Map<String, dynamic>.from(jsonDecode(s) as Map);
          final res = m['result'];
          if (res is Map) {
            final rm = Map<String, dynamic>.from(res);
            final site = (rm['name'] ?? '').toString();
            final tags = [
              for (final t in (rm['tags'] as List?) ?? []) _tagLabel('$t')
            ];
            for (final it in (rm['items'] as List?) ?? []) {
              final im = Map<String, dynamic>.from(it as Map);
              final url = (im['url'] ?? '').toString();
              if (url.isEmpty) continue;
              out.add(ResourceItem(
                site: site,
                title: (im['name'] ?? '').toString(),
                url: url,
                tags: tags,
              ));
            }
          }
        } catch (_) {}
      }
    }
    return out;
  }

  static String _tagLabel(String raw) {
    switch (raw) {
      case 'NoReq':
        return ResourceTag.noLogin;
      case 'Login':
      case 'LoginPay':
      case 'LoginRep':
        return ResourceTag.needLogin;
      case 'magic':
        return ResourceTag.needMagic;
      default:
        return raw;
    }
  }

  static String _short(Object e) {
    var s = e.toString();
    if (s.length > 120) s = '${s.substring(0, 120)}…';
    return s;
  }

  void dispose() => _dio.close(force: true);
}
