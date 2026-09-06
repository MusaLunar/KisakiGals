"""ReinaManager → KisakiGals 数据迁移脚本。

用法：
  python tool/migrate_reinamanager.py <reina_backup.db> [--kisakigals-data <目录>] [--dry-run]

说明：
- <reina_backup.db>：ReinaManager 的 SQLite 备份（如
  E:/ReinaManager/resources/data/backups/reina_manager_20260906_170628.db）
- --kisakigals-data：KisakiGals 数据目录（含 kisakigals.db 与 covers/）。
  缺省时按 优先级尝试：--out 显式路径 > ./data > Release/data > Debug/data
- 不存在目标库时会按 KisakiGals v2 schema 自动建库
- 默认 dry-run 只打印将迁移的内容；加 --yes 实际写入
- 封面：从 ReinaManager covers/game_{id}/{image} 复制到 KisakiGals covers/
- 迁移内容：游戏（名称/别名/简介/开发商/发售日/评分/状态/时长/时间戳/封面）、
  平台数据（ymgal/vndb/kun…的 id 与评分）、游玩会话、每日统计、平台 Token
- 幂等：按「归一化名称」查重，已存在的游戏跳过
"""

import argparse
import json
import os
import re
import shutil
import sqlite3
import sys
from datetime import datetime, timezone

# ---------------- KisakiGals schema（v2） ----------------

K_SCHEMA = """
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
  background_url TEXT NOT NULL DEFAULT ''
);
CREATE TABLE game_sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  source_id TEXT NOT NULL DEFAULT '',
  rating REAL NOT NULL DEFAULT 0,
  vote_count INTEGER NOT NULL DEFAULT 0,
  raw TEXT NOT NULL DEFAULT '',
  UNIQUE(game_id, source)
);
CREATE TABLE game_tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  weight REAL NOT NULL DEFAULT 1.0,
  source TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_tags_game ON game_tags(game_id);
CREATE INDEX idx_tags_tag ON game_tags(tag);
CREATE TABLE game_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  start_ts TEXT NOT NULL,
  end_ts TEXT NOT NULL,
  seconds INTEGER NOT NULL,
  date TEXT NOT NULL,
  hour INTEGER NOT NULL,
  closed INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX idx_sessions_game ON game_sessions(game_id);
CREATE INDEX idx_sessions_date ON game_sessions(date);
CREATE TABLE daily_stats (
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  seconds INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(game_id, date)
);
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT ''
);
CREATE TABLE accounts (
  platform TEXT PRIMARY KEY,
  token TEXT NOT NULL DEFAULT '',
  extra TEXT NOT NULL DEFAULT '',
  verified_at TEXT NOT NULL DEFAULT ''
);
"""

# ReinaManager clear → KisakiGals PlayStatus.value
CLEAR_TO_STATUS = {
    0: 1,  # 未玩 → 想玩
    1: 1,  # 想玩
    2: 3,  # 已通关 → 玩过
    3: 2,  # 在玩
    4: 5,  # 弃坑
}

PLATFORM_TOKEN_MAP = {
    'bgm_auth': 'bgm',
    'vndb_token': 'vndb',
    'hikarinagi_auth': 'hikarinagi',
}


def iso(ts) -> str:
    """unix 秒 → 本地时间 ISO（KisakiGals 存本地时间字符串）。"""
    if not ts:
        return ''
    try:
        return datetime.fromtimestamp(int(ts)).isoformat()
    except (ValueError, OSError, OverflowError):
        return ''


def norm_key(name: str) -> str:
    """归一化名称用于查重：小写、去符号去空白。"""
    return re.sub(r'[^0-9a-z\u3400-\u9fff]+', '', (name or '').lower())


def find_cover(reina_covers_dir: str, game_id: int, image_name: str) -> str:
    """covers/game_{id}/ 下找封面：优先精确名 → 后缀匹配 → 第一张。"""
    d = os.path.join(reina_covers_dir, f'game_{game_id}')
    if not os.path.isdir(d):
        return ''
    files = sorted(os.listdir(d))
    if not files:
        return ''
    if image_name:
        p = os.path.join(d, image_name)
        if os.path.isfile(p):
            return p
        for f in files:  # ReinaManager 会加 cover_N_ 前缀
            if f.endswith(image_name):
                return os.path.join(d, f)
    return os.path.join(d, files[0])


def guess_ext(path_or_name: str) -> str:
    m = re.search(r'(webp|png|jpe?g|gif|avif)', (path_or_name or '').lower())
    return ('.' + m.group(1)) if m else '.jpg'


