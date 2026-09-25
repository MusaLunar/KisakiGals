/// 探索页的筛选条件（不可变值对象）。
///
/// 这里只放**用户意图**：来源、排序、评分下限、年份区间、是否只看非 R18、
/// 标签、关键词。页面自己的东西（滚动位置、入库中的条目）不放这里。
///
/// **关键词为什么也在这里**：工具条的搜索框现在有两层语义——输入时过滤
/// 已加载的条目（页面自己处理，不进本对象），回车/点「搜索」时则向数据源
/// 发起一次关键词查询。「换关键词」与「换筛选条件」对信息流来说是完全
/// 同一件事：手上的条目全部作废、回到第一页重新拉，因此关键词必须和
/// 来源/排序一样进本对象，才能共用 [DiscoverFilter.key] 这套「数据是不是
/// 当前条件下的」判定（否则搜索结果会和榜单条目混在一个网格里）。
library;

import '../../core/constants.dart';

/// 排序维度。
///
/// [value] 直接就是 VNDB 的 `sort` 字段取值（rating / votecount / released /
/// title，实测 VNDB 仅这四个可用于榜单浏览，其它值会 400）；Bangumi 只有
/// rank / date 两种排序，映射关系见 `discover_state.dart` 里的参数拼装。
enum DiscoverSort {
  rating('rating', '按评分'),
  votecount('votecount', '按评价数'),
  released('released', '按发售日'),
  title('title', '按名称');

  final String value;
  final String label;
  const DiscoverSort(this.value, this.label);

  /// 是否需要倒序：评分/评价数/发售日都是「越大越靠前」才有意义，
  /// 只有名称排序要正序（A→Z）。VNDB 的 `reverse` 参数由此决定。
  bool get reverse => this != DiscoverSort.title;
}

/// 浏览的数据源。
enum DiscoverSource {
  vndb(KisakiSources.vndb, 'VNDB', '评分/评价数/年份/标签都可服务端筛选；含简介与截图'),
  bgm(KisakiSources.bangumi, 'Bangumi', '按排名或发售日浏览；年份区间与评分下限在本地补筛');

  /// 与 [KisakiSources] 一致的源 id（MetadataFetcher / 适配器都按它分发）。
  final String id;
  final String label;

  /// 该源的能力说明（筛选面板里显示，避免用户以为筛了却没生效）。
  final String hint;

  const DiscoverSource(this.id, this.label, this.hint);

  static DiscoverSource fromId(String id) => DiscoverSource.values
      .firstWhere((s) => s.id == id, orElse: () => DiscoverSource.vndb);
}

/// 探索页可选的 VNDB 标签（预设常用标签）。
///
/// id 均为本机实测查到的真实 VNDB 标签 id（`POST /kana/tag` 按名称检索），
/// 中文名是对应标签名的意译——VNDB 标签 id 不会变，改中文名只影响显示。
/// 这里刻意只放 content / tech 类标签（不放 ero 类），否则一个默认
/// 「隐藏 R18」的页面上全是会被筛掉的成人向标签，选择体验很差。
class DiscoverTags {
  const DiscoverTags._();

  static const presets = <({String id, String label})>[
    (id: 'g96', label: '恋爱'), // Romance
    (id: 'g47', label: '校园'), // School
    (id: 'g2', label: '奇幻'), // Fantasy
    (id: 'g105', label: '科幻'), // Science Fiction
    (id: 'g19', label: '悬疑'), // Mystery
    (id: 'g104', label: '喜剧'), // Comedy
    (id: 'g454', label: '日常'), // Slice of Life
    (id: 'g596', label: '泣系'), // Nakige
    (id: 'g693', label: '郁系'), // Utsuge
    (id: 'g349', label: '时间轮回'), // Time Loop
    (id: 'g97', label: '百合'), // Girl x Girl Romance
  ];

  /// 标签 id → 显示名（未知 id 原样显示，不编造）。
  static String label(String id) {
    for (final t in presets) {
      if (t.id == id) return t.label;
    }
    return id;
  }
}

/// 探索页筛选条件。
class DiscoverFilter {
  final DiscoverSource source;
  final DiscoverSort sort;

  /// 最低评分 0-10（0 = 不筛）。
  final double minRating;

  /// 年份区间（null = 无界）。
  final int? yearFrom;
  final int? yearTo;

  /// 是否只看非 R18（默认 true：默认不显示 R18）。
  final bool onlySfw;

  /// VNDB 标签 id 列表（默认空）。多标签之间是「与」关系，
  /// 与 VNDB 的 tag 过滤器语义一致；Bangumi 不支持标签筛选。
  final List<String> tagIds;

  /// 关键词（空串 = 按榜单浏览）。
  ///
  /// 已 trim。非空时数据源走「关键词搜索」而不是榜单：VNDB 用
  /// `['search','=',kw]` 过滤 + `searchrank` 排序；Bangumi 走
  /// `POST /v0/search/subjects`（相关度排序）。此时排序条件不生效
  /// （两个源都按各自的相关度排），筛选栏里会如实提示。
  final String keyword;

  const DiscoverFilter({
    this.source = DiscoverSource.vndb,
    this.sort = DiscoverSort.rating,
    this.minRating = 0,
    this.yearFrom,
    this.yearTo,
    this.onlySfw = true,
    this.tagIds = const [],
    this.keyword = '',
  });

  /// 是否有生效的筛选条件。
  ///
  /// 来源与排序算「浏览方式」而不是筛选（它们始终体现在 [summary] 里），
  /// 因此这里只看评分/年份/标签/R18 四项——决定页面上「已筛选」标记亮不亮。
  /// 关键词也不算（它有自己的徽标与清除入口，页面上单独显示）。
  bool get hasActiveFilters =>
      minRating > 0 ||
      yearFrom != null ||
      yearTo != null ||
      !onlySfw ||
      tagIds.isNotEmpty;

