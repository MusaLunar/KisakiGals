# KisakiGals Fluent 2 全量 UI/UX 重写设计规格

- **日期**：2026-11-15
- **目标**：完全抛弃现有 `lib/ui/` 与 Material 3 视觉体系，采用 `fluent_ui`、`flutter_acrylic`、`system_theme`、`fluentui_system_icons`、`flutter_animate` 对 KisakiGals 桌面端应用进行彻底的 UI/UX 重写，并同步更新 Win32 原生托盘弹窗配色以实现全局一致的 Windows 11 原生体验。

---

## 1. 设计目标与硬性边界

### 1.1 技术栈与依赖
| 职责 | 选型 | 说明 |
|---|---|---|
| 基础组件与主题体系 | `fluent_ui` (`^4.17.0`) | 根壳切换为 `FluentApp` + `NavigationView` + 原生 Fluent 控件 |
| 窗口材质 | `flutter_acrylic` (`^1.1.4`) | 主窗默认动态 `Mica`，支持 `Tabbed Mica` / `Acrylic` / `Solid` |
| 系统强调色 | `system_theme` (`^3.3.0`) | 读取并实时监听 Windows 系统强调色，支持设置内覆盖预设 |
| 图标系统 | `fluentui_system_icons` (`^1.1.273`) | 全局统一常规态 (`regular`) 与激活态 (`filled`) 双态图标 |
| 动效系统 | `flutter_animate` (`^4.5.2`) | 交错入场、切换平滑过渡、微悬停与微光骨架（尊重系统减少动画） |
| 保留基础能力 | `flutter_riverpod`, `fl_chart`, `window_manager`, `tray_manager`, `cached_network_image`, `desktop_drop`, `file_picker` | 全量业务数据、图表、拖放、窗口与系统托盘能力保持不变 |

### 1.2 非 UI 层零破坏边界
以下非 UI 模块的所有核心逻辑、数据结构、数据库 Schema（SQLite v5）保持不变：
- `lib/data/`（仅在 `SettingsStore` 新增 2 个可选外观偏好键：`kAccentPreset`、`kBackdropEffect`）
- `lib/services/`（仅将 `game_launch_service.dart` 中 `showNotice` 的导入路径切换至新通知模块，`showNotice(...)` 函数签名不变）
- `lib/state/`（仅将 `ai_state.dart` 中 `showNotice` 的导入路径切换至新通知模块，函数签名不变）
- `lib/scraping/`、`lib/core/`
- `lib/providers.dart`（保留全部既有 Provider，新增强调色预设与窗口材质 Provider 接入 `SettingsStore`）

### 1.3 既有业务规则强制保留项
1. **R18 徽章顺序**：在主页 Spotlight、详情 Hero、探索百科 Hero 等同时展示 R18 标记与评分的场景中，**R18 标记始终位于评分之前**。
2. **下载资源无入库按钮**：探索页「资源」搜索模式与游戏百科页「下载」标签页中的具体下载资源条目仅提供外链打开/复制，**不展示入库按钮**。
3. **游玩路径快捷键截图与笔记**：支持游戏运行中通过热键（默认 `F12`，可在设置内修改）无感截屏并写入 `play_path_nodes`，支持在详情页内查看时间轴、点击大图灯箱预览及撰写/编辑文字笔记。
4. **跳转联动契约**：`Tabs` 索引常量（`home=0`..`settings=5`）、`jumpToLibraryFiltered(...)`、`jumpToSettingsSection(ref, 3)` 保持完全兼容。

---

## 2. 全局基座：`lib/ui/fluent/` 原语系统

彻底删除旧 `lib/ui/design.dart`、`lib/ui/kit.dart`、`lib/ui/theme.dart` 及全部旧组件，新建纯正 Fluent 2 原语层（**零 `package:flutter/material.dart` 依赖**）：

### 2.1 `fluent_theme.dart` — 动态系统主题与窗口材质桥
- **强调色同步 (`SystemTheme`)**：
  - 应用启动前执行 `await SystemTheme.accentColor.load()`。
  - 通过 `SystemTheme.onColorChange` 监听 Windows 个性化设置变化，当 `kAccentPreset == 'system'` 时自动重建 Fluent `AccentColor` 七阶调色板（`darkest` / `darker` / `dark` / `normal` / `light` / `lighter` / `lightest`）。
  - 支持在设置内切换预设强调色：`system`（跟随系统，默认）、`sakura`（绯樱 `#D85C84`）、`lavender`（薰衣草 `#7B61D6`）、`azure`（Win11 天蓝 `#0078D4`）。
