/// 通用工具函数。
library;

import 'dart:convert';

/// 平台评分统一归一化到 0-10。
/// VNDB 为 0-100，其余多为 0-10；超出 10 视为百分制折算。
double normalizeRating(num raw) {
  double r = raw.toDouble();
  if (r > 10) r = r / 10;
  return r.clamp(0, 10).toDouble();
}

/// 搜索候选与查询词的匹配打分。
/// 精确=100，压扁相等=95，压扁包含=55，反包含=50，全词命中=45，多数词命中=25，否则 0。
/// 比较前先归一化（符号视作分隔、全角转半角、繁简折叠、去标点），
/// 使「pure connect」可匹配「PURE×CONNECT」、「千恋万花」可匹配「千恋＊万花」。
int bestMatchScore(String query, String candidate) {
  final q = normalizeForMatch(query);
  final c = normalizeForMatch(candidate);
  if (q.isEmpty || c.isEmpty) return 0;
  final qs = q.replaceAll(' ', '');
  final cs = c.replaceAll(' ', '');
  if (q == c) return 100;
  if (qs == cs) return 95;
  if (cs.contains(qs)) return 55;
  if (cs.length >= 2 && qs.contains(cs)) return 50;
  final qt = q.split(' ').where((s) => s.isNotEmpty).toSet();
  final ct = c.split(' ').where((s) => s.isNotEmpty).toSet();
  if (qt.isNotEmpty && ct.containsAll(qt)) return 45;
  final matched = qt.intersection(ct).length;
  if (qt.length >= 2 && matched * 2 >= qt.length) return 25;
  return 0;
}

const _tradToSimpMap = <int, int>{
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

/// 名称匹配归一化：小写、全角 ASCII 化、常见繁简字折叠、符号转空格、压缩空白。
/// 「PURE×CONNECT」→「pure connect」。
String normalizeForMatch(String s) {
  final buf = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      buf.writeCharCode(r - 0xFEE0);
    } else {
      buf.writeCharCode(_tradToSimpMap[r] ?? r);
    }
  }
  var t = buf.toString();
  // 非字母/数字统一转空格（×、・、-、' 等都视作词边界）
  t = t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 从可执行文件名清洗出用于搜索的游戏名。
/// 去扩展名、常见安装词、版本号、括号注记。
String cleanExeName(String exeFileName) {
  var name = exeFileName;
  if (name.contains('.')) name = name.substring(0, name.lastIndexOf('.'));
  name = name.replaceAll(RegExp(r'[_\.]+'), ' ');
  name = name.replaceAll(
      RegExp(r'\(([^)]*)\)|\[[^\]]*\]|（([^）]*)）|【([^】]*)】'), ' ');
  name = name.replaceAll(
      RegExp(
          r'\b(v|ver|version|release|final|hd|remaster|dlc|enhanced|edition|update|setup|install|crack|repack| game)\s*[\d\.]*\b',
          caseSensitive: false),
      ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  return name;
}

/// 秒数格式化为可读时长："12.5 小时" / "35 分钟" / "尚无记录"。
String fmtDuration(num? seconds) {
  final s = (seconds ?? 0).toInt();
  if (s <= 0) return '尚无记录';
  if (s < 3600) return '${(s / 60).round()} 分钟';
  final h = s / 3600;
  return h >= 100
      ? '${h.toStringAsFixed(0)} 小时'
      : '${h.toStringAsFixed(1)} 小时';
}

/// "YYYY-MM-DD HH:mm" 本地时间格式（避免依赖 intl 初始化）。
String fmtDateTime(DateTime t) =>
    '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';

String fmtDate(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}';
String two(int n) => n.toString().padLeft(2, '0');

/// 相对时间描述："3 分钟前" / "昨天 21:30" / "2025-08-01"。
String fmtRelative(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 2) return '昨天';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return fmtDate(t);
}

String jsonEncodeMap(Map<String, dynamic> m) => jsonEncode(m);

Map<String, dynamic> jsonDecodeMap(String? s) =>
    s == null || s.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(s) as Map);

List<Map<String, dynamic>> jsonDecodeList(String? s) => s == null || s.isEmpty
    ? <Map<String, dynamic>>[]
    : (jsonDecode(s) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

/// 相对时间（统一口径，供主页动态/统计等复用）：
/// <1 分钟「刚刚」→ <60 分钟「x 分钟前」→ <24 小时「x 小时前」→
/// <7 天「x 天前」→ 更早用 YYYY-MM-DD。
/// 注意与 [fmtRelative] 的区别：后者 1~2 天会给「昨天」，
/// 与列表右对齐时间列的「x 天前」口径不一致，混用会出现两种风格。
String fmtRelativeShort(DateTime t) {
  final now = DateTime.now();
  final d = now.difference(t);
  if (d.inSeconds < 60) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays < 7) return '${d.inDays} 天前';
  return fmtDate(t);
}
