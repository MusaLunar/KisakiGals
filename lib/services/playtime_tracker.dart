/// 游玩会话跟踪：轮询进程表 + 前台窗口判定，产出会话。
library;

import 'dart:async';
import 'dart:io';

import '../core/constants.dart';
import '../data/models.dart';
import 'process_monitor.dart';

class PlaytimeTracker {
  Timer? _timer;
  final _controller = StreamController<PlaySessionEnd>.broadcast();

  /// 会话结束事件流。
  Stream<PlaySessionEnd> get onSessionEnd => _controller.stream;

  int? _gameId;
  String _exeName = '';
  Set<String> _watchNames = {};
  TimeTrackingMode _mode = TimeTrackingMode.foreground;

  DateTime? _startedAt;
  int _countedSeconds = 0;
  int _misses = 0; // 连续未见游戏进程的次数
  bool _sawProcess = false;

  /// 是否正在跟踪。
  bool get tracking => _gameId != null;

  int? get trackedGameId => _gameId;

  /// 开始跟踪一个游戏（先启动 exe，再调用）。
  void startTracking({
    required int gameId,
    required String exePath,
    required String directory,
    required TimeTrackingMode mode,
  }) {
    stopTracking(saveSession: false);
    _gameId = gameId;
    _mode = mode;
    _startedAt = DateTime.now();
    _countedSeconds = 0;
    _misses = 0;
    _sawProcess = false;

    _exeName = exePath.split(Platform.pathSeparator).last.toLowerCase();
    _watchNames = {_exeName};
    try {
      final dir = Directory(directory);
      if (dir.existsSync()) {
        for (final f in dir.listSync(recursive: true)) {
          if (f is File && f.path.toLowerCase().endsWith('.exe')) {
            _watchNames.add(f.path.split(Platform.pathSeparator).last.toLowerCase());
            if (_watchNames.length > 200) break; // 防异常目录
          }
        }
      }
    } catch (_) {}

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final procs = enumerateProcesses();
    final matched = <int>{};
    for (final p in procs) {
      if (_watchNames.contains(p.exeFile.toLowerCase())) {
        matched.add(p.pid);
      }
    }

    if (matched.isNotEmpty) {
      _sawProcess = true;
      _misses = 0;
      final counting = _mode == TimeTrackingMode.elapsed ||
          matched.contains(foregroundPid());
      if (counting) {
        _countedSeconds++;
      }
    } else {
      _misses++;
      // 进程消失 ≥3 秒 → 会话结束（尚未出现进程时给 60s 启动宽限）
      if (_sawProcess && _misses >= 3) {
        stopTracking(saveSession: true);
      } else if (!_sawProcess &&
          _startedAt != null &&
          DateTime.now().difference(_startedAt!).inSeconds > 60) {
        stopTracking(saveSession: _countedSeconds > 0);
      }
    }
  }

  /// 结束跟踪；始终发出事件（session 可为 null，用于 UI 复位），有有效时长时才计会话。
  void stopTracking({bool saveSession = true}) {
    _timer?.cancel();
    _timer = null;
    final game = _gameId;
    final start = _startedAt;
    _gameId = null;
    _startedAt = null;
    _watchNames = {};
    if (game == null || start == null) return;
    final end = DateTime.now();
    final elapsed = end.difference(start).inSeconds;
    final session =
        saveSession && _countedSeconds > 0
            ? GameSession(gameId: game, start: start, end: end, seconds: _countedSeconds)
            : null;
    _controller.add(PlaySessionEnd(
        session: session, elapsedSeconds: elapsed, gameId: game));
  }

  /// 当前已计入秒数（UI 实时展示）。
  int get liveSeconds => _countedSeconds;

  void dispose() {
    stopTracking(saveSession: false);
    _controller.close();
  }
}

class PlaySessionEnd {
  final GameSession? session; // null = 会话无效（进程未出现/零时长）
  final int elapsedSeconds;
  final int gameId;
  const PlaySessionEnd(
      {required this.session, required this.elapsedSeconds, required this.gameId});
}