- **材质同步 (`flutter_acrylic`)**：
  - `WindowBackdropEffect` 枚举：`mica`（默认）、`tabbed`、`acrylic`、`solid`。
  - 每当 `ThemeMode`、系统 `Brightness` 或材质设置变化时，计算当前真实 `isDark` 并调用：
    ```dart
    await acrylic.Window.setEffect(
      effect: resolvedEffect,
      color: resolvedTintColor, // Mica 保持透明/微染色；Acrylic 带半透明底色
      dark: isDark,
    );
    ```
  - 根部 `NavigationView` 外壳背景保持透明（`Colors.transparent`），确保底层 Windows Mica/Acrylic 质感自然透出。

### 2.2 `fluent_surfaces.dart` — Win11 层级表面与防剧透组件
- 封装符合 Win11 Fluent 2 的中性层容器（Card 表面 1px 微妙描边 + 圆角 `8px` / 浮层 `12px`）：
  - `FluentSurfaceCard`：可选悬停边框高亮与轻量提升。
  - `FluentAcrylicOverlay`：用于详情页 Hero 底层遮罩、拖拽文件提示蒙层、全局工具浮层的局部 `Acrylic` 组件。
  - `FluentCoverImage`：集成 `cached_network_image` / 本地文件加载、默认占位图、以及基于 `nsfwBlurProvider` 的可点击/悬停揭露 R18 高斯模糊保护层。
  - `FluentBadge` / `FluentStatusTag`：R18 警告标签、运行中脉冲徽章、评分胶囊与可点击标签胶囊。

### 2.3 `fluent_motion.dart` — 基于 `flutter_animate` 的 Win11 动效规范
- **统一时长与曲线**：
  - 快速微交互：`140ms` (`Curves.easeOutCubic`)
  - 标准容器与状态切换：`220ms` (`Curves.easeOutCubic`)
  - 页面与大区块入场：`280ms` (`Curves.easeOutQuart`)
- **无障碍兜底**：统一检查 `MediaQuery.maybeDisableAnimationsOf(context) ?? false`，当系统开启“关闭不必要动画”时自动跳过位移与缩放效果。
- **典型用法约束**：
  - 列表/网格首屏采用封装的 `fluentEntrance(index: i)` 实现克制的交错渐显（上限错峰 6 项，避免长列表等待）。
  - 重绘敏感区块（Hero 背景、图表、复杂卡片）外包 `RepaintBoundary`，防止滚动或悬停抖动。
  - Tab/模式切换采用轻柔竖向或横向短位移淡入，不使用高开销持续动画。

### 2.4 `fluent_notices.dart` — 基于 `InfoBar` 的全局通知中心
- 保留全局 `NoticeCenter`（`ChangeNotifier`，无 `WidgetRef` 生命周期隐患，最多并发 3 条）与顶层 `void showNotice(String message, {bool error = false, Duration? duration})`。
- 挂载于 `FluentApp.builder` 的顶层 `Overlay` 中，以右上角浮层堆栈呈现原生 Fluent `InfoBar`：
  - `error == true` 映射 `InfoBarSeverity.error`；常规消息映射 `InfoBarSeverity.info` / `success`。
  - 使用 `flutter_animate` 实现右侧轻滑入场，支持手势点按关闭与超时自动移除。

### 2.5 `fluent_dialogs.dart` & `fluent_icons.dart`
- 全应用模态确认、表单编辑、评分、存档备份、路径选择均封装基于 Fluent `ContentDialog` 的统一弹窗原语。
- 全局图标通过 `fluentui_system_icons` 统一提供，导航与切换按钮采用「未选中 `*_regular` / 选中 `*_filled`」双态设计。

---

## 3. 顶层导航与外壳架构 (`lib/ui/shell/`)

