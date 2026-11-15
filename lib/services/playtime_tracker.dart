/// 游玩会话跟踪：轮询进程表 + 前台窗口判定，产出会话。
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../app_services.dart';
import '../core/constants.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import 'process_monitor.dart';
import 'save_write_watcher.dart';
import 'window_capture.dart';

class PlaytimeTracker {
  Timer? _timer;
  Timer? _hotkeyTimer;
  final _controller = StreamController<PlaySessionEnd>.broadcast();
  final _captureController = StreamController<PlayPathCaptureEvent>.broadcast();

  /// 会话结束事件流。
  Stream<PlaySessionEnd> get onSessionEnd => _controller.stream;

  /// 游玩路径截图采集结果事件流。
  Stream<PlayPathCaptureEvent> get onScreenshotCaptured =>
      _captureController.stream;

  String _captureHotkeyName = 'F12';
  bool _hotkeyWasDown = false;
  bool _capturingShot = false;
  DateTime? _lastShotAt;

  /// 存档写入监视：游戏运行期间「往哪些目录写过文件」是识别存档目录的最强
  /// 证据，因此在会话的开始/结束处跟着启停（UI 从 SaveWriteWatcher.lastHits 读）。
  final SaveWriteWatcher saveWatcher = SaveWriteWatcher();

  int? _gameId;
  String _exeName = '';
  Set<String> _watchNames = {};
  Set<int> _lastMatchedPids = {};
  int _trackingEpoch = 0;
  TimeTrackingMode _mode = TimeTrackingMode.foreground;

  DateTime? _startedAt;
  int _countedSeconds = 0;
  int _misses = 0; // 连续未见游戏进程的次数
  bool _sawProcess = false;

  /// 是否正在跟踪。
  bool get tracking => _gameId != null;

  int? get trackedGameId => _gameId;

  /// 最近一次轮询命中该游戏的进程 PID 集合。
  Set<int> get lastMatchedPids => Set.unmodifiable(_lastMatchedPids);

  /// 运行时更新全局截图热键配置（设置页修改时立即生效）。
  void reloadCaptureHotkey(String hotkeyName) {
    _captureHotkeyName = hotkeyName;
    _hotkeyWasDown = false;
  }

  Future<void> _loadHotkeySetting() async {
    try {
      final saved = await AppServices.I.settings.getString(
        SettingsStore.kScreenshotHotkey,
        'F12',
      );
      _captureHotkeyName = saved;
    } catch (_) {}
  }

  /// 立即复核当前跟踪的游戏进程是否仍在后台存活。
  /// 若已捕获过进程但此时进程已全部退出，则立即结算结束跟踪并返回 false，
  /// 避免在 3 秒轮询宽限期内误拦用户的新启动操作。
  bool refreshAndCheckActive() {
    if (_gameId == null) return false;
    final procs = enumerateProcesses();
    final matched = <int>{};
    for (final p in procs) {
      if (_watchNames.contains(p.exeFile.toLowerCase())) {
        matched.add(p.pid);
      }
    }
    if (matched.isNotEmpty) {
      _lastMatchedPids = matched;
      _sawProcess = true;
      _misses = 0;
      return true;
    }
    _lastMatchedPids = {};
    if (_sawProcess) {
      stopTracking(saveSession: true);
      return false;
    }
    // 刚启动尚未在进程表出现时，10 秒内视为仍在启动中
    if (_startedAt != null &&
        DateTime.now().difference(_startedAt!).inSeconds <= 10) {
      return true;
    }
    stopTracking(saveSession: _countedSeconds > 0);
    return false;
  }

