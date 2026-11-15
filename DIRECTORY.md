# 📁 KisakiGals 项目目录与架构规范手册 (Directory & Architecture)

本文档系统性地梳理了 **KisakiGals** 的工程目录拓扑、分层架构模式、代码职责划分与协作规范，方便开发者与维护者快速定位模块与扩展功能。

---

## 🗺️ 1. 项目全景拓扑树

```text
KisakiGals/
├── lib/                             # 核心业务源码 (Flutter + Riverpod)
│   ├── core/                        # 基础设施层：常量、路径配置、媒体路径解析、全局工具
│   ├── data/                        # 数据访问层：SQLite 数据库 (v5)、Repository、实体模型、设置存储
│   ├── scraping/                    # 元数据抓取层：VNDB、Bangumi、TouchGal、Kun 等 9 源适配器与标签本地化
│   ├── services/                    # 领域服务层：进程监听、时长统计、游玩路径窗口截图、自动备份、LE 转区、OAuth、AI 助手
│   ├── state/                       # 独立领域状态管理 (AI 助手流式生成状态等)
│   ├── ui/                          # 用户界面表现层：页面、抽屉、组件库与 Material Design 3 设计系统
│   │   ├── add/                     # 游戏添加流程与多源刮削页
│   │   ├── ai/                      # AI 助手对话与生成建议界面
│   │   ├── detail/                  # 游戏详情主页（含游玩路径时间线与笔记）、编辑与评分弹窗
│   │   ├── discover/                # 探索榜单、关键词查询、全景游戏百科与资源站检索
│   │   ├── home/                    # 仪表盘主页 (常玩游戏、时间线、动态推荐)
│   │   ├── library/                 # 游戏库 (双视图切换、M3 右键菜单、批量操作)
│   │   ├── settings/                # 系统偏好设置 (常规、游玩记录与热键、数据、AI、关于)
│   │   ├── shell/                   # 窗口外壳 (无边框标题栏、M3 胶囊侧栏导航、Tab 懒加载保活栈)
│   │   ├── stats/                   # 统计分析 (时长趋势、星级评分墙、喜好词云)
│   │   ├── widgets/                 # 全局通用 UI 控件 (筛选边栏、悬浮章节定位、通知浮层等)
│   │   ├── design.dart              # 设计系统 Tokens (间距、M3 圆角、海拔阴影、文字阶梯、弹簧动效)
│   │   ├── kit.dart                 # 原子 UI 基础组件库 (KCard, KPill, KChip, KPage 等)
│   │   └── theme.dart               # Material Design 3 明暗主题规范 (#DA839C / #D0C0F5 / #EDABA0)
│   ├── app_services.dart            # 全局服务容器单例与初始化/生命周期接管
│   ├── main.dart                    # 应用主入口 (窗口设置、托盘生命周期、Mica 原生效果)
│   └── providers.dart               # 全局 Riverpod Provider 状态定义与跨页通信总线
│
├── assets/                          # 打包进二进制的静态只读资源
│   ├── data/                        # 预置离线数据 (vndb_tags_zh_cn.json 标签中文对照)
│   ├── fonts/                       # 内置思源黑体字体 (NotoSansSC Regular/Medium/Bold)
│   └── logo/                        # 各分辨率应用图标 (kisaki.ico, logo_32~512.png)
│
├── windows/                         # Windows 桌面平台原生 C++ / CMake Runner (含自绘托盘弹窗 tray_popup.cpp)
├── test/                            # 自动化测试套件 (单元测试、数据库迁移、游玩路径截图、UI 样式断言)
│   └── dll/                         # 离线单元测试所依赖的原生 sqlite3.dll
├── tool/                            # Release 打包脚本与 Inno Setup 安装配置
│   ├── ChineseSimplified.isl        # Inno Setup 简体中文语言包
│   ├── installer.iss                # Inno Setup 6 安装包脚本
│   └── package.ps1                  # Release 打包流水线 (便携 zip + setup 安装包)
├── docs/                            # 项目文档与展示截图
│   ├── OVERVIEW_AND_DESIGN.md       # 项目核心功能与 M3 视觉规范详解
│   └── screens/                     # README 展示用的各页面截图 (home, library, detail_top 等 8 张)
│
├── backups/                         # [Git 忽略] 本地整理/清理前的快照备份归档
├── build/                           # [Git 忽略] Flutter 与 CMake 编译生成目录
├── dist/                            # [Git 忽略] Release 打包产物输出目录 (v1.1.0 便携版与安装包)
│
├── CHANGELOG.md                     # 详细版本演进与更新日志
├── DIRECTORY.md                     # 本目录与架构规范手册
├── README.md                        # 项目主页介绍与功能说明
├── LICENSE                          # AGPL-3.0 开源许可协议
├── pubspec.yaml                     # Flutter 项目声明、三方依赖与资产映射
├── analysis_options.yaml            # Dart 官方静态代码分析与 Lint 规则
└── dart_test.yaml                   # 单元测试并发与环境配置
```

