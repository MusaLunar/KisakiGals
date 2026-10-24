/// 游戏探索百科聚合服务：参考 `Ph-Rank/The-Order` 的多源百科与跨媒体关联架构。
///
/// 聚合数据源：
/// 1. **NextMoe Catalog API (`https://api.nextmoe.dev/v2`)**：
///    - 作品百科主干（多语种标题、横幅 CG、高清截图、开发/发行商、引擎、系列、多站评分、外部关联 ID）
///    - 发行资料（`/v2/catalog/works/{id}/releases`：一般发行/数字版/实体版/体验版/补丁、语言、平台、引擎）
///    - 角色与声优（主角/配角/客串、立绘、CV、剧透标记）
///    - 制作人员（按职位分组：剧本、原画、人物设定、音乐、导演、企划、程序等）
///    - 相关游戏（续作、前传、FanDisc、衍生作、同世界观）
/// 2. **Bangumi API (`https://api.bgm.tv/v0`)**：
///    - 跨媒体衍生条目（`/v0/subjects/{id}/subjects`）：
///      - 动画 (`type == 2`)
///      - 音乐 (`type == 3`：原声集 OST、片头/片尾/插入曲、角色歌、广播剧)
///      - 漫画 (`type == 1` 中漫画/单行本/四格/选集)
///      - 轻小说 (`type == 1` 中轻小说/文库/设定集/视觉书)
///      - 相关游戏补充 (`type == 4`)
///    - 当 NextMoe 未收录角色/制作人员时的自动回退补充（`/characters`、`/persons`）
/// 3. **VNDB Kana API (`https://api.vndb.org/kana`)**：
///    - 补充发行版本（`/kana/release`）与跨源评分/链接。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../app_services.dart';
import '../core/constants.dart';
import '../data/models.dart';
import '../scraping/scraped_game.dart';
import 'kungal_oauth.dart';

// ============================ 数据模型 ============================

/// 多站点评分徽章数据
class ExploreSourceRating {
  final String source;
  final String label;
  final double score; // 统一折算为 10 分制便于展示，或保留展示文本
  final String displayScore;
  final int voteCount;
  final String url;

  const ExploreSourceRating({
    required this.source,
    required this.label,
    required this.score,
    required this.displayScore,
    this.voteCount = 0,
    this.url = '',
  });
}

/// 外部站点/商店/视频链接
class ExploreExternalLink {
  final String source;
  final String label;
  final String subtitle;
  final String url;
  final bool isVideo;
  final bool isStore;

  const ExploreExternalLink({
    required this.source,
    required this.label,
    this.subtitle = '',
    required this.url,
    this.isVideo = false,
    this.isStore = false,
  });
}

/// 媒体画廊截图/CG
class ExploreScreenshot {
  final String url;
  final int width;
  final int height;
  final bool nsfw;
  final String caption;

  const ExploreScreenshot({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.nsfw = false,
    this.caption = '',
  });
}

/// 发行版本资料（参考 The-Order `CatalogReleaseItemDisplayDto`）
class ExploreReleaseItem {
  final String id;
  final String title;
  final String kind; // default / digital / physical / trial / patch
  final String kindLabel; // 一般发行 / 数字发行 / 实体发行 / 体验版 / 补丁
  final String date;
  final List<String> languages; // 简体中文 / 繁体中文 / 日语 / 英语 ...
  final List<String> platforms; // Windows / Nintendo Switch / PS4 ...
  final String engine;
  final List<ExploreExternalLink> links;

  const ExploreReleaseItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.kindLabel,
    required this.date,
    this.languages = const [],
    this.platforms = const [],
    this.engine = '',
    this.links = const [],
  });
}

/// 角色与声优条目（参考 The-Order `RemoteWorkCharacterDto`）
class ExploreCharacter {
  final String id;
  final String name;
  final String originalName;
  final String role; // main / secondary / appears
  final String roleLabel; // 主角 / 配角 / 客串
  final String imageUrl;
  final List<String> voiceActors;
  final bool spoiler;
  final bool nsfw;

  const ExploreCharacter({
    required this.id,
    required this.name,
    this.originalName = '',
    required this.role,
    required this.roleLabel,
    this.imageUrl = '',
    this.voiceActors = const [],
    this.spoiler = false,
    this.nsfw = false,
  });

  String get voiceActorLine =>
      voiceActors.isEmpty ? 'CV 未公开' : 'CV ${voiceActors.join(' / ')}';
}

/// 制作人员单项
class ExploreStaffMember {
  final String id;
  final String name;
  final String originalName;
  final String note;

  const ExploreStaffMember({
    required this.id,
    required this.name,
    this.originalName = '',
    this.note = '',
  });
}

/// 制作人员按职位分组（参考 The-Order `CatalogStaffRoles`）
class ExploreCreditGroup {
  final String roleKey;
  final String roleLabel;
  final List<ExploreStaffMember> people;

  const ExploreCreditGroup({
    required this.roleKey,
    required this.roleLabel,
    required this.people,
  });
}

/// 相关游戏条目（点击后可在探索页内继续深入跳转）
class ExploreRelatedWork {
  final String id;
  final String source; // 'kun' / 'bgm' / 'vndb'
  final String title;
  final String originalTitle;
  final String relationLabel; // 续作 / 前传 / FanDisc / 衍生作品 / 相同世界观 ...
  final String groupLabel; // 续作与前传 / 衍生与番外 / 同世界观与系列 / 其他关联
  final String coverUrl;
  final String releaseDate;
  final bool nsfw;
  final String externalUrl;
  final ScrapedGame seedGame;

  const ExploreRelatedWork({
    required this.id,
    required this.source,
    required this.title,
    this.originalTitle = '',
    required this.relationLabel,
    required this.groupLabel,
    this.coverUrl = '',
    this.releaseDate = '',
    this.nsfw = false,
    this.externalUrl = '',
    required this.seedGame,
  });
}

/// 跨媒体条目（动画 / 音乐 / 漫画 / 轻小说）
class ExploreCrossMediaItem {
  final String id;
  final String category; // 'anime' | 'music' | 'manga' | 'novel'
  final String title;
  final String originalTitle;
  final String relationLabel; // 改编动画 / 原声集 / 片头曲 / 漫画 / 轻小说 ...
  final String coverUrl;
  final String date;
  final double score;
  final int voteCount;
  final String summary;
  final Map<String, String> facts; // 话数、作者、插图、艺术家、出版社、编号等
  final List<ExploreExternalLink> links;

  const ExploreCrossMediaItem({
    required this.id,
    required this.category,
    required this.title,
    this.originalTitle = '',
    required this.relationLabel,
    this.coverUrl = '',
    this.date = '',
    this.score = 0,
    this.voteCount = 0,
    this.summary = '',
    this.facts = const {},
    this.links = const [],
  });
}

/// 游戏探索页完整聚合视图模型
class ExploreWorkDetail {
  final String cacheKey;
  final ScrapedGame seedGame;
  final String nextmoeId;
  final String bangumiId;
  final String vndbId;

  final String title;
  final String originalTitle;
  final List<String> aliases;
  final String coverUrl;
  final String bannerUrl;
  final bool nsfw;

  final List<String> developers;
  final List<String> publishers;
  final String releaseDate;
  final List<String> engines;
  final List<String> series;
  final String summary;

  final List<ExploreSourceRating> ratings;
  final List<String> tags;

  // 四大百科区块
  final List<ExploreReleaseItem> releases;
  final List<ExploreCharacter> characters;
  final List<ExploreCreditGroup> credits;
  final List<ExploreRelatedWork> relatedGames;

  // 六大切换 Tab 数据（媒体 / 动画 / 音乐 / 漫画 / 轻小说 / 下载）
  final List<ExploreScreenshot> screenshots;
  final List<ExploreExternalLink> mediaLinks; // 视频 PV + 官方网站 + 商店与百科链接
  final List<ExploreCrossMediaItem> animeList;
  final List<ExploreCrossMediaItem> musicList;
  final List<ExploreCrossMediaItem> mangaList;
  final List<ExploreCrossMediaItem> novelList;

  const ExploreWorkDetail({
    required this.cacheKey,
    required this.seedGame,
    this.nextmoeId = '',
    this.bangumiId = '',
    this.vndbId = '',
    required this.title,
    this.originalTitle = '',
    this.aliases = const [],
    this.coverUrl = '',
    this.bannerUrl = '',
    this.nsfw = false,
    this.developers = const [],
    this.publishers = const [],
    this.releaseDate = '',
    this.engines = const [],
    this.series = const [],
    this.summary = '',
    this.ratings = const [],
    this.tags = const [],
    this.releases = const [],
    this.characters = const [],
    this.credits = const [],
    this.relatedGames = const [],
    this.screenshots = const [],
    this.mediaLinks = const [],
    this.animeList = const [],
    this.musicList = const [],
    this.mangaList = const [],
    this.novelList = const [],
  });

  /// 用于「下载」Tab (`ResourceLinkSection`) 的增强版 `ScrapedGame`，
  /// 注入了从 NextMoe / Bangumi / VNDB 聚合到的全部多语种标题与别名，提升资源站命中率。
  ScrapedGame get enrichedScrapedGame {
    final mergedAliases = <String>{
      ...seedGame.aliases,
      ...aliases,
      if (originalTitle.isNotEmpty) originalTitle,
      if (title.isNotEmpty) title,
    }..removeWhere((e) => e.trim().isEmpty || e == title || e == originalTitle);

    return ScrapedGame(
      source: seedGame.source.isNotEmpty
          ? seedGame.source
          : (nextmoeId.isNotEmpty
              ? KisakiSources.kun
              : (vndbId.isNotEmpty
                  ? KisakiSources.vndb
                  : KisakiSources.bangumi)),
      sourceId: seedGame.sourceId.isNotEmpty
          ? seedGame.sourceId
          : (nextmoeId.isNotEmpty
              ? nextmoeId
              : (vndbId.isNotEmpty ? vndbId : bangumiId)),
      name: originalTitle.isNotEmpty ? originalTitle : seedGame.name,
      nameCn: title.isNotEmpty ? title : seedGame.nameCn,
      aliases: mergedAliases.toList(),
      developer: developers.isNotEmpty
          ? developers.join(' / ')
          : seedGame.developer,
      releaseDate:
          releaseDate.isNotEmpty ? releaseDate : seedGame.releaseDate,
      summary: summary.isNotEmpty ? summary : seedGame.summary,
      coverUrl: coverUrl.isNotEmpty ? coverUrl : seedGame.coverUrl,
      screenshots: screenshots.isNotEmpty
          ? screenshots.map((s) => s.url).toList()
          : seedGame.screenshots,
      rating: ratings.isNotEmpty ? ratings.first.score : seedGame.rating,
      voteCount:
          ratings.isNotEmpty ? ratings.first.voteCount : seedGame.voteCount,
      nsfw: nsfw || seedGame.nsfw,
      tags: tags.isNotEmpty
          ? tags.map((t) => ScrapedTag(t)).toList()
          : seedGame.tags,
    );
  }
}

// ============================ 聚合服务实现 ============================

num? _parseNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

double _parseDouble(Object? v, [double def = 0.0]) =>
    _parseNum(v)?.toDouble() ?? def;

int _parseInt(Object? v, [int def = 0]) => _parseNum(v)?.toInt() ?? def;

