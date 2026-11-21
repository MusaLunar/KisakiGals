import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:system_theme/system_theme.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_services.dart';
import 'core/constants.dart';
import 'core/utils.dart';
import 'data/models.dart';
import 'data/settings_store.dart';
import 'providers.dart';
import 'services/game_launch_service.dart';
import 'ui/fluent/fluent_notices.dart';
import 'ui/fluent/fluent_theme.dart';
import 'ui/library/game_actions.dart' show tryAppServices;
import 'ui/shell/app_shell.dart';
import 'ui/shell/tabs.dart' show Tabs;

const MethodChannel _trayPopupChannel = MethodChannel('kisaki/tray_menu');
const MethodChannel _windowEnvChannel = MethodChannel('kisaki/window_env');

Future<WindowBackdropCaps> _probeWindowBackdropCaps() async {
  if (!Platform.isWindows) return const WindowBackdropCaps.unsupported();
  try {
    final raw = await _windowEnvChannel
        .invokeMethod<Map<Object?, Object?>>('getBackdropCaps');
    return WindowBackdropCaps.fromMap(raw);
  } catch (_) {
    return const WindowBackdropCaps.unsupported();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 调优图片缓存上限（配合 CoverImage 按显示像素比降采样解码，减少低配设备内存占用）
  PaintingBinding.instance.imageCache.maximumSize = 180;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 96 << 20; // 96 MB

  SystemTheme.fallbackColor = kDefaultWin11Azure;
  await SystemTheme.accentColor.load();

  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  final caps = await _probeWindowBackdropCaps();
  final initialDark =
      PlatformDispatcher.instance.platformBrightness == Brightness.dark;
  final initialEffective =
      resolveEffectiveBackdrop(BackdropEffectPref.mica, caps);
  await syncWindowBackdrop(
    effect: initialEffective,
    dark: initialDark,
    caps: caps,
  );

  final windowOptions = WindowOptions(
    title: 'KisakiGals',
    minimumSize: const Size(1080, 680),
    size: const Size(1280, 800),
    center: true,
    backgroundColor: initialEffective == BackdropEffectPref.solid
        ? neutralWindowBackground(initialDark)
        : Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await AppServices.init();

  runApp(
    ProviderScope(
      overrides: [
        windowBackdropCapsProvider.overrideWith((ref) => caps),
      ],
      child: const KisakiApp(),
    ),
  );
}

/// F10 截图边界（全局，覆盖所有路由）。
final GlobalKey shotBoundaryKey = GlobalKey();

bool _trayReady = false;

/// 构建自绘「誌面」托盘弹出面板的数据载荷（不使用 Windows 原生 HMENU）。
Future<Map<String, dynamic>> _buildTrayPopupPayload({
  String? runningGameTitle,
  bool? darkOverride,
  int? accentArgb,
}) async {
  final services = tryAppServices();
  if (services == null) {
    return {
      'dark': darkOverride ?? false,
      'accentArgb': accentArgb ??
          resolveAccentBaseColor(
            AccentPreset.system,
            SystemTheme.accentColor.accent,
          ).toARGB32(),
      'version': AppInfo.version,
      'runningTitle': runningGameTitle?.trim() ?? '',
      'recentGames': const <Map<String, dynamic>>[],
    };
  }

  final tracker = services.tracker;
  final activeId =
      tracker.refreshAndCheckActive() ? tracker.trackedGameId : null;
  var activeTitle = runningGameTitle?.trim() ?? '';
  if (activeTitle.isEmpty && activeId != null) {
    final activeGame = await services.repo.getGame(activeId);
    activeTitle = activeGame?.displayName ?? '';
  }

  // 查询最近游玩的 2 部作品
  List<Game> recentGames = const [];
  try {
    recentGames = await services.repo.recentPlayedGames(limit: 2);
  } catch (_) {}

  bool dark = darkOverride ?? false;
  if (darkOverride == null) {
    final mode =
        await services.settings.getString(SettingsStore.kThemeMode, 'system');
    if (mode == 'dark') {
      dark = true;
    } else if (mode == 'light') {
      dark = false;
    } else {
      dark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
  }

  final nsfwMode =
      await services.settings.getString(SettingsStore.kNsfwMode, 'blur');

  final recentPayload = <Map<String, dynamic>>[];
  for (final g in recentGames) {
    final gid = g.id;
    if (gid == null) continue;
    final isRunning = activeId == gid;
    var coverPath = (g.nsfw && nsfwMode != 'show') || g.coverPath.isEmpty
        ? ''
        : services.paths.resolveStored(g.coverPath);
    if (coverPath.isNotEmpty && !File(coverPath).existsSync()) {
      coverPath = '';
    }
    final subtitle = isRunning
        ? '正在游玩中'
        : (g.totalSeconds > 0
            ? '累计 ${fmtDuration(g.totalSeconds)}'
            : '点击即刻启动');
    recentPayload.add({
      'id': gid,
      'title': g.displayName,
      'subtitle': subtitle,
      'coverPath': coverPath,
      'running': isRunning,
    });
  }

  return {
    'dark': dark,
    'accentArgb': accentArgb ??
        resolveAccentBaseColor(
          AccentPreset.system,
          SystemTheme.accentColor.accent,
        ).toARGB32(),
    'version': AppInfo.version,
    'runningTitle': activeTitle,
    'recentGames': recentPayload,
  };
}

/// 同步托盘悬停提示（右键菜单由自绘「誌面」顶层弹出窗口渲染，不再调用 Windows 原生菜单）。
Future<void> updateTrayMenu({String? runningGameTitle}) async {
  if (!_trayReady) return;
  final services = tryAppServices();
  if (services == null) return;

  final tracker = services.tracker;
  final activeId =
      tracker.refreshAndCheckActive() ? tracker.trackedGameId : null;
  var activeTitle = runningGameTitle?.trim() ?? '';
  if (activeTitle.isEmpty && activeId != null) {
    final activeGame = await services.repo.getGame(activeId);
    activeTitle = activeGame?.displayName ?? '';
  }

  final tip = activeTitle.isNotEmpty
      ? 'KisakiGals · 正在游玩 $activeTitle'
      : 'KisakiGals v${AppInfo.version}';
  try {
    await trayManager.setToolTip(tip);
  } catch (_) {}
}

/// 创建托盘图标。
Future<void> _setupTray() async {
  if (_trayReady) return;
  final services = tryAppServices();
  if (services == null) return;
  // 把 ico 从资源包复制到数据目录，保证 release 下路径可解析
  final icoPath = '${services.paths.root}/tray.ico';
  try {
    final data = await rootBundle.load('assets/logo/kisaki.ico');
    await File(icoPath).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  } catch (_) {
    return;
  }
  await trayManager.setIcon(icoPath);
  await trayManager.setToolTip('KisakiGals v${AppInfo.version}');
  _trayReady = true;
  await updateTrayMenu();
}

/// 应用「关闭行为」设置：exit=直接退出；tray=隐藏到托盘。
/// 托盘图标**始终存在**（与关闭行为无关），关闭行为只决定点 × 的动作。
/// 设置页切换后调用以实时生效。
Future<void> applyCloseBehavior() async {
  final services = tryAppServices();
  if (services == null) return;
  final behavior =
      await services.settings.getString(SettingsStore.kCloseBehavior, 'exit');
  await windowManager.setPreventClose(behavior == 'tray');
  await _setupTray();
}

/// 最小化到托盘（隐藏窗口，托盘图标保留）。
Future<void> minimizeToTray() async {
  await _setupTray();
  await windowManager.hide();
}

/// 应用根：Fluent 2 主题 / 系统强调色 / DWM Backdrop + 外壳 + 托盘/关闭行为。
class KisakiApp extends ConsumerStatefulWidget {
  final bool enableDesktopHooks;

  const KisakiApp({super.key, this.enableDesktopHooks = true});

  @override
  ConsumerState<KisakiApp> createState() => _KisakiAppState();
}

class _KisakiAppState extends ConsumerState<KisakiApp>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  StreamSubscription<SystemAccentColor>? _accentSub;
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.enableDesktopHooks) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _trayPopupChannel.setMethodCallHandler((call) async {
        if (call.method == 'onTrayAction') {
          final action = (call.arguments ?? '').toString();
          if (action.isNotEmpty) {
            await _handleTrayAction(action);
          }
        }
      });
      _accentSub = SystemTheme.onChange.listen((event) {
        if (mounted) {
          ref.read(systemAccentColorProvider.notifier).state = event.accent;
        }
      });

      Future.microtask(() async {
        if (!mounted) return;
        final services = tryAppServices();
        if (services == null) return;
        final s = services.settings;
        ref.read(performanceModeProvider.notifier).state =
            await s.getBool(SettingsStore.kPerformanceMode, def: false);
        ref.read(nsfwModeProvider.notifier).state =
            await s.getString(SettingsStore.kNsfwMode, 'blur');
        ref.read(nsfwBlurProvider.notifier).state =
            await s.getDouble('nsfw.blur', 12);
        ref.read(detailBgBlurProvider.notifier).state =
            await s.getDouble('detail.bg_blur', 14);
        ref.read(libraryLayoutProvider.notifier).state =
            await s.getString(SettingsStore.kLibraryLayout, 'grid');
        ref.read(discoverLayoutProvider.notifier).state =
            await s.getString(SettingsStore.kDiscoverLayout, 'grid');
        await applyCloseBehavior();
        if (mounted) {
          _syncBackdrop();
        }
      });
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (widget.enableDesktopHooks) {
      _syncBackdrop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accentSub?.cancel();
    if (widget.enableDesktopHooks) {
      _trayPopupChannel.setMethodCallHandler(null);
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  T _watchOptional<T>(ProviderListenable<T> provider, T fallback) {
    try {
      return ref.watch(provider);
    } catch (_) {
      return fallback;
    }
  }

  T _readOptional<T>(ProviderListenable<T> provider, T fallback) {
    try {
      return ref.read(provider);
    } catch (_) {
      return fallback;
    }
  }

  bool _isDarkForPref(ThemeModePref pref) => switch (pref) {
        ThemeModePref.dark => true,
        ThemeModePref.light => false,
        ThemeModePref.system =>
          PlatformDispatcher.instance.platformBrightness == Brightness.dark,
      };

  void _syncBackdrop() {
    if (!widget.enableDesktopHooks) return;
    final pref = _readOptional(themeProvider, ThemeModePref.system);
    final perfMode = _readOptional(performanceModeProvider, false);
    final effect = perfMode
        ? BackdropEffectPref.solid
        : _readOptional(backdropEffectProvider, BackdropEffectPref.mica);
    final caps = _readOptional<WindowBackdropCaps?>(
      windowBackdropCapsProvider,
      null,
    );
    unawaited(
      syncWindowBackdrop(
        effect: effect,
        dark: _isDarkForPref(pref),
        caps: caps,
      ),
    );
  }

  @override
  void onWindowClose() async {
    final services = tryAppServices();
    final behavior = services == null
        ? 'exit'
        : await services.settings
            .getString(SettingsStore.kCloseBehavior, 'exit');
    if (behavior == 'tray') {
      await minimizeToTray();
    } else {
      // 退出前收尾：把进行中的游玩会话落库（否则这段时长永久丢失）、
      // 关闭数据库（触发 WAL checkpoint）与网络客户端
      await _shutdown();
      await windowManager.destroy();
    }
  }

  /// 应用退出前的资源收尾（幂等）：
  /// 1) 按设置做一次「退出备份」（受最小间隔约束）
  /// 2) 挂起定时调度器并等待运行中的备份结束，避免写到一半被杀
  /// 3) 收尾服务（会话落库、关库触发 WAL checkpoint）
  Future<void> _shutdown() async {
    try {
      await _trayPopupChannel.invokeMethod('hidePopup');
    } catch (_) {}
    final services = tryAppServices();
    if (services == null) return;
    try {
      final scheduler = services.autoBackup;
      await scheduler.backupOnExitIfDue();
      scheduler.suspend();
      await scheduler.waitForRunning();
    } catch (_) {}
    try {
      await services.dispose();
    } catch (_) {}
  }

  Future<void> _restoreAndFocusWindow() async {
    final isMin = await windowManager.isMinimized();
    if (isMin) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() async {
    try {
      await _trayPopupChannel.invokeMethod('hidePopup');
    } catch (_) {}
    await _restoreAndFocusWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    // 弹出自绘「誌面」托盘菜单（含 2 部最近游玩游戏封面与一键启动）
    final pref = _readOptional(themeProvider, ThemeModePref.system);
    final dark = _isDarkForPref(pref);
    final preset = _readOptional(accentPresetProvider, AccentPreset.system);
    final sysAccent = ref.read(systemAccentColorProvider);
    final accent = resolveAccentBaseColor(preset, sysAccent);

    final payload = await _buildTrayPopupPayload(
      darkOverride: dark,
      accentArgb: accent.toARGB32(),
    );
    try {
      await _trayPopupChannel.invokeMethod('showPopup', payload);
    } catch (_) {}
  }

  Future<void> _handleTrayAction(String key) async {
    final services = tryAppServices();
    if (key.startsWith('launch_game_')) {
      final gameId = int.tryParse(key.substring('launch_game_'.length));
      if (gameId == null || services == null) return;
      final game = await services.repo.getGame(gameId);
      if (game == null) return;
      if (game.exePath.isEmpty || !File(game.exePath).existsSync()) {
        await _restoreAndFocusWindow();
        showNotice(
          '未找到「${game.displayName}」的可执行文件，请先在游戏详情中配置路径',
          error: true,
        );
        return;
      }
      await GameLaunchService.launchAndTrack(game, ref);
      await updateTrayMenu(runningGameTitle: game.displayName);
      return;
    }

    switch (key) {
      case 'show':
        await _restoreAndFocusWindow();
      case 'nav_library':
        await _restoreAndFocusWindow();
        ref.read(tabIndexProvider.notifier).state = Tabs.library;
      case 'nav_discover':
        await _restoreAndFocusWindow();
        ref.read(tabIndexProvider.notifier).state = Tabs.discover;
      case 'nav_stats':
        await _restoreAndFocusWindow();
        ref.read(tabIndexProvider.notifier).state = Tabs.stats;
      case 'nav_settings':
        await _restoreAndFocusWindow();
        ref.read(tabIndexProvider.notifier).state = Tabs.settings;
      case 'stop_tracking':
        services?.tracker.stopTracking(saveSession: true);
        ref.read(trackingGameProvider.notifier).state = null;
        await updateTrayMenu();
      case 'quit':
        if (_quitting) return;
        _quitting = true;
        try {
          await _shutdown().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
        } catch (_) {}
        try {
          await trayManager.destroy().timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
        } catch (_) {}
        try {
          await windowManager.setPreventClose(false);
        } catch (_) {}
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableDesktopHooks) {
      // 监听运行中的游戏与库变更，动态刷新托盘状态提示
      ref.listen<int?>(trackingGameProvider, (prev, next) async {
        final services = tryAppServices();
        if (next != null && services != null) {
          final game = await services.repo.getGame(next);
          await updateTrayMenu(runningGameTitle: game?.displayName ?? '');
        } else {
          await updateTrayMenu();
        }
      });
      ref.listen<int>(libraryVersionProvider, (prev, next) async {
        await updateTrayMenu();
      });
      ref.listen<ThemeModePref>(themeProvider, (prev, next) {
        _syncBackdrop();
      });
      ref.listen<BackdropEffectPref>(backdropEffectProvider, (prev, next) {
        _syncBackdrop();
      });
      ref.listen<bool>(performanceModeProvider, (prev, next) {
        _syncBackdrop();
      });
    }

    final pref = _watchOptional(themeProvider, ThemeModePref.system);
    final preset = _watchOptional(accentPresetProvider, AccentPreset.system);
    final backdrop = _watchOptional(
      backdropEffectProvider,
      BackdropEffectPref.mica,
    );
    final perfMode = _watchOptional(performanceModeProvider, false);
    final caps = _watchOptional<WindowBackdropCaps?>(
      windowBackdropCapsProvider,
      null,
    );
    final effectiveBackdrop = perfMode
        ? BackdropEffectPref.solid
        : effectiveBackdropFor(backdrop, caps);
    final systemAccent = ref.watch(systemAccentColorProvider);

    return FluentApp(
      title: 'KisakiGals',
      debugShowCheckedModeBanner: false,
      theme: buildFluentTheme(
        brightness: Brightness.light,
        preset: preset,
        systemAccent: systemAccent,
        backdrop: effectiveBackdrop,
      ),
      darkTheme: buildFluentTheme(
        brightness: Brightness.dark,
        preset: preset,
        systemAccent: systemAccent,
        backdrop: effectiveBackdrop,
      ),
      themeMode: switch (pref) {
        ThemeModePref.system => ThemeMode.system,
        ThemeModePref.light => ThemeMode.light,
        ThemeModePref.dark => ThemeMode.dark,
      },
      localizationsDelegates: const [
        FluentLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      supportedLocales: FluentLocalizations.supportedLocales,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final content = Stack(
          children: [
            RepaintBoundary(
              key: shotBoundaryKey,
              child: child ?? const SizedBox.shrink(),
            ),
            const FluentNoticeHost(),
          ],
        );
        if (!perfMode || mq.disableAnimations) return content;
        return MediaQuery(
          data: mq.copyWith(disableAnimations: true),
          child: content,
        );
      },
      home: AppShell(enableWindowHooks: widget.enableDesktopHooks),
    );
  }
}
