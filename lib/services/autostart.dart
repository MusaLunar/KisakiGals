/// 开机自启（HKCU Run 注册表项）与备份服务。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class AutostartService {
  static const _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'KisakiGals';

  Future<bool> isEnabled() async {
    final r = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
    return r.exitCode == 0;
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      final exe = Platform.resolvedExecutable;
      await Process.run('reg', [
        'add', _runKey, '/v', _valueName, '/t', 'REG_SZ', '/d', '"$exe"', '/f'
      ]);
    } else {
      await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
    }
  }
}

class BackupService {
  final String dbFile;
  final String backupsDir;

  BackupService({required this.dbFile, required this.backupsDir});

  /// 创建备份，返回备份文件路径。
  Future<String> backup() async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final target = p.join(backupsDir, 'kisakigals-$stamp.db');
    await File(dbFile).copy(target);
    return target;
  }

  /// 从备份恢复（覆盖当前数据库文件，需重启应用生效）。
  Future<void> restore(String backupFile) async {
    await File(backupFile).copy(dbFile);
  }

  /// 列出备份（新→旧）。
  List<FileSystemEntity> list() {
    final dir = Directory(backupsDir);
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  /// 只保留最近 [keep] 份。
  Future<int> prune(int keep) async {
    final files = list();
    var removed = 0;
    for (var i = keep; i < files.length; i++) {
      await files[i].delete();
      removed++;
    }
    return removed;
  }

  /// 导出 JSON（设置/账号之外的库数据概要，供迁移）。
  Future<String> exportInfo() async {
    return jsonEncode({
      'dbSize': File(dbFile).lengthSync(),
      'backups': list().map((f) => p.basename(f.path)).toList(),
    });
  }
}
