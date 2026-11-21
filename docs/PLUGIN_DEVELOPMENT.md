# KisakiGals 插件开发与分发规范（v1 · AI 开发规范参考）

> **定位说明**：本文件是**供 AI 编程助手与核心开发者查阅的技术规范**（Schema、权限、安全规则与 CI 契约）。如果你希望了解**人类开发者如何使用 Vibe Coding 借助 AI 开发并发布插件到 GitHub**，请阅读 [`docs/VIBE_CODING_PLUGIN_GUIDE.md`](./VIBE_CODING_PLUGIN_GUIDE.md)。

本文档定义 **KisakiGals** 外部插件的包结构、`manifest.json` Schema v1、运行时生命周期钩子、安全校验规范，以及基于官方聚合仓库的静态元数据插件市场分发流程。

---

## 1. 两种安装方式与分发架构

KisakiGals 移除硬编码内置插件后，插件统一通过以下两种方式安装，安装后落盘至 `<data>/plugins/<plugin-id>/` 并持久化开关与配置：

1. **内置插件市场安装（推荐）**：在「设置 → 插件与关于 → 浏览插件市场」浏览插件目录，选择直连或加速站下载 `.zip` / `.js` 包并一键安装 / 更新。
2. **本地导入 `.zip` 安装**：点击「导入 `.zip` 插件」选择离线插件压缩包，宿主完成 Schema 校验、Zip Slip 安全检测与 SHA-256 计算后解压安装。

### 优化后的插件市场分发架构

```text
开发者 (Developer)
  └─ 提交 PR（新增/更新官方聚合目录 plugins/<id>.json 或直接附带制品）
       ↓
官方聚合目录 (Registry Repo: MusaLunar/KisakiGals → plugins/)
  └─ GitHub Actions 自动审查 / 校验
       ├─ 1) manifest Schema v1 校验（id/SemVer/minAppVersion/权限白名单）
       ├─ 2) downloadUrl 连通性探测 + 体积上限检查（<= 32 MB）
       └─ 3) 自动计算/比对制品 SHA-256 哈希，防止上游资产被篡改
       ↓ PR 合并后触发 CI 构建
静态元数据发布 (GitHub Raw / jsDelivr CDN / GitHub Pages)
  └─ 聚合校验条目生成全量索引 plugins/index.json（含 generatedAt 与 sha256/sizeBytes）
       ↓ 客户端拉取（支持自定义 Registry URL 与离线精选兜底）
宿主客户端 (KisakiGals App)
  └─ 浏览市场 → 比对已安装版本号 → 优选直连 / 加速站下载 .zip / .js
       └─ SHA-256 核验 + 防目录穿越安全解压 → 注册插件与设置项 → 热启用
```

#### 架构关键优化点
- **按单插件拆分清单文件（`plugins/<id>.json`）**：开发者的 PR 只修改各自插件文件，由 CI 统一汇总生成全量 `index.json`，彻底避免多人同时提 PR 时的 `plugins.json` 合并冲突。
- **CI 锁定 `sha256` 与 `sizeBytes`**：CI 在审查和构建阶段从 Release 拉取制品计算真实 SHA-256 写入 `index.json`；客户端下载后强校验摘要，即使经由第三方 GitHub 加速代理站传输也无法注入恶意字节。
- **多加速源自动回退**：宿主客户端支持 `智能优选（auto）`、`GitHub 直连（direct）`、`ghfast.top`、`gh-proxy.com`、`jsDelivr CDN` 五种下载策略；对 `raw.githubusercontent.com` 自动重写为 `cdn.jsdelivr.net/gh/...` 静态加速节点。
- **本地离线精选兜底**：当网络隔离或聚合仓库暂未发布时，客户端内置精选目录仍可直接体验与按需安装基础插件（如「Locale Emulator 转区启动」`locale-emulator`）。

---

## 2. 插件包结构规范

### 2.1 标准 `.zip` 插件包

压缩包根目录（或唯一顶层同名子目录，如 `my-plugin/`）必须包含 `manifest.json`：

```text
my-plugin-1.0.0.zip
├── manifest.json       # 必填：插件元数据、权限、设置项与钩子定义
├── main.js             # 必填（或 manifest.entry 指定）：入口脚本
├── README.md           # 可选：说明文档
└── assets/             # 可选：图标或附加静态资源（总解压体积 <= 32 MB）
```