  /// 是否处于关键词搜索（而不是榜单浏览）。
  bool get searching => keyword.isNotEmpty;

  /// 一行摘要，例如「按评分 · 评分 ≥ 8 · 2015-2024」。
  String get summary {
    final parts = <String>[
      // 关键词搜索时两个源都按各自的相关度排，此时说「按评分」是错的
      if (searching) '搜索「$keyword」' else sort.label,
    ];
    if (minRating > 0) parts.add('评分 ≥ ${_trim(minRating)}');
    final years = _yearLabel;
    if (years != null) parts.add(years);
    if (tagIds.isNotEmpty) {
      parts.add(tagIds.length == 1
          ? '标签：${DiscoverTags.label(tagIds.first)}'
          : '标签 ×${tagIds.length}');
    }
    if (!onlySfw) parts.add('含 R18');
    if (parts.length == 1) parts.add('未筛选');
    return parts.join(' · ');
  }

  String? get _yearLabel {
    if (yearFrom == null && yearTo == null) return null;
    if (yearFrom != null && yearTo != null) {
      return yearFrom == yearTo ? '$yearFrom 年' : '$yearFrom-$yearTo 年';
    }
    if (yearFrom != null) return '$yearFrom 年以后';
    return '$yearTo 年以前';
  }

  /// 条件的稳定标识：用来判断「手上的榜单数据是不是当前条件下拉到的」
  /// （换筛选/换源/换关键词之后，旧的条目不能再当作新条件的结果显示）。
  /// 标签先排序，保证「先选 A 再选 B」与「先选 B 再选 A」得到同一个 key。
  ///
  /// 关键词放在最后一段：它只影响「重新拉数据」的判定，不参与标签那类
  /// 无序比较，放末尾便于调试时一眼看出是不是搜索态。
  String get key {
    final tags = [...tagIds]..sort();
    return '${source.id}|${sort.value}|$minRating|$yearFrom|$yearTo|'
        '$onlySfw|${tags.join("+")}|kw=$keyword';
  }

  /// copyWith 的「保持原值」哨兵：年份是可空字段，不区分「没传」与
  /// 「传了 null」就没法清空年份（传 null 表示清除区间）。
  static const Object _keep = Object();

  DiscoverFilter copyWith({
    DiscoverSource? source,
    DiscoverSort? sort,
    double? minRating,
    Object? yearFrom = _keep,
    Object? yearTo = _keep,
    bool? onlySfw,
    List<String>? tagIds,
    String? keyword,
  }) {
    return DiscoverFilter(
      source: source ?? this.source,
      sort: sort ?? this.sort,
      minRating: (minRating ?? this.minRating).clamp(0, 10).toDouble(),
      yearFrom: identical(yearFrom, _keep) ? this.yearFrom : yearFrom as int?,
      yearTo: identical(yearTo, _keep) ? this.yearTo : yearTo as int?,
      onlySfw: onlySfw ?? this.onlySfw,
      tagIds: tagIds ?? this.tagIds,
      keyword: (keyword ?? this.keyword).trim(),
    );
  }

  /// 把颠倒的年份区间摆正（用户先填 2024 再填 2015 时不该得到空区间）。
  DiscoverFilter normalized() {
    final from = yearFrom;
    final to = yearTo;
    if (from != null && to != null && from > to) {
      return copyWith(yearFrom: to, yearTo: from);
    }
    return this;
  }

  /// 切换一个标签（选中 ↔ 取消）。
  DiscoverFilter toggleTag(String tagId) {
    final next = [...tagIds];
    if (next.contains(tagId)) {
      next.remove(tagId);
    } else {
      next.add(tagId);
    }
    return copyWith(tagIds: next);
  }

  /// 清空筛选条件（保留来源、排序与关键词）。
  ///
  /// 关键词刻意保留：搜索框里还写着那个词，条件却被悄悄清掉会得到
  /// 「框里是 A、列表是榜单」的错位。清关键词有它自己的入口（搜索框的
  /// 清空按钮、关键词徽标）。
  DiscoverFilter cleared() => DiscoverFilter(
      source: source, sort: sort, onlySfw: true, keyword: keyword);

  /// 清空关键词，回到榜单浏览（其余条件保持）。
  DiscoverFilter browse() => copyWith(keyword: '');

  /// 换关键词（trim 由 [copyWith] 负责）。
  DiscoverFilter withKeyword(String kw) => copyWith(keyword: kw);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiscoverFilter &&
          other.source == source &&
          other.sort == sort &&
          other.minRating == minRating &&
          other.yearFrom == yearFrom &&
          other.yearTo == yearTo &&
          other.onlySfw == onlySfw &&
          other.keyword == keyword &&
          _sameTags(other.tagIds, tagIds));

  @override
  int get hashCode => Object.hash(source, sort, minRating, yearFrom, yearTo,
      onlySfw, keyword, Object.hashAllUnordered(tagIds));

  @override
  String toString() =>
      'DiscoverFilter(${source.id}, ${sort.value}, min=$minRating, '
      'years=$yearFrom-$yearTo, sfw=$onlySfw, tags=${tagIds.join("+")}, '
      'kw=$keyword)';

  /// 标签顺序不影响筛选结果（hashCode 用 hashAllUnordered 与之保持一致），
  /// 免得切换顺序后把同一个条件误判成「筛选变了」而白拉一次网络。
  static bool _sameTags(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  /// 8.0 → "8"，8.5 → "8.5"（评分摘要不要出现无意义的小数位）。
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
