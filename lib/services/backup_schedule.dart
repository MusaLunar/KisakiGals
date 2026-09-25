/// 备份排期的纯逻辑（不依赖 Flutter / AppServices，便于单测）。
///
/// 与 `auto_backup_scheduler.dart`（负责 Timer 与 IO）分离：这里只有
/// 「下一次该在什么时候备份」这一条规则。
library;

/// 解析设置里持久化的时间戳；空串或非法值都视为「没有锚点」。
DateTime? parseBackupTimestamp(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t);
}

/// 计算下一次自动备份的时刻。
///
/// - 锚点 = `max(lastSuccess, lastAttempt)`：失败后不会立刻重试，
///   避免网络/磁盘异常时反复备份（参考 ReinaManager 的调度语义）。
/// - 从未备份过、或已逾期（应用刚启动、休眠唤醒）时，给 [grace] 宽限，
///   让启动阶段的其他初始化先跑完。
DateTime nextBackupDueAt({
  required DateTime now,
  DateTime? lastSuccess,
  DateTime? lastAttempt,
  required Duration interval,
  Duration grace = const Duration(seconds: 60),
}) {
  final anchors = [lastSuccess, lastAttempt]
      .whereType<DateTime>()
      .where((t) => !t.isAfter(now))
      .toList();
  if (anchors.isEmpty) return now.add(grace);
  var latest = anchors.first;
  for (final t in anchors) {
    if (t.isAfter(latest)) latest = t;
  }
  final due = latest.add(interval);
  return due.isAfter(now) ? due : now.add(grace);
}

/// 退出备份是否到期（独立的最小间隔；0 表示每次退出都备份）。
bool isExitBackupDue({
  required DateTime now,
  DateTime? lastSuccess,
  required int minHours,
}) {
  if (minHours <= 0) return true;
  if (lastSuccess == null) return true;
  return now.difference(lastSuccess).inHours >= minHours;
}
