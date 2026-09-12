/// SQLite 打开与 schema 迁移。
library;


import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int kSchemaVersion = 4;

/// 打开应用数据库。[dbPath] 为完整文件路径（不做二次拼接）。
Future<Database> openAppDb(String dbPath, {Database? inMemoryForTest}) async {
  if (inMemoryForTest != null) return inMemoryForTest;
  final factory = databaseFactoryFfi;
  return factory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) => db.transaction((tx) async {
        for (final ddl in kCreateTables) {
          await tx.execute(ddl);
        }
      }),
      onUpgrade: (db, oldV, newV) async {
        // v2：详情页背景（截图列表 + 背景图）
        if (oldV < 2) {
          await db.execute(
              "ALTER TABLE games ADD COLUMN screenshots TEXT NOT NULL DEFAULT '[]'");
          await db.execute(
              "ALTER TABLE games ADD COLUMN background_url TEXT NOT NULL DEFAULT ''");
        }
        // v4：设备识别与可移植路径（换设备导入数据库时自动重定位游戏目录）
        if (oldV < 4) {
          await db.execute(
              "ALTER TABLE games ADD COLUMN device_id TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE games ADD COLUMN rel_path TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE games ADD COLUMN dir_name TEXT NOT NULL DEFAULT ''");
        }
        // v3：Locale Emulator 转区启动 + 存档目录
        if (oldV < 3) {
          await db.execute(
              "ALTER TABLE games ADD COLUMN locale_mode TEXT NOT NULL DEFAULT 'none'");
          await db.execute(
              "ALTER TABLE games ADD COLUMN save_path TEXT NOT NULL DEFAULT ''");
        }
      },
    ),
  );
}

const List<String> kCreateTables = [
  '''
  CREATE TABLE games (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL DEFAULT '',
    name_cn TEXT NOT NULL DEFAULT '',
    aliases TEXT NOT NULL DEFAULT '',
    cover_path TEXT NOT NULL DEFAULT '',
    developer TEXT NOT NULL DEFAULT '',
    release_date TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    nsfw INTEGER NOT NULL DEFAULT 0,
    play_status INTEGER NOT NULL DEFAULT 1,
    user_rating REAL NOT NULL DEFAULT 0,
    user_review TEXT NOT NULL DEFAULT '',
    exe_path TEXT NOT NULL DEFAULT '',
    directory TEXT NOT NULL DEFAULT '',
    launch_type TEXT NOT NULL DEFAULT 'local',
    is_favorite INTEGER NOT NULL DEFAULT 0,
    total_seconds INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    first_played_at TEXT NOT NULL DEFAULT '',
    last_played_at TEXT NOT NULL DEFAULT '',
    screenshots TEXT NOT NULL DEFAULT '[]',
    background_url TEXT NOT NULL DEFAULT '',
    locale_mode TEXT NOT NULL DEFAULT 'none',
    save_path TEXT NOT NULL DEFAULT '',
    device_id TEXT NOT NULL DEFAULT '',
    rel_path TEXT NOT NULL DEFAULT '',
    dir_name TEXT NOT NULL DEFAULT ''
  )''',
  '''
  CREATE TABLE game_sources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    source TEXT NOT NULL,
    source_id TEXT NOT NULL DEFAULT '',
    rating REAL NOT NULL DEFAULT 0,
    vote_count INTEGER NOT NULL DEFAULT 0,
    raw TEXT NOT NULL DEFAULT '',
    UNIQUE(game_id, source)
  )''',
  '''
  CREATE TABLE game_tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    weight REAL NOT NULL DEFAULT 1.0,
    source TEXT NOT NULL DEFAULT ''
  )''',
  'CREATE INDEX idx_tags_game ON game_tags(game_id)',
  'CREATE INDEX idx_tags_tag ON game_tags(tag)',
  '''
  CREATE TABLE game_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    start_ts TEXT NOT NULL,
    end_ts TEXT NOT NULL,
    seconds INTEGER NOT NULL,
    date TEXT NOT NULL,
    hour INTEGER NOT NULL,
    closed INTEGER NOT NULL DEFAULT 1
  )''',
  'CREATE INDEX idx_sessions_game ON game_sessions(game_id)',
  'CREATE INDEX idx_sessions_date ON game_sessions(date)',
  '''
  CREATE TABLE daily_stats (
    game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    seconds INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(game_id, date)
  )''',
  '''
  CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
  )''',
  '''
  CREATE TABLE accounts (
    platform TEXT PRIMARY KEY,
    token TEXT NOT NULL DEFAULT '',
    extra TEXT NOT NULL DEFAULT '',
    verified_at TEXT NOT NULL DEFAULT ''
  )''',
];
