# KisakiGals 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans（本会话内联执行）。

**Goal:** Flutter Windows 桌面 galgame 管理器：四 Tab（主页/游戏库/统计/设置）+ 添加游戏 + 详情页 + 9 源刮削 + 时长监控 + 评价同步上传 + 插件。

**Architecture:** Riverpod 单仓分层：`core`（路径/工具）、`data`（SQLite 仓储）、`scraping`（源适配器+调度）、`services`（监控/上传/插件/备份）、`ui`（主题+外壳+各页）。设计文档：`docs/superpowers/specs/2026-09-05-kisakigals-design.md`。

**Tech Stack:** Flutter 3.47.2 · flutter_riverpod · sqflite_common_ffi + sqlite3_flutter_libs · dio · fl_chart · window_manager + flutter_acrylic · cached_network_image · desktop_drop · file_picker · dart:ffi(Win32)

## Global Constraints

- SDK：`export PATH=/e/flutter/bin:$PATH; export PUB_CACHE=/e/flutter/pub-cache`（每个 shell 都要带）
- UI 全中文；`flutter analyze` 0 error；每任务 `flutter test` 通过后 `git commit`
- 数据目录便携式：`<exe>/data/` 优先，回退 `%APPDATA%/KisakiGals`
- 评分统一 0-10；NSFW 封面按设置模糊/占位
- 界面文案不得出现占位词；版本 0.1.0；作者 MusaLunar

## 文件结构

```
lib/main.dart, lib/app.dart
lib/core/{paths,constants,utils}.dart
lib/data/{db,models,game_repository,settings_store,account_store,metadata_cache}.dart
lib/scraping/{scraped_game,source_adapter,rate_limiter,tag_translator,metadata_fetcher}.dart
lib/scraping/sources/{vndb,bangumi,ymgal,hikarinagi,steam,cngal,kun,touchgal,dlsite}.dart
lib/services/{process_monitor,game_launcher,autostart,backup_service,plugin_system}.dart
lib/services/upload/{bangumi_upload,vndb_upload,hikarinagi_upload}.dart
lib/ui/{theme,shell}.dart
lib/ui/widgets/{cover_image,glass_panel,rating_stars,empty_state}.dart
lib/ui/home/{home_page,stat_card,hero_card,timeline_card,recommendation_card}.dart
lib/ui/library/{library_page,game_card,filter_bar}.dart
lib/ui/stats/{stats_page,info_tab,ratings_tab,summary_tab,word_cloud}.dart
lib/ui/settings/{settings_page,system_section,account_section,source_section,data_section,plugin_section,about_section}.dart
lib/ui/add/{add_game_page,scrape_step,custom_step}.dart
lib/ui/detail/{game_detail_page,rate_dialog,edit_sheet}.dart
assets/data/vndb_tags_zh_cn.json   ← 复制自 .reference/chronotide/assets/data/（MIT）
assets/logo/logo_*.png
windows/runner/runner.ico
test/{utils_test,db_test,scraping_test,sessions_test}.dart
```

## 关键接口（跨任务契约）

```dart
// core/constants.dart
enum PlayStatus { wish, playing, played, onHold, dropped }  // 存 int 1-5
enum TimeTrackingMode { foreground, elapsed }
class KisakiSources { static const vndb='vndb', bangumi='bgm', ymgal='ymgal', hikarinagi='hikarinagi', steam='steam', cngal='cngal', kun='kun', touchgal='touchgal', dlsite='dlsite', custom='custom'; }

// core/utils.dart
double normalizeRating(num raw);              // >10 → /10 clamp 0-10
int bestMatchScore(String query, String candidate); // 精确100/前缀40/包含20/否则0
String fmtDuration(int seconds);              // "12.5 小时"/"35 分钟"

// data/db.dart
Future<Database> openAppDb(String dir);       // 建表 DDL 见设计文档 §3，schema v1

// data/game_repository.dart
class GameRepository {
  Future<int> insertGame(Game g);
  Future<void> updateGame(Game g);
  Future<void> deleteGame(int id);
  Future<Game?> getGame(int id);
  Future<List<Game>> listGames({String? query, PlayStatus? status, String? tag, String? developer, String? source, bool? favorite, GameSort sort = GameSort.addedDesc});
  Future<void> setTags(int gameId, List<TagItem> tags);
  Future<void> upsertSource(int gameId, SourceRecord rec);
  Future<List<SourceRecord>> sourcesOf(int gameId);
  Future<void> addSession(GameSession s);            // 事务内更新 games.total_seconds/last_played + daily_stats
  Future<void> recoverUnclosedSession(GameSession s);
  Future<AggStats> stats({required Period period});   // totalSeconds, activeDays, sessionCount, byHour[24], byWeekday[7], daily[30], topGames[10]
  Future<List<ActivityItem>> recentActivity({int limit});
}

// scraping/source_adapter.dart
abstract class SourceAdapter {
  String get id; String get label; bool get needsToken;
  Future<List<ScrapedGame>> search(String kw);
  Future<ScrapedGame?> fetchById(String id);
}

// scraping/metadata_fetcher.dart
class MetadataFetcher {
  Future<List<ScrapedGame>> searchAll(String kw, {List<String>? only});  // 并发启用源
  Future<ScrapedGame?> fetchBest(String kw);                              // 打分取最优（bestMatchScore）
  Future<void> rescan(ScrapedGame pick);                                  // fetchById 补全
}

// services/process_monitor.dart
class ProcessMonitor {
  Stream<PlaySessionEnd> track(int gameId, String exePath, TimeTrackingMode mode); // 1s 轮询；结束时吐 Session
  static List<ProcInfo> enumerate();        // CreateToolhelp32Snapshot FFI
  static int foregroundPid();               // GetForegroundWindow+GetWindowThreadProcessId
}

// services/upload/*
Future<UploadResult> uploadReview(Platform p, Account a, SourceRecord src, double rating01to10, String comment);
```

