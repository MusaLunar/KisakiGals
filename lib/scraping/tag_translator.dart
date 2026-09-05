/// VNDB 标签英→中翻译器（资源来自 ChronoTide 内置 MIT 数据，~3000 条）。
library;

class TagTranslator {
  final Map<String, String> _zh = {};

  TagTranslator._();

  static TagTranslator? _instance;

  static TagTranslator get instance => _instance ??= TagTranslator._();

  static void init(Map<String, dynamic> data) {
    final t = instance;
    data.forEach((k, v) {
      t._zh[k.toLowerCase()] = v.toString();
    });
  }

  String translate(String en) {
    if (en.isEmpty) return en;
    return _zh[en.toLowerCase()] ?? en;
  }

  bool get loaded => _zh.isNotEmpty;
}
