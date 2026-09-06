/// 开机自启（HKCU Run 注册表项）与备份服务。
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  /// [checkpointDb]：应用内调用时传入已打开的数据库连接，
  /// 先把 WAL 合并回主库，否则运行中复制的文件可能缺最新数据。
  Future<String> backup({Database? checkpointDb}) async {
    if (checkpointDb != null) {
      try {
        await checkpointDb.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final target = p.join(backupsDir, 'kisakigals-$stamp.db');
    await File(dbFile).copy(target);
    return target;
  }

  /// 校验文件是否为 SQLite 数据库（文件头 magic）。
  static bool looksLikeSqlite(String path) {
    try {
      final raf = File(path).openSync();
      final head = raf.readSync(16);
      raf.closeSync();
      return String.fromCharCodes(head.take(15)) == 'SQLite format 3';
    } catch (_) {
      return false;
    }
  }

  /// 删除 WAL/SHM 附属文件（恢复覆盖前必须，否则旧数据会回写）。
  void removeSidecarFiles() {
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$dbFile$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// 从备份恢复（覆盖当前数据库文件）。
  /// 注意：必须在数据库连接关闭后调用，恢复后需重启应用。
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