def main():
    ap = argparse.ArgumentParser(description='ReinaManager → KisakiGals 迁移')
    ap.add_argument('reina_db', help='ReinaManager 备份 db 路径')
    ap.add_argument('--kisakigals-data', help='KisakiGals 数据目录')
    ap.add_argument('--out', help='直接指定目标 kisakigals.db 路径')
    ap.add_argument('--dry-run', action='store_true', help='只统计不写入（默认）')
    ap.add_argument('--yes', action='store_true', help='实际写入')
    args = ap.parse_args()

    if not os.path.isfile(args.reina_db):
        print(f'找不到 ReinaManager 备份：{args.reina_db}')
        sys.exit(1)

    # 目标库路径
    out_db = args.out
    if not out_db:
        data_dir = args.kisakigals_data
        if not data_dir:
            candidates = [
                os.path.join(os.getcwd(), 'data'),
                os.path.join(os.getcwd(),
                             'build/windows/x64/runner/Release/data'),
                os.path.join(os.getcwd(),
                             'build/windows/x64/runner/Debug/data'),
            ]
            data_dir = next(
                (c for c in candidates if os.path.isfile(
                    os.path.join(c, 'kisakigals.db'))), None)
            if data_dir is None:
                data_dir = candidates[1] if os.path.isdir(candidates[1]) \
                    else candidates[0]
        out_db = os.path.join(data_dir, 'kisakigals.db')

    os.makedirs(os.path.dirname(out_db) or '.', exist_ok=True)
    covers_dir = os.path.join(os.path.dirname(out_db), 'covers')
    base = os.path.dirname(os.path.abspath(args.reina_db))
    candidates = [
        os.path.normpath(os.path.join(base, '..', 'covers')),        # data/covers
        os.path.normpath(os.path.join(base, '..', '..', 'covers')),  # resources/covers
        os.path.normpath(os.path.join(base, 'covers')),              # backups/covers
        r'E:\ReinaManager\resources\covers',
    ]
    reina_covers_dir = next(
        (c for c in candidates if os.path.isdir(c)), candidates[0])
    print(f'ReinaManager 封面目录：{reina_covers_dir}'
          f'（存在={os.path.isdir(reina_covers_dir)}）')

    fresh = not os.path.isfile(out_db)
    con_out = sqlite3.connect(out_db)
    if fresh:
        con_out.executescript(K_SCHEMA)
        print(f'已创建目标库：{out_db}')

    existing = {}
    for gid, name, name_cn, aliases, exe in con_out.execute(
            'SELECT id, name, name_cn, aliases, exe_path FROM games'):
        keys = {norm_key(name), norm_key(name_cn)}
        try:
            for a in json.loads(aliases or '{}').get('list', []):
                keys.add(norm_key(a))
        except json.JSONDecodeError:
            pass
        keys.discard('')
        for k in keys:
            existing.setdefault(k, gid)
        if exe:
            existing.setdefault('exe:' + exe.lower().replace('\\', '/'), gid)

    src = sqlite3.connect(args.reina_db)
    src.row_factory = sqlite3.Row

    stats_rows = {r['game_id']: r for r in src.execute(
        'SELECT * FROM game_statistics')}
    sources_rows = {}
    for r in src.execute('SELECT * FROM game_sources'):
        sources_rows.setdefault(r['game_id'], []).append(r)

    write = args.yes and not args.dry_run
    if args.dry_run and args.yes:
        print('--dry-run 与 --yes 同时给出，按 dry-run 处理')
        write = False

    migrated = skipped = 0
    session_total = 0
    daily_total = 0
    src_total = 0
    cover_total = 0
    new_ids = []

    for g in src.execute('SELECT * FROM games ORDER BY id'):
        try:
            custom = json.loads(g['custom_data'] or '{}')
        except json.JSONDecodeError:
            custom = {}
        name = (custom.get('name') or '').strip()
        if not name:
            name = os.path.basename(g['localpath'] or '')
        aliases = [a for a in (custom.get('aliases') or [])
                   if isinstance(a, str) and a.strip()]

        # 查重：归一化名称 / exe 路径
        keys = {norm_key(name), *(norm_key(a) for a in aliases)}
        keys.discard('')
        exe_path = ''
        if g['localpath'] and g['executable']:
            exe_path = os.path.join(g['localpath'], g['executable'])
        exe_key = ('exe:' + exe_path.lower().replace('\\', '/')) \
            if exe_path else None
        if keys & existing.keys() or (exe_key and exe_key in existing):
            skipped += 1
            continue

        stat = stats_rows.get(g['id'])
        sessions = list(src.execute(
            'SELECT * FROM game_sessions WHERE game_id = ?', (g['id'],)))
        first_play = min((s['start_time'] for s in sessions), default=None)
        summary = custom.get('summary') or ''
        tags = [t for t in (custom.get('tags') or [])
                if isinstance(t, str) and t.strip()]
        rating = float(custom.get('user_rating') or g['user_rating'] or 0)
        play_status = CLEAR_TO_STATUS.get(g['clear'], 1)
        total_seconds = int((stat['total_time'] if stat else 0)) * 60
        last_played = iso(stat['last_played']) if stat else ''
        created = iso(g['created_at']) or datetime.now().isoformat()
        updated = iso(g['updated_at']) or created

        if write:
            cur = con_out.execute(
                "INSERT INTO games (name, name_cn, aliases, cover_path,"
                " developer, release_date, summary, nsfw, play_status,"
                " user_rating, exe_path, directory, total_seconds,"
                " created_at, updated_at, first_played_at, last_played_at)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (name, '', json.dumps({'list': aliases}, ensure_ascii=False),
                 '', custom.get('developer') or '', g['date'] or '',
                 summary, 0, play_status, rating, exe_path,
                 g['localpath'] or '', total_seconds, created, updated,
                 iso(first_play), last_played))
            new_id = cur.lastrowid
            # 平台数据
            for s in sources_rows.get(g['id'], []):
                try:
                    con_out.execute(
                        "INSERT OR REPLACE INTO game_sources"
                        " (game_id, source, source_id, rating, vote_count,"
                        " raw) VALUES (?,?,?,?,?,?)",
                        (new_id, s['source'], s['external_id'] or '',
                         float(s['score'] or 0), 0, s['data'] or ''))
                    src_total += 1
                except sqlite3.IntegrityError:
                    pass
            # 标签
            for i, t in enumerate(tags):
                con_out.execute(
                    "INSERT INTO game_tags (game_id, tag, weight, source)"
                    " VALUES (?,?,?,?)",
                    (new_id, t, max(0.2, 1.0 - i * 0.02), 'reina'))
            # 会话（duration 为分钟）
            for sess in sessions:
                start = iso(sess['start_time'])
                end = iso(sess['end_time'])
                if not start or not end:
                    continue
                con_out.execute(
                    "INSERT INTO game_sessions (game_id, start_ts, end_ts,"
                    " seconds, date, hour, closed) VALUES (?,?,?,?,?,?,1)",
                    (new_id, start, end,
                     int(sess['duration'] or 0) * 60,
                     sess['date'] or start[:10],
                     datetime.fromtimestamp(sess['start_time']).hour))
                session_total += 1
            # 每日统计
            if stat and stat['daily_stats']:
                try:
                    for d in json.loads(stat['daily_stats']):
                        con_out.execute(
                            "INSERT OR REPLACE INTO daily_stats"
                            " (game_id, date, seconds) VALUES (?,?,?)",
                            (new_id, d.get('date', ''),
                             int(d.get('playtime', 0)) * 60))
                        daily_total += 1
                except json.JSONDecodeError:
                    pass
            # 封面复制
            cover_src = find_cover(reina_covers_dir, g['id'],
                                   custom.get('image') or '')
            if cover_src:
                ext = guess_ext(cover_src)
                dst = os.path.join(covers_dir, f'game_{new_id}{ext}')
                try:
                    os.makedirs(covers_dir, exist_ok=True)
                    shutil.copyfile(cover_src, dst)
                    con_out.execute(
                        'UPDATE games SET cover_path = ? WHERE id = ?',
                        (dst, new_id))
                    cover_total += 1
                except OSError as e:
                    print(f'  封面复制失败 game_{g["id"]}: {e}')
            con_out.commit()
            new_ids.append((new_id, name))

        # 查重登记（无论是否写入，避免同轮重复）
        for k in keys:
            existing.setdefault(k, -1)
        if exe_key:
            existing.setdefault(exe_key, -1)
        migrated += 1

    # 平台 Token
    token_row = src.execute('SELECT * FROM user LIMIT 1').fetchone()
    tokens = []
    if token_row:
        for col, platform in PLATFORM_TOKEN_MAP.items():
            v = (token_row[col] or '').strip() if token_row[col] else ''
            if v:
                tokens.append((platform, v))
                if write:
                    con_out.execute(
                        "INSERT OR REPLACE INTO accounts"
                        " (platform, token, extra, verified_at)"
                        " VALUES (?,?,?,?)",
                        (platform, v, json.dumps({'from': 'ReinaManager'}),
                         datetime.now().isoformat()))
    if write and tokens:
        con_out.commit()

    mode = '已写入' if write else 'dry-run（未写入，加 --yes 执行）'
    print(f'[{mode}]')
    print(f'  游戏：迁移 {migrated} 部，跳过（已存在）{skipped} 部')
    print(f'  平台数据：{src_total} 条；游玩会话：{session_total} 条；'
          f'每日统计：{daily_total} 天；封面：{cover_total} 张')
    if tokens:
        print(f'  平台 Token：{", ".join(t[0] for t in tokens)}')
    if new_ids:
        for nid, name in new_ids[:10]:
            print(f'  + #{nid} {name}')
        if len(new_ids) > 10:
            print(f'  … 共 {len(new_ids)} 部')
    print(f'目标库：{out_db}')
    con_out.close()
    src.close()


if __name__ == '__main__':
    main()
