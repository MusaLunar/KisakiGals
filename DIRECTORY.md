# 📁 KisakiGals 项目目录与架构规范手册 (Directory & Architecture · v1.2.0)

本文档系统性地梳理了 **KisakiGals** 的工程目录拓扑、分层架构模式、代码职责划分与协作规范，方便开发者与维护者快速定位模块与扩展功能。

---

## 🗺️ 1. 项目全景拓扑树

```text
KisakiGals/
├── lib/                                 # 核心业务源码 (Flutter Windows + Fluent 2 + Riverpod)
│   ├── core/                            # 基础设施层：常量 (AppInfo v1.2.0)、路径配置、媒体路径解析、工具函数
│   ├── data/                            # 数据访问层：SQLite 数据库、Repository、实体模型、设置存储
│   ├── scraping/                        # 元数据抓取层：VNDB、Bangumi、TouchGal、Kun 等多源适配器与标签本地化
│   ├── services/                        # 领域服务层：进程监听、时长统计、截图、自动备份、插件系统与市场、OAuth、AI
│   ├── state/                           # 独立领域状态管理 (AI 助手流式生成状态等)
│   ├── ui/                              # Fluent 2 (Windows 11) 用户界面表现层（严禁引入 Material 组件）
│   │   ├── fluent/                      # Fluent 2 设计系统原语层（主题/调色板、动效、亚克力面板、弹窗、InfoBar 通知）
│   │   ├── add/                         # 游戏入库工作区（拖拽识别 + 多源并发搜刮 + 自定义添加）
│   │   ├── ai/                          # AI 助手对话与游玩推荐界面
│   │   ├── detail/                      # 游戏详情页（PlayPath 时间线、编辑/评分/存档备份弹窗、LE 插件开关）
│   │   ├── discover/                    # 探索榜单与全网搜索、7 工作台全景游戏百科、站点发布页检索
│   │   ├── home/                        # 主页仪表盘（Spotlight 横幅、KPI 矩阵、最近游玩/待玩货架、时间线、推荐）
│   │   ├── library/                     # 游戏库（状态/收藏快捷胶囊、网格/列表双视图、MenuFlyout、FilterRail、批量管理）
│   │   ├── settings/                    # 7 分区设置中心（含插件管理、市场弹窗、低配性能模式与检查更新）
│   │   ├── shell/                       # 应用外壳（KisakiTitleBar + 双向游戏库搜索框 + NavigationView 保活栈）
│   │   ├── stats/                       # 统计分析（趋势图表、评分分布墙、标签词云）
│   │   └── widgets/                     # 共享业务选择器弹窗（多源封面挑拣、存档目录探测选择）
│   ├── app_services.dart                # 全局服务容器单例与初始化/生命周期接管（含插件管理器初始化）
│   ├── main.dart                        # 应用主入口 (单实例互斥、托盘事件回调分发、DWM 窗口材质)
│   └── providers.dart                   # 全局 Riverpod Provider 状态定义与跨页通信总线
│
├── assets/                              # 打包进二进制的静态只读资源
│   ├── data/                            # 预置离线数据 (vndb_tags_zh_cn.json 标签中文对照)
│   ├── fonts/                           # 内置思源黑体 Source Han Sans CN (Regular/Medium/Bold)
│   └── logo/                            # 各分辨率应用图标 (kisaki.ico, logo_32~512.png)
│
├── plugins/                             # 官方插件聚合索引与内置维护的插件包源码/制品
│   ├── index.json                       # 静态市场全量索引（含版本号、downloadUrl、SHA-256 与体积）
│   ├── locale-emulator.json             # Locale Emulator 插件单文件注册清单
│   ├── locale-emulator/                 # Locale Emulator 转区启动插件源码 (manifest.json / main.js / README.md)
│   └── dist/                            # 发布到插件市场的正式插件 .zip 压缩包产物
│
├── windows/                             # Windows 桌面平台原生 C++ / CMake Runner (含自绘 Fluent 托盘弹出菜单 tray_popup.cpp)
├── test/                                # 自动化测试套件 (单元测试、Fluent 2 各模块 Widget 测试与插件系统测试)
│   └── dll/                             # 离线单元测试所依赖的原生 sqlite3.dll
├── tool/                                # Release 打包脚本与 Inno Setup 安装配置
│   ├── ChineseSimplified.isl            # Inno Setup 简体中文语言包
│   ├── installer.iss                    # Inno Setup 6 安装包脚本
│   └── package.ps1                      # Release 打包流水线 (便携 zip + setup 安装包)
├── docs/                                # 项目文档与展示截图
│   ├── OVERVIEW_AND_DESIGN.md           # 项目核心功能与 Fluent 2 设计规范详解
│   ├── PLUGIN_DEVELOPMENT.md            # KisakiGals 插件开发与分发技术规范 (供 AI 开发者参考)
│   ├── VIBE_CODING_PLUGIN_GUIDE.md      # 零基础用 AI (Vibe Coding) 开发并发布插件指南
│   └── screens/                         # README 展示用的各页面截图
│
├── backups/                             # [Git 忽略] 本地快照备份目录
├── build/                               # [Git 忽略] Flutter 与 CMake 编译生成目录
├── dist/                                # [Git 忽略] 宿主客户端 Release 打包输出目录 (v1.2.0 便携版与安装包)
│
├── CHANGELOG.md                         # 详细版本演进与更新日志
├── DIRECTORY.md                         # 本目录与架构规范手册
├── README.md                            # 项目主页介绍与功能说明
├── LICENSE                              # AGPL-3.0 开源许可协议
├── pubspec.yaml                         # Flutter 项目声明、三方依赖与资产映射
├── analysis_options.yaml                # Dart 官方静态代码分析与 Lint 规则
└── dart_test.yaml                       # 单元测试并发与环境配置
```

