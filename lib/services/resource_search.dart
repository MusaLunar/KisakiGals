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
import 'kungal_oauth.dart';

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

/// 鲲Galgame（通过 NextMoe 统一目录接口查询，实测可达；支持匿名与 OAuth Token）
class KunResourceAdapter implements ResourceAdapter {
  @override
  String get site => '鲲Galgame';
  @override
  List<String> get tags => const [ResourceTag.noLogin];

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    String? bearer;
    try {
      bearer = await KunOAuthService.instance.validAccessToken();
    } catch (_) {}

    final r = await dio.get(
      'https://api.nextmoe.dev/v2/catalog/works',
      queryParameters: {
        'q': kw,
        'nsfw': 'true',
        'limit': 20,
        'include': 'titles',
        'fields': 'display_name,latin,localized',
      },
      options: (bearer != null && bearer.isNotEmpty)
          ? Options(headers: {'Authorization': 'Bearer $bearer'})
          : null,
    );
    final data = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
    final topItems = data?['items'];
    final rawData = data?['data'];
    final items = topItems is List
        ? topItems
        : (rawData is List
            ? rawData
            : (rawData is Map
                ? (rawData['items'] as List? ?? const [])
                : const []));
    final out = <ResourceItem>[];
    for (final it in items) {
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it);
      final id = m['id'];
      if (id == null) continue;
      var localized = '';
      final locField = m['localized'];
      if (locField is String) {
        localized = locField.trim();
      } else if (locField is Map) {
        for (final k in ['zh-Hans', 'zh-CN', 'zh-Hant', 'ja', 'en']) {
          final v = locField[k];
          if (v is Map && (v['value'] ?? '').toString().trim().isNotEmpty) {
            localized = v['value'].toString().trim();
            break;
          } else if (v is String && v.trim().isNotEmpty) {
            localized = v.trim();
            break;
          }
        }
      }
      final displayName =
          (m['display_name'] ?? m['name_original'] ?? m['name'] ?? '')
              .toString()
              .trim();
      final title = localized.isNotEmpty ? localized : displayName;
      if (title.isEmpty) continue;
      out.add(ResourceItem(
        site: site,
        title: title,
        url: 'https://www.kungal.com/galgame/$id',
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

  Future<List<ResourceItem>> _queryOnce(
      Dio dio, String queryKw, String matchKw) async {
    final r = await dio.get('https://gallibrary.pw/galgame/game/manyGame',
        queryParameters: {
          'page': 1,
          'type': 1,
          'count': 60,
          'keyWord': queryKw,
        });
    Map<String, dynamic>? data;
    final raw = r.data;
    if (raw is Map) {
      data = Map<String, dynamic>.from(raw);
    } else if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('{')) {
        try {
          data = Map<String, dynamic>.from(jsonDecode(trimmed) as Map);
        } catch (_) {}
      }
    }
    if (data == null || data['code'] != 200) return const [];
    final list = (data['data'] as List?) ?? [];
    final out = <ResourceItem>[];
    final seenIds = <String>{};
    for (final it in list) {
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it);
      final id = '${m['id'] ?? ''}'.trim();
      if (id.isEmpty || !seenIds.add(id)) continue;
      final texts = (m['listGameText'] as List?) ?? [];
      final candidates = <String>[];
      for (final entry in texts) {
        if (entry is Map) {
          final s = _cleanHtmlText('${entry['data'] ?? ''}');
          if (s.isNotEmpty && !candidates.contains(s)) candidates.add(s);
        }
      }
      if (candidates.isEmpty) continue;
      // 优先选择与搜索词相关度最高、或更易读的中文标题
      var bestTitle = candidates.length > 1 ? candidates[1] : candidates.first;
      var bestScore = -1.0;
      for (final c in candidates) {
        final sc = ResourceSearcher.relevance(c, matchKw);
        if (sc > bestScore) {
          bestScore = sc;
          bestTitle = c;
        }
      }
      if (bestScore <= 0 &&
          candidates.every((c) => ResourceSearcher.relevance(c, queryKw) <= 0)) {
        continue;
      }
      out.add(ResourceItem(
        site: site,
        title: bestTitle,
        url: 'https://gallibrary.pw/game.html?id=$id',
        tags: tags,
      ));
    }
    return out;
  }

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    // GAL图书馆数据库中使用半角 * 匹配符号标题（如「千恋*万花」）
    final primary = kw.replaceAll('＊', '*');
    var out = await _queryOnce(dio, primary, kw);
    if (out.isNotEmpty) return out;

    final fallback = _fallbackCoreKeyword(kw);
    if (fallback != null && fallback != primary) {
      final extra = await _queryOnce(dio, fallback, kw);
      out = extra
          .where((it) => ResourceSearcher.relevance(it.title, kw) > 0)
          .toList();
    }
    return out;
  }
}

