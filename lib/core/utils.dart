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
/// 精确=100，压扁相等=95，压扁包含=55，全词命中=45，多数词命中=25，否则 0。
/// 比较前先归一化（符号视作分隔、全角转半角、去标点），
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
  final qt = q.split(' ').where((s) => s.isNotEmpty).toSet();
  final ct = c.split(' ').where((s) => s.isNotEmpty).toSet();
  if (qt.isNotEmpty && ct.containsAll(qt)) return 45;
  final matched = qt.intersection(ct).length;
  if (qt.length >= 2 && matched * 2 >= qt.length) return 25;
  return 0;
}

/// 名称匹配归一化：小写、全角 ASCII 化、符号转空格、压缩空白。
/// 「PURE×CONNECT」→「pure connect」。
String normalizeForMatch(String s) {
  var t = s.toLowerCase();
  // 全角可见字符 (U+FF01-U+FF5E) → 半角
  t = t.replaceAllMapped(RegExp(r'[\uFF01-\uFF5E]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFEE0));
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
