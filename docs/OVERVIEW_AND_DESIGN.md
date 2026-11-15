# KisakiGals 项目功能概述与配色设计规范

> **项目定位**：Windows 桌面端 Galgame（视觉小说）本地收藏、游玩时长追踪与多源百科探索管理器  
> **当前版本**：`v1.1.0`  
> **技术栈**：Flutter 3.x (Windows Desktop) + Riverpod + SQLite (FFI) + Win32 / GDI+ / DWM Native C++

---

## 一、 核心功能概述

### 1. 桌面工作区与核心页面

| 模块 | 对应源码 | 核心能力说明 |
| :--- | :--- | :--- |
| **🏠 主页（仪表盘）** | [`lib/ui/home/home_page.dart`](../lib/ui/home/home_page.dart) | • **卷首主推卡**：展示最近游玩的作品封面、游玩进度并提供一键启动/继续<br>• **时长速览矩阵**：等宽展示本周、本月与累计总游玩时长<br>• **动态时间线 & 为你推荐**：按时间轴回溯游玩历史，并基于库存特征展示推荐作品 |
| **📚 游戏库** | [`lib/ui/library/library_page.dart`](../lib/ui/library/library_page.dart)<br>[`lib/ui/library/game_card_actions.dart`](../lib/ui/library/game_card_actions.dart) | • **双视图切换**：支持 `2:3` 封面网格与 `88px` 紧凑列表视图平滑切换<br>• **M3 右键菜单**：鼠标右侧弹出自定义 M3 Expressive 菜单，含 2:3 迷你封面头、5 态胶囊切换及快速入口<br>• **多维筛选与批量管理**：支持关键词（含繁简折算）、排序、状态、标签与多选批量操作 |
| **🎮 游戏详情、编辑与游玩路径** | [`lib/ui/detail/game_detail_page.dart`](../lib/ui/detail/game_detail_page.dart)<br>[`lib/ui/detail/edit_sheet.dart`](../lib/ui/detail/edit_sheet.dart) | • **双栏连贯版面**：左栏呈现 `2:3` 封面、作品档案表与跨平台评分源；右栏呈现主刊头、操作行、游玩时长账本、近 30 天轨迹图与**游玩路径时间线**<br>• **游玩路径与笔记**：游追踪期间按热键（默认 `F12`）自动截取游戏窗口并保存至本地，支持随时补充图文笔记或手动导入图片<br>• **全字段信息编辑**：支持多源封面与背景挑拣、启动与存档配置，配备脏检查与右侧悬浮定位窗（[`floating_anchor_nav.dart`](../lib/ui/widgets/floating_anchor_nav.dart)） |
| **🧭 探索、资源与全景百科** | [`lib/ui/discover/discover_page.dart`](../lib/ui/discover/discover_page.dart)<br>[`lib/ui/discover/game_explore_page.dart`](../lib/ui/discover/game_explore_page.dart) | • **探索榜单**：聚合浏览 VNDB / Bangumi 热门与高分作品榜单，支持年份、评分、标签筛选与一键入库<br>• **多源资源检索**：并发聚合鲲Galgame、GAL图书馆、量子ACG、真红小站等发布页并按相关度排序<br>• **全景游戏百科**：提供 **7 大工作区 Tab**（`百科资料`、`媒体画廊`、`动画`、`音乐`、`漫画`、`轻小说`、`资源下载`），涵盖发行版本规格、角色与声优立绘、制作人员职能分组、关联作品图谱及 LightBox 高清 CG 预览 |
| **📊 游玩统计** | [`lib/ui/stats/stats_page.dart`](../lib/ui/stats/stats_page.dart) | • 分为 **信息 / 评分 / 总结** 三大视图，提供时段分布、星期分布、月度热力图、评分分布墙与作品标签词云 |
| **🤖 AI 助手** | [`lib/ui/ai/ai_page.dart`](../lib/ui/ai/ai_page.dart) | • 支持接入任意 OpenAI 兼容接口，结合本地真实游玩记录生成个性化品鉴总结与新作推荐 |
| **➕ 添加游戏与多源刮削** | [`lib/ui/add/add_game_page.dart`](../lib/ui/add/add_game_page.dart)<br>[`lib/scraping/metadata_fetcher.dart`](../lib/scraping/metadata_fetcher.dart) | • 支持拖拽 `.exe` 或游戏文件夹直接入库，或通过关键词跨源搜索<br>• 并发整合 **9 大数据源**（Bangumi、VNDB、月幕GAL、Hikarinagi、Steam、KunGal、TouchGal、DLsite、CnGal），同一作品自动合并多源字段与内置 VNDB 中文标签 |

