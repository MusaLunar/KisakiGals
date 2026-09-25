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

  /// 榜单浏览专用字段表：在 [_fields] 基础上只改写两处（复用同一常量，
  /// 避免「搜索」与「浏览」的字段表各写一份后逐渐漂移）：
  /// - `image` 补 `sexual`/`violence`：VNDB 的 VN 对象**没有** R18 标记，
  ///   只能靠封面图的成人内容票数判定（实测 v137 封面 sexual=2）；
  /// - `tags` 补 `category`：`ero` 类标签数量是更可靠的 R18 信号
  ///   （实测校准见 [_looksNsfw]）。
  static final _browseFields = _fields
      .replaceFirst('image{url}', 'image{url, sexual, violence}')
      .replaceFirst('tags{name, rating, spoiler, lie}',
          'tags{name, category, rating, spoiler, lie}');

  /// 最近一次 [browse] 之后是否还有下一页（VNDB 响应里的 `more` 字段）。
  /// VNDB 官方建议用 `more` 分页（比 `count` 便宜），因此这里如实透出，
  /// 由 MetadataFetcher 读走后交给 UI 决定还要不要继续加载。
  bool lastBrowseHasMore = false;

  /// 榜单浏览支持的排序字段（实测：其余值会 400）。
  static const browseSorts = {'rating', 'votecount', 'released', 'title'};

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

  /// 榜单浏览：没有关键词时按评分/评价数/发售日/名称翻页浏览作品。
  ///
  /// 为什么用 sort + filters 而不是别的接口：VNDB **没有**「随机条目」接口
  /// （官方文档的 Random entry 一节只给了「先取一批 id 再随机抽」的客户端
  /// 做法），也没有专门的榜单端点，浏览只能靠 POST /vn 的排序 + 分页实现。
  ///
  /// 参数都是「用户意图」，服务端能力之外的判断（R18）留给调用方：
  /// [sort] ∈ [browseSorts]；[minRating] 0-10（0=不筛）下发前换算成
  /// VNDB 的 10-100 整数；[tagIds] 为 VNDB 标签 id（如 `g505`），
  /// 多标签之间是「与」关系（与 VNDB 的 tag 过滤器语义一致）。
  ///
  /// [keyword] 非空时走**关键词搜索**（与 [search] 同一条服务端能力）：
  /// 加 `['search','=',kw]` 谓词并改用 `searchrank` 排序——`search` 谓词
  /// 命中标题/别名，`searchrank` 就是"与关键词的相关度"，两者搭配正是
  /// [search] 一直在用的组合（本机实测可用）。此时 [sort]/[reverse] 不再
  /// 下发：用户要在搜索结果里按评分排是另一件事，而混着用会先按评分排完
  /// 再分页，让最相关的结果散在后面几页。
  ///
  /// 返回本页条目；「是否还有下一页」写入 [lastBrowseHasMore]
  /// （取响应里的 `more`，不是「条数 == results」的推断——VNDB 的
  /// `more` 才是权威答案，且末页条数常常刚好等于 results）。
  Future<List<ScrapedGame>> browse({
    String sort = 'rating',
    bool reverse = true,
    int page = 1,
    int results = 50,
    double? minRating,
    int? yearFrom,
    int? yearTo,
    List<String>? tagIds,
    String? keyword,
  }) async {
    final kw = (keyword ?? '').trim();
    final searching = kw.isNotEmpty;

    // 过滤谓词。注意：VNDB 的 `and` 必须是**扁平**形式 `["and", f1, f2]`，
    // 写成 `["and", [f1, f2]]` 会直接 400（本机实测），文档示例也是扁平写法。
    final predicates = <List<dynamic>>[
      if (searching) ['search', '=', kw],
    ];
    if (minRating != null && minRating > 0) {
      final r = (minRating * 10).round().clamp(10, 100);
      predicates.add(['rating', '>=', r]);
    }
    if (yearFrom != null) {
      predicates.add(['released', '>=', '$yearFrom-01-01']);
    }
    if (yearTo != null) {
      predicates.add(['released', '<=', '$yearTo-12-31']);
    }
    for (final t in tagIds ?? const <String>[]) {
      final id = t.trim();
      if (id.isEmpty) continue;
      predicates.add(['tag', '=', id]);
    }
    final Object? filters = predicates.isEmpty
        ? null
        : (predicates.length == 1 ? predicates.first : ['and', ...predicates]);

    final requestedPage = page < 1 ? 1 : page;
    final response = await limitedPost('$base/vn',
        data: {
          // 无条件时**不带** filters 字段（API 里所有成员可选，缺省即不过滤）
          if (filters != null) 'filters': filters,
          'fields': _browseFields,
          // 关键词搜索：按相关度（searchrank 只在带了 search 谓词时才有意义，
          // 因此这两个字段必须成对出现，且搜索时不接受用户的排序条件）
          'sort': searching
              ? 'searchrank'
              : (browseSorts.contains(sort) ? sort : 'rating'),
          'reverse': searching ? false : reverse,
          'page': requestedPage,
          'results': results.clamp(1, 100),
        },
        headers: _headers);
    if (response.statusCode != 200) {
      lastBrowseHasMore = false;
      return [];
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final results_ = (data['results'] as List?) ?? const [];
    lastBrowseHasMore = data['more'] == true;
    // 浏览结果带 R18 判定（搜索/详情不带，保持原有行为不变）
    return results_.map((r) => _parse(r, withNsfw: true)).toList();
  }

  @override
  Future<ScrapedGame?> fetchById(String id) async {
    final vid = id.startsWith('v') ? id : 'v$id';
    final results = await _query(['id', '=', vid]);
    if (results == null || results.isEmpty) return null;
    return _parse(results.first);
  }

  ScrapedGame _parse(dynamic raw, {bool withNsfw = false}) {
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
      nsfw: withNsfw && _looksNsfw(m, image),
    );
  }

  /// R18 启发式判定（只在浏览榜单时使用；VNDB 没有「R18」标记字段）。
  ///
  /// 两条信号，阈值按实测校准（本机抽样：全年龄的 STEINS;GATE / CLANNAD /
  /// Ever17 / Summer Pockets 的 `ero` 类标签为 0-1 个、封面 sexual=0；
  /// 而 R18 的 Fate/stay night=24、Saya no Uta=29、Muramasa=31、Rance X=11）：
  /// - `tags` 里 `category == 'ero'` 的标签数 ≥ 3；
  /// - 封面图 `sexual` 票 ≥ 1.5（0-2 的均值，封面本身就是限制级）。
  ///
  /// 因此**会有漏判与误判**（R18 但标签少且封面安全的作品会漏；少量
  /// 带轻度性内容标签的全年龄作品可能被误判），故它只服务于「探索页默认
  /// 隐藏 R18」这个可一键关闭的过滤，不写回游戏库、也不参与刮削打分。
  static bool _looksNsfw(Map<String, dynamic> m, Map<String, dynamic> image) {
    final sexual = (image['sexual'] ?? 0) as num;
    if (sexual >= 1.5) return true;
    var ero = 0;
    for (final t in (m['tags'] as List?) ?? const []) {
      if ((Map<String, dynamic>.from(t as Map)['category'] ?? '') == 'ero') {
        ero++;
        if (ero >= 3) return true;
      }
    }
    return false;
  }

  static String _stripSp(String s) => s
      .replaceAll(RegExp(r'\[url=[^\]]*\]'), '')
      .replaceAll('[/url]', '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .trim();
}
