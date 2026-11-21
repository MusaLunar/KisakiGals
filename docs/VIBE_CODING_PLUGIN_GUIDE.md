# KisakiGals 插件开发与上架指南（Vibe Coding 人类实战版）

> **阅读对象声明**：
> - **本文件（`docs/VIBE_CODING_PLUGIN_GUIDE.md`）是写给人类开发者看的**，教你如何用 AI（Vibe Coding）零基础做出插件、打包测试并发布到 GitHub 与插件市场。
> - **AI 编程助手不需要读本文件**；让 AI 写代码时，请直接让它读取 **[`docs/PLUGIN_DEVELOPMENT.md`](./PLUGIN_DEVELOPMENT.md)**（以及宿主核心源码 [`lib/services/plugin_system.dart`](../lib/services/plugin_system.dart)）。

---

## 0. 开始前准备（5 分钟）

1. **一款 AI 编程工具**（任选其一）：
   - IDE / 编辑器类：Antigravity、Cursor、Windsurf、VS Code + Copilot
   - 终端 Agent 类：Claude Code、Codex CLI、Gemini CLI
2. **基础环境**（可选，AI 也会帮你执行）：
   - Windows PowerShell（系统自带，用于打包 `.zip` 与计算 SHA-256）
   - [Git](https://git-scm.com/) 与 [GitHub CLI (`gh`)](https://cli.github.com/)（用于把插件推上 GitHub 并自动提 PR）
   - 一个免费 GitHub 账号

---

## 1. 第一步：用 Vibe Coding 让 AI 生成插件

新建一个空文件夹作为你的插件仓库（例如 `D:\kisaki-plugin-mytool`），在该目录打开你的 AI 工具，**把下面整段话改一改需求发给 AI**。

### 通用 Vibe Coding 提示词模板（可直接复制）

```text
请先完整阅读 KisakiGals 的插件技术规范文件：
- docs/PLUGIN_DEVELOPMENT.md（GitHub Raw: https://raw.githubusercontent.com/MusaLunar/KisakiGals/main/docs/PLUGIN_DEVELOPMENT.md）
- 若在 KisakiGals 仓库工作区内，请同时参考 lib/services/plugin_system.dart

严格遵守其中的 manifest.json Schema v1、id 正则、权限白名单、hooks 规则与目录限制，帮我在当前目录生成一个可安装的 KisakiGals 插件项目：

【我要做的插件功能】：
- 插件名称：______（例如：自动启动手柄映射工具）
- 插件 ID：______（仅限小写字母/数字/._-，如 gamepad-mapper）
- 核心逻辑：______（例如：配置外部 exe 路径、设置 boolean/int 参数、或监听游玩结束 onSessionEnd 发送应用内通知）
- 参考开源项目（可选）：______

请一次性输出并创建以下文件：
1. manifest.json（包含完整 schemaVersion=1、permissions 白名单、settings 配置项、hooks 定义）
2. main.js（入口脚本）
3. README.md（包含安装说明与原项目致谢/开源协议）
4. plugins/<id>.json（用于向官方仓库 MusaLunar/KisakiGals 的 plugins/ 目录提交 PR 的登记清单）
5. package.ps1（一行脚本：校验字段、打包成 <id>-<version>.zip 并打印小写 sha256 哈希）
```

### 进阶示例：像官方 Locale Emulator 插件一样封装外部工具

如果你想给其他工具（例如类似 [`xupefei/Locale-Emulator`](https://github.com/xupefei/Locale-Emulator) 的存档同步器、翻译器、帧率解锁器等）做插件，可以这样对 AI 说：

```text
请参考 docs/PLUGIN_DEVELOPMENT.md 中 locale-emulator 插件的设计模式，我需要为一个第三方 Windows 工具制作 KisakiGals 插件：
- 工具项目地址：https://github.com/xxxxx/xxxxx
- 需要让用户在 KisakiGals「设置 → 插件与关于」中配置工具的 exe 路径（string 类型、key 命名为 tool_path）和一个功能开关（bool 类型）
- 声明最小必需权限（如 process.launch / settings.storage / notifications）
请生成完整的 manifest.json、main.js、README.md，以及对应的市场登记清单和打包脚本。
```

### AI 改错与排障提示词

如果在客户端点击「导入 `.zip` 插件」时弹出报错提示（例如权限不在白名单、压缩包缺少 `manifest.json` 等），**直接把报错原文截图或复制给 AI**：

```text
我在 KisakiGals 导入你生成的 .zip 插件时报错：
“<粘贴 KisakiGals 右上角 InfoBar 报错文本>”
请对照 docs/PLUGIN_DEVELOPMENT.md 的校验规则修正 manifest.json 和打包脚本，重新生成 zip 包和 sha256。
```

---

## 2. 第二步：在本地打包并安装测试

在插件项目根目录运行 PowerShell（或者直接让 AI 帮你跑），打包为 `.zip` 并算出 SHA-256：

```powershell
# 假设你的插件目录里已有 manifest.json、main.js、README.md
$id = "my-plugin"
$ver = "1.0.0"
Compress-Archive -Path manifest.json, main.js, README.md -DestinationPath "$id-$ver.zip" -Force
(Get-FileHash "$id-$ver.zip" -Algorithm SHA256).Hash.ToLower()
```

记下控制台输出的那串 **64 位小写 SHA-256 哈希值**（后面上传市场时要用到）。

然后打开 **KisakiGals**：
1. 进入左侧栏 **设置 → 插件与关于**。
2. 点击 **导入 `.zip` 插件**，选中刚才生成的 `<id>-<version>.zip`。
3. 确认：
   - 插件出现在已安装列表中，状态为 **开**。
   - 若你在 `manifest.json` 中定义了 `settings`（如路径配置框、开关、数字阈值），它们会自动渲染在卡片右侧，点击测试保存是否正常。
   - 若做了类似 Locale Emulator 的启动集成，检查对应设置或通知是否按预期触发。

---

## 3. 第三步：上传到 GitHub 并发布 Release

想让其他玩家能在 KisakiGals 的「插件市场」直接下载你的插件，需要把插件放到你自己的 GitHub 仓库并打一个 **Release**。

### 方法 A：让 AI 用 `gh` CLI 一步全自动搞定（最省事）

如果你电脑已安装并登录了 GitHub CLI（运行一次 `gh auth login`），直接把下面这句话发给 AI：

```text
请检查当前目录并帮我执行 GitHub 发布流程（请先向我确认仓库名）：
1. 初始化 git 仓库，添加合理 .gitignore（忽略临时打包产物或只保留源码）并提交首个 commit。
2. 使用 gh repo create 在我的 GitHub 账号下创建一个公开仓库（如 kisaki-plugin-<id>）并推送到 main 分支。
3. 重新生成干净的 <id>-<version>.zip，使用 gh release create v<version> <id>-<version>.zip 发布正式 Release。
4. 获取该 Release 附件的永久下载链接和 SHA-256，自动填入 plugins/<id>.json 备用。
```

### 方法 B：GitHub 网页端手动操作（无需命令行 Git）

1. 登录 [GitHub](https://github.com)，点击右上角 **`+` → `New repository`**，创建一个公开（Public）仓库，例如 `kisaki-plugin-demo`。
2. 在仓库页面点击 **`Add file` → `Upload files`**，把你的 `manifest.json`、`main.js`、`README.md` 拖进去提交到 `main` 分支。
3. 回到仓库主页，点击右侧栏 **`Releases` → `Create a new release`**：
   - **Tag version**：填 `v1.0.0`（与 `manifest.json` 的 `version` 对应）
   - **Release title**：填 `v1.0.0`
   - 在最下方的 **`Attach binaries by dropping them here or selecting them`** 区域，把你本地测试通过的 `<id>-<version>.zip` 拖进去。
   - 点击绿色按钮 **`Publish release`**。
4. 发布完成后，在 Release 页面右键点击那个 `.zip` 文件，选择 **复制链接地址**，你会得到类似下面的链接：
   `https://github.com/你的用户名/仓库名/releases/download/v1.0.0/my-plugin-1.0.0.zip`

> 小提示：如果你的插件是一个纯粹的单文件 `.js` 脚本（`packageType: "js"`），也可以直接上传 `main.js` 到仓库的 `main` 分支，使用 `https://raw.githubusercontent.com/你的用户名/仓库名/main/main.js` 作为 `downloadUrl`（KisakiGals 会自动通过 jsDelivr 镜像站加速拉取）。

---

## 4. 第四步：提交 PR 上架 KisakiGals 官方插件市场

KisakiGals 的插件市场采用 **单插件单文件注册机制**（官方仓库聚合目录为 [`MusaLunar/KisakiGals` 的 `plugins/`](https://github.com/MusaLunar/KisakiGals/tree/main/plugins)），你的 PR 只需要新增一个属于你自己的 `.json` 文件，**不会和任何其他开发者的 PR 冲突**。

### 4.1 准备 `plugins/<你的插件id>.json`

让 AI（或你自己）创建文件 `plugins/<你的插件id>.json`，内容格式如下（其中字段规范详见 AI 规范文档）：

```json
{
  "schemaVersion": 1,
  "id": "my-plugin",
  "name": "我的实用插件",
  "version": "1.0.0",
  "author": "你的 GitHub 用户名",
  "description": "一句话说明插件的作用",
  "homepage": "https://github.com/你的用户名/你的插件仓库",
  "repository": "https://github.com/你的用户名/你的插件仓库",
  "license": "MIT",
  "minAppVersion": "1.1.0",
  "entry": "main.js",
  "packageType": "zip",
  "category": "效率工具",
  "tags": ["效率", "工具"],
  "permissions": ["notifications", "settings.storage"],
  "settings": [],
  "hooks": [],
  "downloadUrl": "https://github.com/你的用户名/你的插件仓库/releases/download/v1.0.0/my-plugin-1.0.0.zip",
  "sha256": "把第二步算出来的64位小写sha256粘贴在这里",
  "updatedAt": "2026-11-21"
}
```

### 4.2 提交 Pull Request

#### 方式 1：网页端直接提 PR（零 Git 基础推荐）
1. 打开官方仓库：[`https://github.com/MusaLunar/KisakiGals`](https://github.com/MusaLunar/KisakiGals)。
2. 点击页面上方 **`Fork`**，把它 Fork 到你自己的 GitHub 账号下。
3. 在你 Fork 出来的仓库里，点击 **`Add file` → `Create new file`**：
   - 文件路径填 `plugins/<你的插件id>.json`（注意文件名必须与你清单里的 `id` 完全一致）。
   - 粘贴上面准备好的 JSON 内容，点击 **`Commit changes...`**。
4. 回到你 Fork 仓库的主页，页面上方会出现 **`Contribute` → `Open pull request`** 提示按钮，点击提交 PR，并在说明里简述插件用途与原项目链接（如有第三方工具请附上原作者仓库地址与开源协议）。
5. PR 合并后更新 `plugins/index.json`，全球用户的 KisakiGals「插件市场」就会立刻刷新出你的插件（包括自动匹配 jsDelivr / 加速源）。

#### 方式 2：让 AI 用 `gh` CLI 自动 Fork + 提 PR

```text
请帮我把 plugins/<id>.json 提交为 MusaLunar/KisakiGals 仓库（plugins/ 目录）的 Pull Request：
1. 检查 plugins/<id>.json 中的 downloadUrl 是否能 HTTP 200 下载，且下载内容的 SHA-256 与清单中 sha256 字段完全一致。
2. 使用 gh repo fork MusaLunar/KisakiGals --clone 到临时目录，新建分支 feat/<id>，放入 plugins/<id>.json 并提交推送。
3. 使用 gh pr create 提交 PR 到 MusaLunar/KisakiGals 的 main 分支，并在 PR 描述中附上版本号、功能简介、权限说明与 sha256 校验结果。
```

---

## 5. 常见上线前自检清单

- [ ] 如果封装了别人的开源项目（例如 `xupefei/Locale-Emulator`），已在 `homepage` / `repository` / `license` / `README.md` 中完整标明原项目地址与开源协议。
- [ ] `plugins/<id>.json` 里的 `sha256` 是用最终上传到 GitHub Release 的同一个 `.zip` 文件现算的（改过哪怕一个空格都需要重新打包、重新上传 Release、重新算哈希）。
- [ ] `permissions` 只申请插件真正用到的权限，不要多填无关权限，避免审查被拒。
- [ ] 先在本地 KisakiGals 客户端通过「导入 `.zip` 插件」完整跑通功能后再发 Release 与 PR。