---

### 2. 系统服务与桌面工程特性

- **⏱️ 毫秒级进程监控、热键截屏与时长统计**（[`lib/services/playtime_tracker.dart`](../lib/services/playtime_tracker.dart)、[`lib/services/window_capture.dart`](../lib/services/window_capture.dart)）：
  - 基于 `dart:ffi` 调用 Win32 `CreateToolhelp32Snapshot` 与 `GetForegroundWindow`，支持**仅前台有效计时**或**全程挂机计时**双模式；
  - 游戏追踪期间支持全局热键（`F12` / `F11` / `F9` / `PrintScreen`）通过 `PrintWindow` / `BitBlt` 直接截取游戏窗口并用 Isolate PNG 编码落盘至游玩路径；
  - 标题栏与详情页实时显示本局时长；支持配置「游戏退出后主程序自动恢复前台并获取焦点」。
- **🌐 转区启动与存档自动守护**（[`lib/services/game_launcher.dart`](../lib/services/game_launcher.dart)、[`lib/services/save_backup.dart`](../lib/services/save_backup.dart)）：
  - 集成 **Locale Emulator (`LEProc.exe`)** 转区启动日文原版游戏；
  - 自动探测常见 Galgame 引擎存档目录，游戏关闭后自动执行原子化存档备份与轮转，恢复存档前自动生成保护快照。
- **🔑 鲲Gal (NextMoe) OAuth 2.0 + 云同步**（[`lib/services/kungal_oauth.dart`](../lib/services/kungal_oauth.dart)、[`lib/services/cloud_sync.dart`](../lib/services/cloud_sync.dart)）：
  - 内置标准 **RFC 7636 PKCE (`S256`)** 授权流与令牌自动刷新；支持同步 Bangumi、VNDB、Hikarinagi 与 NextMoe 的收藏状态及短评评分。
- **🖥️ C++ 原生自绘托盘交互弹窗**（[`windows/runner/tray_popup.cpp`](../windows/runner/tray_popup.cpp)、[`windows/runner/main.cpp`](../windows/runner/main.cpp)）：
  - 摒弃传统 Windows 原生灰底菜单，使用 GDI+ / DWM 离屏双缓冲自绘无边框 Material Design 3 圆角卡片菜单；
  - 实时展示当前运行会话，并列出**最近游玩的 2 部游戏**（带 2:3 封面缩略图与累计时长），支持在托盘菜单直接一键启动游戏；
  - 内置 Win32 命名互斥量（`Local\KisakiGals_SingleInstance_Mutex`），杜绝后台多开并自动唤醒已有主窗口。
- **📦 便携优先与跨设备自动重定位**（[`lib/services/device.dart`](../lib/services/device.dart)）：
  - 所有数据库、封面缓存、游玩路径截图与存档备份均以相对路径保存在程序同级 `data/` 目录；换电脑或移动硬盘盘符变更后自动扫描库根重连游戏与媒体资源。
- **🔄 GitHub 自动检查更新**（[`lib/services/update_checker.dart`](../lib/services/update_checker.dart)）：
  - 支持语义化比对 GitHub Releases 最新版本，展示更新日志并一键跳转下载。

---

## 二、 配色与视觉设计规范

KisakiGals 的视觉系统定义在 [`lib/ui/theme.dart`](../lib/ui/theme.dart) 与 [`lib/ui/design.dart`](../lib/ui/design.dart) 中，采用 **Material Design 3 Tonal Color System**，围绕三枚高辨识度核心色板 **`#DA839C`（M3 Rose 柔瑰粉）**、**`#D0C0F5`（M3 Lavender 熏衣紫）** 与 **`#EDABA0`（M3 Peach 暖桃珊瑚）** 构建，兼顾明暗双模式可读性与柔和表达感。

