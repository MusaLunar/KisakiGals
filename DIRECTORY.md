# 📁 KisakiGals 项目目录与架构规范手册 (Directory & Architecture)

本文档系统性地梳理了 **KisakiGals** 的工程目录拓扑、分层架构模式、代码职责划分与协作规范，方便开发者与维护者快速定位模块与扩展功能。

---

## 🗺️ 1. 项目全景拓扑树

```text
KisakiGals/
├── lib/                             # 核心业务源码 (Flutter + Riverpod)
│   ├── core/                        # 基础设施层：常量、路径配置、全局工具、限流调度
│   ├── data/                        # 数据访问层：SQLite 数据库、Repository、实体模型、设置存储
│   ├── scraping/                    # 元数据抓取层：VNDB、Bangumi、TouchGal 适配器与标签本地化
│   ├── services/                    # 领域服务层：进程监听、时长统计、自动备份、LE 转区、AI 助手
│   ├── state/                       # 独立领域状态管理 (AI 助手流式生成状态等)
│   ├── ui/                          # 用户界面表现层：页面、抽屉、组件库与设计系统
│   │   ├── add/                     # 游戏添加流程与表单抽屉
│   │   ├── ai/                      # AI 助手对话与生成建议界面
│   │   ├── detail/                  # 游戏详情主页与信息/背景编辑面板
│   │   ├── discover/                # 探索榜单、关键词查询与资源站检索
│   │   ├── home/                    # 仪表盘主页 (常玩游戏、时间线、动态推荐)
│   │   ├── library/                 # 游戏库 (双视图切换、多维筛选边栏、批量操作)
│   │   ├── settings/                # 系统偏好设置 (常规、数据、AI、关于)
│   │   ├── shell/                   # 窗口外壳 (自定义无边框标题栏、侧栏导航、Tab 保活栈)
│   │   ├── stats/                   # 统计分析 (时长趋势、星级评分墙、喜好词云)
│   │   ├── widgets/                 # 全局通用 UI 控件 (筛选组、区间输入、状态卡片、通知浮层)
│   │   ├── design.dart              # 设计系统 Tokens (Color, Font, Spacing, Radius, Motion)
│   │   ├── kit.dart                 # 原子 UI 基础组件库 (KCard, KButton, KChip, KPage 等)
│   │   └── theme.dart               # Light / Dark 主题规范构建器
│   ├── app_services.dart            # 全局服务容器单例与初始化/生命周期接管
│   ├── main.dart                    # 应用主入口 (窗口设置、托盘生命周期、Mica 原生亚克力效果)
│   └── providers.dart               # 全局 Riverpod Provider 状态定义与跨页通信总线
│
├── assets/                          # 打包进二进制的静态只读资源
│   ├── data/                        # 预置离线数据 (vndb_tags_zh_cn.json 标签中文对照)
│   ├── fonts/                       # 内置思源黑体字体 (NotoSansSC Regular/Medium/Bold)
│   └── logo/                        # 各分辨率应用图标 (kisaki.ico, logo_16~512.png)
│
├── windows/                         # Windows 桌面平台原生 C++ / CMake Runner
├── test/                            # 自动化测试套件 (单元测试、数据库迁移、备份排期、UI 样式断言)
│   └── dll/                         # 离线单元测试所依赖的原生 sqlite3.dll
├── tool/                            # 工程辅助与打包脚本
│   ├── installer.iss                # Inno Setup 6 安装包脚本
│   ├── package.ps1                  # Release 打包流水线 (便携 zip + setup 安装包)
│   └── ...                          # 冒烟测试、窗口截图、数据迁移脚本
├── docs/                            # 项目文档与设计资产
│   ├── screens/                     # 界面截图与视觉评审存档
│   ├── superpowers/                 # 历史规格提案与设计计划归档
│   ├── icon_preview.png             # 图标预览图
│   └── icon_source.jpg              # 图标设计原始素材
│
├── .reference/                      # [Git 忽略] 架构与交互设计参考仓库 (ChronoTide, ReinaManager)
├── .testdata/                       # [Git 忽略] 本地数据迁移与回归测试假数据
├── build/                           # [Git 忽略] Flutter 与 CMake 编译生成目录
├── dist/                            # [Git 忽略] Release 打包产物输出目录
│
├── CHANGELOG.md                     # 详细版本演进与更新日志
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
- [`paths.dart`](file:///e:/Programming/KisakiGals/lib/core/paths.dart)：应用本地存储根目录、数据库路径、媒体缓存与备份目录解析。
- [`utils.dart`](file:///e:/Programming/KisakiGals/lib/core/utils.dart)：格式化工具、时长换算、模糊字符串匹配、评分归一化。
- [`rate_limiter.dart`](file:///e:/Programming/KisakiGals/lib/core/rate_limiter.dart)：网络抓取智能退避与速率控制器。

### 2.2 数据访问层 (`lib/data/`)
- [`models.dart`](file:///e:/Programming/KisakiGals/lib/data/models.dart)：游戏数据结构实体（`Game`、`GameSession`、`GameSource` 等）。
- [`db.dart`](file:///e:/Programming/KisakiGals/lib/data/db.dart)：SQLite 数据库连接初始化、WAL 模式开启与 Schema 迁移版本控制。
- [`game_repository.dart`](file:///e:/Programming/KisakiGals/lib/data/game_repository.dart)：业务数据仓储（增删改查、聚合统计、全文搜索、多字段过滤排序）。
- [`settings_store.dart`](file:///e:/Programming/KisakiGals/lib/data/settings_store.dart)：用户偏好设置持久化键值存储。
- [`metadata_cache.dart`](file:///e:/Programming/KisakiGals/lib/data/metadata_cache.dart)：外部元数据本地缓存。

### 2.3 元数据爬取层 (`lib/scraping/`)
- [`metadata_fetcher.dart`](file:///e:/Programming/KisakiGals/lib/scraping/metadata_fetcher.dart)：多源并发拉取调度器。
- [`sources/`](file:///e:/Programming/KisakiGals/lib/scraping/sources/)：各平台协议适配器（VNDB API、Bangumi、TouchGal 等）。
- [`tag_translator.dart`](file:///e:/Programming/KisakiGals/lib/scraping/tag_translator.dart)：外文标签与本地中文标签词典映射转换。

### 2.4 领域服务层 (`lib/services/`)
- [`process_monitor.dart`](file:///e:/Programming/KisakiGals/lib/services/process_monitor.dart)：Win32 底层 FFI 进程快照枚举与前台焦点窗口捕获。
- [`playtime_tracker.dart`](file:///e:/Programming/KisakiGals/lib/services/playtime_tracker.dart)：游戏运行时长计时器、进程退出判定与窗口前台焦点恢复。
- [`auto_backup_scheduler.dart`](file:///e:/Programming/KisakiGals/lib/services/auto_backup_scheduler.dart)：后台常驻与退出时数据库自动备份排期器。
- [`save_backup.dart`](file:///e:/Programming/KisakiGals/lib/services/save_backup.dart) & [`save_write_watcher.dart`](file:///e:/Programming/KisakiGals/lib/services/save_write_watcher.dart)：游戏存档目录智能感知、文件写入监视与版本快照回滚。
- [`game_launcher.dart`](file:///e:/Programming/KisakiGals/lib/services/game_launcher.dart)：直接启动 / Locale Emulator 转区启动引擎。
- [`ai_service.dart`](file:///e:/Programming/KisakiGals/lib/services/ai_service.dart)：OpenAI 兼容协议客户端（提供作品推荐、感悟总结与评分分析）。

### 2.5 视图与表现层 (`lib/ui/`)
- **设计系统规范**：
  - [`design.dart`](file:///e:/Programming/KisakiGals/lib/ui/design.dart)：严格遵循 Design Tokens（统一色彩阶梯、文字排版层级、圆角比例、投影外发光与动画缓动）。
  - [`kit.dart`](file:///e:/Programming/KisakiGals/lib/ui/kit.dart)：应用内**唯一合法**的基础 UI 原语库（杜绝在业务页面裸手写 Container 和硬编码 BoxDecoration）。
  - [`theme.dart`](file:///e:/Programming/KisakiGals/lib/ui/theme.dart)：全局浅色 / 深色 Material 主题装配。
- **业务视图与外壳**：
  - `shell/`：提供自定义非客户区标题栏与 `_LazyKeepAliveTabStack`（延迟挂载 + 0ms 页面保活切换）。
  - `home/`、`library/`、`discover/`、`stats/`、`ai/`、`settings/`、`detail/`：以功能域聚合的高内聚页面模块。

---

## 🛠️ 3. 开发协作与文件放置准则

为保持目录长期整洁、防止架构腐化，请遵循以下规范：

1. **新业务页面**：放置于 `lib/ui/<feature>/` 目录下，若含有专属于该页面的子组件或私有状态，直接就近维护在同级目录（例如 `discover_state.dart` 置于 `lib/ui/discover/`）。
2. **跨页面复用组件**：必须抽象入 `lib/ui/widgets/`（如 `filter_sidebar.dart`）或原子化收敛至 `lib/ui/kit.dart`。
3. **样式与视觉设计**：禁止在页面组件中硬编码 `Color(0x...)`、`BorderRadius.circular(...)` 或自定义 `Duration`，所有样式取值均需调用 `KisakiColors`、`Radii`、`Gap`、`Type` 与 `MotionTokens`。
4. **外部静态文件**：
   - 随应用打包分发的字体、离线字典、启动图标放入 `assets/`，并在 `pubspec.yaml` 中登记。
   - 开发评审参考、设计图原件、说明文档归入 `docs/`。
5. **本地开发残留排除**：
   - 打包、编译、临时测试生成的文件严格置于 `dist/`、`build/` 或 `.testdata/`，并在 `.gitignore` 中声明，严禁提交到 Git 仓库。