> 安全限制：压缩包内文件总数不得超过 **512** 个，总解压体积不超过 **32 MB**；严禁任何包含 `..`、盘符 `:` 或前导 `/` `\` 的路径（宿主在解码与写盘双阶段拦截 Zip Slip）。

### 2.2 轻量单文件 `.js` 插件

对于仅需单个脚本的小型插件，可在聚合清单中设置 `"packageType": "js"` 并将 `downloadUrl` 指向 `.js` 文件（如 GitHub Raw / jsDelivr）。客户端下载后校验 SHA-256，并在 `<plugins>/<id>/` 下自动写入 `manifest.json` 与入口脚本文件。

---

## 3. `manifest.json` 完整 Schema v1 规范

### 3.1 顶层字段

| 字段 | 类型 | 必填 | 说明与校验规则 |
| --- | --- | --- | --- |
| `schemaVersion` | `int` | 推荐 | 协议版本号，当前固定为 `1` |
| `id` | `string` | 是 | 唯一标识，匹配正则 `^[a-z0-9][a-z0-9._-]{1,63}$`（2~64 位小写字母/数字开头，可含 `._-`） |
| `name` | `string` | 是 | 展示名称（非空字符串） |
| `version` | `string` | 是 | 语义化版本号（SemVer），如 `1.1.0`、`1.2.0-beta.1` |
| `author` | `string` | 是 | 开发者名称或组织 |
| `description` | `string` | 是 | 一句话功能说明 |
| `minAppVersion` | `string` | 推荐 | 最低兼容 KisakiGals 版本（SemVer，如 `1.1.0`）；低于此版本的客户端无法安装 |
| `entry` | `string` | 推荐 | 入口相对路径，默认 `main.js`（不得含 `..` 或绝对路径） |
| `packageType` | `string` | 推荐 | `zip`（默认）或 `js` |
| `category` | `string` | 可选 | 分类标签，如 `健康提醒` / `游玩统计` / `效率工具` / `存档保护` |
| `tags` | `string[]` | 可选 | 检索关键词标签列表 |
| `homepage` | `string` | 可选 | 项目主页 / 文档 URL |
| `repository` | `string` | 可选 | 源码仓库 URL |
| `license` | `string` | 可选 | 开源协议，如 `MIT` / `Apache-2.0` |
| `permissions` | `string[]` | 推荐 | 声明所需宿主权限，必须位于官方白名单内 |
| `settings` | `object[]` | 可选 | 设置页动态渲染的配置项定义 |
| `hooks` | `object[]` | 可选 | 声明式宿主事件监听规则（可免写原生代码联动游玩会话） |

### 3.2 权限白名单（`permissions`）

出现白名单之外的权限名将在本地导入和 CI 校验阶段直接拒绝：

- `notifications`：通过宿主 `NoticeCenter` 发送应用内通知
- `session.listen`：监听游玩会话开始 / 结束等生命周期事件
- `settings.storage`：在本地数据库持久读写插件私有配置（`plugin.<id>.*`）
- `network.http`：声明需要访问外部 HTTP / REST 接口
- `library.read`：读取本地游戏库基础元数据与存档路径状态
- `process.launch`：与外部工具或辅助进程联动

### 3.3 设置项定义（`settings`）

设置页会根据 `settings` 数组自动生成对应控件：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `key` | `string` | 配置键名，宿主持久化为 `plugin.<id>.<key>` |
| `label` | `string` | 设置行左侧 / 控件旁展示标签 |
| `type` | `string` | `int`（数字微调框 `NumberBox`）、`bool`（开关 `ToggleSwitch`）或 `string`（文本框 `TextBox`） |
| `default` | `any` | 默认值（兼容旧字段 `def`） |
| `min` / `max` | `number` | 当 `type == "int"` 时生效的取值范围约束 |
| `description` | `string` | 可选辅助说明 |

### 3.4 声明式钩子（`hooks`）

宿主在插件启用时自动绑定下列事件：

- `event`: `onSessionEnd` | `onSessionTick` | `onGameLaunch` | `onScreenshotCaptured`
- `action`: `notify`（需声明 `notifications` 权限）| `log`
- `thresholdMinutes`: 可选整型阈值；若未显式填写且 `settings` 存在 `minutes` 配置项，默认读取用户设置的 `minutes`
- `message`: 通知模板文本，支持占位符 `{minutes}` 与 `{gameId}`

---

## 4. 完整开发示例：Locale Emulator 转区启动插件（`locale-emulator`）

> 上游原项目：[xupefei/Locale-Emulator](https://github.com/xupefei/Locale-Emulator)（以插件形式配置 `LEProc.exe` 路径与回退策略，并在 KisakiGals 游戏详情页「…」菜单中按作品控制 LE 转区开关）。

### 4.1 `manifest.json`

```json
{
  "schemaVersion": 1,
  "id": "locale-emulator",
  "name": "Locale Emulator 转区启动",
  "version": "1.0.0",
  "author": "xupefei / KisakiGals",
  "description": "基于 Locale Emulator (LEProc.exe) 的日文及非 Unicode 游戏转区启动插件；可在游戏详情界面「…」菜单内按作品开启转区开关",
  "homepage": "https://github.com/xupefei/Locale-Emulator",
  "repository": "https://github.com/xupefei/Locale-Emulator",
  "license": "LGPL-3.0",
  "minAppVersion": "1.1.0",
  "entry": "main.js",
  "packageType": "zip",
  "category": "启动与转区",
  "tags": ["Locale Emulator", "LE", "转区", "日文", "LEProc"],
  "permissions": ["process.launch", "settings.storage", "library.read", "notifications"],
  "settings": [
    {
      "key": "le_path",
      "label": "LEProc.exe 路径",
      "type": "string",
      "default": "",
      "description": "指向 Locale Emulator 安装目录中的 LEProc.exe（原项目：https://github.com/xupefei/Locale-Emulator）"
    },
    {
      "key": "fallback_normal",
      "label": "路径缺失时回退普通启动",
      "type": "bool",
      "default": true,
      "description": "未配置有效 LEProc.exe 时提示并回退普通启动"
    }
  ],
  "hooks": [
    {
      "event": "onGameLaunch",
      "action": "log",
      "message": "通过 Locale Emulator (LEProc.exe) 转区启动游戏 #{gameId}"
    }
  ]
}
```

### 4.2 `main.js`

```js
/**
 * KisakiGals Locale Emulator 转区启动插件入口（v1.0.0）
 * 原项目：https://github.com/xupefei/Locale-Emulator
 */
