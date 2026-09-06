/// 数据模型（与 SQLite 表一一对应）。
library;

import 'dart:convert';

import '../core/constants.dart';
import '../core/utils.dart';

class Game {
  int? id;
  String name;
  String nameCn;
  List<String> aliases;
  String coverPath; // 本地封面绝对路径（空=无）
  String developer;
  String releaseDate; // YYYY-MM-DD
  String summary;
  bool nsfw;
  PlayStatus playStatus;
  double userRating; // 0-10，0=未评分
  String userReview;
  String exePath;
  String directory;
  String launchType; // local
  bool isFavorite;
  int totalSeconds;
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? firstPlayedAt;
  DateTime? lastPlayedAt;
  List<String> screenshots; // 刮削得到的截图 URL
  String backgroundUrl; // 详情页背景（本地路径，空=纯色）

  Game({
    this.id,
    this.name = '',
    this.nameCn = '',
    List<String>? aliases,
    this.coverPath = '',
    this.developer = '',
    this.releaseDate = '',
    this.summary = '',
    this.nsfw = false,
    this.playStatus = PlayStatus.wish,
    this.userRating = 0,
    this.userReview = '',
    this.exePath = '',
    this.directory = '',
    this.launchType = 'local',
    this.isFavorite = false,
    this.totalSeconds = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.firstPlayedAt,
    this.lastPlayedAt,
    List<String>? screenshots,
    this.backgroundUrl = '',
  })  : aliases = aliases ?? [],
        screenshots = screenshots ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 显示名：中文名优先。
  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  static List<String> _parseAliases(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecodeMap(raw)['list'];
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
    return const [];
  }

  static List<String> _parseStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      if (jsonDecode(raw) is List) {
        return [for (final e in jsonDecode(raw) as List) e.toString()];
      }
    } catch (_) {}
    return const [];
  }

  static Game fromRow(Map<String, dynamic> r) => Game(
        id: r['id'] as int,
        name: (r['name'] ?? '') as String,
        nameCn: (r['name_cn'] ?? '') as String,
        aliases: _parseAliases(r['aliases'] as String?),
        coverPath: (r['cover_path'] ?? '') as String,
        developer: (r['developer'] ?? '') as String,
        releaseDate: (r['release_date'] ?? '') as String,
        summary: (r['summary'] ?? '') as String,
        nsfw: (r['nsfw'] ?? 0) as int == 1,
        playStatus: PlayStatus.fromValue((r['play_status'] ?? 1) as int),
        userRating: ((r['user_rating'] ?? 0) as num).toDouble(),
        userReview: (r['user_review'] ?? '') as String,
        exePath: (r['exe_path'] ?? '') as String,
        directory: (r['directory'] ?? '') as String,
        launchType: (r['launch_type'] ?? 'local') as String,
        isFavorite: (r['is_favorite'] ?? 0) as int == 1,
        totalSeconds: (r['total_seconds'] ?? 0) as int,
        createdAt: DateTime.tryParse((r['created_at'] ?? '') as String) ??
            DateTime.now(),
        updatedAt: DateTime.tryParse((r['updated_at'] ?? '') as String) ??
            DateTime.now(),
        firstPlayedAt: DateTime.tryParse((r['first_played_at'] ?? '') as String),
        lastPlayedAt: DateTime.tryParse((r['last_played_at'] ?? '') as String),
        screenshots: _parseStringList(r['screenshots'] as String?),
        backgroundUrl: (r['background_url'] ?? '') as String,
      );

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'name_cn': nameCn,
        'aliases': aliases.isEmpty ? '' : jsonEncodeMap({'list': aliases}),
        'cover_path': coverPath,
        'developer': developer,
        'release_date': releaseDate,
        'summary': summary,
        'nsfw': nsfw ? 1 : 0,
        'play_status': playStatus.value,
        'user_rating': userRating,
        'user_review': userReview,
        'exe_path': exePath,
        'directory': directory,
        'launch_type': launchType,
        'is_favorite': isFavorite ? 1 : 0,
        'total_seconds': totalSeconds,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'first_played_at': firstPlayedAt?.toIso8601String() ?? '',
        'last_played_at': lastPlayedAt?.toIso8601String() ?? '',
        'screenshots': jsonEncode(screenshots),
        'background_url': backgroundUrl,
      };
}

