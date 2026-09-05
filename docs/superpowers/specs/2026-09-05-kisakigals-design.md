# KisakiGals 设计文档

日期：2026-09-05 ｜ 作者：MusaLunar（项目作者署名） ｜ 状态：已获用户批准

## 1. 目标

Windows 桌面 galgame 管理器，高性能、功能全面：游戏库管理、元数据刮削（9 源）、游玩时长统计、评分评价同步上传、插件系统。UI 参考 ReinaManager（Material 风格 + 毛玻璃），数据存储自行设计。

## 2. 技术栈

- Flutter 3.47.2 stable（Windows desktop），界面语言：中文
- flutter_riverpod：状态管理
- sqflite_common_ffi + sqlite3_flutter_libs：SQLite 存储
- dio：HTTP；fl_chart：图表；自研加权词云组件
- window_manager + flutter_acrylic：Mica/Acrylic 毛玻璃（失败回退纯色/渐变）
- dart:ffi（kernel32/user32）：进程枚举与前台窗口检测（时长监控）
- desktop_drop、file_picker：拖拽与选择 exe；cached_network_image：网络封面

## 3. 数据存储

数据目录（便携式）：默认 `<exe目录>/data/`，不可写回退 `%APPDATA%/KisakiGals`，可在设置更改。子目录：`kisakigals.db`、`covers/`、`cache/`、`backups/`、`logs/`、`plugins/`。

SQLite 表：
- `games`：id, name, name_cn, aliases(json), cover_path, developer, release_date, summary, nsfw(int), play_status(1 想玩/2 在玩/3 玩过/4 搁置/5 弃坑), user_rating(real 0-10), user_review(text), exe_path, directory, launch_type(local), is_favorite, created_at, updated_at, first_played_at, last_played_at, total_seconds(int)
- `game_sources`：id, game_id, source(vndb/bgm/ymgal/hikarinagi/steam/cngal/kun/touchgal/dlsite/custom), source_id, rating(real), vote_count(int), raw(json)
- `game_tags`：game_id, tag, weight(real), source
- `game_sessions`：id, game_id, start_ts, end_ts, seconds, date(YYYY-MM-DD), hour(0-23)
- `daily_stats`：game_id, date, seconds（会话落库时增量聚合）
- `settings`：key TEXT PK, value TEXT(json)
- `accounts`：platform PK, token, extra(json), verified_at

## 4. 元数据刮削

统一模型 `ScrapedGame{name, nameCn, aliases, coverUrl, developer, releaseDate, summary, rating(0-10), voteCount, tags[{name,weight,isSpoiler}], screenshots[], nsfw, source, sourceId}`。每源一个 Adapter（search / fetchById / 字段映射）。MetadataFetcher 并发查启用源（Future.wait + 每源 try-catch），最佳匹配打分：去标点小写后 精确=100/前缀=40/包含=20。每源限流（最小间隔+60s 滑动窗口，429 退避重试一次）。磁盘缓存 24h（`cache/metadata/`）。封面原图下载入 `covers/`。

| 源 | 端点 | 鉴权 |
|---|---|---|
| VNDB | POST https://api.vndb.org/kana/vn `{filters:["search","=",kw], fields:"id,title,titles{lang,title},image{url},screenshots{url},description,rating,votecount,released,developers{name},tags{name,rating,spoiler},length_minutes", sort:"searchrank"}` | 可选 Token |
| Bangumi | POST https://api.bgm.tv/v0/search/subjects `{keyword,sort:"rank",filter:{type:[4],nsfw:true}}`；GET /v0/subjects/{id} | 可选 PAT Bearer |
| ymgal | GET www.ymgal.games/oauth/token（client_id=ymgal&client_secret=luna0327&scope=public）→ GET /open/archive/search-game?mode=accurate&keyword=（头 version:1, Accept json） | client_credentials |
| Hikarinagi | POST id.hikarinagi.org/oidc/token（Basic hkn_/hks_ 凭据，scope=catalog:read）→ GET www.hikarinagi.org/api/v3/open/search?q=&types=galgame → /galgames/{id} | client_credentials |
| Steam | GET store.steampowered.com/api/storesearch/?term=&l=schinese&cc=CN → /api/appdetails?appids= | 无 |
| CnGal | api.cngal.org 搜索/详情接口 | 无 |
| Kun | GET www.kungal.com/api/search?keywords=&type=galgame → /api/galgame/{id} | 无 |
| TouchGal | GET developer.touchgal.com/api/v1/games/search?... | 无 |
| DLsite | HTML 刮削 dlsite.com（可选，默认关闭） | 无 |

