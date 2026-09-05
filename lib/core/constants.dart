/// 全局常量与枚举。
library;

/// 游玩状态（与数据库 int 1-5 对应）。
enum PlayStatus {
  wish(1, '想玩'),
  playing(2, '在玩'),
  played(3, '玩过'),
  onHold(4, '搁置'),
  dropped(5, '弃坑');

  final int value;
  final String label;
  const PlayStatus(this.value, this.label);

  static PlayStatus fromValue(int v) =>
      PlayStatus.values.firstWhere((e) => e.value == v, orElse: () => PlayStatus.wish);
}

/// 游玩时间记录方式。
enum TimeTrackingMode {
  foreground, // 仅前台时计时
  elapsed, // 进程存活即计时
}

/// 排序维度。
enum GameSort {
  addedDesc('添加日期'),
  lastPlayedDesc('上次游玩'),
  userRatingDesc('我的评分'),
  platformRatingDesc('平台评分'),
  playtimeDesc('游玩时长'),
  nameAsc('名称');

  final String label;
  const GameSort(this.label);
}

/// 统计周期。
enum StatsPeriod {
  week('本周'),
  month('本月'),
  year('今年'),
  all('总计');

  final String label;
  const StatsPeriod(this.label);
}

/// 元数据源 id（与数据库 game_sources.source 对应）。
class KisakiSources {
  static const vndb = 'vndb';
  static const bangumi = 'bgm';
  static const ymgal = 'ymgal';
  static const hikarinagi = 'hikarinagi';
  static const steam = 'steam';
  static const cngal = 'cngal';
  static const kun = 'kun';
  static const touchgal = 'touchgal';
  static const dlsite = 'dlsite';
  static const custom = 'custom';

  /// 源 id → 显示名。
  static const Map<String, String> labels = {
    vndb: 'VNDB',
    bangumi: 'Bangumi',
    ymgal: '月幕GAL',
    hikarinagi: 'Hikarinagi',
    steam: 'Steam',
    cngal: 'CnGal',
    kun: 'KunGal',
    touchgal: 'TouchGal',
    dlsite: 'DLsite',
    custom: '自定义',
  };

  /// 默认启用的刮削源。
  static const List<String> defaultEnabled = [
    vndb,
    bangumi,
    ymgal,
    hikarinagi,
    steam,
    cngal,
    kun,
    touchgal,
  ];
}

/// 应用信息。
class AppInfo {
  static const name = 'KisakiGals';
  static const version = '0.1.0';
  static const author = 'MusaLunar';
  static const repository = '（筹备中）';
}