/// TouchGal（官方元数据 API，需 Bearer token；主站有 Cloudflare 质询，
/// 因此搜索走 developer.touchgal.com，链接仍指向主站条目页）
class TouchGalResourceAdapter implements ResourceAdapter {
  static const _base = 'https://developer.touchgal.com/api/v1';
  // 与元数据刮削共用同一把官方 token（默认公开社区凭据，支持环境变量或参数覆盖）
  static const _defaultToken = 'tgal_live_nmnc-ZLyGctzGYQS7160Ruzff7UvaTcKen47wU8phkw';
  final String token;

  TouchGalResourceAdapter({String? token})
      : token = (token != null && token.trim().isNotEmpty)
            ? token.trim()
            : (Platform.environment['TOUCHGAL_TOKEN'] ?? _defaultToken);

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
          'Authorization': 'Bearer $token',
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
      final title = (m['name'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      out.add(ResourceItem(
        site: site,
        title: title,
        url: 'https://www.touchgal.ink/$uid',
        tags: tags,
      ));
    }
    return out;
  }
}

/// 量子ACG（HTML 搜索页解析，优先走最新可用域名 lzacg.cc 并兼容 lzacg.org）
class LiangZiAcgAdapter implements ResourceAdapter {
  static const _domains = ['https://lzacg.cc/', 'https://lzacg.org/'];

  @override
  String get site => '量子ACG';
  @override
  List<String> get tags => const [ResourceTag.noLogin, '自建盘'];

  Future<List<ResourceItem>> _queryOnce(Dio dio, String queryKw) async {
    Object? lastErr;
    for (final baseUrl in _domains) {
      try {
        final r = await dio.get(baseUrl,
            queryParameters: {'s': queryKw},
            options: Options(responseType: ResponseType.plain));
        final html = r.data.toString();
        final re = RegExp(
            r'<h2 class="item-heading"><a[^>]*href="([^"]+)"[^>]*>(.*?)</a></h2>',
            dotAll: true,
            caseSensitive: false);
        final out = <ResourceItem>[];
        for (final m in re.allMatches(html)) {
          final url = m.group(1)!.trim();
          final name = _cleanHtmlText(m.group(2)!);
          if (url.isEmpty || name.isEmpty) continue;
          out.add(ResourceItem(site: site, title: name, url: url, tags: tags));
          if (out.length >= 30) break;
        }
        return out;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) throw lastErr;
    return const [];
  }

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    var out = await _queryOnce(dio, kw);
    if (out.isNotEmpty) return out;

    // 量子ACG 使用精确子串匹配（如库内为「千恋＊万花」，搜「千恋万花」会 0 条），
    // 自动回退核心词前缀并用相关度过滤。
    final fallback = _fallbackCoreKeyword(kw);
    if (fallback != null && fallback != kw) {
      final extra = await _queryOnce(dio, fallback);
      out = extra
          .where((it) => ResourceSearcher.relevance(it.title, kw) > 0)
          .toList();
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

  Future<List<ResourceItem>> _queryOnce(
      Dio dio, String queryKw, String matchKw) async {
    final r = await dio.get('https://www.shinnku.com/search',
        queryParameters: {'q': queryKw},
        options: Options(responseType: ResponseType.plain));
    final html = r.data.toString();
    final re = RegExp(
        r'hover:underline"\s+href="([^"]+)"[^>]*>\s*([^<]+?)\s*</a>',
        dotAll: true,
        caseSensitive: false);
    final out = <ResourceItem>[];
    final seenUrls = <String>{};
    for (final m in re.allMatches(html)) {
      var url = m.group(1)!.trim();
      final name = _cleanHtmlText(m.group(2)!);
      if (url.isEmpty || name.isEmpty) continue;
      if (!url.startsWith('http')) url = 'https://www.shinnku.com$url';
      if (!seenUrls.add(url)) continue;
      // 真红小站在无精确命中时会返回默认热门列表，必须过滤 0 相关度噪声
      if (ResourceSearcher.relevance(name, matchKw) <= 0 &&
          ResourceSearcher.relevance(name, queryKw) <= 0) {
        continue;
      }
      out.add(ResourceItem(site: site, title: name, url: url, tags: tags));
      if (out.length >= 30) break;
    }
    return out;
  }

  @override
  Future<List<ResourceItem>> search(Dio dio, String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    var out = await _queryOnce(dio, kw, kw);
    if (out.isNotEmpty) return out;

    final fallback = _fallbackCoreKeyword(kw);
    if (fallback != null && fallback != kw) {
      out = await _queryOnce(dio, fallback, kw);
    }
    return out;
  }
}

/// 清理 HTML 标签与常见实体。
String _cleanHtmlText(String raw) {
  var s = raw.replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&#038;', '&')
      .replaceAll('&#8211;', '–')
      .replaceAll('&#8212;', '—')
      .replaceAll('&#8216;', '‘')
      .replaceAll('&#8217;', '’')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 当原关键词由于中间夹带特殊符号（如「千恋＊万花」 vs 「千恋万花」）在严格 SQL LIKE
/// 站点零命中时，提取高区分度的核心前缀词用于二次召回（随后经过 relevance 严格过滤）。
String? _fallbackCoreKeyword(String keyword) {
  final kw = keyword.trim();
  if (kw.isEmpty) return null;
  // 1) 若含分隔符（＊、*、・、-、～、：、空格等），取第一段长度 >= 2 的主标题词
  final parts = kw
      .split(RegExp(r'[\s　\-–—:：・~～＊*／/]+'))
      .map((s) => s.trim())
      .where((s) => s.length >= 2)
      .toList();
  if (parts.length >= 2) {
    return parts.first;
  }
  // 2) 若是纯中日文连续字符串且长度 >= 4（如「千恋万花」去查库里的「千恋＊万花」），
  // 取前 2 个字符做前缀召回，再由调用方按完整关键词的 relevance 过滤。
  final cjkOnly = RegExp(r'^[\u3040-\u30FF\u3400-\u9FFF]+$').hasMatch(kw);
  if (cjkOnly && kw.length >= 4) {
    return kw.substring(0, 2);
  }
  return null;
}

class ResourceSearcher {
  final Dio _dio;
  final Dio? _directDio;

  ResourceSearcher({String? proxy})
      : _dio = _buildDio(proxy: proxy),
        _directDio = (proxy != null && proxy.trim().isNotEmpty)
            ? _buildDio(proxy: null)
            : null;

  static Dio _buildDio({String? proxy}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent': 'MusaLunar/${AppInfo.name}/${AppInfo.version} '
            '(Gal Resource Search)',
      },
    ));
    if (proxy != null && proxy.trim().isNotEmpty) {
      dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy =
              (uri) => 'PROXY ${proxy.replaceFirst(RegExp(r'^https?://'), '')}';
          return client;
        };
    }
    return dio;
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