---

## 🏛️ 2. 核心源码分层职责详解 (`lib/`)

KisakiGals 遵循 **分层解耦、单向数据流与服务容器化** 的架构原则：

### 2.1 基础设施层 (`lib/core/`)
- [`constants.dart`](file:///e:/Programming/KisakiGals/lib/core/constants.dart)：业务常量定义（游玩状态枚举、平台类型、NSFW 模式等）。
- [`paths.dart`](file:///e:/Programming/KisakiGals/lib/core/paths.dart) & [`media_paths.dart`](file:///e:/Programming/KisakiGals/lib/core/media_paths.dart)：应用本地存储根目录、数据库路径、封面与游玩路径截图缓存目录（`play_path/`）解析。
- [`utils.dart`](file:///e:/Programming/KisakiGals/lib/core/utils.dart)：格式化工具、时长换算、模糊字符串匹配、评分归一化。

### 2.2 数据访问层 (`lib/data/`)
- [`models.dart`](file:///e:/Programming/KisakiGals/lib/data/models.dart)：游戏数据结构实体（`Game`、`PlayPathNode`、`GameSession`、`SourceRecord` 等）。
- [`db.dart`](file:///e:/Programming/KisakiGals/lib/data/db.dart)：SQLite 数据库连接初始化、WAL 模式开启、索引与 Schema v5 迁移版本控制。
- [`game_repository.dart`](file:///e:/Programming/KisakiGals/lib/data/game_repository.dart)：业务数据仓储（增删改查、聚合统计、全文搜索、游玩路径节点读写）。
- [`settings_store.dart`](file:///e:/Programming/KisakiGals/lib/data/settings_store.dart)：用户偏好设置持久化键值存储（含游玩路径热键 `kScreenshotHotkey`）。
- [`metadata_cache.dart`](file:///e:/Programming/KisakiGals/lib/data/metadata_cache.dart)：外部元数据本地缓存。

### 2.3 元数据爬取层 (`lib/scraping/`)
- [`metadata_fetcher.dart`](file:///e:/Programming/KisakiGals/lib/scraping/metadata_fetcher.dart)：多源并发拉取调度器。
- [`rate_limiter.dart`](file:///e:/Programming/KisakiGals/lib/scraping/rate_limiter.dart)：网络抓取智能退避与速率控制器。
- [`sources/`](file:///e:/Programming/KisakiGals/lib/scraping/sources/)：各平台协议适配器（VNDB API、Bangumi、TouchGal、Kun 等）。
- [`tag_translator.dart`](file:///e:/Programming/KisakiGals/lib/scraping/tag_translator.dart)：外文标签与本地中文标签词典映射转换。

### 2.4 领域服务层 (`lib/services/`)
- [`process_monitor.dart`](file:///e:/Programming/KisakiGals/lib/services/process_monitor.dart)：Win32 底层 FFI 进程快照枚举与前台焦点窗口捕获。
- [`playtime_tracker.dart`](file:///e:/Programming/KisakiGals/lib/services/playtime_tracker.dart)：游戏运行时长计时器、异步进程匹配、全局截图热键轮询与焦点恢复。
- [`window_capture.dart`](file:///e:/Programming/KisakiGals/lib/services/window_capture.dart)：Win32 FFI 游戏窗口画面捕获（`PrintWindow` / `BitBlt`）与后台 Isolate PNG 编码。
- [`auto_backup_scheduler.dart`](file:///e:/Programming/KisakiGals/lib/services/auto_backup_scheduler.dart)：后台常驻与退出时数据库自动备份排期器。
- [`save_backup.dart`](file:///e:/Programming/KisakiGals/lib/services/save_backup.dart) & [`save_write_watcher.dart`](file:///e:/Programming/KisakiGals/lib/services/save_write_watcher.dart)：游戏存档目录智能感知、文件写入监视与版本快照回滚。
- [`game_launcher.dart`](file:///e:/Programming/KisakiGals/lib/services/game_launcher.dart)：直接启动 / Locale Emulator 转区启动引擎。
- [`ai_service.dart`](file:///e:/Programming/KisakiGals/lib/services/ai_service.dart)：OpenAI 兼容协议客户端（提供作品推荐、感悟总结与评分分析）。

### 2.5 视图与表现层 (`lib/ui/`)
- **设计系统规范**：
  - [`design.dart`](file:///e:/Programming/KisakiGals/lib/ui/design.dart)：Design Tokens（间距阶梯、Material Design 3 圆角比例、Tonal 阴影与物理弹簧动效）。
  - [`kit.dart`](file:///e:/Programming/KisakiGals/lib/ui/kit.dart)：应用内统一的基础 UI 原语库（`KPage`、`KCard`、`KPill`、`KChip`、`KBadge` 等）。
  - [`theme.dart`](file:///e:/Programming/KisakiGals/lib/ui/theme.dart)：基于 `#DA839C` / `#D0C0F5` / `#EDABA0` 的 Material Design 3 浅色 / 深色主题装配。
- **业务视图与外壳**：
  - `shell/`：自定义无边框标题栏、M3 胶囊侧栏与 `_LazyKeepAliveTabStack`（`Offstage` + `TickerMode` 懒加载保活切换）。
  - `home/`、`library/`、`discover/`、`stats/`、`ai/`、`settings/`、`detail/`、`add/`：按功能域聚合的高内聚页面模块。

---

## 🛠️ 3. 开发协作与文件放置准则

为保持目录长期整洁、防止架构腐化，请遵循以下规范：

1. **新业务页面**：放置于 `lib/ui/<feature>/` 目录下，若含有专属于该页面的子组件或私有状态，直接就近维护在同级目录（例如 `discover_state.dart` 置于 `lib/ui/discover/`）。
2. **跨页面复用组件**：必须抽象入 `lib/ui/widgets/`（如 `filter_sidebar.dart`）或原子化收敛至 `lib/ui/kit.dart`。
3. **样式与视觉设计**：优先使用 `KisakiColors`（M3 `#DA839C` / `#D0C0F5` / `#EDABA0`  tonal 体系）、`Theme.of(context).colorScheme`、`Radii`、`Gap`、`Type` 与 `Motion`。
4. **外部静态文件**：
   - 随应用打包分发的字体、离线字典、启动图标放入 `assets/`，并在 `pubspec.yaml` 中登记。
   - 展示截图与设计说明文档统一归入 `docs/`。
5. **本地构建与备份排除**：
   - 编译、打包、本地快照备份严格置于 `build/`、`dist/` 或 `backups/`，并在 `.gitignore` 中声明，避免将大体积二进制或历史冗余文件提交到 Git 仓库。
