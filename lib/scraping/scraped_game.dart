/// 刮削统一模型。
library;

class ScrapedGame {
  final String source; // KisakiSources.*
  final String sourceId;
  final String name;
  final String nameCn;
  final List<String> aliases;
  final String coverUrl;
  final String developer;
  final String releaseDate; // YYYY-MM-DD
  final String summary;
  final double rating; // 0-10
  final int voteCount;
  final List<ScrapedTag> tags;
  final List<String> screenshots;
  final bool nsfw;

  const ScrapedGame({
    required this.source,
    required this.sourceId,
    this.name = '',
    this.nameCn = '',
    this.aliases = const [],
    this.coverUrl = '',
    this.developer = '',
    this.releaseDate = '',
    this.summary = '',
    this.rating = 0,
    this.voteCount = 0,
    this.tags = const [],
    this.screenshots = const [],
    this.nsfw = false,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  Map<String, dynamic> toJson() => {
        'source': source,
        'sourceId': sourceId,
        'name': name,
        'nameCn': nameCn,
        'aliases': aliases,
        'coverUrl': coverUrl,
        'developer': developer,
        'releaseDate': releaseDate,
        'summary': summary,
        'rating': rating,
        'voteCount': voteCount,
        'tags': [for (final t in tags) {'name': t.name, 'weight': t.weight}],
        'screenshots': screenshots,
        'nsfw': nsfw,
      };

  static ScrapedGame fromJson(Map<String, dynamic> m) => ScrapedGame(
        source: (m['source'] ?? '') as String,
        sourceId: (m['sourceId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        nameCn: (m['nameCn'] ?? '') as String,
        aliases: [for (final a in (m['aliases'] as List?) ?? []) a.toString()],
        coverUrl: (m['coverUrl'] ?? '') as String,
        developer: (m['developer'] ?? '') as String,
        releaseDate: (m['releaseDate'] ?? '') as String,
        summary: (m['summary'] ?? '') as String,
        rating: ((m['rating'] ?? 0) as num).toDouble(),
        voteCount: (m['voteCount'] ?? 0) as int,
        tags: [
          for (final t in (m['tags'] as List?) ?? [])
            ScrapedTag(
              (t as Map)['name'].toString(),
              weight: ((t['weight'] ?? 1) as num).toDouble(),
            )
        ],
        screenshots: [
          for (final s in (m['screenshots'] as List?) ?? []) s.toString()
        ],
        nsfw: (m['nsfw'] ?? false) as bool,
      );

  ScrapedGame copyWith({
    String? coverUrl,
    String? summary,
    String? developer,
    String? releaseDate,
    double? rating,
    int? voteCount,
    bool? nsfw,
  }) =>
      ScrapedGame(
        source: source,
        sourceId: sourceId,
        name: name,
        nameCn: nameCn,
        aliases: aliases,
        coverUrl: coverUrl ?? this.coverUrl,
        developer: developer ?? this.developer,
        releaseDate: releaseDate ?? this.releaseDate,
        summary: summary ?? this.summary,
        rating: rating ?? this.rating,
        voteCount: voteCount ?? this.voteCount,
        tags: tags,
        screenshots: screenshots,
        nsfw: nsfw ?? this.nsfw,
      );
}

class ScrapedTag {
  final String name;
  final double weight;
  final bool isSpoiler;
  const ScrapedTag(this.name, {this.weight = 1.0, this.isSpoiler = false});
}

/// 搜索候选（列表展示用）。
class ScrapeHit {
  final ScrapedGame game;
  final int score; // 匹配分
  ScrapeHit(this.game, this.score);
}