  /// 开始跟踪一个游戏（先启动 exe，再调用）。
  void startTracking({
    required int gameId,
    required String exePath,
    required String directory,
    required TimeTrackingMode mode,
  }) {
    stopTracking(saveSession: true);
    _trackingEpoch++;
    final epoch = _trackingEpoch;
    _gameId = gameId;
    _mode = mode;
    _startedAt = DateTime.now();
    _countedSeconds = 0;
    _misses = 0;
    _sawProcess = false;
    _lastMatchedPids = {};

    // 存档写入监视：以会话开始时间为界，只统计运行期间新写入的文件
    saveWatcher.start(gameId, gameDir: directory, since: _startedAt!);

    _exeName = exePath.split(Platform.pathSeparator).last.toLowerCase();
    _watchNames = {_exeName};
    // 异步、限深扫描游戏目录下的启动器/子可执行文件，避免启动瞬间同步遍历卡顿 UI 线程
    unawaited(_scanDirectoryExesAsync(directory, epoch));
    unawaited(_loadHotkeySetting());

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (Platform.isWindows) {
      _hotkeyWasDown = false;
      _hotkeyTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _pollCaptureHotkey(),
      );
    }
  }

  void _pollCaptureHotkey() {
    if (_gameId == null || _capturingShot) return;
    final vk = WindowCaptureService.virtualKeyForName(_captureHotkeyName);
    if (vk == null) {
      _hotkeyWasDown = false;
      return;
    }
    final isDown = WindowCaptureService.isVirtualKeyDown(vk);
    if (!isDown) {
      _hotkeyWasDown = false;
      return;
    }
    if (_hotkeyWasDown) return;
    _hotkeyWasDown = true;

    final now = DateTime.now();
    if (_lastShotAt != null && now.difference(_lastShotAt!).inMilliseconds < 450) {
      return;
    }

    // 仅在游戏本身或本应用处于前台时响应快捷键，避免误截其他软件操作中的 F12
    final fgPid = foregroundPid();
    final matched = _matchedPidsNow();
    if (fgPid != pid && !matched.contains(fgPid)) {
      return;
    }

    _lastShotAt = now;
    unawaited(captureCurrentGameWindow());
  }

  Set<int> _matchedPidsNow() {
    if (_lastMatchedPids.isNotEmpty) return _lastMatchedPids;
    if (_watchNames.isEmpty) return const {};
    final procs = enumerateProcesses();
    final found = <int>{};
    for (final proc in procs) {
      if (_watchNames.contains(proc.exeFile.toLowerCase())) {
        found.add(proc.pid);
      }
    }
    if (found.isNotEmpty) {
      _lastMatchedPids = found;
    }
    return found;
  }

  /// 截取当前运行中游戏的窗口画面并写入游玩路径。
  Future<PlayPathNode?> captureCurrentGameWindow({
    int? expectedGameId,
    String initialNote = '',
  }) async {
    final gameId = _gameId;
    if (gameId == null) return null;
    if (expectedGameId != null && expectedGameId != gameId) return null;
    if (_capturingShot) return null;

    _capturingShot = true;
    try {
      final pids = _matchedPidsNow();
      final outPath = p.join(
        AppServices.I.paths.playPath,
        '$gameId',
        '${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final saved = await WindowCaptureService.captureGameWindowToFile(
        candidatePids: pids,
        outputPath: outPath,
      );
      if (saved == null) {
        _captureController.add(PlayPathCaptureEvent(
          gameId: gameId,
          error: '未检测到可截图的游戏窗口（请确保游戏窗口未最小化）',
        ));
        return null;
      }
      final node = await AppServices.I.repo.addPlayPathNode(
        gameId: gameId,
        imagePath: saved,
        note: initialNote,
      );
      _captureController.add(PlayPathCaptureEvent(gameId: gameId, node: node));
      return node;
    } catch (e) {
      _captureController.add(PlayPathCaptureEvent(
        gameId: gameId,
        error: '游戏画面截图失败：$e',
      ));
      return null;
    } finally {
      _capturingShot = false;
    }
  }

  Future<void> _scanDirectoryExesAsync(String directory, int epoch) async {
    if (directory.trim().isEmpty) return;
    try {
      final root = Directory(directory);
      if (!await root.exists()) return;
      final queue = <({Directory dir, int depth})>[(dir: root, depth: 0)];
      const maxDepth = 2;
      while (queue.isNotEmpty && _watchNames.length < 200) {
        if (_trackingEpoch != epoch || _gameId == null) return;
        final current = queue.removeAt(0);
        await for (final entity in current.dir.list(followLinks: false)) {
          if (_trackingEpoch != epoch || _gameId == null) return;
          if (entity is File) {
            final lower = entity.path.toLowerCase();
            if (lower.endsWith('.exe')) {
              _watchNames.add(lower.split(Platform.pathSeparator).last);
              if (_watchNames.length >= 200) break;
            }
          } else if (entity is Directory && current.depth < maxDepth) {
            queue.add((dir: entity, depth: current.depth + 1));
          }
        }
      }
    } catch (_) {}
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
      _lastMatchedPids = matched;
      _sawProcess = true;
      _misses = 0;
      final counting = _mode == TimeTrackingMode.elapsed ||
          matched.contains(foregroundPid());
      if (counting) {
        _countedSeconds++;
      }
    } else {
      _lastMatchedPids = {};
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
    _trackingEpoch++;
    _timer?.cancel();
    _timer = null;
    _hotkeyTimer?.cancel();
    _hotkeyTimer = null;
    _hotkeyWasDown = false;
    // 监视器自己会取消定时器并补最后一轮扫描，命中记入 lastHits；
    // 这里不 await（stopTracking 是同步 API，且它绝不抛异常）
    unawaited(saveWatcher.stop());
    final game = _gameId;
    final start = _startedAt;
    _gameId = null;
    _startedAt = null;
    _watchNames = {};
    _lastMatchedPids = {};
    if (game == null || start == null) return;
    final end = DateTime.now();
    final elapsed = end.difference(start).inSeconds;
    final session =
        saveSession && _countedSeconds > 0
            ? GameSession(gameId: game, start: start, end: end, seconds: _countedSeconds)
            : null;
    _controller.add(PlaySessionEnd(
        session: session, elapsedSeconds: elapsed, gameId: game));
    _restoreFocusIfEnabled();
  }

  /// 游戏进程退出后根据设置自动唤醒主窗口并恢复置顶焦点。
  Future<void> _restoreFocusIfEnabled() async {
    try {
      final enabled = await AppServices.I.settings.getBool(
        SettingsStore.kFocusOnGameExit,
        def: true,
      );
      if (enabled) {
        final isMin = await windowManager.isMinimized();
        if (isMin) {
          await windowManager.restore();
        }
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (_) {}
  }

  /// 当前已计入秒数（UI 实时展示）。
  int get liveSeconds => _countedSeconds;

  void dispose() {
    stopTracking(saveSession: false);
    _controller.close();
    _captureController.close();
  }
}

class PlayPathCaptureEvent {
  final int gameId;
  final PlayPathNode? node;
  final String? error;
  const PlayPathCaptureEvent({
    required this.gameId,
    this.node,
    this.error,
  });
}

class PlaySessionEnd {
  final GameSession? session; // null = 会话无效（进程未出现/零时长）
  final int elapsedSeconds;
  final int gameId;
  const PlaySessionEnd(
      {required this.session, required this.elapsedSeconds, required this.gameId});
}
