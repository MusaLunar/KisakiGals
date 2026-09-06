/// 游戏仓储：games/game_sources/game_tags/game_sessions/daily_stats 的访问与聚合。
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import 'models.dart';

class GameRepository {
  final Database db;
  GameRepository(this.db);

  // ---------- games ----------

  Future<int> insertGame(Game g) async {
    final id = await db.insert('games', g.toRow());
    g.id = id;
    return id;
  }

  Future<void> updateGame(Game g) async {
    g.updatedAt = DateTime.now();
    await db.update('games', g.toRow(), where: 'id = ?', whereArgs: [g.id]);
  }

  Future<void> deleteGame(int id) async {
    await db.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  Future<Game?> getGame(int id) async {
    final rows =
        await db.query('games', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Game.fromRow(rows.first);
  }

  /// 组合筛选 + 搜索 + 排序。
  Future<List<Game>> listGames({
    String? query,
    PlayStatus? status,
    String? tag,
    String? developer,
    String? source,
    bool? favorite,
    GameSort sort = GameSort.addedDesc,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      where.add(
          '(name LIKE ? OR name_cn LIKE ? OR aliases LIKE ? OR developer LIKE ? OR EXISTS(SELECT 1 FROM game_tags t WHERE t.game_id = games.id AND t.tag LIKE ?))');
      args.addAll([q, q, q, q, q]);
    }
    if (status != null) {
      where.add('play_status = ?');
      args.add(status.value);
    }
    if (developer != null && developer.isNotEmpty) {
      where.add('developer = ?');
      args.add(developer);
    }
    if (favorite != null) {
      where.add('is_favorite = ?');
      args.add(favorite ? 1 : 0);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add(
          'EXISTS(SELECT 1 FROM game_tags t WHERE t.game_id = games.id AND t.tag = ?)');
      args.add(tag);
    }
    if (source != null && source.isNotEmpty) {
      where.add(
          'EXISTS(SELECT 1 FROM game_sources s WHERE s.game_id = games.id AND s.source = ?)');
      args.add(source);
    }

    const orderBy = {
      GameSort.addedDesc: 'created_at DESC',
      GameSort.lastPlayedDesc: 'last_played_at DESC',
      GameSort.userRatingDesc: 'user_rating DESC',
      GameSort.playtimeDesc: 'total_seconds DESC',
      GameSort.nameAsc: 'name_cn COLLATE NOCASE ASC',
      GameSort.platformRatingDesc: null, // 需要联表，特殊处理
    };
    String sql;
    if (sort == GameSort.platformRatingDesc) {
      sql = '''
        SELECT games.*, COALESCE(MAX(gs.rating), 0) AS best_platform_rating
        FROM games
        LEFT JOIN game_sources gs ON gs.game_id = games.id
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY games.id
        ORDER BY best_platform_rating DESC
      ''';
    } else {
      sql = 'SELECT * FROM games ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY ${orderBy[sort]}';
    }
    final rows = await db.rawQuery(sql, args);
    return rows.map(Game.fromRow).toList();
  }

  /// 平台评分最高值（排序/展示用）。
  Future<Map<int, double>> bestPlatformRatings() async {
    final rows = await db.rawQuery(
        'SELECT game_id, MAX(rating) AS r FROM game_sources GROUP BY game_id');
    return {
      for (final r in rows) r['game_id'] as int: ((r['r'] ?? 0) as num).toDouble()
    };
  }

  // ---------- tags / sources ----------

  Future<void> setTags(int gameId, List<TagItem> tags) async {
    await db.transaction((tx) async {
      await tx.delete('game_tags', where: 'game_id = ?', whereArgs: [gameId]);
      for (final t in tags) {
        await tx.insert('game_tags', t.toRow(gameId));
      }
    });
  }

  Future<List<TagItem>> tagsOf(int gameId) async {
    final rows = await db.query('game_tags',
        where: 'game_id = ?', whereArgs: [gameId], orderBy: 'weight DESC');
    return rows
        .map((r) => TagItem(
              name: (r['tag'] ?? '') as String,
              weight: ((r['weight'] ?? 1) as num).toDouble(),
              source: (r['source'] ?? '') as String,
            ))
        .toList();
  }

  /// 库内全部标签（按累计权重排序），筛选栏用。
  Future<List<TagItem>> allTags({int limit = 200}) async {
    final rows = await db.rawQuery(
        'SELECT tag, SUM(weight) AS w FROM game_tags GROUP BY tag ORDER BY w DESC LIMIT ?',
        [limit]);
    return rows
        .map((r) => TagItem(
            name: r['tag'] as String, weight: ((r['w'] ?? 0) as num).toDouble()))
        .toList();
  }

  Future<void> upsertSource(int gameId, SourceRecord rec) async {
    rec.gameId = gameId;
    final count = await db.update('game_sources', rec.toRow(),
        where: 'game_id = ? AND source = ?', whereArgs: [gameId, rec.source]);
    if (count == 0) {
      await db.insert('game_sources', rec.toRow());
    }
  }

  Future<List<SourceRecord>> sourcesOf(int gameId) async {
    final rows = await db.query('game_sources',
        where: 'game_id = ?', whereArgs: [gameId]);
    return rows.map(SourceRecord.fromRow).toList();
  }

  /// 平台 id → 本地游戏 索引（云端同步匹配用）。
  /// key 形如「vndb:v123」「bgm:45678」，VNDB 的「v」前缀已归一。
  Future<Map<String, Game>> sourceIndex() async {
    final rows = await db.rawQuery(
        'SELECT gs.source AS src, gs.source_id AS sid, g.* '
        'FROM game_sources gs JOIN games g ON g.id = gs.game_id');
    final map = <String, Game>{};
    for (final r in rows) {
      final source = (r['src'] ?? '') as String;
      var sid = ((r['sid'] ?? '') as String).trim();
      if (sid.isEmpty) continue;
      if (source == 'vndb' && sid.startsWith('v')) sid = sid.substring(1);
      final g = Game.fromRow(r);
      map['$source:$sid'] ??= g;
    }
    return map;
  }

  /// 库内开发商列表（筛选栏用）。
  Future<List<String>> developers() async {
    final rows = await db.query('games',
        columns: ['developer'],
        where: "developer != ''",
        groupBy: 'developer',
        orderBy: 'developer');
    return rows.map((r) => r['developer'] as String).toList();
  }

  Future<List<String>> usedSources() async {
    final rows = await db.rawQuery(
        'SELECT DISTINCT source FROM game_sources ORDER BY source');
    return rows.map((r) => r['source'] as String).toList();
  }

  // ---------- sessions ----------

  /// 记录会话并同步聚合（games.total_seconds / last_played / first_played + daily_stats）。
  Future<void> addSession(GameSession s) async {
    await db.transaction((tx) async {
      await tx.insert('game_sessions', s.toRow());
      await tx.rawUpdate(
          'INSERT INTO daily_stats(game_id, date, seconds) VALUES(?, ?, ?) '
          'ON CONFLICT(game_id, date) DO UPDATE SET seconds = seconds + ?',
          [s.gameId, s.date, s.seconds, s.seconds]);
      await tx.rawUpdate(
          'UPDATE games SET total_seconds = total_seconds + ?, '
          'last_played_at = ?, '
          "first_played_at = CASE WHEN first_played_at = '' THEN ? ELSE first_played_at END "
          'WHERE id = ?',
          [s.seconds, s.end.toIso8601String(), s.start.toIso8601String(), s.gameId]);
    });
  }

  /// 崩溃恢复：把未闭合会话按其实际时长结转。
  Future<void> recoverUnclosedSession(GameSession s) async {
    final rows = await db.query('game_sessions',
        where: 'game_id = ? AND closed = 0', whereArgs: [s.gameId]);
    for (final r in rows) {
      final session = GameSession.fromRow(r);
      await db.update('game_sessions', {'closed': 1},
          where: 'id = ?', whereArgs: [session.id]);
      await addSession(session);
    }
  }

  // ---------- 聚合统计 ----------

  Future<AggStats> stats({required StatsPeriod period}) async {
    final now = DateTime.now();
    DateTime from;
    switch (period) {
      case StatsPeriod.week:
        from = now.subtract(Duration(days: now.weekday - 1));
      case StatsPeriod.month:
        from = DateTime(now.year, now.month, 1);
      case StatsPeriod.year:
        from = DateTime(now.year, 1, 1);
      case StatsPeriod.all:
        from = DateTime(2000);
    }
    final fromDate = fmtDate(from);
    final today = fmtDate(now);

    final total = await db.rawQuery(
        'SELECT COALESCE(SUM(seconds),0) AS s, COUNT(*) AS c FROM game_sessions WHERE date >= ?',
        [fromDate]);
    final totalSeconds = (total.first['s'] ?? 0) as int;
    final sessionCount = (total.first['c'] ?? 0) as int;

    final days = await db.rawQuery(
        'SELECT COUNT(DISTINCT date) AS d FROM game_sessions WHERE date >= ?',
        [fromDate]);
    final activeDays = (days.first['d'] ?? 0) as int;

    final agg = AggStats(
      totalSeconds: totalSeconds,
      sessionCount: sessionCount,
      activeDays: activeDays,
    );

    final hours = await db.rawQuery(
        'SELECT hour, SUM(seconds) AS s FROM game_sessions WHERE date >= ? GROUP BY hour',
        [fromDate]);
    for (final r in hours) {
      final h = (r['hour'] ?? 0) as int;
      if (h >= 0 && h < 24) agg.byHour[h] = (r['s'] ?? 0) as int;
    }

    final wd = await db.rawQuery(
        "SELECT CAST(strftime('%w', date) AS INTEGER) AS w, SUM(seconds) AS s "
        'FROM game_sessions WHERE date >= ? GROUP BY w',
        [fromDate]);
    for (final r in wd) {
      final w = (((r['w'] ?? 0) as int) + 6) % 7; // 周日 0 → 周一 0
      agg.byWeekday[w] = (r['s'] ?? 0) as int;
    }

    final dailyRows = await db.rawQuery(
        'SELECT date, SUM(seconds) AS s FROM daily_stats WHERE date >= ? AND date <= ? '
        'GROUP BY date ORDER BY date',
        [fromDate, today]);
    agg.daily = dailyRows
        .map((r) => DailyPoint(r['date'] as String, (r['s'] ?? 0) as int))
        .toList();

    final top = await db.rawQuery(
        'SELECT ds.game_id, COALESCE(NULLIF(g.name_cn, ""), g.name) AS name, SUM(ds.seconds) AS s '
        'FROM daily_stats ds LEFT JOIN games g ON g.id = ds.game_id '
        'WHERE ds.date >= ? GROUP BY ds.game_id ORDER BY s DESC LIMIT 10',
        [fromDate]);
    agg.topGames = top
        .map((r) => TopGame(
            (r['game_id'] ?? 0) as int,
            (r['name'] ?? '未知') as String,
            (r['s'] ?? 0) as int))
        .toList();

    return agg;
  }

  /// 词云数据：库内标签累计权重，可按时段过滤。
  Future<List<TagItem>> tagCloud({required StatsPeriod period}) async {
    final now = DateTime.now();
    DateTime from;
    switch (period) {
      case StatsPeriod.week:
        from = now.subtract(const Duration(days: 7));
      case StatsPeriod.month:
        from = DateTime(now.year, now.month, 1);
      case StatsPeriod.year:
        from = DateTime(now.year, 1, 1);
      case StatsPeriod.all:
        from = DateTime(2000);
    }
    final rows = await db.rawQuery(
        'SELECT gt.tag AS tag, SUM(gt.weight) AS w FROM game_tags gt '
        'WHERE gt.game_id IN (SELECT DISTINCT game_id FROM game_sessions WHERE date >= ?) '
        'GROUP BY gt.tag ORDER BY w DESC LIMIT 60',
        [fmtDate(from)]);
    if (rows.isEmpty && period != StatsPeriod.all) {
      return tagCloud(period: StatsPeriod.all);
    }
    return rows
        .map((r) => TagItem(
            name: r['tag'] as String, weight: ((r['w'] ?? 0) as num).toDouble()))
        .toList();
  }

  /// 主页动态：添加 + 游玩 + 评分记录合并。
  Future<List<ActivityItem>> recentActivity({int limit = 30}) async {
    final rows = await db.rawQuery('''
      SELECT 'played' AS type, game_id, start_ts AS at, '' AS detail FROM game_sessions
      UNION ALL
      SELECT 'added' AS type, id, created_at AS at, '' AS detail FROM games
      UNION ALL
      SELECT 'rated' AS type, id, updated_at AS at, user_review AS detail FROM games WHERE user_rating > 0
      ORDER BY at DESC LIMIT ?
    ''', [limit]);
    final result = <ActivityItem>[];
    for (final r in rows) {
      final gid = (r['game_id'] ?? 0) as int;
      final g = await getGame(gid);
      if (g == null) continue;
      result.add(ActivityItem(
        type: (r['type'] ?? 'played') as String,
        gameId: gid,
        gameName: g.displayName,
        coverPath: g.coverPath,
        at: DateTime.tryParse((r['at'] ?? '') as String) ?? DateTime.now(),
        detail: (r['detail'] ?? '') as String,
      ));
    }
    return result;
  }

  /// 未开始游玩的游戏数量等总览。
  Future<int> gameCount() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM games');
    return (r.first['c'] ?? 0) as int;
  }
}