## 任务序列（每个任务结束：analyze + test + commit）

1. **脚手架**：`flutter create --org com.musalunar --project-name kisakigals .`；pubspec 加依赖；`ui/theme.dart`（粉紫 M3 主题）+ `ui/shell.dart`（NavigationRail 空 Tab）；`flutter run` 冒烟。提交。
2. **core+data**：paths/constants/utils（含 normalizeRating、bestMatchScore 单测）→ db DDL + models + GameRepository（sqflite_common_ffi in-memory 单测：CRUD/筛选排序/会话聚合/统计）。提交。
3. **settings/account store + metadata_cache**：类型化 KV（主题/计时模式/NSFW/数据源开关/目录）。提交。
4. **scraping**：rate_limiter（滑窗单测）→ tag_translator（asset 加载）→ 9 个 SourceAdapter（端点见设计文档 §4 表）→ MetadataFetcher（searchAll 并发/打分/缓存；单测用假 dio 拦截）。提交。
5. **图标**：Pillow 圆角多尺寸 → `windows/runner/runner.ico` + `assets/logo/`；改 runner.rc/MainWindow；重建验证窗口图标。提交。
6. **通用 widgets**：cover_image（本地优先→网络缓存→占位；NSFW 模糊）、glass_panel、rating_stars、empty_state；shell 接毛玻璃。提交。
7. **游戏库页**：网格、筛选栏（状态/标签/开发商/来源/收藏 chips）、搜索框、排序菜单、空状态。提交。
8. **添加游戏页**：拖拽/选择 exe → 文件名清洗 → searchAll → 结果选择列表（封面+评分+源徽标）→ 入库（下载封面、写 sources/tags）；自定义添加表单；ID 直填。提交。
9. **详情页**：布局（§7）+ 启动/打开目录/编辑表单/重刮/删除 + 统计块 + 截图条 + 评分评价弹窗（本地保存）。提交。
10. **主页**：四卡片（§7 规格）+ 快捷入口。提交。
11. **统计页**：三子 Tab；fl_chart 图表；word_cloud 自绘（Wrap 加权字号/色调）。提交。
12. **设置页**：六分区（§7 规格；系统项接 autostart/monitor/theme；账号接 account_store 测试连接；数据源接 adapters 开关与 token；数据接 backup_service；关于=0.1.0/MusaLunar/检查更新占位）。提交。
13. **时长监控**：process_monitor FFI（参照 .reference/chronotide/lib/services/{win32_process_service,foreground_window_service}.dart）+ launcher + 会话落库/恢复；detail/hero 卡「继续游戏」接入；启动后动作设置生效。单测：会话聚合。提交。
14. **评价上传**：三平台 upload 服务（端点见设计文档 §5）+ 账号设置测试连接 + 详情弹窗勾选上传与结果反馈。提交。
15. **插件+备份+自启**：plugin_system 接口 + 内置插件（自动备份/NSFW 保护/久坐提醒）+ 设置页插件区。提交。
16. **打磨与验收**：空态/加载态/过渡动画、暗色主题走查、`flutter analyze` 清零、`flutter test` 全绿、`flutter build windows --release` 成功；运行 release 包，逐页截图 → dispatch judge 视觉验收 → 修复 → 复验。提交。

## 验证命令

```bash
export PATH=/e/flutter/bin:$PATH PUB_CACHE=/e/flutter/pub-cache
flutter analyze && flutter test          # 每任务
flutter build windows --release          # 任务 16
./build/windows/x64/runner/Release/kisakigals.exe   # 运行验收
```