/// 游戏在某个平台的数据记录。
class SourceRecord {
  int? id;
  int gameId;
  String source; // KisakiSources.*
  String sourceId;
  double rating; // 0-10
  int voteCount;
  Map<String, dynamic> raw;

  SourceRecord({
    this.id,
    required this.gameId,
    required this.source,
    required this.sourceId,
    this.rating = 0,
    this.voteCount = 0,
    this.raw = const {},
  });

  static SourceRecord fromRow(Map<String, dynamic> r) => SourceRecord(
        id: r['id'] as int,
        gameId: r['game_id'] as int,
        source: (r['source'] ?? '') as String,
        sourceId: (r['source_id'] ?? '') as String,
        rating: ((r['rating'] ?? 0) as num).toDouble(),
        voteCount: (r['vote_count'] ?? 0) as int,
        raw: jsonDecodeMap(r['raw'] as String?),
      );

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'game_id': gameId,
        'source': source,
        'source_id': sourceId,
        'rating': rating,
        'vote_count': voteCount,
        'raw': jsonEncodeMap(raw),
      };
}

/// 标签。
class TagItem {
  String name;
  double weight;
  String source;
  TagItem({required this.name, this.weight = 1.0, this.source = ''});

  Map<String, dynamic> toRow(int gameId) => {
        'game_id': gameId,
        'tag': name,
        'weight': weight,
        'source': source,
      };
}

/// 游玩会话。
class GameSession {
  int? id;
  int gameId;
  DateTime start;
  DateTime end;
  int seconds;
  bool closed;

  GameSession({
    this.id,
    required this.gameId,
    required this.start,
    required this.end,
    required this.seconds,
    this.closed = true,
  });

  String get date => fmtDate(start);

  static GameSession fromRow(Map<String, dynamic> r) => GameSession(
        id: r['id'] as int,
        gameId: r['game_id'] as int,
        start: DateTime.parse(r['start_ts'] as String),
        end: DateTime.parse(r['end_ts'] as String),
        seconds: (r['seconds'] ?? 0) as int,
        closed: (r['closed'] ?? 1) as int == 1,
      );

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'game_id': gameId,
        'start_ts': start.toIso8601String(),
        'end_ts': end.toIso8601String(),
        'seconds': seconds,
        'date': fmtDate(start),
        'hour': start.hour,
        'closed': closed ? 1 : 0,
      };
}

/// 聚合统计结果。
class AggStats {
  int totalSeconds;
  int sessionCount;
  int activeDays;
  List<int> byHour; // 24
  List<int> byWeekday; // 7，周一起
  List<DailyPoint> daily; // 时间倒序最近 30/365 天
  List<TopGame> topGames;

  AggStats({
    this.totalSeconds = 0,
    this.sessionCount = 0,
    this.activeDays = 0,
    List<int>? byHour,
    List<int>? byWeekday,
    List<DailyPoint>? daily,
    List<TopGame>? topGames,
  })  : byHour = byHour ?? List.filled(24, 0),
        byWeekday = byWeekday ?? List.filled(7, 0),
        daily = daily ?? [],
        topGames = topGames ?? [];

  int get avgPerActiveDay =>
      activeDays == 0 ? 0 : totalSeconds ~/ activeDays;
}

class DailyPoint {
  final String date; // YYYY-MM-DD
  final int seconds;
  DailyPoint(this.date, this.seconds);
}

class TopGame {
  final int gameId;
  final String name;
  final int seconds;
  TopGame(this.gameId, this.name, this.seconds);
}

/// 主页动态条目。
class ActivityItem {
  final String type; // added / played / finished / rated
  final int gameId;
  final String gameName;
  final String coverPath;
  final DateTime at;
  final String detail;
  ActivityItem({
    required this.type,
    required this.gameId,
    required this.gameName,
    required this.coverPath,
    required this.at,
    this.detail = '',
  });
}