### 3.1 `AppShell` 与 `NavigationView`
- 根组件为 `FluentApp`，启用中文 `FluentLocalizations.delegate` 与中文字体栈（`NotoSansSC` + `Microsoft YaHei UI`）。
- 使用 `NavigationView` 搭配 `NavigationAppBar`：
  - **TitleBar 一体化**：
    - `leading`：当存在可返回的详情页 / 游戏探索百科页 / 添加页栈时显示 Fluent 返回按钮；否则展示应用徽标。
    - `title`：全宽 `DragToMoveArea`（双击最大化）内嵌紧凑应用标题 + **全局 `AutoSuggestBox` 搜索框**（输入关键词实时检索已入库游戏名/厂商/别名，回车或选中直接打开游戏详情页）。
    - `actions`：运行中游戏状态胶囊（显示当前计时状态 + 一键定位到正在运行的游戏详情）+ 原生手感最小化 / 最大化-还原 / 关闭按钮（遵循 `kCloseBehavior`：最小化到托盘或退出）。
  - **`NavigationPane` (`PaneDisplayMode.auto`)**：
    - 宽窗口默认展开侧栏，窄窗口自动折叠为 compact 图标轨，用户可点击汉堡键手动展开/收折。
    - **`items`（主键顺序严格对应 `Tabs` 0..4）**：
      1. `Tabs.home` (0)：主页 (`FluentIcons.home_*`)
      2. `Tabs.library` (1)：游戏库 (`FluentIcons.library_*`)
      3. `Tabs.discover` (2)：探索发现 (`FluentIcons.compass_northwest_*`)
      4. `Tabs.stats` (3)：游玩统计 (`FluentIcons.data_histogram_*`)
      5. `Tabs.ai` (4)：AI 助手 (`FluentIcons.sparkle_*`)
    - **`footerItems`**：
      - `+ 添加游戏`（`Tabs.add = 6`）：独立 `PaneItem`
      - 快捷动作 `PaneItemAction`（**不占用选中索引**）：R18 模糊保护一键切换
      - 快捷动作 `PaneItemAction`（**不占用选中索引**）：深色/浅色快速切换
      - `设置`（`Tabs.settings = 5`）：置于 `footerItems` 末尾
    - **显式索引映射**：由于 `NavigationView` 的 `selected` 索引按 `items` 与 `footerItems`（仅计 `PaneItem`）顺序排列（即 `footer` 的 `+ 添加游戏` 为 paneIdx=5，`设置` 为 paneIdx=6），外壳层维护显式的 `paneIndexToTab(int)` 与 `tabToPaneIndex(int)` 双向映射表，彻底避免 `Tabs.settings = 5` 与新增页面产生错位。
- **右侧内容帧**：保留 `_LazyKeepAliveTabStack` 懒加载保活栈与 `flutter_animate` 短距平滑过渡，切页不销毁各页滚动位置与异步刮削状态。

---

## 4. 全页面与对话框 UX 重设计 (`lib/ui/pages/`)

### 4.1 主页 (`home/home_page.dart`) — Store / Xbox 桌面工作台
1. **Spotlight Hero 横幅**：
   - 自动聚焦「当前正在运行」或「最近游玩」的作品；背景铺满低饱和自适应渐变 + `Acrylic` 遮罩，左侧立绘封面，右侧展示 **R18 徽章（前置）** → 状态与评分胶囊 → 制作商/时长信息 → `FilledButton`（「立即启动」/「运行中 · 结束会话」）+ 次按钮（「详情」「探索百科」）。
2. **4 列 KPI 速览卡片**：总游戏数、累计游玩时长、本月活跃天数、游玩路径节点数。
3. **最近游玩 & 待开坑推荐展架**：Xbox 风格横向流畅卡片带，支持滚轮/左右翻页箭头与卡片右键 `MenuFlyout`。

### 4.2 游戏库 (`library/library_page.dart`) — 工作流主界面
1. **顶部 `CommandBar` 工具条**：添加游戏、扫描目录刷新、实时搜索 `TextBox`、排序 `ComboBox`（最近游玩 / 入库时间 / 评分 / 时长 / 名称）、网格/紧凑列表切换、`Expander` 样式筛选侧栏开关。
2. **可折叠左侧筛选面板**：借助 `AnimatedContainer` + Fluent 中性底面展示状态、评分下限、厂商、数据源、R18 筛选与可滚动多选标签组，提供一键清空按钮。
3. **主展示区与拖放入库 (`desktop_drop`)**：
   - 网格模式（高清封面卡片 + 悬停渐变操作条）与紧凑列表模式（高效多列信息行）。
   - 拖入 `.exe` / `.lnk` / 文件夹时弹出带 `Acrylic` 蒙版的全域拖放提示，落入后自动解析并跳转添加确认流。
