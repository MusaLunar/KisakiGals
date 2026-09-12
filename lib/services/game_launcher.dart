/// 游戏启动：普通启动 / Locale Emulator 转区启动，带启动锁与降级回退。
///
/// 参考 ChronoTide 的启动策略：
/// - 启动锁 + 代际计数 + 120s 安全阀，防止连点与 Process.run 挂死
/// - `ProcessStartMode.detached`，管理器退出不会带走游戏
/// - 首选失败后降级 `cmd /c start`（兼容全角/特殊字符路径）
/// - Locale Emulator 以裸参调用：`LEProc.exe <游戏exe绝对路径>`
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

class LaunchResult {
  final bool ok;
  final String message;
  final int? pid;
  final bool usedLocaleEmulator;
  const LaunchResult({
    required this.ok,
    this.message = '',
    this.pid,
    this.usedLocaleEmulator = false,
  });
}

class GameLauncher {
  static bool _launching = false;
  static int _generation = 0;

  /// 是否正在启动中（UI 可据此禁用按钮）。
  static bool get launching => _launching;

  /// 强制解锁（异常情况下由设置页/开发者调用）。
  static void forceResetLock() {
    _generation++;
    _launching = false;
  }

  /// 启动游戏。
  /// [exePath] 可执行文件；[directory] 工作目录（空则用 exe 父目录）；
  /// [localeEmulatorPath] 非空时用 LE 转区启动（日文游戏防乱码）。
  static Future<LaunchResult> launch(
    String exePath, {
    String directory = '',
    String localeEmulatorPath = '',
  }) async {
    if (_launching) {
      return const LaunchResult(ok: false, message: '正在启动中，请稍候…');
    }
    _launching = true;
    final myGeneration = ++_generation;
    // 安全阀：杀软扫描、cmd start 卡死等情况下的兜底解锁
    final safety = Timer(const Duration(seconds: 120), () {
      if (_generation == myGeneration) _launching = false;
    });
    try {
      return await _doLaunch(exePath,
          directory: directory, localeEmulatorPath: localeEmulatorPath);
    } finally {
      safety.cancel();
      if (_generation == myGeneration) _launching = false;
    }
  }

  static Future<LaunchResult> _doLaunch(
    String exePath, {
    required String directory,
    required String localeEmulatorPath,
  }) async {
    final exe = File(exePath.replaceAll('/', r'\'));
    if (!exe.existsSync()) {
      return const LaunchResult(ok: false, message: '可执行文件不存在');
    }
    final absExe = exe.absolute.path;
    final workDir = directory.isNotEmpty && Directory(directory).existsSync()
        ? directory
        : exe.parent.path;

    // 1) Locale Emulator 转区启动
    final le = localeEmulatorPath.trim();
    if (le.isNotEmpty) {
      final leFile = File(le);
      if (!leFile.existsSync()) {
        return const LaunchResult(
            ok: false, message: '未找到 Locale Emulator（LEProc.exe），请在设置中重新指定路径');
      }
      try {
        // LE 的唯一参数是目标 exe 绝对路径（转区配置来自 LE 自身首个 Profile）
        final r = await Process.run(
          leFile.absolute.path,
          [absExe],
          workingDirectory: workDir,
          runInShell: false,
          includeParentEnvironment: true,
        ).timeout(const Duration(seconds: 30), onTimeout: () {
          return ProcessResult(-1, -1, '', 'LE 启动超时');
        });
        if (r.exitCode != 0 && r.exitCode != -1) {
          // 非零退出码不视为致命：LE 常返回非零但游戏已起来
          return LaunchResult(
              ok: true,
              message: '已通过 Locale Emulator 启动（LE 返回码 ${r.exitCode}）',
              usedLocaleEmulator: true);
        }
        return const LaunchResult(
            ok: true, message: '已通过 Locale Emulator 启动', usedLocaleEmulator: true);
      } catch (e) {
        return LaunchResult(ok: false, message: 'Locale Emulator 启动失败：$e');
      }
    }

    // 2) 普通启动（detached）
    try {
      final process = await Process.start(absExe, [],
          workingDirectory: workDir, mode: ProcessStartMode.detached);
      return LaunchResult(ok: true, pid: process.pid);
    } catch (_) {
      // 3) 降级：cmd /c start（兼容全角路径等场景）
      try {
        await Process.run('cmd.exe', ['/c', 'start', '""', absExe],
                workingDirectory: workDir, runInShell: true)
            .timeout(const Duration(seconds: 15), onTimeout: () {
          throw TimeoutException('启动超时');
        });
        return const LaunchResult(ok: true);
      } catch (e) {
        return LaunchResult(ok: false, message: '启动失败：$e');
      }
    }
  }

  static Future<void> openDirectory(String dir) async {
    if (dir.isEmpty) return;
    await Process.run('explorer.exe', [dir.replaceAll('/', r'\')]);
  }

  static Future<void> openUrl(String url) async {
    await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
  }

  static Future<void> deleteToRecycleBin(String path) async {
    // PowerShell 调用 Shell COM 删除到回收站（转义单引号防注入/断句）
    final safe = path.replaceAll("'", "''");
    final ps =
        "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('$safe', 'OnlyErrorDialogs', 'SendToRecycleBin')";
    await Process.run('powershell', ['-NoProfile', '-Command', ps]);
  }

  /// 从游戏目录自动识别可执行文件（参考 ChronoTide GameLauncherDetector）：
  /// 1. 汉化/补丁关键词且体积最大  2. 体积最大(>1MB)  3. 与文件夹同名  4. 修改时间最新
  static String detectExecutable(String directory) {
    try {
      final dir = Directory(directory);
      if (!dir.existsSync()) return '';
      const patchHints = ['汉化', 'chs', '_cn', 'cn_', 'patch', 'patched', '中文'];
      const skipHints = ['unins', 'setup', 'install', 'config', 'launcher',
        'vcredist', 'dxsetup', 'directx', 'crash', 'updater', 'update'];
      final candidates = <File>[];
      var scanned = 0;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (++scanned > 20000) break; // 防御超大目录
        if (e is! File || !e.path.toLowerCase().endsWith('.exe')) continue;
        final name = p.basename(e.path).toLowerCase();
        if (skipHints.any(name.contains)) continue;
        candidates.add(e);
      }
      if (candidates.isEmpty) return '';
      int size(File f) {
        try {
          return f.lengthSync();
        } catch (_) {
          return 0;
        }
      }

      final dirName = p.basename(directory).toLowerCase();
      final patched = candidates
          .where((f) =>
              patchHints.any(p.basename(f.path).toLowerCase().contains))
          .toList();
      if (patched.isNotEmpty) {
        patched.sort((a, b) => size(b).compareTo(size(a)));
        if (size(patched.first) > 1024 * 1024) return patched.first.path;
      }
      final big = candidates.where((f) => size(f) > 1024 * 1024).toList()
        ..sort((a, b) => size(b).compareTo(size(a)));
      if (big.isNotEmpty) return big.first.path;
      final sameName =
          candidates.where((f) => p.basenameWithoutExtension(f.path).toLowerCase() == dirName);
      if (sameName.isNotEmpty) return sameName.first.path;
      candidates.sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified));
      return candidates.first.path;
    } catch (_) {
      return '';
    }
  }
}