  /// 归一化：小写、去空白与装饰符号、全角转半角、常见繁简字折叠。
  static const _punct =
      " \t\r\n-_–—_・,，。.:：;；!！?？~～＊*★☆「」『』[]()（）'\"“”";

  static const _tradToSimp = <int, int>{
    0x6200: 0x604B, // 戀 -> 恋
    0x842C: 0x4E07, // 萬 -> 万
    0x6AFB: 0x6A31, // 櫻 -> 樱
    0x8A69: 0x8BD7, // 詩 -> 诗
    0x8A9E: 0x8BED, // 語 -> 语
    0x5B78: 0x5B66, // 學 -> 学
    0x5712: 0x56ED, // 園 -> 园
    0x9CE5: 0x9E1F, // 鳥 -> 鸟
    0x5CF6: 0x5C9B, // 島 -> 岛
    0x98A8: 0x98CE, // 風 -> 风
    0x96F2: 0x4E91, // 雲 -> 云
    0x611B: 0x7231, // 愛 -> 爱
    0x83EF: 0x534E, // 華 -> 华
    0x8449: 0x53F6, // 葉 -> 叶
    0x5922: 0x68A6, // 夢 -> 梦
    0x8655: 0x5904, // 處 -> 处
    0x570B: 0x56FD, // 國 -> 国
    0x6642: 0x65F6, // 時 -> 时
    0x9593: 0x95F4, // 間 -> 间
    0x84BC: 0x82CD, // 蒼 -> 苍
    0x96D9: 0x53CC, // 雙 -> 双
    0x8F2A: 0x8F6E, // 輪 -> 轮
    0x8FF4: 0x56DE, // 廻 -> 回
    0x7DE3: 0x7F18, // 緣 -> 缘
    0x9928: 0x9986, // 館 -> 馆
    0x9418: 0x949F, // 鐘 -> 钟
    0x7A62: 0x79FD, // 穢 -> 秽
  };

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
      final folded = _tradToSimp[r] ?? r;
      final c = String.fromCharCode(folded);
      if (_punct.contains(c)) continue;
      buf.write(c);
    }
    return buf.toString();
  }

  /// 判断是否为代理握手/连接层瞬态故障（可回退直连或重试）。
  static bool _isTransientNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('handshake') ||
        s.contains('connection terminated') ||
        s.contains('connection reset') ||
        s.contains('socketexception') ||
        s.contains('timed out') ||
        s.contains('timeout');
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
            // 若走代理发生 TLS 握手中断或超时，自动改用直连或重试一次
            if (_isTransientNetworkError(e)) {
              try {
                final fallbackDio = _directDio ?? _dio;
                final items = await a.search(fallbackDio, keyword);
                return ResourceSourceResult(
                    site: a.site, items: items, tags: a.tags);
              } catch (e2) {
                return ResourceSourceResult(
                    site: a.site, error: _short(e2), tags: a.tags);
              }
            }
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

  void dispose() {
    _dio.close(force: true);
    _directDio?.close(force: true);
  }
}
