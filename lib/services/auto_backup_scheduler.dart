/// 常驻自动备份调度器。
///
/// 参考 ReinaManager 0.30 的 `autoBackupScheduler`：
/// - 只有一个调度锚点：`max(上次成功时间, 上次尝试时间)`，避免"失败后立刻重试"
///   把网络/磁盘打满；到期即备份，逾期（应用刚启动、休眠唤醒）给 60 秒宽限。
/// - 与手动备份共用一把串行锁（这里用一个 Future 队列表达），避免并发写同一目录。
/// - 退出前可 `suspend()` 并 `await waitForRunning()`，保证退出备份不与定时备份重叠。
///
/// 与 ReinaManager 的差异：Dart 的 `Timer` 不受 32 位时长限制，无需分片重排；
/// 数据库是 sqflite/WAL，备份前用 `PRAGMA wal_checkpoint(TRUNCATE)` 合并即可，
/// 不需要"退出时先关连接再冷拷贝"。
library;

import 'dart:async';

import '../app_services.dart';
import '../data/settings_store.dart';
import 'autostart.dart';
import 'backup_schedule.dart';

class AutoBackupScheduler {
  Timer? _timer;
  bool _suspended = false;
  bool _running = false;

  /// 串行队列：备份/恢复/清理都排队执行，避免并发写同一目录
  Future<void> _queue = Future.value();

  /// 上次成功/尝试时间的内存副本（同时持久化到设置，重启后仍生效）
  DateTime? _lastSuccess;
  DateTime? _lastAttempt;

  bool get isRunning => _running;

  /// 启动调度（应用启动时调用一次，幂等）。
  Future<void> start() async {
    final s = AppServices.I.settings;
    _lastSuccess = _parse(await s.getString(SettingsStore.kBackupLastSuccess, ''));
    _lastAttempt = _parse(await s.getString(SettingsStore.kBackupLastAttempt, ''));
    _suspended = false;
    await _scheduleNext();
  }

  /// 设置变更后重新排期（设置页保存时调用）。
  Future<void> reschedule() async {
    _timer?.cancel();
    if (_suspended) return;
    await _scheduleNext();
  }

  /// 退出前挂起（不再排新的定时任务）。
  void suspend() {
    _suspended = true;
    _timer?.cancel();
    _timer = null;
  }

  /// 等待正在执行的备份结束（退出前调用，避免写到一半被杀）。
  Future<void> waitForRunning() => _queue;

  Future<void> _scheduleNext() async {
    final s = AppServices.I.settings;
    if (!await s.getBool(SettingsStore.kBackupAutoEnabled, def: false)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    final hours =
        (await s.getInt(SettingsStore.kBackupAutoHours, 12)).clamp(1, 24 * 30);
    final now = DateTime.now();
    // 排期规则见 backup_schedule.dart（纯函数，便于单测）
    final due = nextBackupDueAt(
      now: now,
      lastSuccess: _lastSuccess,
      lastAttempt: _lastAttempt,
      interval: Duration(hours: hours),
    );
    final delay = due.difference(now);
    _timer?.cancel();
    _timer = Timer(delay, runNow);
  }

  /// 立即执行一次自动备份（定时触发，或用户点「立即运行一次」）。
  /// 失败只记录状态，不重试 —— 下一个周期自然会再试。
  Future<void> runNow() async {
    if (_running) return; // 单飞
    _running = true;
    final s = AppServices.I.settings;
    _lastAttempt = DateTime.now();
    await s.setString(
        SettingsStore.kBackupLastAttempt, _lastAttempt!.toIso8601String());
    try {
      await _enqueue(() async {
        final keep = await s.getInt(SettingsStore.kBackupKeep, 20);
        final svc = BackupService(
          dbFile: AppServices.I.paths.dbFile,
          backupsDir: AppServices.I.paths.backups,
          dataRoot: AppServices.I.paths.root,
        );
        final path = await svc.backup(checkpointDb: AppServices.I.db, auto: true);
        // 只裁剪自动备份：手动导出的备份永不自动删除
        await svc.prune(keep, autoOnly: true);
        _lastSuccess = DateTime.now();
        await s.setString(SettingsStore.kBackupLastSuccess,
            _lastSuccess!.toIso8601String());
        lastAutoBackupPath = path;
      });
    } catch (e) {
      lastAutoBackupError = '$e';
    } finally {
      _running = false;
      if (!_suspended) await _scheduleNext();
    }
  }

  /// 退出时备份（可选）：独立的最小间隔，避免频繁开关应用时反复备份。
  Future<void> backupOnExitIfDue() async {
    final s = AppServices.I.settings;
    if (!await s.getBool(SettingsStore.kBackupOnExit, def: false)) return;
    final minHours = await s.getInt(SettingsStore.kBackupExitMinHours, 6);
    if (!isExitBackupDue(
        now: DateTime.now(), lastSuccess: _lastSuccess, minHours: minHours)) {
      return;
    }
    await runNow();
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task());
    // 队列本身吞掉异常，避免一次失败阻断后续排队
    _queue = next.catchError((_) {});
    return next;
  }

  static DateTime? _parse(String raw) => parseBackupTimestamp(raw);
}

/// 最近一次自动备份结果（UI/通知用）
String lastAutoBackupPath = '';
String lastAutoBackupError = '';

/// 测试探针：把调度器的纯函数部分暴露出来（不依赖 AppServices）。
class AutoBackupSchedulerProbe {
  static DateTime? parse(String raw) => AutoBackupScheduler._parse(raw);
}