4. **原生右键 `MenuFlyout`**：启动游戏、Locale Emulator 启动、查看详情、探索百科、编辑信息、评分、存档备份、打开游戏目录、移出游戏库。

### 4.3 游戏详情与游玩路径 (`detail/game_detail_page.dart`)
1. **头部定位**：`BreadcrumbBar`（`游戏库 > 作品名`） + 右侧 `CommandBar`（启动、LE 启动、探索百科、编辑、评分、存档备份、打开文件夹、移除）。
2. **Split Hero 概览**：模糊背景图（受 `detailBgBlurProvider` 控制）+ `Acrylic` 遮罩；清晰封面（带 R18 模糊保护开关）；右侧信息保持 **R18 标记在评分徽章之前**，附带状态标签、累计游玩、厂商、发售日与可执行文件状态提示。
3. **Fluent 分页视图（游玩路径 / 档案与标签 / 会话与存档）**：
   - **「游玩路径」**：展示 `play_path_nodes` 时间轴节点卡片流，顶部提供热键提示徽章（默认 `F12` 运行时自动截屏入轴）以及「写一条笔记 / 导入截图」快捷输入区；点击节点图片弹出 `ContentDialog` 灯箱看大图，支持编辑笔记与删除节点。
   - **「档案与标签」**：完整多语言名称、简介、来源站点直链徽章、标签组（点击直接 `jumpToLibraryFiltered` 跳转）。
   - **「会话与存档」**：近期游玩时长日志列表 + 直接拉起 `SaveBackupDialog` 管理本地存档快照。
4. **编辑与评分弹窗**：
   - **编辑信息 (`edit_dialog.dart`)**：Fluent 宽幅 `ContentDialog`，内部按 `Expander` 分区（基本资料 / 启动与 LE 配置 / 存档路径与规则 / 封面图片 / 数据源），右侧或顶部保留快捷分段锚点导航，一键直达任意分区。
   - **评分弹窗 (`rate_dialog.dart`)**：Fluent 十分制/星级滑块 (`Slider`) + 短评输入框。

### 4.4 探索发现与游戏百科 (`discover/discover_page.dart`, `discover/game_explore_page.dart`)
1. **探索主页**：
   - 顶部 Segmented 切换「探索发现（VNDB / Bangumi 榜单与搜索）」与「资源聚合搜索」。
   - 「资源」模式纯展示资源搜索结果与快捷跳转链接，**不展示入库按钮**。
2. **游戏探索百科页 (`game_explore_page.dart`)**：
   - 保持 `BreadcrumbBar`（`探索 > 游戏名`）与清爽无冗余推广横幅的布局。
   - 两栏 Hero 概览：**R18 标记在评分之前**，支持一键入库或跳转已在库详情。
   - 使用自适应 Fluent 页签切换全维度资料：**发行资料 / 角色与声优 / 制作人员 / 相关游戏（支持点击联动开启新百科页） / 媒体 / 动画 / 音乐 / 漫画 / 轻小说 / 下载资源**；其中「下载资源」只保留外链跳转/复制，**不展示入库按钮**，各页签采用规整的 Win11 响应式卡片网格消除拥挤感。

### 4.5 统计 (`stats/stats_page.dart`)、AI 助手 (`ai/ai_page.dart`)、添加游戏 (`add/add_game_page.dart`)
- **统计页**：`fl_chart` 全面注入 `FluentTheme` 色板与字体（无 `Material` 查找依赖），配合词云标签直跳筛选。
- **AI 助手**：接入 `ai_state.dart`，未配置时展示 Fluent `InfoBar` 并提供直达设置分区的快捷按钮；生成中呈现 `ProgressRing` + 微光骨架，推荐卡片支持一键检索元数据入库。
- **添加游戏页**：左右双入口卡片（拖放/选择本地 `.exe`/文件夹 vs 在线多源关键词刮削），结果列表使用 Fluent `Expander` 预览并一键入库。

