# KisakiGals 项目功能概述与设计规范

> **项目定位**：Windows 桌面端 Galgame（视觉小说）本地收藏、游玩时长追踪、插件扩展与多源百科探索管理器  
> **当前版本**：`v1.2.0`  
> **技术栈**：Flutter 3.x (Windows Desktop · Fluent 2 / `fluent_ui`) + Riverpod + SQLite (FFI) + Win32 / GDI+ / DWM Native C++

---

## 一、 核心功能概述

### 1. 桌面工作区与核心页面

| 模块 | 对应源码 | 核心能力说明 |
| :--- | :--- | :--- |
| **🏠 主页（仪表盘）** | [`lib/ui/home/home_page.dart`](../lib/ui/home/home_page.dart) | • **Spotlight 主推横幅**：展示最近游玩的作品封面、游玩进度与快速启动入口<br>• **KPI 数据矩阵**：等宽数字展示本周、本月与累计总游玩时长及库统计<br>• **货架与推荐**：最近游玩 & 待玩清单水平货架、动态时间线及标签驱动的探索推荐 |
| **📚 游戏库** | [`lib/ui/library/library_page.dart`](../lib/ui/library/library_page.dart)<br>[`lib/ui/library/game_actions.dart`](../lib/ui/library/game_actions.dart) | • **与标题栏搜索统一**：`KisakiTitleBar` 搜索框在游戏库页直接驱动实时筛选，消除重复输入框<br>• **双视图与统一工具栏**：支持网格 / 列表无缝切换、状态与收藏快捷胶囊、`CommandBar` 与可折叠 `256px` `FilterRail` 筛选栏<br>• **Fluent `MenuFlyout` 右键菜单 & 批量管理**：支持启动/停止会话、状态切换、收藏、编辑、评分、存档备份与批量修改 |
| **🎮 游戏详情与游玩路径** | [`lib/ui/detail/game_detail_page.dart`](../lib/ui/detail/game_detail_page.dart)<br>[`lib/ui/detail/edit_dialog.dart`](../lib/ui/detail/edit_dialog.dart) | • **沉浸式双栏布局**：左栏呈现封面、档案与多平台评分；右栏呈现时长账本、30 天轨迹、**游玩路径截图时间线**与简介<br>• **「…」更多菜单与 LE 插件开关**：安装并启用 `locale-emulator` 插件后，直接在详情页「…」菜单中按单部作品切换转区启动开关<br>• **高内聚弹窗**：编辑信息、0.1 步进评分、多源封面挑拣与存档备份全部采用 Fluent 2 对话框体系 |
| **🧭 探索与全景百科** | [`lib/ui/discover/discover_page.dart`](../lib/ui/discover/discover_page.dart)<br>[`lib/ui/discover/game_explore_page.dart`](../lib/ui/discover/game_explore_page.dart) | • **与游戏库统一的探索视图**：共享 `CommandBar`、网格/列表切换与 `256px` 筛选栏；聚合浏览 VNDB / Bangumi 榜单或全网关键词搜索<br>• **7 大工作台全景百科**：覆盖`百科资料`、`媒体画廊（LightBox）`、`动画`、`音乐`、`漫画`、`轻小说`、`下载`；其中「下载」Tab 顶部直接置顶**站点发布页检索**，紧接官方商城与外部站点链接 |
| **➕ 入库（添加游戏）** | [`lib/ui/add/add_game_page.dart`](../lib/ui/add/add_game_page.dart) | • **统一单一入口**：左侧栏「入库」与游戏库「添加游戏」/ 拖拽导入直达同一 `Tabs.add` 页面，支持 `.exe`/`.lnk`/文件夹自动识别与多源并发刮削合併 |
| **📊 统计 & 🤖 AI 助手** | [`lib/ui/stats/stats_page.dart`](../lib/ui/stats/stats_page.dart)<br>[`lib/ui/ai/ai_page.dart`](../lib/ui/ai/ai_page.dart) | • 时段分布、星期分布、高分墙与标签词云；OpenAI 兼容接口支持后台流式生成总结与推荐 |
| **⚙️ 设置中心与插件** | [`lib/ui/settings/settings_page.dart`](../lib/ui/settings/settings_page.dart) | • 重组为 **7 大内聚分区**（外观与显示 / 游戏与启动 / 游戏库与网络 / 账号与云同步 / AI 服务 / 存储与备份 / 插件与关于），配备双向定位目录与搜索高亮 |