module.exports = {
  id: 'locale-emulator',
  onInit(ctx) {
    const lePath = String(ctx.config.le_path || '');
    ctx.log(`locale-emulator initialized, le_path=${lePath || '(unset)'}`);
  },
  onDispose() {
    // 清理外部句柄或临时状态
  }
};
```

### 4.3 打包 `.zip` 制品并计算校验和

```powershell
Compress-Archive -Path manifest.json, main.js, README.md -DestinationPath locale-emulator-1.0.0.zip -Force
(Get-FileHash locale-emulator-1.0.0.zip -Algorithm SHA256).Hash.ToLower()
```

---

## 5. 官方聚合仓库 PR 与 CI 规范

### 5.1 开发者提交文件（`plugins/<id>.json`）

建议官方聚合仓库采用 `plugins/<id>.json` 单文件注册，合并至 `main` 时由 CI 构建 `index.json`：

```json
{
  "schemaVersion": 1,
  "id": "locale-emulator",
  "name": "Locale Emulator 转区启动",
  "version": "1.0.0",
  "author": "xupefei / KisakiGals",
  "description": "基于 Locale Emulator (LEProc.exe) 的日文及非 Unicode 游戏转区启动插件；可在游戏详情界面「…」菜单内按作品开启转区开关",
  "homepage": "https://github.com/xupefei/Locale-Emulator",
  "repository": "https://github.com/xupefei/Locale-Emulator",
  "license": "LGPL-3.0",
  "minAppVersion": "1.1.0",
  "entry": "main.js",
  "packageType": "zip",
  "category": "启动与转区",
  "permissions": ["process.launch", "settings.storage", "library.read", "notifications"],
  "settings": [
    {
      "key": "le_path",
      "label": "LEProc.exe 路径",
      "type": "string",
      "default": "",
      "description": "指向 Locale Emulator 安装目录中的 LEProc.exe（原项目：https://github.com/xupefei/Locale-Emulator）"
    },
    {
      "key": "fallback_normal",
      "label": "路径缺失时回退普通启动",
      "type": "bool",
      "default": true
    }
  ],
  "hooks": [
    {
      "event": "onGameLaunch",
      "action": "log",
      "message": "通过 Locale Emulator (LEProc.exe) 转区启动游戏 #{gameId}"
    }
  ],
  "downloadUrl": "https://raw.githubusercontent.com/MusaLunar/KisakiGals/main/plugins/dist/locale-emulator-1.0.0.zip",
  "sha256": "10081ca25156f47d5db3aa0bfb108b3261fd724e5e2560503fb084c6002daf8d",
  "sizeBytes": 2109,
  "verified": true,
  "updatedAt": "2026-11-21"
}
```

### 5.2 GitHub Actions 自动审查与索引发布示例（`.github/workflows/registry-ci.yml`）

```yaml
name: Registry Validate & Publish index.json

on:
  pull_request:
    paths: ['plugins/*.json', 'plugins.json']
  push:
    branches: ['main']

jobs:
  validate-and-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Validate manifests & fetch release SHA-256
        run: node scripts/build-index.mjs --verify-urls
      - name: Publish index.json to gh-pages / main
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./dist
```

CI 生成的 `plugins/index.json` 格式（客户端 `PluginMarketplaceService.parseIndexJson` 直接兼容顶层对象与纯数组两种格式，默认拉取 `https://raw.githubusercontent.com/MusaLunar/KisakiGals/main/plugins/index.json`）：

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-21T04:00:00Z",
  "plugins": [
    {
      "id": "locale-emulator",
      "name": "Locale Emulator 转区启动",
      "version": "1.0.0",
      "packageType": "zip",
      "homepage": "https://github.com/xupefei/Locale-Emulator",
      "downloadUrl": "https://github.com/.../locale-emulator-1.0.0.zip",
      "sha256": "...",
      "sizeBytes": 2048,
      "verified": true
    }
  ]
}
```