VNDB 标签英→中：复用 ChronoTide 内置 MIT 资源 `vndb_tags_zh_cn.json`（~3000 条，assets 内置）。评分统一归一化到 0-10。NSFW：VNDB 标签/Bangumi nsfw 字段判定，封面可模糊或替换占位图（设置项）。

## 5. 评价上传（账号同步）

- Bangumi：PAT（设置粘贴+测试 `GET /v0/me`）→ `POST /v0/users/-/collections/{sid}` body `{type, rate(1-10), comment}`
- VNDB：API Token（listwrite 权限）→ `PATCH https://api.vndb.org/kana/ulist/{vid}` body `{vote: 10-100}`
- Hikarinagi：Token → `PUT https://api.hikarinagi.org/v3/user/me/rates/galgames/{id}`

详情页评分弹窗：评分 + 文字评价 + 三平台勾选，逐个上传并显示结果。

## 6. 时长监控

启动 exe（Process.start，工作目录=游戏目录）→ 监控循环 1s：CreateToolhelp32Snapshot 枚举进程，匹配 exe 同目录的进程集合（含子进程）；GetForegroundWindow→GetWindowThreadProcessId 判断前台归属。两种模式：「仅前台计时」/「挂机即计时」。会话结束（进程消失≥3 次连续）落库 game_sessions + daily_stats，支持崩溃恢复（启动时结转未闭合会话）。游戏启动后动作可配置（最小化到托盘/无）。

## 7. UI 结构

左侧 NavigationRail：主页 / 游戏库 / 统计 / 设置。Material 3，主题：樱花粉(#F48FB1/#F8BBD0) × 藤紫(#B39DDB/#D1C4E9) × 奶油白(#FFF8F2)，暗色同套色。圆角 16-24 卡片 + 毛玻璃面板 + 细腻阴影。NSFW 封面按设置模糊/占位。

- **主页**：StatCard（周/月/总：时长、会话、完成数）；HeroCard（近 30 天游玩封面轮播、继续游戏按钮、上次游玩时间）；ActivityTimeline（添加/游玩/完成记录）；RecommendationCard（基于库内标签权重从 VNDB 搜索推荐，可刷新）；另加快捷入口行。
- **游戏库**：自适应网格（封面 2:3 竖版卡片+名称），筛选（游玩状态/标签/开发商/来源/收藏），搜索（名称/别名/开发商/标签），排序（添加日期/上次游玩/我的评分/VNDB/Bangumi 等平台评分/总时长/名称）。「添加游戏」按钮。
- **统计**：信息页（总时长/活跃天数/日均/会话数、24h 时段分布柱状图、近 30 天趋势线、Top 游戏榜、星期分布）；评分页（我的评分墙 + 平台评分对比）；总结页（周/月/年/全部 标签词云 + 规则生成总结文本）。
- **设置**（左导航六类）：系统（开机自启、游戏启动后动作、计时模式、NSFW 处理、主题、关闭行为）；账号（bgm/vndb/hikarinagi 登录态与测试）；数据源（每源启用开关、VNDB/Bangumi Token、刮削并发与 NSFW 选项、测试连接）；数据（存储目录、备份/恢复、清理缓存）；插件（列表/开关/每插件设置/导入）；关于（版本、检查更新、作者 MusaLunar、项目地址占位）。
- **添加游戏**：选择/拖拽 exe → 自动以文件名搜索刮削 → 多源结果选择 → 确认入库；或自定义添加（手填名称/封面/标签）；可填平台 ID 直取。
- **游戏详情**：封面+标题+开发商+发售日+平台评分行；标签；简介；我的评分评价（弹窗，可同步上传）；统计（总时长/次数/最近）；操作（启动/打开目录/编辑信息/重新刮削/删除）；截图条。

## 8. 插件系统

轻量内置插件架构：`KisakiPlugin` 接口（id/名称/描述/onInit/settingsSchema/buildSettingsWidgets），内置插件：① 自动备份（每日备份 db 到 backups/，保留 N 份）② NSFW 封面保护（模糊）③ 闲置提醒（前台游戏超时长提醒休息）。插件页提供开关与设置；`data/plugins/*.json` 清单导入为占位扩展点（v1 支持导入并展示信息）。

## 9. 图标

Pillow 处理 `icon_source.jpg`：中心方裁 → 圆角蒙版（半径≈22%）→ 多尺寸 PNG（512/256/128/64/48/32/16）→ `runner.ico`（Flutter Windows runner 资源）+ 应用内 logo PNG。

## 10. 错误处理与测试

- 网络：每源独立失败不互相影响；超时 10s/接收 15s；离线可用（本地库完整功能）。
- DB：事务写入；schema 版本迁移函数。
- 测试：模型/归一化/匹配打分/限流器/会话聚合单元测试（flutter test）；UI 以构建运行 + 截图视觉验收。
