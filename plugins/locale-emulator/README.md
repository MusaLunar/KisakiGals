# Locale Emulator 转区启动插件 (`locale-emulator`)

本插件为 [KisakiGals](https://github.com/MusaLunar/KisakiGals) 提供基于 **[xupefei/Locale-Emulator](https://github.com/xupefei/Locale-Emulator)** (`LEProc.exe`) 的 Windows 非 Unicode 日文游戏转区启动支持。

## 功能说明

- 在 **设置 → 插件与关于** 中启用本插件并填入本机 `LEProc.exe` 路径，可按需开启「路径缺失时回退普通启动」。
- 安装并启用后，进入任意游戏详情页右上角 **「…」更多菜单**，即可看到独立的 **「使用 LE 转区启动」** 开关，按单部作品自由控制是否转区启动。
- 当未启用本插件或游戏未打开转区开关时，直接以常规方式启动。

## 致谢与协议

- 上游工具项目：[https://github.com/xupefei/Locale-Emulator](https://github.com/xupefei/Locale-Emulator)
- 开源协议：LGPL-3.0
- 本插件仅调用用户本地已安装的 `LEProc.exe` 可执行文件，不包含或分发 Locale Emulator 二进制文件。