---

## 二、 系统服务与插件扩展特性

- **🧩 开放插件系统与官方插件市场**（[`lib/services/plugin_system.dart`](../lib/services/plugin_system.dart)、[`docs/PLUGIN_DEVELOPMENT.md`](PLUGIN_DEVELOPMENT.md)）：
  - 支持从官方聚合市场（[`plugins/index.json`](../plugins/index.json)）浏览与通过多 GitHub 镜像加速下载安装，或导入本地 `.zip` 插件包；严格校验 Manifest v1 Schema、权限白名单、SHA-256 校验和与 Zip Slip 路径安全。
  - 原内置 Locale Emulator 功能独立为 [`locale-emulator`](../plugins/locale-emulator) 插件（致谢 [`xupefei/Locale-Emulator`](https://github.com/xupefei/Locale-Emulator)），由用户在插件配置中指定 `LEProc.exe` 路径与缺失回退策略。
- **⏱️ 毫秒级进程监控与热键截屏**（[`lib/services/playtime_tracker.dart`](../lib/services/playtime_tracker.dart)、[`lib/services/window_capture.dart`](../lib/services/window_capture.dart)）：
  - 支持仅前台有效计时或进程存活计时；游戏追踪期间按全局热键自动截取游戏窗口并在后台 Isolate PNG 编码落盘。
- **🖥️ Fluent 2 原生托盘右键交互窗**（[`windows/runner/tray_popup.cpp`](../windows/runner/tray_popup.cpp)）：
  - GDI+ + DWM 圆角与 `DWMSBT_TRANSIENTWINDOW` 亚克力质感自绘弹出菜单，排版与密度严格对齐应用内 `MenuFlyout`（`32px` 行高、`16px` Segoe Fluent 图标、最近游玩直启与安全退出）。
- **🔑 鲲Gal OAuth 2.0 & 检查更新**（[`lib/services/kungal_oauth.dart`](../lib/services/kungal_oauth.dart)、[`lib/services/update_checker.dart`](../lib/services/update_checker.dart)）：
  - 标准 RFC 7636 PKCE 授权与语义化版本在线检查更新。

---

## 三、 Fluent 2 视觉与性能规范

视觉系统统一定义于 [`lib/ui/fluent/fluent_theme.dart`](../lib/ui/fluent/fluent_theme.dart) 与 [`lib/ui/fluent/fluent_surfaces.dart`](../lib/ui/fluent/fluent_surfaces.dart)：

1. **窗口材质与兼容性适配**：支持 `Mica`、`Acrylic`、`Tabbed` 与 `Solid`；在不支持特定 DWM 材质的系统上自动优雅回退并维持清晰描边与可读性。
2. **强调色与语义色**：支持跟随 Windows 系统强调色，或切换预设色板（`azure` / `sakura` / `violet` / `peach`），并按明暗模式自动校验高对比度文本前景色（`accentInk` / `dangerInk` / `favoriteInk`）。
3. **内置思源黑体排印**：全应用打包分发 **Source Han Sans CN（思源黑体）** Regular / Medium / Bold，搭配 `tabularFigures` 等宽数字，消除跨设备字体缺失导致的布局偏差。
4. **低性能设备流畅模式**：可在「设置 → 外观与显示」开启性能优化模式，全局关闭复杂动效、亚克力半透明层叠与实时模糊背景，确保低功耗与集成显卡设备流畅运行。