---

## 🏛️ 2. 核心源码分层职责详解 (`lib/`)

KisakiGals 遵循 **分层解耦、单向数据流与服务容器化** 的架构原则：

### 2.1 基础设施层 (`lib/core/`)
- [`constants.dart`](lib/core/constants.dart)：业务常量与版本标识（`AppInfo.version = '1.2.0'`、`PlayStatus`、`GameSort`、`KisakiSources` 等）。
- [`paths.dart`](lib/core/paths.dart) & [`media_paths.dart`](lib/core/media_paths.dart)：应用本地存储根目录、数据库路径、封面与游玩路径截图缓存目录解析。
- [`utils.dart`](lib/core/utils.dart)：格式化工具、时长换算、繁简折算与模糊字符串匹配、评分归一化。

### 2.2 数据访问层 (`lib/data/`)
- [`models.dart`](lib/data/models.dart)：游戏实体模型（`Game`、`PlayPathNode`、`GameSession`、`SourceRecord`、`TagItem` 等）。
- [`db.dart`](lib/data/db.dart)：SQLite 数据库连接初始化、WAL 模式开启、索引与 Schema 迁移版本控制。
- [`game_repository.dart`](lib/data/game_repository.dart)：业务数据仓储（增删改查、聚合统计、全文搜索、游玩路径节点读写）。
- [`settings_store.dart`](lib/data/settings_store.dart)：用户偏好设置持久化键值存储（主题、窗口材质、性能模式、`plugin.*` 配置等）。
- [`metadata_cache.dart`](lib/data/metadata_cache.dart)：外部元数据本地缓存。

### 2.3 元数据爬取层 (`lib/scraping/`)
- [`metadata_fetcher.dart`](lib/scraping/metadata_fetcher.dart)：多源并发拉取调度器。
- [`rate_limiter.dart`](lib/scraping/rate_limiter.dart)：网络抓取智能退避与速率控制器。
- [`sources/`](lib/scraping/sources/)：各平台协议适配器（VNDB、Bangumi、月幕GAL、Hikarinagi、Steam、CnGal、KunGal、TouchGal、DLsite 等）。
- [`tag_translator.dart`](lib/scraping/tag_translator.dart)：外文标签与本地中文标签词典映射转换。

