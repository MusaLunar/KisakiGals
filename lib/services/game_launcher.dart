/// 游戏启动与目录打开。
library;

import 'dart:io';

class GameLauncher {
  /// 启动游戏 exe；返回 Process（监控器轮询其存活状态）。
  static Future<Process> launch(String exePath, String directory) async {
    final exe = exePath.replaceAll('/', r'\');
    return Process.start(exe, [],
        workingDirectory: directory.isEmpty ? null : directory,
        mode: ProcessStartMode.detached);
  }

  static Future<void> openDirectory(String dir) async {
    if (dir.isEmpty) return;
    await Process.run('explorer.exe', [dir.replaceAll('/', r'\')]);
  }

  static Future<void> openUrl(String url) async {
    await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
  }

  static Future<void> deleteToRecycleBin(String path) async {
    // PowerShell 调用 Shell COM 删除到回收站
    final ps =
        "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('$path', 'OnlyErrorDialogs', 'SendToRecycleBin')";
    await Process.run('powershell', ['-NoProfile', '-Command', ps]);
  }
}
