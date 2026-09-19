/// 开机自启（HKCU Run 注册表项）与备份服务。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
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

  /// 数据根目录（含 covers/ 等媒体目录）；为 null 时只备份数据库。
  final String? dataRoot;

  BackupService({
    required this.dbFile,
    required this.backupsDir,
    this.dataRoot,
  });

  /// 备份扩展名：zip 内含数据库 + 封面/背景图（换设备迁移后仍能看到图）
  static const ext = '.kgbak';

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
    final target = p.join(backupsDir, 'kisakigals-$stamp$ext');

    final archive = Archive();
    // 1) 数据库
    final dbBytes = await File(dbFile).readAsBytes();
    archive.addFile(ArchiveFile('kisakigals.db', dbBytes.length, dbBytes));
    // 2) 封面/背景等媒体（covers/ 与 saves/ 下的存档备份目录一并带上）
    final root = dataRoot;
    if (root != null) {
      for (final sub in ['covers', 'saves']) {
        final dir = Directory(p.join(root, sub));
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          final rel = p
              .relative(f.path, from: root)
              .replaceAll('\\', '/');
          final bytes = await f.readAsBytes();
          archive.addFile(ArchiveFile(rel, bytes.length, bytes));
        }
      }
    }
    // 3) 说明文件（版本与时间，便于人工确认）
    final info = utf8.encode(jsonEncode({
      'app': 'KisakiGals',
      'createdAt': DateTime.now().toIso8601String(),
      'files': archive.files.length,
    }));
    archive.addFile(ArchiveFile('backup_info.json', info.length, info));

    final out = File(target);
    await out.writeAsBytes(ZipEncoder().encode(archive), flush: true);
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

  /// 是否为（新版）打包备份。
  static bool looksLikeArchive(String path) {
    try {
      final raf = File(path).openSync();
      final head = raf.readSync(4);
      raf.closeSync();
      // PK\x03\x04
      return head.length >= 4 &&
          head[0] == 0x50 &&
          head[1] == 0x4B &&
          head[2] == 0x03 &&
          head[3] == 0x04;
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

  /// 从备份恢复（覆盖当前数据库；打包备份还会还原封面等媒体文件）。
  /// 注意：必须在数据库连接关闭后调用，恢复后需重启应用。
  /// 返回还原的媒体文件数（旧版 .db 备份为 0）。
  Future<int> restore(String backupFile) async {
    if (looksLikeArchive(backupFile)) {
      final archive = ZipDecoder().decodeBytes(
          await File(backupFile).readAsBytes(),
          verify: false);
      var media = 0;
      final root = dataRoot;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = f.name.replaceAll('\\', '/');
        if (name == 'kisakigals.db') {
          await File(dbFile).writeAsBytes(f.content as List<int>, flush: true);
          continue;
        }
        if (name == 'backup_info.json') continue;
        if (root == null) continue;
        // 只允许还原到 covers/ 与 saves/ 下，避免任意路径写入
        if (!(name.startsWith('covers/') || name.startsWith('saves/'))) {
          continue;
        }
        final dst = File(p.join(root, name.replaceAll('/', Platform.pathSeparator)));
        dst.parent.createSync(recursive: true);
        await dst.writeAsBytes(f.content as List<int>, flush: true);
        media++;
      }
      return media;
    }
    // 兼容旧版：纯 .db 文件
    await File(backupFile).copy(dbFile);
    return 0;
  }

  /// 列出备份（新→旧）：打包备份 .kgbak 与旧版 .db 都列出。
  List<FileSystemEntity> list() {
    final dir = Directory(backupsDir);
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(ext) || f.path.endsWith('.db'))
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
}
