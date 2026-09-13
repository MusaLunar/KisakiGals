<div align="center">

# 🌸 KisakiGals

**Galgame 收藏、游玩时长与资源搜索管理器** · Flutter Windows 桌面应用 · VIBE CODING

> 「无论何时，都想与她们再次相见。」

**当前版本：0.9.1-beta** ｜ 作者：MusaLunar ｜ [项目主页](https://github.com/MusaLunar/KisakiGals)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

</div>

---

## ✨ 功能

- 🏠 **主页**：本周/本月/总计速览、最近游玩一键继续、动态时间线、为你推荐
- 📚 **游戏库**：封面 2:3 网格、筛选边栏（排序/状态/收藏/来源/开发商/标签）、批量管理
- 🎮 **详情页**：游玩记录卡片（总时长 / 本次实时计时 / 平均单次）、30 天趋势、平台评分、标签与简介
- 🔍 **资源搜索**：聚合多个资源站的发布页，并发搜索、按相关度排序，一键打开下载页或直接入库
- 📊 **统计**：信息 / 评分 / 总结三页，含时段分布、星期分布、词云与月度热力
- 🤖 **AI 助手**：结合你的游玩数据生成总结与作品推荐（支持任意 OpenAI 兼容接口）
- ➕ **添加游戏**：拖入 exe 或文件夹自动搜刮，也可关键词搜索；9 个数据源并发、同一作品多源合并

**游玩时长** · 秒级进程检测，仅前台计时或挂机计时双模式；标题栏与详情页实时显示本局时长；最小化到托盘也照常计时。

**启动与存档** · 支持 Locale Emulator 转区启动（日文原版防乱码）；可自动识别游戏程序与存档目录，退出游戏后自动备份存档，恢复前自动留快照。

**数据与迁移** · 记录设备与相对路径，换电脑或换盘后导入数据库会自动找回游戏目录；一键备份/恢复，可导出到任意路径。

**评分与云同步** · 本地评分与评论，可同步 Bangumi、VNDB、Hikarinagi 的收藏与评价。

**界面** · 明暗双主题 + Mica 毛玻璃；NSFW 封面支持模糊 / 占位 / 显示三种模式。

---

## 📸 截图

| | |
| --- | --- |
| ![主页](docs/screens/home.png) | ![游戏库](docs/screens/library.png) |
| ![详情页](docs/screens/detail_top.png) | ![添加游戏](docs/screens/add_game.png) |
| ![统计](docs/screens/stats_info.png) | ![AI 助手](docs/screens/ai_page.png) |
| ![设置](docs/screens/settings_system.png) | ![编辑信息](docs/screens/edit_sheet.png) |

---

## 🚀 下载与运行

从 [Releases](https://github.com/MusaLunar/KisakiGals/releases) 下载便携版压缩包，解压后运行 `kisakigals.exe`。
数据（数据库、封面、存档备份）都保存在 exe 同目录的 `data/` 文件夹，整个文件夹拷走即可迁移。

> 需要 **Windows 10 1809 或更高版本**（Windows 11 可获得毛玻璃效果）。

从源码构建（Flutter 3.x + Visual Studio 2022 C++ 桌面工作负载）：

```bash
flutter pub get
flutter build windows --release
```

---

## ⚙️ 使用提示

- **添加游戏**：拖入 exe 或整个游戏文件夹即可自动搜刮；也可输入名称跨源搜索后确认
- **资源搜索**：输入中文名效果最好，结果按相关度排序；「下载页」用浏览器打开，「入库」直接进入搜刮流程
- **换封面**：详情页「编辑信息」中可从各平台封面里挑选，候选多时可点「查看全部」
- **转区启动**：先在设置 → 系统里选择 `LEProc.exe`，再到「编辑信息 → 启动与存档」按游戏开启
- **存档备份**：详情页「⋯ → 存档备份」，可自动识别存档目录并备份、恢复
- **AI 助手**：设置 → AI 填入 Base URL / API Key / 模型后即可使用

---

## 🧩 灵感与致谢

参考了以下开源项目，特此致谢：

| 项目 | 参考内容 |
| --- | --- |
| [ChronoTide](https://github.com/hardman1314/-Chrono.Tide-) | 多源元数据刮削、VNDB 标签中文化资源、启动与存档管理思路 |
| [ReinaManager](https://github.com/huoshen80/ReinaManager) | 账号体系与多源元数据整合、存档备份策略、界面风格启发 |
| [SearchGal](https://github.com/Moe-Sakura/SearchGal) | 资源搜索的多站点聚合思路与结果呈现 |
| [LunaBox](https://github.com/Saramanda9988/LunaBox) | 元数据服务实现对照 |

元数据与搜索数据来自以下社区站点，版权归各站点与投稿者所有：Bangumi、VNDB、月幕GAL、Hikarinagi、Steam、KunGal、TouchGal、DLsite、CnGal，以及鲲Galgame、GAL图书馆、量子ACG、真红小站等资源站。

---

## 📜 许可

以 **AGPL-3.0** 发布（见 LICENSE）。内置的 VNDB 标签中文化资源来自 ChronoTide 项目（MIT）。

本项目与任何商业发行商无关，仅供学习与个人管理使用；请通过 Steam、DLSite 等正规渠道支持开发者。

---

<div align="center">
Made with Flutter & ♥ · KisakiGals v0.9.1-beta
</div>
