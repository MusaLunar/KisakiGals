import 'dart:io';

import 'package:kisakigals/services/backup_schedule.dart';
import 'package:kisakigals/services/autostart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 自动备份调度器的纯逻辑 + BackupService 的命名/保留策略。
///
/// 这些点来自 ReinaManager 0.30 的两次修复（定时调度、唯一命名与安全发布）：
/// 同秒重名不能静默覆盖、失败不能留下半成品、保留策略不能误删手动备份。
void main() {
  group('备份文件命名与发布', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('kisaki_autobk_');
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// 备份目录与数据库文件必须分开：`list()` 为兼容旧格式也会列出 .db，
    /// 若把源数据库放进备份目录会被误计入备份数量。
    BackupService svc(Directory d) {
      final root = Directory(p.join(d.path, 'root'))..createSync(recursive: true);
      final backups = Directory(p.join(d.path, 'backups'))..createSync(recursive: true);
      File(p.join(root.path, 'test.db')).writeAsStringSync('payload');
      return BackupService(
        dbFile: p.join(root.path, 'test.db'),
        backupsDir: backups.path,
        dataRoot: root.path,
      );
    }

    test('auto 前缀与手动前缀分离', () {
      expect(BackupService.autoPrefix, 'kisakigals-auto-');
      expect(BackupService.manualPrefix, 'kisakigals-');
      // 手动前缀是自动前缀的前缀之一，因此裁剪必须显式按 auto 前缀过滤
      expect(BackupService.autoPrefix.startsWith(BackupService.manualPrefix),
          isTrue);
    });

    test('同秒内连续备份得到不同文件名（序号避让，不覆盖）', () async {
      final d = Directory.systemTemp.createTempSync('kisaki_bk2_');
      addTearDown(() => d.deleteSync(recursive: true));
      final s = svc(d);
      final a = await s.backup(auto: true);
      final b = await s.backup(auto: true);
      final c = await s.backup(); // 手动
      expect({a, b, c}.length, 3, reason: '三次备份文件名应互不相同');
      expect(p.basename(a).startsWith(BackupService.autoPrefix), isTrue);
      expect(p.basename(c).startsWith(BackupService.autoPrefix), isFalse);
    });

    test('发布后不残留 .creating 临时文件，且产物可被 zip 解析', () async {
      final s = svc(dir);
      final path = await s.backup(auto: true);
      final leftovers = Directory(s.backupsDir)
          .listSync()
          .where((e) => e.path.endsWith('.creating'))
          .toList();
      expect(leftovers, isEmpty);
      expect(File(path).lengthSync(), greaterThan(100));
      expect(BackupService.looksLikeArchive(path), isTrue);
    });

    test('prune(autoOnly: true) 只清理自动备份，手动备份永不删除', () async {
      final d = Directory.systemTemp.createTempSync('kisaki_bk3_');
      addTearDown(() => d.deleteSync(recursive: true));
      final s = svc(d);
      // 1 份手动 + 3 份自动
      await s.backup();
      for (var i = 0; i < 3; i++) {
        await s.backup(auto: true);
        await Future.delayed(const Duration(milliseconds: 1050));
      }
      expect(s.list().length, 4);
      await s.prune(1, autoOnly: true);
      final left = s.list().map((f) => p.basename(f.path)).toList();
      expect(left.where((n) => n.startsWith(BackupService.autoPrefix)).length, 1,
          reason: '自动备份应被裁剪到 1 份');
      expect(left.where((n) => !n.startsWith(BackupService.autoPrefix)).length, 1,
          reason: '手动备份必须保留');
    });
  });

  group('排期规则', () {
    final now = DateTime(2026, 9, 13, 12, 0, 0);

    test('时间戳解析：空串/非法值视为没有锚点', () {
      expect(parseBackupTimestamp(''), isNull);
      expect(parseBackupTimestamp('not-a-date'), isNull);
      expect(parseBackupTimestamp('2026-09-13T10:00:00'), isNotNull);
    });

    test('从未备份过：给宽限而不是立刻备份', () {
      final due = nextBackupDueAt(
          now: now,
          interval: const Duration(hours: 12),
          grace: const Duration(seconds: 60));
      expect(due.difference(now), const Duration(seconds: 60));
    });

    test('锚点取「上次成功/上次尝试」的较晚者（失败不会立刻重试）', () {
      final due = nextBackupDueAt(
        now: now,
        lastSuccess: now.subtract(const Duration(hours: 12)),
        lastAttempt: now.subtract(const Duration(minutes: 5)),
        interval: const Duration(hours: 12),
      );
      // 以 5 分钟前的尝试为锚 → 还需约 11 小时 55 分
      expect(due.difference(now).inMinutes, closeTo(715, 2));
    });

    test('已逾期（休眠/刚启动）：给宽限', () {
      final due = nextBackupDueAt(
        now: now,
        lastSuccess: now.subtract(const Duration(days: 3)),
        interval: const Duration(hours: 12),
      );
      expect(due.difference(now), const Duration(seconds: 60));
    });

    test('退出备份最小间隔：0 表示每次退出；未备份过立即到期', () {
      expect(
          isExitBackupDue(now: now, lastSuccess: null, minHours: 6), isTrue);
      expect(
          isExitBackupDue(
              now: now,
              lastSuccess: now.subtract(const Duration(hours: 2)),
              minHours: 6),
          isFalse);
      expect(
          isExitBackupDue(
              now: now,
              lastSuccess: now.subtract(const Duration(hours: 7)),
              minHours: 6),
          isTrue);
      expect(
          isExitBackupDue(
              now: now,
              lastSuccess: now.subtract(const Duration(minutes: 1)),
              minHours: 0),
          isTrue);
    });
  });
}
