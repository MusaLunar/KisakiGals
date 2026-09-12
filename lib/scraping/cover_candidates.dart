/// 封面候选：从各平台已刮削记录中提取**平台封面图**，
/// 供编辑界面选择（而不是拿 VNDB 的 screenshots 当封面）。
library;

import '../data/models.dart';
import '../core/constants.dart' show KisakiSources;

class CoverCandidate {
  final String source; // 平台 id
  final String url;
  const CoverCandidate(this.source, this.url);

  String get label {
    final name = KisakiSources.labels[source] ?? source;
    return name;
  }
}

/// 各平台 raw JSON 中可能承载封面图的字段名（按优先级）。
const _coverKeys = [
  'cover', // hikarinagi: cover{url} / kun: coverUrl / touchgal
  'coverUrl',
  'cover_url',
  'image', // vndb/bgm/ymgal: image
  'imageUrl',
  'mainPicture', // cngal
  'mainImage',
  'bannerUrl', // touchgal
  'effective_portrait_url', // kun
  'thumbnail',
];

class CoverCandidates {
  /// 从游戏的全部平台记录里提取封面候选（去重，保持平台顺序）。
  static List<CoverCandidate> fromSources(List<SourceRecord> sources) {
    final out = <CoverCandidate>[];
    final seen = <String>{};
    for (final s in sources) {
      final url = _extract(s.raw);
      if (url.isEmpty || url.startsWith('data:')) continue;
      if (seen.add(url)) out.add(CoverCandidate(s.source, url));
    }
    return out;
  }

  static String _extract(Map<String, dynamic> m) {
    if (m.isEmpty) return '';
    for (final key in _coverKeys) {
      final v = m[key];
      if (v is String && v.trim().isNotEmpty) return _absolute(v.trim());
      // 形如 {"cover": {"url": "..."}}（hikarinagi）
      if (v is Map) {
        final inner = Map<String, dynamic>.from(v);
        for (final k2 in ['url', 'path', 'src']) {
          final u = inner[k2];
          if (u is String && u.trim().isNotEmpty) return _absolute(u.trim());
        }
      }
    }
    return '';
  }

  /// 补全协议相对 URL（Bangumi 的 //lain.bgm.tv/... 形式）。
  static String _absolute(String url) {
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return 'https://lain.bgm.tv$url';
    return url;
  }
}
