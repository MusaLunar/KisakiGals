<div align="center">

# 🌸 KisakiGals

**Galgame 收藏 / 游玩时长 / 资源搜索管理器** · Flutter Windows 桌面应用 · Vibe Coding

> 「无论何时，都想与她们再次相见。」

**当前版本：0.9.1-beta** ｜ 作者：MusaLunar ｜ [项目主页](https://github.com/MusaLunar/KisakiGals)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

</div>

---

## ✨ 功能一览

| 模块 | 说明 |
| --- | --- |
| 🏠 **主页** | 统计速览（本周/本月/总计）、最近游玩快速继续、动态时间线、为你推荐，固定一屏布局 |
| 📚 **游戏库** | 自适应网格（封面严格 2:3）+ 右侧筛选边栏（排序/状态/收藏/来源/开发商/标签，清除筛选置顶）+ 右键菜单 + 批量管理 |
| 🎮 **详情页** | 游玩记录卡片（总时长 / **本次实时计时** / 平均单次，与主页同款视觉）、30 天趋势、平台评分、标签、简介、背景图 |
| 🔍 **资源搜索** | 聚合多个资源站的**发布页链接**：并发流式出结果、**按相关度排序**、一键打开下载页或直接入库 |
| 📊 **统计** | 信息/评分/总结三页 × 本周/本月/今年/总计：时段分布、星期分布、词云、月度热力 |
| 🤖 **AI 助手** | 结合游玩数据与标签词云生成**智能总结**与**作品推荐**，推荐卡片一键搜刮入库（支持任意 OpenAI 兼容端点） |
| ⚙️ **设置** | 系统（主题/NSFW/关闭行为/转区启动）、账号（Bangumi/VNDB/Hikarinagi Token 与**云端同步**）、数据源、资源搜索、AI、数据（备份/恢复）、插件、关于 |
| ➕ **添加游戏** | 拖拽 exe/文件夹自动搜刮 / 关键词搜索：**9 个数据源并发**、跨源身份分组、多源元数据整合、图片区统一选择器 |

### 游玩时长监控
- 秒级进程轮询 + 前台窗口检测（仅前台 / 挂机即计时双模式）
- 会话自动落库，驱动全部统计与动态；**标题栏常驻显示当前游戏与本局实时时长**（点击进详情）
- 最小化到托盘后继续计时；退出前自动收尾落库，不丢时长
- 「启动游戏后最小化」= 最小化到托盘，不占任务栏、不挡在游戏前面

### 元数据刮削（9 源并发）
Bangumi · VNDB · 月幕GAL(Ymgal) · Hikarinagi · Steam · KunGal · TouchGal · DLsite · CnGal

- 智能匹配打分（别名/符号归一化），每源限流 + 24h 磁盘缓存
- **跨源整合**：同一游戏的多源条目分组展示，合并简介/标签/截图/各平台评分
- **多语言标题互认**：VNDB 的 `titles[]`（日文/英文/罗马音）与 KUN 的 `all_titles` 写入别名，搜英文名也能与日文名归为同一作品
- **封面来自各平台**（不是 VNDB 的截图），候选多时可「查看全部」大图网格挑选
- 封面、截图、详情背景一键缓存到本地 `covers/`；标签英译中（VNDB 标签中文化资源）

### 资源搜索（参考 SearchGal）
- 内置适配器：鲲Galgame · GAL图书馆 · TouchGal · 量子ACG · 真红小站
- 可另配 **SearchGal 兼容聚合接口**（自建 Cloudflare Workers / Vercel / Docker 部署），一次聚合 27+ 站点
- 并发搜索、流式返回、**按相关度排序**（完全匹配 > 前缀 > 中间命中 > 多词部分命中，归一化处理全角与装饰符号）
- 每个结果可**用浏览器打开发布页**，或**带关键词入库**（自动进入搜刮流程补齐元数据）

### 启动与存档
- **Locale Emulator 转区启动**：设置中配置 `LEProc.exe`，按游戏开关（日文原版防乱码）
- **exe 自动识别**：汉化补丁关键词 → 体积最大 → 与文件夹同名 → 最新修改
- **启动加固**：启动锁 + 代际计数 + 120s 安全阀；失败降级 `cmd /c start`，失败原因可见
- **存档备份**：自动识别存档目录（`savedata`/`save`/`セーブ`…），支持手动/退出游戏后自动备份、恢复前快照、保留份数上限；备份为明文目录，可直接翻看替换
- **设备识别与路径可移植**：记录设备标识与相对库根路径，换电脑/换盘导入数据库后**自动重定位游戏目录**，无需逐个重设

### 评分与云同步
- 本地评分（五星 × 10 分制）+ 评论，可同步 Bangumi 收藏、VNDB 游玩列表、Hikarinagi 评价
- 账号页配置 Token 后可**拉取云端记录**回填游玩状态与评分

### 其他
- 右侧滚动通知卡片（替代底部 SnackBar，失败原因不再静默）
- 数据备份/恢复（可导出到任意路径，恢复前校验并自动重启）
- 托盘图标常驻：左键唤起、右键菜单（打开/退出）
- 明暗双主题 + Mica 毛玻璃；NSFW 封面 模糊/占位/显示 三种模式（实时生效）
- 插件系统：久坐提醒内置，外部清单可导入

---

## 📸 截图

| | |
| --- | --- |
| ![主页](docs/screens/home.png) | ![游戏库](docs/screens/library.png) |
| ![详情页](docs/screens/detail_top.png) | ![添加游戏](docs/screens/add_game.png) |
| ![统计](docs/screens/stats_info.png) | ![AI 助手](docs/screens/ai_page.png) |
| ![设置](docs/screens/settings_system.png) | ![编辑信息](docs/screens/edit_sheet.png) |

---

## 🚀 快速开始

### 方式一：便携版（推荐）
下载 `KisakiGals-<version>-portable.zip`，解压后直接运行 `kisakigals.exe`。
数据（数据库/封面/缓存/存档备份）保存在 exe 同目录的 `data/`，整个文件夹拷走即迁移。

### 方式二：从源码构建
见下方「从源码构建」。仓库只保留应用源码，安装包/便携包等打包脚本不入库（见「仓库内容说明」）。

> ⚠️ 需要 **Windows 10 1809+**（Windows 11 可获得 Mica 毛玻璃效果）。
> 首次启动若杀毒软件拦截，请添加信任（应用为本地自编译；除你主动配置的刮削、AI、资源搜索请求外无任何网络上传行为）。

---

## 🛠️ 从源码构建

环境：Flutter 3.x stable（Windows 桌面）+ Visual Studio 2022（C++ 桌面工作负载）

```bash
flutter pub get
flutter build windows --release
# 产物：build\windows\x64\runner\Release\kisakigals.exe
```

测试与静态检查：

```bash
flutter analyze        # 0 issues
dart test              # 39 项单元测试
```

---

## 📦 仓库内容说明

仓库只包含**运行所需的源码与资源**。以下内容刻意不入库（`tool/`、`docs/superpowers/` 已在 `.gitignore` 中）：

| 未入库内容 | 原因 |
| --- | --- |
| Inno Setup 安装脚本、便携包打包脚本 | 发布打包用，与运行无关 |
| 设计文档 / 开发计划 | 个人开发过程文档 |
| 数据迁移脚本（Reinamanager → KisakiGals） | 一次性本地迁移用 |
| 截图/自动化测试等开发辅助脚本 | 依赖本机环境（窗口句柄、截图工具等） |
| `tools_sqlite3.dll` 等杂项文件 | 未被应用引用 |
| `.flutter-plugins-dependencies` | Flutter 自动生成的中间产物 |

---

## ⚙️ 使用提示

- **AI 配置**：设置 → AI → Base URL / API Key / 模型（OpenAI、DeepSeek、通义、Ollama、LM Studio 等任意兼容端点）
- **搜刮**：游戏库右上「添加游戏」→ 拖入 exe（或整个游戏文件夹）或输入名称 → 分组结果中确认 → 调封面/各源 ID/背景 → 入库
- **资源搜索**：侧栏「资源搜索」→ 输入中文名 → 结果按相关度排序 → 「下载页」用浏览器打开，或「入库」直接进入搜刮流程
- **重刮/换封面**：详情页「编辑信息」（全屏页面）→ 封面候选来自各平台，可「查看全部」批量挑
- **转区启动**：设置 → 系统 → 配置 `LEProc.exe`；再到「编辑信息 → 启动与存档」按游戏开启
- **存档备份**：详情页「⋯ → 存档备份」，可自动识别存档目录、手动备份、恢复（带恢复前快照）
- **备份迁移**：设置 → 数据 → 「备份到…」选择任意路径 → 在另一台电脑「从文件恢复…」（游戏路径会按设备自动重定位）

---

## 🧩 灵感与致谢（Inspiration）

本项目深度参考了以下开源项目，特此致谢：

| 项目 | 作者 | 参考内容 |
| --- | --- | --- |
| [ChronoTide](https://github.com/hardman1314/-Chrono.Tide-) | hardman1314 | 多源元数据刮削架构、VNDB 标签中文化资源（MIT，见下）、Hikarinagi 凭据流程、限流策略、启动锁与 Locale Emulator 调用方式、存档扫描与备份模型 |
| [ReinaManager](https://github.com/huoshen80/ReinaManager) | huoshen80 | 数据源适配层与 OAuth 账号体系、Token 获取入口、多源元数据整合思路、每游戏存档备份/保留策略、界面视觉风格启发 |
| [SearchGal](https://github.com/Moe-Sakura/SearchGal) | Moe-Sakura | 资源搜索的聚合思路：多站点适配器结构、发布页链接而非直链的定位、站点标签语义（免登录/需登录/需代理）、SSE 流式结果与相关度呈现 |
| [LunaBox](https://github.com/Saramanda9988/LunaBox) | Saramanda9988 | Go 侧元数据服务实现对照（元数据调度、代理解析） |

**特别说明**：
- `assets/data/vndb_tags_zh_cn.json`（VNDB 标签英→中翻译表，约 3000 条）来自 ChronoTide 项目（MIT）。
- 资源搜索的站点适配器为**本项目自行实现**，仅访问各站公开搜索接口并展示其发布页链接；本项目不解析直链、不托管任何资源。

元数据与搜索能力来自以下社区 API / 站点（各站点数据版权归其自身与投稿者所有）：Bangumi、VNDB、月幕GAL、Hikarinagi、Steam、KunGal、TouchGal、DLsite、CnGal；资源站：鲲Galgame、GAL图书馆、TouchGal、量子ACG、真红小站等。

---

## 📜 许可

- 应用源码：本项目以 **GNU Affero General Public License v3.0（AGPL-3.0）** 发布（见 LICENSE）。
- `assets/data/vndb_tags_zh_cn.json`（第三方内置资源）：MIT © ChronoTide 项目，按 MIT 条款使用。

**本项目与任何商业 galgame 发行商无关，仅供学习与个人管理使用；请在尊重各作品版权的前提下使用。请通过 Steam / DLSite 等正规渠道支持开发者。**

---

<div align="center">
Made with Flutter & ♥ · KisakiGals v0.9.1-beta
</div>