### 2.4 领域服务层 (`lib/services/`)
- [`process_monitor.dart`](lib/services/process_monitor.dart)：Win32 底层 FFI 进程快照枚举与前台焦点窗口捕获。
- [`playtime_tracker.dart`](lib/services/playtime_tracker.dart)：游戏运行时长计时器、异步进程匹配、全局截图热键轮询与焦点恢复。
- [`window_capture.dart`](lib/services/window_capture.dart)：Win32 FFI 游戏窗口画面捕获（`PrintWindow` / `BitBlt`）与后台 Isolate PNG 编码。
- [`auto_backup_scheduler.dart`](lib/services/auto_backup_scheduler.dart)：后台常驻与退出时数据库自动备份排期器。
- [`save_backup.dart`](lib/services/save_backup.dart) & [`save_write_watcher.dart`](lib/services/save_write_watcher.dart)：游戏存档目录智能感知、文件写入监视与版本快照回滚。
- [`game_launcher.dart`](lib/services/game_launcher.dart) & [`game_launch_service.dart`](lib/services/game_launch_service.dart)：游戏启动引擎与插件化 LE 转区启动解析、追踪挂接。
- [`plugin_system.dart`](lib/services/plugin_system.dart)：Manifest v1 规范校验、`zip`/`js` 安全安装与 Zip Slip 防护、`PluginMarketplaceService` 静态索引拉取与多加速镜像解析。
- [`ai_service.dart`](lib/services/ai_service.dart)：OpenAI 兼容协议客户端（提供作品推荐与游玩总结）。

### 2.5 Fluent 2 视图与表现层 (`lib/ui/`)
- **Fluent 2 设计系统原语 (`lib/ui/fluent/`)**：
  - [`fluent_theme.dart`](lib/ui/fluent/fluent_theme.dart)：明暗主题装配、Windows 系统强调色及预设强调色、思源黑体排印阶梯与低性能模式检测。
  - [`fluent_surfaces.dart`](lib/ui/fluent/fluent_surfaces.dart)：`FluentSurfaceCard`、`FluentAcrylicPanel`、`FluentSearchBox`、`FluentSegmentedControl`、`FluentEmptyState` 等核心原语。
  - [`fluent_motion.dart`](lib/ui/fluent/fluent_motion.dart)、[`fluent_dialogs.dart`](lib/ui/fluent/fluent_dialogs.dart)、[`fluent_notices.dart`](lib/ui/fluent/fluent_notices.dart)、[`fluent_icons.dart`](lib/ui/fluent/fluent_icons.dart)、[`fluent_chrome.dart`](lib/ui/fluent/fluent_chrome.dart)：物理缓动曲线、统一对话框、`InfoBar` 通知主机及窗口边框按钮。
- **业务视图与外壳**：
  - `shell/`：`NavigationView` 导航壳层、带游戏库实时筛选联动的 `KisakiTitleBar` 与 `_LazyKeepAliveTabStack`。
  - `home/`、`library/`、`discover/`、`stats/`、`ai/`、`add/`、`detail/`、`settings/`：全部采用纯 `fluent_ui` 组件体系的高内聚模块。

---

## 🛠️ 3. 开发协作与文件放置准则

1. **纯净 Fluent 2 依赖边界**：`lib/` 与 `test/` 中统一使用 `package:fluent_ui/fluent_ui.dart` 与 `lib/ui/fluent/` 原语，禁止混入 `package:flutter/material.dart`。
2. **跨页复用组件**：全局视觉原语统一沉淀至 `lib/ui/fluent/`，游戏操作（右键菜单、详情跳转、启动等）收敛于 [`game_actions.dart`](lib/ui/library/game_actions.dart)。
3. **插件扩展优先**：可选的第三方工具联动能力通过 [`plugins/`](plugins/index.json) 插件包与 [`plugin_system.dart`](lib/services/plugin_system.dart) 接入，而非硬编码进入主程序设置。
4. **本地构建与发布产物**：Release 打包产物（`-portable.zip` 与 `-setup.exe`）输出至根目录 `dist/`（由 `.gitignore` 的 `/dist/` 忽略）；市场发布的插件包 `.zip` 统一维护在 `plugins/dist/` 下。
