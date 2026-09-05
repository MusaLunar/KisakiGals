/// 元数据磁盘缓存（24h TTL）。
library;

import 'dart:convert';
import 'dart:io';

class MetadataCache {
  final String dir;
  final Duration ttl;
  final Map<String, String> _mem = {};

  MetadataCache(this.dir, {this.ttl = const Duration(hours: 24)});

  File _file(String key) {
    final safe = key.replaceAll(RegExp(r'[^\w\u4e00-\u9fff-]'), '_');
    return File('$dir/mc_$safe.json');
  }

  List<Map<String, dynamic>>? get(String key) {
    final mem = _mem[key];
    if (mem != null) return _decode(mem);
    final f = _file(key);
    if (!f.existsSync()) return null;
    try {
      final obj = Map<String, dynamic>.from(jsonDecode(f.readAsStringSync()) as Map);
      final at = DateTime.tryParse((obj['at'] ?? '') as String) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (DateTime.now().difference(at) > ttl) {
        f.deleteSync();
        return null;
      }
      final s = (obj['data'] ?? '[]') as String;
      _mem[key] = s;
      return _decode(s);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>>? _decode(String s) {
    try {
      return (jsonDecode(s) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  void put(String key, List<Map<String, dynamic>> data) {
    final s = jsonEncode(data);
    _mem[key] = s;
    try {
      _file(key).writeAsStringSync(jsonEncode({'at': DateTime.now().toIso8601String(), 'data': s}));
    } catch (_) {}
  }

  void clear() {
    _mem.clear();
    final d = Directory(dir);
    if (d.existsSync()) {
      for (final f in d.listSync()) {
        if (f is File && f.path.contains('mc_')) f.deleteSync();
      }
    }
  }
}