bool _parseBool(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v > 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

/// 从 NextMoe / VNDB / 本地字典中安全提取多语种文本，
/// 防御性兼容：
/// 1. String：如 "秘密舞会"
/// 2. LocalizedDict Map：如 `{"zh-Hans": {"value": "秘密舞会", "is_machine": false}, "ja": ...}`
/// 3. Stringified Map（若此前被直接 .toString() 序列化）：
///    如 `{en: {value: Mimi Wuhui, is_machine: false}, ja: {value: 秘密舞会, is_machine: false}, zh-Hans: {value: 秘密舞会, is_machine: false}}`
/// 4. 任意嵌套的 value / name / text / content 结构
String _extractLocalizedText(
  dynamic raw, {
  List<String> langPriority = const [
    'zh-Hans',
    'zh-CN',
    'zh_hans',
    'zh_cn',
    'zh',
    'zh-Hant',
    'zh-TW',
    'zh-HK',
    'zh_hant',
    'zh_tw',
    'zh_hk',
    'ja',
    'japanese',
    'en',
    'english',
  ],
}) {
  if (raw == null) return '';

  if (raw is Map) {
    // 1. 若本身直接包含 value / name / text 且非多语种字典
    if (raw.containsKey('value') && raw['value'] != null) {
      final v = raw['value'];
      if (v is! Map) return '$v'.trim();
    }
    // 2. 依据语言优先级查找
    final lowerKeyMap = <String, dynamic>{};
    for (final e in raw.entries) {
      lowerKeyMap['${e.key}'.trim().toLowerCase()] = e.value;
    }
    for (final lang in langPriority) {
      final k = lang.toLowerCase();
      if (lowerKeyMap.containsKey(k)) {
        final sub = lowerKeyMap[k];
        final clean = _extractSingleLocalizedVal(sub);
        if (clean.isNotEmpty) return clean;
      }
    }
    // 3. 回退：遍历任意存在的语言项
    for (final v in raw.values) {
      final clean = _extractSingleLocalizedVal(v);
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  final str = raw.toString().trim();
  if (str.isEmpty) return '';

  // 4. 防御：如果传入的是已经 toString() 化的 Dart Map
  // 例如 `{en: {value: Mimi Wuhui, is_machine: false}, ja: {value: 秘密舞会, is_machine: false}, zh-Hans: {value: 秘密舞会, is_machine: false}}`
  if (str.startsWith('{') && str.endsWith('}')) {
    for (final lang in langPriority) {
      final escaped = RegExp.escape(lang);
      final pattern = RegExp(
        '$escaped\\s*:\\s*(?:\\{[^}]*value\\s*:\\s*([^,}]+)|[\'"]?([^\'",}]+))',
        caseSensitive: false,
      );
      final m = pattern.firstMatch(str);
      if (m != null) {
        var res = (m.group(1) ?? m.group(2) ?? '').trim();
        res = res.replaceAll('"', '').replaceAll("'", '').trim();
        if (res.isNotEmpty && res != 'null') return res;
      }
    }
    // 兜底：匹配任意 value: xxx
    final fallbackVal = RegExp(r'value\s*:\s*([^,}]+)', caseSensitive: false);
    final fm = fallbackVal.firstMatch(str);
    if (fm != null) {
      var res = (fm.group(1) ?? '').trim();
      res = res.replaceAll('"', '').replaceAll("'", '').trim();
      if (res.isNotEmpty && res != 'null') return res;
    }
  }

  return str;
}

String _extractSingleLocalizedVal(dynamic sub) {
  if (sub == null) return '';
  if (sub is String) return sub.trim();
  if (sub is Map) {
    if (sub['value'] != null) {
      final v = sub['value'];
      if (v is! Map) return '$v'.trim();
      return _extractSingleLocalizedVal(v);
    }
    if (sub['text'] != null) return '${sub['text']}'.trim();
    if (sub['name'] != null) return '${sub['name']}'.trim();
    for (final v in sub.values) {
      final c = _extractSingleLocalizedVal(v);
      if (c.isNotEmpty) return c;
    }
  }
  if (sub is num || sub is bool) return '$sub';
  return '';
}

List<String> _extractAllLocalizedTexts(dynamic raw) {
  if (raw == null) return const [];
  final out = <String>{};
  if (raw is Map) {
    for (final v in raw.values) {
      final c = _extractSingleLocalizedVal(v);
      if (c.isNotEmpty) out.add(c);
    }
  } else if (raw is String) {
    final s = raw.trim();
    if (s.startsWith('{') && s.endsWith('}')) {
      final reg = RegExp(r'value\s*:\s*([^,}]+)', caseSensitive: false);
      for (final m in reg.allMatches(s)) {
        var val = (m.group(1) ?? '').trim();
        val = val.replaceAll('"', '').replaceAll("'", '').trim();
        if (val.isNotEmpty && val != 'null') out.add(val);
      }
    } else if (s.isNotEmpty) {
      out.add(s);
    }
  }
  return out.toList();
}

class GameExploreService {
  GameExploreService._();
  static final GameExploreService instance = GameExploreService._();

  static String extractLocalizedText(
    dynamic raw, {
    List<String> langPriority = const [
      'zh-Hans',
      'zh-CN',
      'zh_hans',
      'zh_cn',
      'zh',
      'zh-Hant',
      'zh-TW',
      'zh-HK',
      'ja',
      'en',
    ],
  }) =>
      _extractLocalizedText(raw, langPriority: langPriority);

  static List<String> extractAllLocalizedTexts(dynamic raw) =>
      _extractAllLocalizedTexts(raw);

  static const _nextmoeBase = 'https://api.nextmoe.dev/v2';
  static const _bgmBase = 'https://api.bgm.tv';
  static const _vndbBase = 'https://api.vndb.org/kana';

  final Map<String, ExploreWorkDetail> _cache = {};

  Dio _buildDio() {
    String? proxy;
    try {
      proxy = AppServices.I.fetcher.proxy;
    } catch (_) {}
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      validateStatus: (_) => true,
      headers: {
        'Accept': 'application/json',
        'User-Agent':
            'MusaLunar/${AppInfo.name}/${AppInfo.version} (Explore Encyclopedia)',
      },
    ));
    if (proxy != null && proxy.trim().isNotEmpty) {
      final cleanProxy = proxy.trim().replaceFirst(RegExp(r'^https?://'), '');
      dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY $cleanProxy';
          return client;
        };
    }
    return dio;
  }

  Future<Map<String, String>?> _nextmoeAuthHeaders() async {
    try {
      final token = await KunOAuthService.instance.validAccessToken();
      if (token != null && token.isNotEmpty) {
        return {'Authorization': 'Bearer $token'};
      }
    } catch (_) {}
    return null;
  }

  /// 从本地入库游戏构造种子 `ScrapedGame` 并记载已知源 ID
  static ScrapedGame seedFromLocalGame(
    Game game,
    List<SourceRecord> sources,
  ) {
    String primarySource = KisakiSources.kun;
    String primaryId = '';
    double bestRating = game.userRating;
    int bestVotes = 0;

    for (final s in sources) {
      if (s.sourceId.isNotEmpty && primaryId.isEmpty) {
        primarySource = s.source;
        primaryId = s.sourceId;
      }
      if (s.rating > 0 && bestRating <= 0) {
        bestRating = s.rating;
        bestVotes = s.voteCount;
      }
    }

    return ScrapedGame(
      source: primarySource,
      sourceId: primaryId,
      name: game.name,
      nameCn: game.nameCn,
      aliases: game.aliases,
      developer: game.developer,
      releaseDate: game.releaseDate,
      summary: game.summary,
      coverUrl: game.coverPath.startsWith('http') ? game.coverPath : '',
      screenshots:
          game.screenshots.where((u) => u.startsWith('http')).toList(),
      rating: bestRating,
      voteCount: bestVotes,
      nsfw: game.nsfw,
    );
  }

  /// 生成缓存键
  String buildCacheKey(
    ScrapedGame seed, {
    List<SourceRecord> knownSources = const [],
  }) {
    for (final s in knownSources) {
      if (s.sourceId.isNotEmpty) {
        return '${s.source}:${s.sourceId}';
      }
    }
    if (seed.source.isNotEmpty && seed.sourceId.isNotEmpty) {
      return '${seed.source}:${seed.sourceId}';
    }
    return 'title:${seed.displayName.trim().toLowerCase()}';
  }

  ExploreWorkDetail? getCached(
    ScrapedGame seed, {
    List<SourceRecord> knownSources = const [],
  }) {
    return _cache[buildCacheKey(seed, knownSources: knownSources)];
  }

  /// 加载作品探索详情（支持强制刷新）
  Future<ExploreWorkDetail> loadWorkDetail(
    ScrapedGame seed, {
    List<SourceRecord> knownSources = const [],
    bool forceRefresh = false,
  }) async {
    final key = buildCacheKey(seed, knownSources: knownSources);
    if (!forceRefresh && _cache.containsKey(key)) {
      return _cache[key]!;
    }

    // 1. 提取初始已知的三方 ID
    String nextmoeId = '';
    String bangumiId = '';
    String vndbId = '';

    void registerSource(String src, String id) {
      final clean = id.trim();
      if (clean.isEmpty) return;
      if (src == KisakiSources.kun) {
        nextmoeId = clean;
      } else if (src == KisakiSources.bangumi) {
        bangumiId = clean;
      } else if (src == KisakiSources.vndb) {
        vndbId = clean.replaceFirst(RegExp(r'^v'), '');
      }
    }

    registerSource(seed.source, seed.sourceId);
    for (final s in knownSources) {
      registerSource(s.source, s.sourceId);
    }

    // 2. 若还没有 nextmoeId，用候选标题或已知 vndb/bgm ID 去 NextMoe 搜索匹配
    if (nextmoeId.isEmpty) {
      nextmoeId = await _resolveNextMoeId(
        seed: seed,
        vndbId: vndbId,
        bangumiId: bangumiId,
      );
    }

    // 3. 并行拉取 NextMoe 作品详情与发行列表
    Map<String, dynamic>? nextmoeWork;
    List<Map<String, dynamic>> nextmoeReleases = const [];
    if (nextmoeId.isNotEmpty) {
      final results = await Future.wait([
        _fetchNextMoeWork(nextmoeId),
        _fetchNextMoeReleases(nextmoeId),
      ]);
      nextmoeWork = results[0] as Map<String, dynamic>?;
      nextmoeReleases = results[1] as List<Map<String, dynamic>>;

      // 从 NextMoe refs 中提取关联的 bangumiId / vndbId
      final refs = nextmoeWork?['refs'];
      if (refs is List) {
        for (final r in refs.whereType<Map<String, dynamic>>()) {
          final src = '${r['source'] ?? ''}'.trim().toLowerCase();
          final extId = '${r['external_id'] ?? ''}'.trim();
          if (extId.isEmpty) continue;
          if (src == 'bangumi' && bangumiId.isEmpty) {
            bangumiId = extId;
          } else if (src == 'vndb' && vndbId.isEmpty) {
            vndbId = extId.replaceFirst(RegExp(r'^v'), '');
          }
        }
      }
    }

    // 4. 若仍无 bangumiId，通过标题去 Bangumi 搜索匹配（为了获取动画/音乐/漫画/轻小说跨媒体关联）
    if (bangumiId.isEmpty) {
      bangumiId = await _resolveBangumiId(
        seed: seed,
        nextmoeWork: nextmoeWork,
      );
    }

    // 5. 并行拉取 Bangumi 关联条目、条目详情、（按需）角色与制作人员、（按需）VNDB 补充
    final needBgmChars =
        _extractNextMoeCharacters(nextmoeWork).isEmpty && bangumiId.isNotEmpty;
    final needBgmStaff =
        _extractNextMoeCredits(nextmoeWork).isEmpty && bangumiId.isNotEmpty;
    final needVndbSupplement =
        vndbId.isNotEmpty && (nextmoeWork == null || nextmoeReleases.isEmpty);

    final bgmSubjectFuture = bangumiId.isNotEmpty
        ? _fetchBangumiSubject(bangumiId)
        : Future.value(null);
    final bgmRelationsFuture = bangumiId.isNotEmpty
        ? _fetchBangumiRelations(bangumiId)
        : Future.value(const <Map<String, dynamic>>[]);
    final bgmCharsFuture = needBgmChars
        ? _fetchBangumiCharacters(bangumiId)
        : Future.value(const <Map<String, dynamic>>[]);
    final bgmPersonsFuture = needBgmStaff
        ? _fetchBangumiPersons(bangumiId)
        : Future.value(const <Map<String, dynamic>>[]);
    final vndbWorkFuture = needVndbSupplement
        ? _fetchVndbWork(vndbId)
        : Future.value(null);
    final vndbReleasesFuture =
        (vndbId.isNotEmpty && nextmoeReleases.isEmpty)
            ? _fetchVndbReleases(vndbId)
            : Future.value(const <ExploreReleaseItem>[]);

    final bgmSubject = await bgmSubjectFuture;
    final bgmRelations = await bgmRelationsFuture;
    final bgmChars = await bgmCharsFuture;
    final bgmPersons = await bgmPersonsFuture;
    final vndbWork = await vndbWorkFuture;
    final vndbReleases = await vndbReleasesFuture;

    // 6. 解析并丰富 Bangumi 跨媒体条目（动画 type=2 / 音乐 type=3 / 书籍 type=1 区分漫画与轻小说）
    final crossMedia = await _buildCrossMediaCollections(bgmRelations);

    // 7. 组装 ExploreWorkDetail
    final detail = _assembleDetail(
      cacheKey: key,
      seed: seed,
      nextmoeId: nextmoeId,
      bangumiId: bangumiId,
      vndbId: vndbId,
      nextmoeWork: nextmoeWork,
      nextmoeReleases: nextmoeReleases,
      bgmSubject: bgmSubject,
      bgmRelations: bgmRelations,
      bgmChars: bgmChars,
      bgmPersons: bgmPersons,
      vndbWork: vndbWork,
      vndbReleases: vndbReleases,
      crossMedia: crossMedia,
    );

    if (_cache.length >= 24) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = detail;
    return detail;
  }

  // ==================== NextMoe 接口请求 ====================

  Future<String> _resolveNextMoeId({
    required ScrapedGame seed,
    required String vndbId,
    required String bangumiId,
  }) async {
    final queries = <String>[
      if (seed.nameCn.trim().isNotEmpty) seed.nameCn.trim(),
      if (seed.name.trim().isNotEmpty) seed.name.trim(),
      if (seed.displayName.trim().isNotEmpty) seed.displayName.trim(),
      for (final a in seed.aliases.take(2))
        if (a.trim().isNotEmpty) a.trim(),
    ];
    final seen = <String>{};

    final dio = _buildDio();
    final authHeaders = await _nextmoeAuthHeaders();

    for (final q in queries) {
      if (!seen.add(q)) continue;
      try {
        final res = await dio.get<Object>(
          '$_nextmoeBase/catalog/works',
          queryParameters: {
            'q': q,
            'limit': '10',
            'nsfw': 'true',
            'include': 'refs,titles',
          },
          options: Options(headers: authHeaders),
        );
        if (res.statusCode != 200 || res.data == null) continue;
        final body = res.data is String ? jsonDecode(res.data as String) : res.data;
        final items = (body is Map ? body['items'] : null);
        if (items is! List || items.isEmpty) continue;

        final candidates = items.whereType<Map<String, dynamic>>().toList();

        // 优先 1：refs 里 vndb 或 bangumi 外部 ID 精确命中
        for (final item in candidates) {
          final refs = item['refs'];
          if (refs is List) {
            for (final r in refs.whereType<Map<String, dynamic>>()) {
              final src = '${r['source'] ?? ''}'.toLowerCase();
              final extId =
                  '${r['external_id'] ?? ''}'.replaceFirst(RegExp(r'^v'), '');
              if (vndbId.isNotEmpty && src == 'vndb' && extId == vndbId) {
                return '${item['id'] ?? ''}';
              }
              if (bangumiId.isNotEmpty &&
                  src == 'bangumi' &&
                  extId == bangumiId) {
                return '${item['id'] ?? ''}';
              }
            }
          }
        }

        // 优先 2：标题或别名归一化完全一致
        final targetNorms = <String>{
          _normTitle(seed.name),
          _normTitle(seed.nameCn),
          _normTitle(seed.displayName),
          for (final a in seed.aliases) _normTitle(a),
        }..remove('');

        for (final item in candidates) {
          final itemNorms = <String>{
            _normTitle(_extractLocalizedText(item['display_name'])),
            _normTitle(_extractLocalizedText(item['localized'])),
            ..._extractAllLocalizedTexts(item['localized']).map(_normTitle),
          };
          final titles = item['titles'];
          if (titles is List) {
            for (final t in titles.whereType<Map<String, dynamic>>()) {
              final tText = _firstNonEmpty([
                _extractLocalizedText(t['title']),
                _extractLocalizedText(t['value']),
                _extractLocalizedText(t['display_name']),
              ]);
              if (tText.isNotEmpty) itemNorms.add(_normTitle(tText));
            }
          }
          itemNorms.remove('');
          if (itemNorms.any(targetNorms.contains)) {
            return '${item['id'] ?? ''}';
          }
        }

        // 优先 3：首条搜索结果包含核心词
        final first = candidates.first;
        final firstTitle =
            _normTitle(_extractLocalizedText(first['display_name']));
        final firstLoc =
            _normTitle(_extractLocalizedText(first['localized']));
        final qNorm = _normTitle(q);
        if (qNorm.length >= 2 &&
            (firstTitle.contains(qNorm) ||
                firstLoc.contains(qNorm) ||
                qNorm.contains(firstTitle) && firstTitle.length >= 2)) {
          return '${first['id'] ?? ''}';
        }
      } catch (_) {}
    }
    return '';
  }

  Future<Map<String, dynamic>?> _fetchNextMoeWork(String workId) async {
    try {
      final dio = _buildDio();
      final authHeaders = await _nextmoeAuthHeaders();
      final res = await dio.get<Object>(
        '$_nextmoeBase/catalog/works/$workId',
        queryParameters: const {
          'nsfw': 'true',
          'include':
              'titles,refs,relations,links,intros,covers,screenshots,companies,ratings,tags,characters,credits,engines,series',
        },
        options: Options(headers: authHeaders),
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final decoded =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNextMoeReleases(
    String workId,
  ) async {
    try {
      final dio = _buildDio();
      final authHeaders = await _nextmoeAuthHeaders();
      final res = await dio.get<Object>(
        '$_nextmoeBase/catalog/works/$workId/releases',
        queryParameters: const {
          'nsfw': 'true',
          'limit': '100',
        },
        options: Options(headers: authHeaders),
      );
      if (res.statusCode != 200 || res.data == null) return const [];
      final decoded =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      final items = decoded is Map ? decoded['items'] : null;
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  // ==================== Bangumi 接口请求 ====================

  Future<String> _resolveBangumiId({
    required ScrapedGame seed,
    Map<String, dynamic>? nextmoeWork,
  }) async {
    final candidates = <String>[
      if (nextmoeWork != null)
        _extractLocalizedText(nextmoeWork['display_name']),
      if (nextmoeWork != null)
        _extractLocalizedText(nextmoeWork['localized']),
      if (nextmoeWork != null)
        ..._extractAllLocalizedTexts(nextmoeWork['localized']),
      seed.name.trim(),
      seed.nameCn.trim(),
      seed.displayName.trim(),
    ];
    final seen = <String>{};
    final dio = _buildDio();

    for (final q in candidates) {
      if (q.isEmpty || !seen.add(q)) continue;
      try {
        final res = await dio.post<Object>(
          '$_bgmBase/v0/search/subjects?limit=8',
          data: {
            'keyword': q,
            'filter': {
              'type': [4],
            },
          },
        );
        if (res.statusCode != 200 || res.data == null) continue;
        final body =
            res.data is String ? jsonDecode(res.data as String) : res.data;
        final data = body is Map ? body['data'] : null;
        if (data is! List || data.isEmpty) continue;
        final list = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final targetNorms = <String>{
          for (final c in candidates) _normTitle(c),
        }..remove('');

        for (final item in list) {
          final n1 = _normTitle('${item['name'] ?? ''}');
          final n2 = _normTitle('${item['name_cn'] ?? ''}');
          if ((n1.isNotEmpty && targetNorms.contains(n1)) ||
              (n2.isNotEmpty && targetNorms.contains(n2))) {
            return '${item['id'] ?? ''}';
          }
        }
        return '${list.first['id'] ?? ''}';
      } catch (_) {}
    }
    return '';
  }

  Future<Map<String, dynamic>?> _fetchBangumiSubject(String subjectId) async {
    try {
      final dio = _buildDio();
      final res = await dio.get<Object>('$_bgmBase/v0/subjects/$subjectId');
      if (res.statusCode != 200 || res.data == null) return null;
      final decoded =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBangumiRelations(
    String subjectId,
  ) async {
    try {
      final dio = _buildDio();
      final res =
          await dio.get<Object>('$_bgmBase/v0/subjects/$subjectId/subjects');
      if (res.statusCode != 200 || res.data == null) return const [];
      final decoded =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBangumiCharacters(
    String subjectId,
  ) async {
    try {
      final dio = _buildDio();
      final res =
          await dio.get<Object>('$_bgmBase/v0/subjects/$subjectId/characters');
      if (res.statusCode != 200 || res.data == null) return const [];
      final decoded =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBangumiPersons(
    String subjectId,
  ) async {
    try {
      final dio = _buildDio();
      final res =
          await dio.get<Object>('$_bgmBase/v0/subjects/$subjectId/persons');
      if (res.statusCode != 200 || res.data == null) return const [];
      final decoded =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  // ==================== VNDB 补充接口请求 ====================

  Future<Map<String, dynamic>?> _fetchVndbWork(String vndbId) async {
    try {
      final dio = _buildDio();
      final res = await dio.post<Object>(
        '$_vndbBase/vn',
        data: {
          'filters': ['id', '=', 'v$vndbId'],
          'fields': 'id,title,alttitle,titles{lang,title,official},'
              'released,developers{name,original},description,'
              'rating,votecount,image{url,sexual},'
              'screenshots{url,sexual,dims},'
              'tags{name,rating,spoiler},'
              'relations{id,relation,relation_official,title,titles{lang,title}},'
              'staff{id,name,original,role,note},'
              'va{note,character{id,name,original,image{url,sexual}},staff{id,name,original}}',
        },
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final body =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      final results = body is Map ? body['results'] : null;
      if (results is List && results.isNotEmpty) {
        final first = results.first;
        return first is Map ? Map<String, dynamic>.from(first) : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<ExploreReleaseItem>> _fetchVndbReleases(String vndbId) async {
    try {
      final dio = _buildDio();
      final res = await dio.post<Object>(
        '$_vndbBase/release',
        data: {
          'filters': ['vn', '=', 'v$vndbId'],
          'fields':
              'id,title,alttitle,released,minage,patch,freeware,official,'
                  'languages{lang,title,main},platforms,engine,extlinks{url,label,name,id}',
          'sort': 'released',
          'results': 60,
        },
      );
      if (res.statusCode != 200 || res.data == null) return const [];
      final body =
          res.data is String ? jsonDecode(res.data as String) : res.data;
      final results = body is Map ? body['results'] : null;
      if (results is! List) return const [];

      final out = <ExploreReleaseItem>[];
      for (final r in results.whereType<Map<String, dynamic>>()) {
        final id = '${r['id'] ?? ''}';
        final title = '${r['title'] ?? ''}'.trim();
        final date = '${r['released'] ?? ''}'.trim();
        final isPatch = r['patch'] == true;
        final isTrial = r['freeware'] == true &&
            title.toLowerCase().contains('trial');
        final kind = isPatch
            ? 'patch'
            : (isTrial ? 'trial' : 'default');

        final langs = <String>[];
        final rawLangs = r['languages'];
        if (rawLangs is List) {
          for (final l in rawLangs.whereType<Map<String, dynamic>>()) {
            final label = _formatLanguageCode('${l['lang'] ?? ''}');
            if (label.isNotEmpty && !langs.contains(label)) {
              langs.add(label);
            }
          }
        }

        final platforms = <String>[];
        final rawPlats = r['platforms'];
        if (rawPlats is List) {
          for (final p in rawPlats) {
            final label = _formatPlatformCode('$p');
            if (label.isNotEmpty && !platforms.contains(label)) {
              platforms.add(label);
            }
          }
        }

        final links = <ExploreExternalLink>[
          if (id.isNotEmpty)
            ExploreExternalLink(
              source: 'vndb',
              label: 'VNDB $id',
              url: 'https://vndb.org/$id',
            ),
        ];
        final extlinks = r['extlinks'];
        if (extlinks is List) {
          for (final e in extlinks.whereType<Map<String, dynamic>>()) {
            final url = '${e['url'] ?? ''}'.trim();
            if (url.isEmpty) continue;
            links.add(ExploreExternalLink(
              source: '${e['name'] ?? 'link'}',
              label: '${e['label'] ?? e['name'] ?? '外部链接'}',
              url: url,
              isStore: true,
            ));
          }
        }

        out.add(ExploreReleaseItem(
          id: id,
          title: title.isEmpty ? '发行版本' : title,
          kind: kind,
          kindLabel: _formatReleaseKind(kind),
          date: date,
          languages: langs,
          platforms: platforms,
          engine: '${r['engine'] ?? ''}'.trim(),
          links: links,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // ==================== 跨媒体关联解析（动画 / 音乐 / 漫画 / 轻小说） ====================

  Future<_CrossMediaBundle> _buildCrossMediaCollections(
    List<Map<String, dynamic>> bgmRelations,
  ) async {
    if (bgmRelations.isEmpty) return const _CrossMediaBundle();

    // 筛选出 type = 1 (书籍: 漫画/轻小说), 2 (动画), 3 (音乐)
    final mediaRels = bgmRelations.where((r) {
      final t = r['type'];
      return t == 1 || t == 2 || t == 3;
    }).toList();

    if (mediaRels.isEmpty) return const _CrossMediaBundle();

    // 限制并发拉取详情（最多前 24 条关联跨媒体，6 并发）
    final toEnrich = mediaRels.take(24).toList();
    final detailsById = <String, Map<String, dynamic>>{};

    const batchSize = 6;
    for (var i = 0; i < toEnrich.length; i += batchSize) {
      final slice = toEnrich.skip(i).take(batchSize);
      final fetched = await Future.wait(
        slice.map((r) async {
          final id = '${r['id'] ?? ''}'.trim();
          if (id.isEmpty) return null;
          final d = await _fetchBangumiSubject(id);
          return d == null ? null : MapEntry(id, d);
        }),
      );
      for (final entry in fetched) {
        if (entry != null) {
          detailsById[entry.key] = entry.value;
        }
      }
    }

    final animeList = <ExploreCrossMediaItem>[];
    final musicList = <ExploreCrossMediaItem>[];
    final mangaList = <ExploreCrossMediaItem>[];
    final novelList = <ExploreCrossMediaItem>[];

    for (final rel in mediaRels) {
      final id = '${rel['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final type = rel['type'] as int? ?? 0;
      final relation = '${rel['relation'] ?? ''}'.trim();
      final detail = detailsById[id];

      final rawName = '${detail?['name'] ?? rel['name'] ?? ''}'.trim();
      final rawNameCn = '${detail?['name_cn'] ?? rel['name_cn'] ?? ''}'.trim();
      final title = rawNameCn.isNotEmpty ? rawNameCn : rawName;
      final originalTitle =
          (rawName.isNotEmpty && rawName != title) ? rawName : '';

      final images =
          (detail?['images'] ?? rel['images']) as Map<String, dynamic>?;
      final coverUrl =
          '${images?['large'] ?? images?['common'] ?? images?['medium'] ?? ''}'
              .trim();

      final date = '${detail?['date'] ?? ''}'.trim();
      final summary = _cleanSummary('${detail?['summary'] ?? ''}');
      final ratingMap = detail?['rating'] as Map<String, dynamic>?;
      final score = _parseDouble(ratingMap?['score']);
      final voteCount = _parseInt(ratingMap?['total']);
      final infobox = detail?['infobox'];

      if (type == 2) {
        // 动画 (Anime)
        final facts = <String, String>{};
        final eps = detail?['eps'] ?? detail?['total_episodes'];
        if (eps is int && eps > 0) {
          facts['话数'] = '$eps 话';
        }
        final platform = '${detail?['platform'] ?? ''}'.trim();
        if (platform.isNotEmpty) {
          facts['放送形式'] = platform;
        }
        _extractInfoboxFacts(infobox, facts, const [
          '话数',
          '放送开始',
          '上映年度',
          '发售日',
          '导演',
          '动画制作',
          '脚本',
          '音乐',
        ]);

        final q = Uri.encodeComponent(
            originalTitle.isNotEmpty ? originalTitle : title);
        final qCn = Uri.encodeComponent(title);
        animeList.add(ExploreCrossMediaItem(
          id: id,
          category: 'anime',
          title: title,
          originalTitle: originalTitle,
          relationLabel: relation.isEmpty ? '动画' : relation,
          coverUrl: coverUrl,
          date: date,
          score: score,
          voteCount: voteCount,
          summary: summary,
          facts: facts,
          links: [
            ExploreExternalLink(
              source: 'bangumi',
              label: 'Bangumi 番组计划',
              url: 'https://bgm.tv/subject/$id',
            ),
            ExploreExternalLink(
              source: 'bilibili',
              label: '哔哩哔哩番剧搜索',
              url: 'https://search.bilibili.com/bangumi?keyword=$qCn',
            ),
            ExploreExternalLink(
              source: 'anilist',
              label: 'AniList',
              url: 'https://anilist.co/search/anime?search=$q',
            ),
          ],
        ));
      } else if (type == 3) {
        // 音乐 (Music) —— 参考 The-Order `BangumiMusicFactsMapping`
        final facts = <String, String>{};
        _extractInfoboxFacts(infobox, facts, const [
          '艺术家',
          '作曲',
          '作词',
          '编曲',
          '厂牌',
          '发售日期',
          '价格',
          '播放时长',
          '碟片数量',
          '编号',
          '版本特性',
        ]);

        final q = Uri.encodeComponent(
            originalTitle.isNotEmpty ? originalTitle : title);
        musicList.add(ExploreCrossMediaItem(
          id: id,
          category: 'music',
          title: title,
          originalTitle: originalTitle,
          relationLabel: relation.isEmpty ? '相关音乐' : relation,
          coverUrl: coverUrl,
          date: date.isNotEmpty ? date : (facts['发售日期'] ?? ''),
          score: score,
          voteCount: voteCount,
          summary: summary,
          facts: facts,
          links: [
            ExploreExternalLink(
              source: 'bangumi',
              label: 'Bangumi 音乐条目',
              url: 'https://bgm.tv/subject/$id',
            ),
            ExploreExternalLink(
              source: 'musicbrainz',
              label: 'MusicBrainz',
              url: 'https://musicbrainz.org/search?query=$q&type=release',
            ),
            ExploreExternalLink(
              source: 'vgmdb',
              label: 'VGMdb',
              url: 'https://vgmdb.net/search?q=$q',
            ),
            ExploreExternalLink(
              source: 'netease',
              label: '网易云音乐搜索',
              url: 'https://music.163.com/#/search/m/?s=$q',
            ),
          ],
        ));
      } else if (type == 1) {
        // 书籍 (Book)：精确区分「漫画 (Manga)」与「轻小说 (Light Novel)」
        // 参考 The-Order `BangumiBookFactsMapping`
        final facts = <String, String>{};
        final platform = '${detail?['platform'] ?? ''}'.trim();
        if (platform.isNotEmpty) {
          facts['类别'] = platform;
        }
        final volumes = detail?['volumes'];
        if (volumes is int && volumes > 0) {
          facts['册数'] = '$volumes 卷';
        }
        _extractInfoboxFacts(infobox, facts, const [
          '作者',
          '作画',
          '插图',
          '原作',
          '出版社',
          '连载杂志',
          '文库',
          '发售日',
          '页数',
          '册数',
          'ISBN',
        ]);

        final isManga = _classifyBookAsManga(
          relation: relation,
          platform: platform,
          title: title,
          originalTitle: originalTitle,
          facts: facts,
        );

        final q = Uri.encodeComponent(
            originalTitle.isNotEmpty ? originalTitle : title);
        final item = ExploreCrossMediaItem(
          id: id,
          category: isManga ? 'manga' : 'novel',
          title: title,
          originalTitle: originalTitle,
          relationLabel: relation.isNotEmpty
              ? relation
              : (isManga ? '漫画' : '轻小说'),
          coverUrl: coverUrl,
          date: date.isNotEmpty ? date : (facts['发售日'] ?? ''),
          score: score,
          voteCount: voteCount,
          summary: summary,
          facts: facts,
          links: [
            ExploreExternalLink(
              source: 'bangumi',
              label: 'Bangumi 书籍条目',
              url: 'https://bgm.tv/subject/$id',
            ),
            if (isManga)
              ExploreExternalLink(
                source: 'mangadex',
                label: 'MangaDex',
                url: 'https://mangadex.org/titles?q=$q',
              ),
            ExploreExternalLink(
              source: 'bookwalker',
              label: 'BOOK☆WALKER',
              url: 'https://bookwalker.jp/search/?word=$q',
            ),
            ExploreExternalLink(
              source: 'ndl',
              label: '日本国会图书馆 NDL',
              url: 'https://ndlsearch.ndl.go.jp/search?cs=bib&keyword=$q',
            ),
          ],
        );

        if (isManga) {
          mangaList.add(item);
        } else {
          novelList.add(item);
        }
      }
    }

    return _CrossMediaBundle(
      animeList: animeList,
      musicList: musicList,
      mangaList: mangaList,
      novelList: novelList,
    );
  }

  /// 判断 Bangumi `type == 1` 书籍条目是否属于「漫画」而非「轻小说/书籍」
  bool _classifyBookAsManga({
    required String relation,
    required String platform,
    required String title,
    required String originalTitle,
    required Map<String, String> facts,
  }) {
    final combined =
        '$relation $platform $title $originalTitle'.toLowerCase();
    // 明确是小说/轻小说/画集/设定集的特征
    if (platform.contains('小说') ||
        platform.toLowerCase().contains('novel') ||
        facts.containsKey('文库') ||
        facts.containsKey('插图')) {
      if (!platform.contains('漫画') && !facts.containsKey('作画')) {
        return false;
      }
    }
    if (combined.contains('轻小说') ||
        combined.contains('小说') ||
        combined.contains('ノベル') ||
        combined.contains('文庫') ||
        combined.contains('小説')) {
      return false;
    }
    // 明确是漫画的特征
    if (platform.contains('漫画') ||
        platform.toLowerCase().contains('comic') ||
        platform.toLowerCase().contains('manga') ||
        facts.containsKey('作画') ||
        facts.containsKey('连载杂志') ||
        combined.contains('漫画') ||
        combined.contains('コミカライズ') ||
        combined.contains('コミック') ||
        combined.contains('4コマ') ||
        combined.contains('四格') ||
        combined.contains('アンソロジー') ||
        combined.contains('电击G')) {
      return true;
    }
    // 若关系写的是「画集」「设定集」「Visual Fan Book」归入轻小说/出版物
    if (combined.contains('画集') ||
        combined.contains('设定') ||
        combined.contains('fan book') ||
        combined.contains('fanbook') ||
        combined.contains('artbook') ||
        combined.contains('visual')) {
      return false;
    }
    // 默认：Bangumi 改编书籍中若无「小说/文库/画集」字样，常为单行本漫画
    return relation.contains('单行本') || relation.contains('改编');
  }

  void _extractInfoboxFacts(
    Object? rawInfobox,
    Map<String, String> out,
    List<String> keysOfInterest,
  ) {
    if (rawInfobox is! List) return;
    for (final entry in rawInfobox.whereType<Map<String, dynamic>>()) {
      final k = '${entry['key'] ?? ''}'.trim();
      if (k.isEmpty || !keysOfInterest.contains(k) || out.containsKey(k)) {
        continue;
      }
      final val = entry['value'];
      if (val is String && val.trim().isNotEmpty) {
        out[k] = val.trim();
      } else if (val is List) {
        final parts = <String>[];
        for (final item in val) {
          if (item is Map) {
            final v = '${item['v'] ?? ''}'.trim();
            if (v.isNotEmpty) parts.add(v);
          } else if (item != null) {
            final v = '$item'.trim();
            if (v.isNotEmpty) parts.add(v);
          }
        }
        if (parts.isNotEmpty) {
          out[k] = parts.join(' / ');
        }
      }
    }
  }

  // ==================== 组装 ExploreWorkDetail ====================

  ExploreWorkDetail _assembleDetail({
    required String cacheKey,
    required ScrapedGame seed,
    required String nextmoeId,
    required String bangumiId,
    required String vndbId,
    required Map<String, dynamic>? nextmoeWork,
    required List<Map<String, dynamic>> nextmoeReleases,
    required Map<String, dynamic>? bgmSubject,
    required List<Map<String, dynamic>> bgmRelations,
    required List<Map<String, dynamic>> bgmChars,
    required List<Map<String, dynamic>> bgmPersons,
    required Map<String, dynamic>? vndbWork,
    required List<ExploreReleaseItem> vndbReleases,
    required _CrossMediaBundle crossMedia,
  }) {
    // 1. 标题与多语种别名
    final nmDisplay = _extractLocalizedText(nextmoeWork?['display_name']);
    final nmLocalized = _extractLocalizedText(nextmoeWork?['localized']);
    final bgmName = '${bgmSubject?['name'] ?? ''}'.trim();
    final bgmNameCn = '${bgmSubject?['name_cn'] ?? ''}'.trim();
    final vndbTitle = '${vndbWork?['title'] ?? ''}'.trim();
    final vndbAlt = '${vndbWork?['alttitle'] ?? ''}'.trim();

    final title = _firstNonEmpty([
      nmLocalized,
      _extractLocalizedText(seed.nameCn),
      bgmNameCn,
      _extractLocalizedText(seed.displayName),
      nmDisplay,
      bgmName,
      vndbAlt,
      vndbTitle,
    ]);

    final originalTitle = _firstNonEmpty([
      _extractLocalizedText(
        nextmoeWork?['display_name'],
        langPriority: const ['ja', 'en', 'zh-Hans'],
      ),
      _extractLocalizedText(seed.name),
      bgmName,
      vndbAlt,
      vndbTitle,
    ]);

    final aliasSet = <String>{
      ...seed.aliases.map(_extractLocalizedText),
      ..._extractAllLocalizedTexts(nextmoeWork?['localized']),
      if (nmDisplay.isNotEmpty) nmDisplay,
      if (nmLocalized.isNotEmpty) nmLocalized,
      if (bgmName.isNotEmpty) bgmName,
      if (bgmNameCn.isNotEmpty) bgmNameCn,
    };
    final nmTitles = nextmoeWork?['titles'];
    if (nmTitles is List) {
      for (final t in nmTitles.whereType<Map<String, dynamic>>()) {
        final text = _firstNonEmpty([
          _extractLocalizedText(t['title']),
          _extractLocalizedText(t['value']),
          _extractLocalizedText(t['display_name']),
        ]);
        if (text.isNotEmpty) aliasSet.add(text);
      }
    }
    aliasSet.removeWhere(
        (a) => a.isEmpty || a == title || a == originalTitle);

    // 2. 封面与横幅背景 CG
    String coverUrl = '';
    final nmCovers = nextmoeWork?['covers'];
    if (nmCovers is List && nmCovers.isNotEmpty) {
      final firstCover = nmCovers.first;
      if (firstCover is Map<String, dynamic>) {
        coverUrl = '${firstCover['url'] ?? ''}'.trim();
      }
    }
    if (coverUrl.isEmpty) {
      final bgmImages = bgmSubject?['images'] as Map<String, dynamic>?;
      coverUrl = _firstNonEmpty([
        seed.coverUrl,
        '${bgmImages?['large'] ?? bgmImages?['common'] ?? ''}',
        '${(vndbWork?['image'] as Map?)?['url'] ?? ''}',
      ]);
    }

    final screenshots = _extractScreenshots(
      nextmoeWork: nextmoeWork,
      vndbWork: vndbWork,
      seed: seed,
    );

    final nmBanner = nextmoeWork?['banner'] as Map<String, dynamic>?;
    final bannerUrl = _firstNonEmpty([
      '${nmBanner?['url'] ?? ''}',
      if (screenshots.isNotEmpty) screenshots.first.url,
      coverUrl,
    ]);

    // 3. 开发商 / 发行商 / 发售日 / 引擎 / 系列 / 简介
    final developers = <String>[];
    final publishers = <String>[];
    final nmCompanies = nextmoeWork?['companies'];
    if (nmCompanies is List) {
      for (final c in nmCompanies.whereType<Map<String, dynamic>>()) {
        final name = _firstNonEmpty([
          _extractLocalizedText(c['localized']),
          _extractLocalizedText(c['display_name']),
        ]);
        if (name.isEmpty) continue;
        final role = '${c['attribution_role'] ?? ''}'.toLowerCase();
        if (role == 'publisher') {
          if (!publishers.contains(name)) publishers.add(name);
        } else {
          if (!developers.contains(name)) developers.add(name);
        }
      }
    }
    if (developers.isEmpty && seed.developer.trim().isNotEmpty) {
      developers.add(_extractLocalizedText(seed.developer.trim()));
    }

    final releaseDate = _firstNonEmpty([
      '${nextmoeWork?['released_at'] ?? ''}',
      seed.releaseDate,
      '${bgmSubject?['date'] ?? ''}',
      '${vndbWork?['released'] ?? ''}',
    ]);

    final engines = <String>[];
    final nmEngines = nextmoeWork?['engines'];
    if (nmEngines is List) {
      for (final e in nmEngines.whereType<Map<String, dynamic>>()) {
        final n = _firstNonEmpty([
          _extractLocalizedText(e['localized']),
          _extractLocalizedText(e['display_name']),
        ]);
        if (n.isNotEmpty && !engines.contains(n)) engines.add(n);
      }
    }

    final series = <String>[];
    final nmSeries = nextmoeWork?['series'];
    if (nmSeries is List) {
      for (final s in nmSeries.whereType<Map<String, dynamic>>()) {
        final n = _firstNonEmpty([
          _extractLocalizedText(s['localized']),
          _extractLocalizedText(s['display_name']),
        ]);
        if (n.isNotEmpty && !series.contains(n)) series.add(n);
      }
    }

    String summary = '';
    final nmIntros = nextmoeWork?['intros'];
    if (nmIntros is List && nmIntros.isNotEmpty) {
      for (final intro in nmIntros.whereType<Map<String, dynamic>>()) {
        final body = _extractLocalizedText(intro['body']);
        if (body.isNotEmpty) {
          summary = body;
          break;
        }
      }
    }
    if (summary.isEmpty) {
      summary = _firstNonEmpty([
        _extractLocalizedText(seed.summary),
        _cleanSummary('${bgmSubject?['summary'] ?? ''}'),
        _cleanSummary('${vndbWork?['description'] ?? ''}'),
      ]);
    }

    // 4. 多站点评分聚合（参考 The-Order `RemoteWorkRatingDto`）
    final ratings = _extractRatings(
      nextmoeWork: nextmoeWork,
      bgmSubject: bgmSubject,
      vndbWork: vndbWork,
      seed: seed,
      nextmoeId: nextmoeId,
      bangumiId: bangumiId,
      vndbId: vndbId,
    );

    // 5. 标签聚合
    final tags = _extractTags(
      nextmoeWork: nextmoeWork,
      bgmSubject: bgmSubject,
      vndbWork: vndbWork,
      seed: seed,
    );

    // 6. 发行版本资料（NextMoe Releases -> VNDB Releases 回退）
    final releases = nextmoeReleases.isNotEmpty
        ? _mapNextMoeReleases(nextmoeReleases)
        : vndbReleases;

    // 7. 角色与声优（NextMoe -> Bangumi -> VNDB 回退）
    var characters = _extractNextMoeCharacters(nextmoeWork);
    if (characters.isEmpty && bgmChars.isNotEmpty) {
      characters = _mapBangumiCharacters(bgmChars);
    }
    if (characters.isEmpty && vndbWork != null) {
      characters = _mapVndbCharacters(vndbWork);
    }

    // 8. 制作人员（NextMoe -> Bangumi -> VNDB 回退）
    var credits = _extractNextMoeCredits(nextmoeWork);
    if (credits.isEmpty && bgmPersons.isNotEmpty) {
      credits = _mapBangumiPersons(bgmPersons);
    }
    if (credits.isEmpty && vndbWork != null) {
      credits = _mapVndbStaff(vndbWork);
    }

    // 9. 相关游戏（合并 NextMoe relations 与 Bangumi type=4 游戏关联）
    final relatedGames = _extractRelatedGames(
      nextmoeWork: nextmoeWork,
      bgmRelations: bgmRelations,
      vndbWork: vndbWork,
    );

    // 10. 媒体与外部百科/商店/PV链接
    final mediaLinks = _extractMediaAndStoreLinks(
      title: title,
      originalTitle: originalTitle,
      nextmoeId: nextmoeId,
      bangumiId: bangumiId,
      vndbId: vndbId,
      nextmoeWork: nextmoeWork,
    );

    final nsfw = seed.nsfw ||
        (bgmSubject?['nsfw'] == true) ||
        (nmBanner?['sexual'] == true);

    return ExploreWorkDetail(
      cacheKey: cacheKey,
      seedGame: seed,
      nextmoeId: nextmoeId,
      bangumiId: bangumiId,
      vndbId: vndbId,
      title: title.isEmpty ? seed.displayName : title,
      originalTitle:
          originalTitle == title ? '' : originalTitle,
      aliases: aliasSet.take(16).toList(),
      coverUrl: coverUrl,
      bannerUrl: bannerUrl,
      nsfw: nsfw,
      developers: developers,
      publishers: publishers,
      releaseDate: releaseDate,
      engines: engines,
      series: series,
      summary: summary,
      ratings: ratings,
      tags: tags,
      releases: releases,
      characters: characters,
      credits: credits,
      relatedGames: relatedGames,
      screenshots: screenshots,
      mediaLinks: mediaLinks,
      animeList: crossMedia.animeList,
      musicList: crossMedia.musicList,
      mangaList: crossMedia.mangaList,
      novelList: crossMedia.novelList,
    );
  }

  // ==================== 细分字段转换工具 ====================

  List<ExploreScreenshot> _extractScreenshots({
    required Map<String, dynamic>? nextmoeWork,
    required Map<String, dynamic>? vndbWork,
    required ScrapedGame seed,
  }) {
    final out = <ExploreScreenshot>[];
    final seen = <String>{};

    final nmShots = nextmoeWork?['screenshots'];
    if (nmShots is List) {
      for (final s in nmShots.whereType<Map<String, dynamic>>()) {
        final url = '${s['url'] ?? ''}'.trim();
        if (url.isEmpty || !seen.add(url)) continue;
        out.add(ExploreScreenshot(
          url: url,
          width: _parseInt(s['width']),
          height: _parseInt(s['height']),
          nsfw: _parseBool(s['sexual']),
          caption: '${s['caption'] ?? ''}'.trim(),
        ));
      }
    }

    final vndbShots = vndbWork?['screenshots'];
    if (vndbShots is List) {
      for (final s in vndbShots.whereType<Map<String, dynamic>>()) {
        final url = '${s['url'] ?? ''}'.trim();
        if (url.isEmpty || !seen.add(url)) continue;
        final dims = s['dims'];
        out.add(ExploreScreenshot(
          url: url,
          width: (dims is List && dims.isNotEmpty)
              ? _parseInt(dims[0])
              : 0,
          height: (dims is List && dims.length > 1)
              ? _parseInt(dims[1])
              : 0,
          nsfw: _parseDouble(s['sexual']) >= 1.0,
        ));
      }
    }

    for (final url in seed.screenshots) {
      final clean = url.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      out.add(ExploreScreenshot(url: clean, nsfw: seed.nsfw));
    }

    return out;
  }

  List<ExploreSourceRating> _extractRatings({
    required Map<String, dynamic>? nextmoeWork,
    required Map<String, dynamic>? bgmSubject,
    required Map<String, dynamic>? vndbWork,
    required ScrapedGame seed,
    required String nextmoeId,
    required String bangumiId,
    required String vndbId,
  }) {
    final out = <ExploreSourceRating>[];
    final seenSources = <String>{};

    // 提取外部链接映射
    final refIds = <String, String>{
      if (nextmoeId.isNotEmpty) 'nextmoe': nextmoeId,
      if (bangumiId.isNotEmpty) 'bangumi': bangumiId,
      if (vndbId.isNotEmpty) 'vndb': vndbId,
    };
    final nmRefs = nextmoeWork?['refs'];
    if (nmRefs is List) {
      for (final r in nmRefs.whereType<Map<String, dynamic>>()) {
        final s = '${r['source'] ?? ''}'.toLowerCase();
        final id = '${r['external_id'] ?? ''}'.trim();
        if (s.isNotEmpty && id.isNotEmpty) refIds[s] = id;
      }
    }

    final nmRatings = nextmoeWork?['ratings'];
    if (nmRatings is List) {
      for (final r in nmRatings.whereType<Map<String, dynamic>>()) {
        final src = '${r['source'] ?? ''}'.trim().toLowerCase();
        final rawScore = _parseDouble(r['score']);
        final votes = _parseInt(r['vote_count']);
        if (src.isEmpty || rawScore <= 0) continue;
        // howlongtobeat 存的是游玩时长而非评分，跳过评分芯片
        if (src == 'howlongtobeat') continue;

        double score10 = rawScore;
        String display = rawScore.toStringAsFixed(1);
        if (src == 'vndb' || src == 'erogamescape') {
          if (rawScore > 10) {
            score10 = rawScore / 10.0;
            display = score10.toStringAsFixed(2);
          }
        } else if (src == 'dlsite' && rawScore <= 5.0) {
          score10 = rawScore * 2.0;
          display = '${rawScore.toStringAsFixed(1)} / 5';
        }

        final label = switch (src) {
          'nextmoe' || 'kun' => '鲲Gal',
          'vndb' => 'VNDB',
          'bangumi' => 'Bangumi',
          'erogamescape' => '批评空间',
          'dlsite' => 'DLsite',
          'steam' => 'Steam',
          _ => src.toUpperCase(),
        };

        seenSources.add(src == 'nextmoe' ? 'kun' : src);
        out.add(ExploreSourceRating(
          source: src == 'nextmoe' ? 'kun' : src,
          label: label,
          score: score10,
          displayScore: display,
          voteCount: votes,
          url: _buildRefUrl(src, refIds[src] ?? ''),
        ));
      }
    }

    // 补充 Bangumi 评分
    if (!seenSources.contains('bangumi') && bgmSubject != null) {
      final ratingMap = bgmSubject['rating'] as Map<String, dynamic>?;
      final s = _parseDouble(ratingMap?['score']);
      final v = _parseInt(ratingMap?['total']);
      if (s > 0) {
        seenSources.add('bangumi');
        out.add(ExploreSourceRating(
          source: 'bangumi',
          label: 'Bangumi',
          score: s,
          displayScore: s.toStringAsFixed(1),
          voteCount: v,
          url: bangumiId.isNotEmpty
              ? 'https://bgm.tv/subject/$bangumiId'
              : '',
        ));
      }
    }

    // 补充 VNDB 评分
    if (!seenSources.contains('vndb') && vndbWork != null) {
      final raw = _parseDouble(vndbWork['rating']);
      final v = _parseInt(vndbWork['votecount']);
      if (raw > 0) {
        final s10 = raw > 10 ? raw / 10.0 : raw;
        seenSources.add('vndb');
        out.add(ExploreSourceRating(
          source: 'vndb',
          label: 'VNDB',
          score: s10,
          displayScore: s10.toStringAsFixed(2),
          voteCount: v,
          url: vndbId.isNotEmpty ? 'https://vndb.org/v$vndbId' : '',
        ));
      }
    }

    // 兜底种子评分
    if (out.isEmpty && seed.rating > 0) {
      final label = KisakiSources.labels[seed.source] ?? seed.source;
      out.add(ExploreSourceRating(
        source: seed.source,
        label: label,
        score: seed.rating,
        displayScore: seed.rating.toStringAsFixed(1),
        voteCount: seed.voteCount,
      ));
    }

    return out;
  }

  List<String> _extractTags({
    required Map<String, dynamic>? nextmoeWork,
    required Map<String, dynamic>? bgmSubject,
    required Map<String, dynamic>? vndbWork,
    required ScrapedGame seed,
  }) {
    final out = <String>[];
    final seen = <String>{};

    void addTag(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty || !seen.add(clean.toLowerCase())) return;
      out.add(clean);
    }

    final nmTags = nextmoeWork?['tags'];
    if (nmTags is List) {
      for (final t in nmTags.whereType<Map<String, dynamic>>()) {
        addTag(_firstNonEmpty([
          _extractLocalizedText(t['localized']),
          _extractLocalizedText(t['display_name']),
        ]));
      }
    }

    final bgmTags = bgmSubject?['tags'];
    if (bgmTags is List) {
      for (final t in bgmTags.whereType<Map<String, dynamic>>()) {
        addTag('${t['name'] ?? ''}');
      }
    }

    for (final t in seed.tags) {
      addTag(t.name);
    }

    return out.take(36).toList();
  }

  /// 参考 The-Order `NextMoeCatalog.ReleasesDisplay.cs` & `CatalogReleases.cs`
  List<ExploreReleaseItem> _mapNextMoeReleases(
    List<Map<String, dynamic>> rawList,
  ) {
    final out = <ExploreReleaseItem>[];
    for (final r in rawList) {
      final id = '${r['id'] ?? ''}'.trim();
      final title = _firstNonEmpty([
        _extractLocalizedText(r['title']),
        _extractLocalizedText(r['name']),
      ]);
      final kind = '${r['release_kind'] ?? 'default'}'.trim().toLowerCase();
      final date = '${r['date'] ?? ''}'.trim();

      // 语言解析（支持逗号/斜杠分隔的多个语言代码）
      final languages = <String>[];
      final rawLang = '${r['lang'] ?? ''}'.trim();
      if (rawLang.isNotEmpty) {
        for (final part in rawLang.split(RegExp(r'[,;/|\s]+'))) {
          final formatted = _formatLanguageCode(part);
          if (formatted.isNotEmpty && !languages.contains(formatted)) {
            languages.add(formatted);
          }
        }
      }

      // 平台解析（支持 `platforms` 数组 + `platform` 字段）
      final platforms = <String>[];
      final rawPlats = r['platforms'];
      if (rawPlats is List) {
        for (final p in rawPlats) {
          final formatted = _formatPlatformCode('$p');
          if (formatted.isNotEmpty && !platforms.contains(formatted)) {
            platforms.add(formatted);
          }
        }
      }
      final singlePlat = _formatPlatformCode('${r['platform'] ?? ''}');
      if (singlePlat.isNotEmpty && !platforms.contains(singlePlat)) {
        platforms.add(singlePlat);
      }

      // 引擎
      String engine = '';
      final rawEngine = r['engine'];
      if (rawEngine is Map<String, dynamic>) {
        engine = _firstNonEmpty([
          _extractLocalizedText(rawEngine['localized']),
          _extractLocalizedText(rawEngine['display_name']),
        ]);
      }

      // 外部版本引用链接
      final links = <ExploreExternalLink>[];
      final refs = r['refs'];
      if (refs is List) {
        for (final ref in refs.whereType<Map<String, dynamic>>()) {
          final src = '${ref['source'] ?? ''}'.trim().toLowerCase();
          final extId = '${ref['external_id'] ?? ''}'.trim();
          final url = _buildReleaseRefUrl(src, extId);
          if (url.isEmpty) continue;
          links.add(ExploreExternalLink(
            source: src,
            label: _formatRefSourceLabel(src, extId),
            url: url,
            isStore: src == 'steam' || src == 'dlsite' || src == 'getchu',
          ));
        }
      }

      out.add(ExploreReleaseItem(
        id: id,
        title: title.isEmpty ? '发行版本' : title,
        kind: kind,
        kindLabel: _formatReleaseKind(kind),
        date: date,
        languages: languages,
        platforms: platforms,
        engine: engine,
        links: links,
      ));
    }

    // 按发售日期升序排列（空日期置后）
    out.sort((a, b) {
      if (a.date.isEmpty && b.date.isEmpty) return 0;
      if (a.date.isEmpty) return 1;
      if (b.date.isEmpty) return -1;
      return a.date.compareTo(b.date);
    });
    return out;
  }

  List<ExploreCharacter> _extractNextMoeCharacters(
    Map<String, dynamic>? nextmoeWork,
  ) {
    final rawChars = nextmoeWork?['characters'];
    if (rawChars is! List || rawChars.isEmpty) return const [];

    final out = <ExploreCharacter>[];
    for (final c in rawChars.whereType<Map<String, dynamic>>()) {
      final id = '${c['id'] ?? ''}'.trim();
      final display = _extractLocalizedText(c['display_name']);
      final localized = _extractLocalizedText(c['localized']);
      final name = localized.isNotEmpty ? localized : display;
      if (name.isEmpty) continue;
      final originalName = (display.isNotEmpty && display != name)
          ? display
          : '';
      final role = '${c['roster_role'] ?? 'secondary'}'.toLowerCase();
      final roleLabel = switch (role) {
        'main' || 'protagonist' => '主角',
        'secondary' || 'side' => '配角',
        'appears' || 'cameo' => '客串',
        _ => '角色',
      };
      final imageMap = c['image'] as Map<String, dynamic>?;
      final imageUrl = '${imageMap?['url'] ?? ''}'.trim();
      final sexual = _parseBool(imageMap?['sexual']);
      final spoiler = _parseBool(c['spoiler']);

      final cvs = <String>[];
      final voices = c['voices'];
      if (voices is List) {
        for (final v in voices.whereType<Map<String, dynamic>>()) {
          final cvName = _firstNonEmpty([
            _extractLocalizedText(v['localized']),
            _extractLocalizedText(v['display_name']),
          ]);
          if (cvName.isNotEmpty && !cvs.contains(cvName)) {
            cvs.add(cvName);
          }
        }
      }

      out.add(ExploreCharacter(
        id: id,
        name: name,
        originalName: originalName,
        role: role,
        roleLabel: roleLabel,
        imageUrl: imageUrl,
        voiceActors: cvs,
        spoiler: spoiler,
        nsfw: sexual,
      ));
    }

    // 排序：主角 -> 配角 -> 客串，带立绘优先
    int roleRank(String r) => switch (r) {
          'main' || 'protagonist' => 0,
          'secondary' || 'side' => 1,
          _ => 2,
        };
    out.sort((a, b) {
      final rr = roleRank(a.role).compareTo(roleRank(b.role));
      if (rr != 0) return rr;
      final aHasImg = a.imageUrl.isNotEmpty ? 0 : 1;
      final bHasImg = b.imageUrl.isNotEmpty ? 0 : 1;
      return aHasImg.compareTo(bHasImg);
    });
    return out;
  }

  List<ExploreCharacter> _mapBangumiCharacters(
    List<Map<String, dynamic>> bgmChars,
  ) {
    final out = <ExploreCharacter>[];
    for (final c in bgmChars) {
      final id = '${c['id'] ?? ''}';
      final name = '${c['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final rel = '${c['relation'] ?? '角色'}'.trim();
      final role = rel.contains('主角')
          ? 'main'
          : (rel.contains('配角') ? 'secondary' : 'appears');
      final images = c['images'] as Map<String, dynamic>?;
      final imageUrl =
          '${images?['medium'] ?? images?['large'] ?? images?['grid'] ?? ''}'
              .trim();
      final cvs = <String>[];
      final actors = c['actors'];
      if (actors is List) {
        for (final a in actors.whereType<Map<String, dynamic>>()) {
          final n = '${a['name'] ?? ''}'.trim();
          if (n.isNotEmpty && !cvs.contains(n)) cvs.add(n);
        }
      }
      out.add(ExploreCharacter(
        id: id,
        name: name,
        role: role,
        roleLabel: rel.isEmpty ? '角色' : rel,
        imageUrl: imageUrl,
        voiceActors: cvs,
      ));
    }
    return out;
  }

  List<ExploreCharacter> _mapVndbCharacters(Map<String, dynamic> vndbWork) {
    final vaList = vndbWork['va'];
    if (vaList is! List || vaList.isEmpty) return const [];
    final byCharId = <String, ExploreCharacter>{};
    for (final entry in vaList.whereType<Map<String, dynamic>>()) {
      final charMap = entry['character'] as Map<String, dynamic>?;
      if (charMap == null) continue;
      final cid = '${charMap['id'] ?? ''}';
      if (cid.isEmpty) continue;
      final name = _firstNonEmpty([
        '${charMap['original'] ?? ''}',
        '${charMap['name'] ?? ''}',
      ]);
      if (name.isEmpty) continue;
      final imgMap = charMap['image'] as Map<String, dynamic>?;
      final imgUrl = '${imgMap?['url'] ?? ''}'.trim();
      final staffMap = entry['staff'] as Map<String, dynamic>?;
      final cvName = _firstNonEmpty([
        '${staffMap?['original'] ?? ''}',
        '${staffMap?['name'] ?? ''}',
      ]);

      final existing = byCharId[cid];
      final cvs = <String>[
        ...?existing?.voiceActors,
        if (cvName.isNotEmpty &&
            !(existing?.voiceActors.contains(cvName) ?? false))
          cvName,
      ];
      byCharId[cid] = ExploreCharacter(
        id: cid,
        name: name,
        originalName: '${charMap['name'] ?? ''}',
        role: 'main',
        roleLabel: '登场角色',
        imageUrl: imgUrl,
        voiceActors: cvs,
      );
    }
    return byCharId.values.toList();
  }

  /// 参考 The-Order `CatalogStaffRoles` & `catalog-staff-roles.json`
  List<ExploreCreditGroup> _extractNextMoeCredits(
    Map<String, dynamic>? nextmoeWork,
  ) {
    final rawCredits = nextmoeWork?['credits'];
    if (rawCredits is! List || rawCredits.isEmpty) return const [];

    final grouped = <String, List<ExploreStaffMember>>{};
    final roleKeyByLabel = <String, String>{};

    for (final g in rawCredits.whereType<Map<String, dynamic>>()) {
      final roleKey = '${g['role_key'] ?? ''}'.trim();
      final roleName = '${g['role_name'] ?? ''}'.trim();
      final label = _translateStaffRole(
        roleKey.isNotEmpty ? roleKey : roleName,
      );
      roleKeyByLabel.putIfAbsent(label, () => roleKey);

      final list = grouped.putIfAbsent(label, () => <ExploreStaffMember>[]);
      final people = g['credits'];
      if (people is List) {
        for (final p in people.whereType<Map<String, dynamic>>()) {
          final id = '${p['id'] ?? ''}';
          final display = _extractLocalizedText(p['display_name']);
          final localized = _extractLocalizedText(p['localized']);
          final name = localized.isNotEmpty ? localized : display;
          if (name.isEmpty) continue;
          if (list.any((e) => e.name == name)) continue;
          list.add(ExploreStaffMember(
            id: id,
            name: name,
            originalName: display != name ? display : '',
          ));
        }
      }
    }

    return grouped.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => ExploreCreditGroup(
              roleKey: roleKeyByLabel[e.key] ?? e.key,
              roleLabel: e.key,
              people: e.value,
            ))
        .toList();
  }

  List<ExploreCreditGroup> _mapBangumiPersons(
    List<Map<String, dynamic>> bgmPersons,
  ) {
    final grouped = <String, List<ExploreStaffMember>>{};
    for (final p in bgmPersons) {
      final id = '${p['id'] ?? ''}';
      final name = '${p['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final rel = _translateStaffRole('${p['relation'] ?? '制作人员'}');
      final list = grouped.putIfAbsent(rel, () => <ExploreStaffMember>[]);
      if (list.any((e) => e.name == name)) continue;
      list.add(ExploreStaffMember(id: id, name: name));
    }
    return grouped.entries
        .map((e) => ExploreCreditGroup(
              roleKey: e.key,
              roleLabel: e.key,
              people: e.value,
            ))
        .toList();
  }

  List<ExploreCreditGroup> _mapVndbStaff(Map<String, dynamic> vndbWork) {
    final rawStaff = vndbWork['staff'];
    if (rawStaff is! List || rawStaff.isEmpty) return const [];
    final grouped = <String, List<ExploreStaffMember>>{};
    for (final s in rawStaff.whereType<Map<String, dynamic>>()) {
      final id = '${s['id'] ?? ''}';
      final name = _firstNonEmpty([
        '${s['original'] ?? ''}',
        '${s['name'] ?? ''}',
      ]);
      if (name.isEmpty) continue;
      final roleLabel = _translateStaffRole('${s['role'] ?? 'staff'}');
      final list = grouped.putIfAbsent(roleLabel, () => <ExploreStaffMember>[]);
      if (list.any((e) => e.name == name)) continue;
      list.add(ExploreStaffMember(
        id: id,
        name: name,
        originalName: '${s['name'] ?? ''}',
        note: '${s['note'] ?? ''}'.trim(),
      ));
    }
    return grouped.entries
        .map((e) => ExploreCreditGroup(
              roleKey: e.key,
              roleLabel: e.key,
              people: e.value,
            ))
        .toList();
  }

  /// 提取相关游戏（参考 The-Order `RelatedWorksProjection.cs`）
  List<ExploreRelatedWork> _extractRelatedGames({
    required Map<String, dynamic>? nextmoeWork,
    required List<Map<String, dynamic>> bgmRelations,
    required Map<String, dynamic>? vndbWork,
  }) {
    final out = <ExploreRelatedWork>[];
    final seenTitles = <String>{};

    // 1. NextMoe relations (优先：带 claim/id 可以直接跳转到 NextMoe 百科)
    final nmRels = nextmoeWork?['relations'];
    if (nmRels is List) {
      for (final rel in nmRels.whereType<Map<String, dynamic>>()) {
        final work = rel['work'] as Map<String, dynamic>?;
        if (work == null) continue;
        final medium = '${work['medium'] ?? 'game'}'.toLowerCase();
        if (medium.isNotEmpty && medium != 'game' && medium != 'vn') continue;

        final workId = '${work['id'] ?? ''}'.trim();
        final display = _extractLocalizedText(work['display_name']);
        final localized = _extractLocalizedText(work['localized']);
        final title = localized.isNotEmpty ? localized : display;
        if (title.isEmpty) continue;

        final norm = _normTitle(title);
        if (norm.isNotEmpty && !seenTitles.add(norm)) continue;
        if (display.isNotEmpty) seenTitles.add(_normTitle(display));

        final relType = '${rel['relation_type'] ?? ''}'.trim();
        final phrase = '${rel['phrase'] ?? ''}'.trim();
        final (relLabel, groupLabel) = _formatGameRelation(relType, phrase);

        final coverMap = work['cover'] as Map<String, dynamic>?;
        final coverUrl = '${coverMap?['url'] ?? ''}'.trim();
        final nsfw = coverMap?['sexual'] == true;

        final seed = ScrapedGame(
          source: KisakiSources.kun,
          sourceId: workId,
          name: display.isNotEmpty ? display : title,
          nameCn: localized,
          coverUrl: coverUrl,
          nsfw: nsfw,
        );

        out.add(ExploreRelatedWork(
          id: workId,
          source: KisakiSources.kun,
          title: title,
          originalTitle: display != title ? display : '',
          relationLabel: relLabel,
          groupLabel: groupLabel,
          coverUrl: coverUrl,
          nsfw: nsfw,
          externalUrl: workId.isNotEmpty
              ? 'https://www.kungal.com/zh-cn/galgame/$workId'
              : '',
          seedGame: seed,
        ));
      }
    }

    // 2. Bangumi type == 4 (游戏关联补充)
    for (final rel in bgmRelations) {
      if (rel['type'] != 4) continue;
      final bgmId = '${rel['id'] ?? ''}'.trim();
      final name = '${rel['name'] ?? ''}'.trim();
      final nameCn = '${rel['name_cn'] ?? ''}'.trim();
      final title = nameCn.isNotEmpty ? nameCn : name;
      if (title.isEmpty) continue;

      final norm1 = _normTitle(title);
      final norm2 = _normTitle(name);
      if ((norm1.isNotEmpty && seenTitles.contains(norm1)) ||
          (norm2.isNotEmpty && seenTitles.contains(norm2))) {
        continue;
      }
      if (norm1.isNotEmpty) seenTitles.add(norm1);
      if (norm2.isNotEmpty) seenTitles.add(norm2);

      final rawRelation = '${rel['relation'] ?? '相关游戏'}'.trim();
      final (relLabel, groupLabel) = _formatGameRelation(rawRelation, '');
      final images = rel['images'] as Map<String, dynamic>?;
      final coverUrl =
          '${images?['large'] ?? images?['common'] ?? images?['medium'] ?? ''}'
              .trim();

      final seed = ScrapedGame(
        source: KisakiSources.bangumi,
        sourceId: bgmId,
        name: name.isNotEmpty ? name : title,
        nameCn: nameCn,
        coverUrl: coverUrl,
      );

      out.add(ExploreRelatedWork(
        id: bgmId,
        source: KisakiSources.bangumi,
        title: title,
        originalTitle: name != title ? name : '',
        relationLabel: relLabel,
        groupLabel: groupLabel,
        coverUrl: coverUrl,
        externalUrl:
            bgmId.isNotEmpty ? 'https://bgm.tv/subject/$bgmId' : '',
        seedGame: seed,
      ));
    }

    return out;
  }

  List<ExploreExternalLink> _extractMediaAndStoreLinks({
    required String title,
    required String originalTitle,
    required String nextmoeId,
    required String bangumiId,
    required String vndbId,
    required Map<String, dynamic>? nextmoeWork,
  }) {
    final links = <ExploreExternalLink>[];
    final seenUrls = <String>{};

    void addLink(ExploreExternalLink link) {
      if (link.url.isEmpty || !seenUrls.add(link.url)) return;
      links.add(link);
    }

    // 1. 宣传视频 PV 搜索入口（Bilibili / YouTube）
    final searchName =
        originalTitle.isNotEmpty ? originalTitle : title;
    if (searchName.isNotEmpty) {
      final qPv = Uri.encodeComponent('$searchName OP PV');
      final qCnPv = Uri.encodeComponent('$title PV OP 宣传片');
      addLink(ExploreExternalLink(
        source: 'bilibili_pv',
        label: '哔哩哔哩 · 宣传 PV / OP 检索',
        subtitle: '在 Bilibili 观看「$title」的开场动画与宣传片',
        url: 'https://search.bilibili.com/all?keyword=$qCnPv',
        isVideo: true,
      ));
      addLink(ExploreExternalLink(
        source: 'youtube_pv',
        label: 'YouTube · 官方 PV / OP 检索',
        subtitle: '在 YouTube 检索「$searchName」的官方宣传映像',
        url: 'https://www.youtube.com/results?search_query=$qPv',
        isVideo: true,
      ));
    }

    // 2. NextMoe links (官方网站等)
    final nmLinks = nextmoeWork?['links'];
    if (nmLinks is List) {
      for (final l in nmLinks.whereType<Map<String, dynamic>>()) {
        final src = '${l['source'] ?? ''}'.trim();
        final url = '${l['url'] ?? ''}'.trim();
        if (url.isEmpty) continue;
        final isVideo = url.contains('youtube.com') ||
            url.contains('youtu.be') ||
            url.contains('bilibili.com') ||
            url.contains('nicovideo.jp');
        addLink(ExploreExternalLink(
          source: src.isEmpty ? 'official' : src,
          label: src == 'official_site' || src == 'official'
              ? '作品官方网站'
              : _formatRefSourceLabel(src, ''),
          subtitle: url,
          url: url,
          isVideo: isVideo,
        ));
      }
    }

    // 3. NextMoe refs (Steam / DLsite / VNDB / Bangumi / 批评空间)
    final nmRefs = nextmoeWork?['refs'];
    if (nmRefs is List) {
      for (final r in nmRefs.whereType<Map<String, dynamic>>()) {
        final src = '${r['source'] ?? ''}'.trim().toLowerCase();
        final extId = '${r['external_id'] ?? ''}'.trim();
        final url = _buildRefUrl(src, extId);
        if (url.isEmpty) continue;
        addLink(ExploreExternalLink(
          source: src,
          label: _formatRefSourceLabel(src, extId),
          subtitle: url,
          url: url,
          isStore: src == 'steam' || src == 'dlsite',
        ));
      }
    }

    // 4. 确保三大百科主页链接齐全
    if (nextmoeId.isNotEmpty) {
      addLink(ExploreExternalLink(
        source: 'kun',
        label: '鲲Gal (NextMoe) 作品档案',
        subtitle: 'https://www.kungal.com',
        url: 'https://www.kungal.com',
      ));
    }
    if (bangumiId.isNotEmpty) {
      addLink(ExploreExternalLink(
        source: 'bangumi',
        label: 'Bangumi 番组计划 (bgm:$bangumiId)',
        subtitle: 'https://bgm.tv/subject/$bangumiId',
        url: 'https://bgm.tv/subject/$bangumiId',
      ));
    }
    if (vndbId.isNotEmpty) {
      addLink(ExploreExternalLink(
        source: 'vndb',
        label: 'VNDB 视觉小说数据库 (v$vndbId)',
        subtitle: 'https://vndb.org/v$vndbId',
        url: 'https://vndb.org/v$vndbId',
      ));
    }

    return links;
  }

  // ==================== 字典翻译与格式化（移植自 The-Order） ====================

  static String _formatReleaseKind(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'default' || 'normal' || 'standard' => '一般发行',
      'digital' || 'download' => '数字发行',
      'physical' || 'package' => '实体发行',
      'trial' || 'demo' => '体验版',
      'patch' || 'update' => '补丁',
      'complete' => '完全版',
      _ => raw.isEmpty ? '一般发行' : raw,
    };
  }

  static String _formatLanguageCode(String raw) {
    final clean = raw.trim().toLowerCase();
    return switch (clean) {
      'zh-hans' || 'zh_cn' || 'chs' || 'sc' => '简体中文',
      'zh-hant' || 'zh_tw' || 'zh_hk' || 'cht' || 'tc' => '繁体中文',
      'zh' => '中文',
      'ja' || 'jp' || 'jpn' => '日语',
      'en' || 'eng' => '英语',
      'ko' || 'kor' => '韩语',
      'ru' || 'rus' => '俄语',
      'fr' || 'fra' => '法语',
      'de' || 'deu' => '德语',
      'es' || 'spa' => '西班牙语',
      'pt' || 'pt-br' => '葡萄牙语',
      'vi' => '越南语',
      _ => raw.trim(),
    };
  }

  static String _formatPlatformCode(String raw) {
    final clean = raw.trim().toLowerCase();
    return switch (clean) {
      'win' || 'windows' || 'pc' => 'Windows',
      'swi' || 'switch' || 'nintendo switch' => 'Nintendo Switch',
      'ps4' => 'PlayStation 4',
      'ps5' => 'PlayStation 5',
      'ps3' => 'PlayStation 3',
      'ps2' => 'PlayStation 2',
      'ps1' || 'psx' => 'PlayStation',
      'psv' || 'vita' => 'PS Vita',
      'psp' => 'PSP',
      'and' || 'android' => 'Android',
      'ios' => 'iOS',
      'mac' || 'macos' || 'osx' => 'macOS',
      'lin' || 'linux' => 'Linux',
      'xb3' || 'xbox360' => 'Xbox 360',
      'xbo' => 'Xbox One',
      'xbs' => 'Xbox Series X/S',
      'drc' || 'dc' => 'Dreamcast',
      'sat' => 'Sega Saturn',
      'nds' || 'ds' => 'Nintendo DS',
      '3ds' => 'Nintendo 3DS',
      'web' || 'browser' => 'Web 浏览器',
      'dvd' || 'bd' => '互动光盘',
      _ => raw.trim(),
    };
  }

  static String _translateStaffRole(String raw) {
    final clean = raw.trim().toLowerCase();
    return switch (clean) {
      'scenario' || 'script' || 'writer' || '剧本' || '脚本' => '剧本',
      'art' ||
      'artist' ||
      'illustrator' ||
      'original_illustration' ||
      '原画' =>
        '原画',
      'chardesign' || 'character_design' || '人物设定' || '角色设计' => '人物设定',
      'music' || 'composer' || 'bgm' || '音乐' => '音乐',
      'director' || '导演' || '监督' => '导演',
      'planning' || 'planner' || '企划' => '企划',
      'producer' || '制作人' => '制作人',
      'program' || 'programmer' || '程序' => '程序',
      'songs' || 'vocal' || 'vocals' || '主题歌演出' || '歌' => '主题歌演出',
      'lyrics' || 'lyricist' || '主题歌作词' || '作词' => '主题歌作词',
      'composition' || '主题歌作曲' => '主题歌作曲',
      'arrangement' || '主题歌编曲' => '主题歌编曲',
      'graphic' || 'graphics' || 'cg' || 'CG' => 'CG 监修',
      'background' || '背景' => '背景美术',
      'movie' || 'opening_video' || '动画制作' || 'OP动画' => '映像制作',
      'sound' || 'se' || '音响監督' || '音效' => '音响与音效',
      'staff' || 'other' => '制作协力',
      _ => raw.trim().isEmpty ? '制作人员' : raw.trim(),
    };
  }

  static (String, String) _formatGameRelation(String relType, String phrase) {
    final combined = '${relType.toLowerCase()} $phrase';
    if (combined.contains('sequel') || combined.contains('续集') || combined.contains('续作')) {
      return ('续作', '续作与前传');
    }
    if (combined.contains('prequel') || combined.contains('前传')) {
      return ('前传', '续作与前传');
    }
    if (combined.contains('fan') ||
        combined.contains('fandisc') ||
        combined.contains('资料片') ||
        combined.contains('外传')) {
      return ('FanDisc / 外传', '衍生与番外');
    }
    if (combined.contains('side') || combined.contains('番外') || combined.contains('衍生')) {
      return ('番外衍生', '衍生与番外');
    }
    if (combined.contains('alt') ||
        combined.contains('不同演绎') ||
        combined.contains('重制') ||
        combined.contains('主线')) {
      return (phrase.isNotEmpty ? phrase : '不同版本 / 演绎', '同系列与版本');
    }
    if (combined.contains('set') ||
        combined.contains('ser') ||
        combined.contains('世界观') ||
        combined.contains('角色出演')) {
      return (phrase.isNotEmpty ? phrase : '相同世界观', '同系列与版本');
    }
    final label = phrase.isNotEmpty
        ? phrase
        : (relType.isNotEmpty ? relType : '相关作品');
    return (label, '其他关联');
  }

  static String _buildRefUrl(String src, String extId) {
    if (extId.isEmpty) return '';
    return switch (src.toLowerCase()) {
      'vndb' =>
        'https://vndb.org/${extId.startsWith('v') ? extId : 'v$extId'}',
      'bangumi' => 'https://bgm.tv/subject/$extId',
      'steam' => 'https://store.steampowered.com/app/$extId',
      'dlsite' =>
        'https://www.dlsite.com/maniax/work/=/product_id/$extId.html',
      'erogamescape' =>
        'https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/game.php?game=$extId',
      _ => '',
    };
  }

  static String _buildReleaseRefUrl(String src, String extId) {
    if (extId.isEmpty) return '';
    return switch (src.toLowerCase()) {
      'vndb' =>
        'https://vndb.org/${extId.startsWith('r') ? extId : 'r$extId'}',
      'steam' => 'https://store.steampowered.com/app/$extId',
      'dlsite' =>
        'https://www.dlsite.com/maniax/work/=/product_id/$extId.html',
      'getchu' => 'https://www.getchu.com/soft.phtml?id=$extId',
      'fanza' || 'dmm' =>
        'https://dlsoft.dmm.co.jp/detail/$extId/',
      _ => _buildRefUrl(src, extId),
    };
  }

  static String _formatRefSourceLabel(String src, String extId) {
    final suffix = extId.isEmpty ? '' : ' ($extId)';
    return switch (src.toLowerCase()) {
      'steam' => 'Steam 商店$suffix',
      'dlsite' => 'DLsite$suffix',
      'vndb' => 'VNDB$suffix',
      'bangumi' => 'Bangumi$suffix',
      'erogamescape' => 'ErogameScape 批评空间',
      'getchu' => 'Getchu$suffix',
      'fanza' || 'dmm' => 'FANZA / DMM$suffix',
      _ => '${src.toUpperCase()}$suffix',
    };
  }

  static String _firstNonEmpty(List<String> values) {
    for (final v in values) {
      final clean = v.trim();
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  static String _normTitle(String s) {
    return s
        .toLowerCase()
        .replaceAll(
          RegExp(r'[\s\u3000\-_~～・·:：!！?？/\\「」『』【】（）()\[\]＊*.,，。]'),
          '',
        )
        .trim();
  }

  static String _cleanSummary(String raw) {
    if (raw.isEmpty) return '';
    return raw
        .replaceAll(RegExp(r'\[url=[^\]]*\](.*?)\[/url\]'), r'$1')
        .replaceAll(RegExp(r'\[/?(b|i|u|s|quote|code|spoiler|raw)\]'), '')
        .trim();
  }
}

class _CrossMediaBundle {
  final List<ExploreCrossMediaItem> animeList;
  final List<ExploreCrossMediaItem> musicList;
  final List<ExploreCrossMediaItem> mangaList;
  final List<ExploreCrossMediaItem> novelList;

  const _CrossMediaBundle({
    this.animeList = const [],
    this.musicList = const [],
    this.mangaList = const [],
    this.novelList = const [],
  });
}