### 1. 基底与表面层级色板（M3 Tonal Surfaces）

| 角色名称 | 代码 Token | 浅色模式 (Light) | 深色模式 (Dark) | 用途与场景 |
| :--- | :--- | :--- | :--- | :--- |
| **导航导览壳层** | `KisakiColors.paperSunken` / `nightBg` | `#F6F1F5` | `#151215` | 左侧导航栏（`AppSidebar`）与顶部标题栏底色 |
| **主画布底色** | `KisakiColors.paper` / `pageSurface` | `#FFFBFD` | `#151215`（主区域 tonal 表面） | 主内容区画布背景 |
| **卡片表面** | `KisakiColors.paperElevated` / `nightCard` | `#FFFFFF` | `#241F24` | 游戏卡片、统计卡、弹窗与右键菜单底色 |
| **次级内嵌容器** | `KisakiColors.paperContainer` / `nightContainer` | `#F0E9EE` | `#2E282E` | 搜索输入框填充、未激活胶囊、次级信息槽 |
| **正文与次级墨色** | `KisakiColors.ink` / `inkMedium` / `nightInk` | 正文 `#1F1A1D`<br>次要 `#554A50` | 正文 `#F5EDF2`<br>次要 `#CBBFC6` | 标题、正文与辅助信息排印 |

---

### 2. Material Design 3 核心三色板（#DA839C / #D0C0F5 / #EDABA0）

| 色彩角色 | 语义定位 | 代码 Token | 主色基准 | 浅/深模式高对比衍生 |
| :--- | :--- | :--- | :--- | :--- |
| **Primary · Rose（柔瑰粉）** | **主交互、选中态与品牌标识** | `KisakiColors.m3Rose` / `roseInk(dark)` | `#DA839C` | 浅色文本/图标 `#9C3E5C` (`m3RoseDeep`)；深色 `#DA839C` |
| **Secondary · Lavender（熏衣紫）** | **实时计时、轨迹图表与次级容器** | `KisakiColors.m3Lavender` / `temporalInk(dark)` | `#D0C0F5` | 浅色文本/图标 `#6B53B8` (`m3LavenderDeep`)；深色 `#D0C0F5` |
| **Tertiary · Peach（暖桃珊瑚）** | **星级评分、荣誉与渐变高光** | `KisakiColors.m3Peach` / `ratingInk(dark)` | `#EDABA0` | 浅色文本/图标 `#9E5142` (`m3PeachDeep`)；深色 `#EDABA0` |
| **系统状态色** | **成功 / 警告 / 危险** | `success` / `warning` / `danger` | — | 成功 `#2A7B56`（深色 `#7AD6A8`）、警告 `#A85B37`、危险 `#C93B4B` |

---

### 3. 几何圆角、投影与动效特征（`Radii`、`Elev` & `Motion`）

定义于 [`lib/ui/design.dart`](../lib/ui/design.dart)：

1. **M3 阶梯圆角（`Radii`）**：`xs = 6px`、`sm = 10px`、`md = 14px`、`lg = 16px`、`xl = 24px`、`xxl = 28px`、`full = 999px`（胶囊组件）。
2. **`1px` 表面描边（`Elev.border`）**：浅色 `#142A1B23` / 深色 `#1AFFFFFF`；高对比度模式自动提升不透明度。
3. **柔化层级阴影（`Elev`）**：
   - **静置卡片 (`Elev.card`)**：`Offset(0, 3)`，`blurRadius: 10`；
   - **悬停抬升 (`Elev.cardHover`)**：`Offset(0, 8), blur: 20` 叠加 `outline` 微光晕；
   - **浮层菜单 (`Elev.overlay`)**：`Offset(0, 10)`，`blurRadius: 26`。
4. **性能与动效协同**：
   - 侧边栏页缘激活胶囊支持流畅插值切换，主页工作区采用 `Offstage` + `TickerMode` + `RepaintBoundary` 懒加载保活机制；
   - 按压组件 `FluidPressable` 按需延迟分配 `AnimationController`，列表 `StaggeredFadeIn` 限制首屏错峰上限，在保持弹簧物理质感的同时降低空闲开销。