### 4.6 设置页 (`settings/settings_page.dart`) — Win11 设置中心
保留顶部/左侧分区导航与 `settingsSectionProvider`（`jumpToSettingsSection(ref, 3)` 精确定位）：
- **分区 0 · 外观与个性化**：深浅主题模式、强调色来源（跟随系统 `system_theme` / 预设色预览卡）、窗口材质切换（`Mica` / `Tabbed Mica` / `Acrylic` / `纯色`）实时生效。
- **分区 1 · 启动、追踪与游玩路径**：进程追踪方式、启动后/关闭时动作、窗口恢复聚焦、Locale Emulator 路径、F12 截屏热键自定义录制器。
- **分区 2 · 游戏库、数据源与隐私**：自动扫描根目录、启用的刮削站点开关、SearchGal API、KunGal OAuth 账号连接与 R18 防护选项。
- **分区 3 · AI 服务设置**：Base URL、API Key、Model、Max Tokens 与测试连接。
- **分区 4 · 备份与更新**：数据目录选择、自动备份与退出备份策略、存档保留份数、导入/恢复与 GitHub 检查更新。

---

## 5. Win32 原生托盘弹窗联动 (`windows/runner/`)

- **协议扩展 (`lib/main.dart` -> `flutter_window.cpp` -> `tray_popup.h`)**：
  - `MethodChannel('kisaki/tray_menu')` 的 `showPopup` 参数新增可选整型 `'accentArgb'`，由 Dart 侧在弹出前传入当前生效强调色（系统色或预设色）。
- **C++ GDI+ 调色板重写 (`windows/runner/tray_popup.cpp`)**：
  - 删除既有 `#DA839C` / `#D0C0F5` / `#EDABA0` M3 硬编码颜色。
  - 采用 Win11 Fluent 中性色基底（Dark：`#202020` 底色、`#2C2C2C` 卡片、`#383838` 悬停、1px `#3D3D3D` 描边；Light：`#F3F3F3` 底色、`#FFFFFF` 卡片、`#EAEAEA` 悬停、1px `#E2E2E2` 描边）。
  - 从 `accent_argb` 动态计算强调色、半透明高光底与自动对比度文字色，统一 Win11 窗体与 inner card `8px`–`12px` 圆角视觉规范。

---

## 6. 目录规划与验证方案

### 6.1 目标目录结构
- `lib/ui/fluent/`：`fluent_theme.dart`, `fluent_surfaces.dart`, `fluent_motion.dart`, `fluent_notices.dart`, `fluent_dialogs.dart`, `fluent_icons.dart`
- `lib/ui/shell/`：`tabs.dart`, `app_shell.dart`
- `lib/ui/home/`：`home_page.dart`
- `lib/ui/library/`：`library_page.dart`, `game_card.dart`, `game_list_tile.dart`, `game_actions.dart`, `filter_rail.dart`
- `lib/ui/detail/`：`game_detail_page.dart`, `play_path_tab.dart`, `edit_dialog.dart`, `rate_dialog.dart`, `save_backup_dialog.dart`
- `lib/ui/discover/`：`discover_page.dart`, `discover_state.dart`, `discover_filter_state.dart`, `game_explore_page.dart`, `resource_links.dart`
- `lib/ui/stats/`：`stats_page.dart`, `word_cloud.dart`
- `lib/ui/ai/`：`ai_page.dart`
- `lib/ui/add/`：`add_game_page.dart`, `scrape_search_dialog.dart`
- `lib/ui/settings/`：`settings_page.dart`
- `lib/ui/widgets/`：`image_picker_dialog.dart`, `save_dir_picker_dialog.dart`（清理掉与 `fluent/` 重复的旧 `common.dart`、`notifications.dart`、`floating_anchor_nav.dart`）

### 6.2 质量与回归验证门禁
1. 重写 `test/ui_redesign_test.dart`：验证 `FluentApp` + 主题切换 + `InfoBar` 通知栈 + `AppShell` (`NavigationView`) 页签切换 + 详情页「R18 在评分前」及探索页不展示下载入库按钮等关键 UI 不变量；既有业务单元测试 (`unit_test.dart`, `play_path_test.dart` 等) 全部保持通过。
2. 执行 `C:\src\flutter\bin\flutter.bat analyze` 零警告/零错误。
3. 执行 `C:\src\flutter\bin\flutter.bat test` 全量测试通过。
4. 执行 `C:\src\flutter\bin\flutter.bat build windows --release` 验证 Flutter + Win32 C++ (`tray_popup.cpp`) 编译打包成功。
