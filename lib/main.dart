import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_services.dart';
import 'data/settings_store.dart';
import 'providers.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  // Windows 11 Mica 效果；失败静默回退纯色背景
  try {
    await acrylic.Window.setEffect(effect: acrylic.WindowEffect.mica);
  } catch (_) {}

  const windowOptions = WindowOptions(
    title: 'KisakiGals',
    minimumSize: Size(1080, 680),
    size: Size(1280, 800),
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await AppServices.init();

  runApp(const ProviderScope(child: KisakiApp()));
}

/// F10 截图边界（全局，覆盖所有路由）。
final GlobalKey shotBoundaryKey = GlobalKey();

bool _trayReady = false;

/// 创建托盘图标与菜单。
Future<void> _setupTray() async {
  if (_trayReady) return;
  // 把 ico 从资源包复制到数据目录，保证 release 下路径可解析
  final icoPath =
      '${AppServices.I.paths.root}/tray.ico';
  try {
    final data = await rootBundle.load('assets/logo/kisaki.ico');
    await File(icoPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true);
  } catch (_) {
    return;
  }
  await trayManager.setIcon(icoPath);
  await trayManager.setToolTip('KisakiGals');
  await trayManager.setContextMenu(Menu(items: [
    MenuItem(key: 'show', label: '打开 KisakiGals'),
    MenuItem.separator(),
    MenuItem(key: 'quit', label: '退出'),
  ]));
  _trayReady = true;
}

/// 应用「关闭行为」设置：exit=直接退出；tray=隐藏到托盘。
/// 托盘图标**始终存在**（与关闭行为无关），关闭行为只决定点 × 的动作。
/// 设置页切换后调用以实时生效。
Future<void> applyCloseBehavior() async {
  final behavior = await AppServices.I.settings
      .getString(SettingsStore.kCloseBehavior, 'exit');
  await windowManager.setPreventClose(behavior == 'tray');
  await _setupTray();
}

/// 最小化到托盘（隐藏窗口，托盘图标保留）。
Future<void> minimizeToTray() async {
  await _setupTray();
  await windowManager.hide();
}

/// 应用根：主题切换 + 外壳 + 托盘/关闭行为。
class KisakiApp extends ConsumerStatefulWidget {
  const KisakiApp({super.key});

  @override
  ConsumerState<KisakiApp> createState() => _KisakiAppState();
}

class _KisakiAppState extends ConsumerState<KisakiApp>
    with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    Future.microtask(() async {
      final s = AppServices.I.settings;
      ref.read(nsfwModeProvider.notifier).state =
          await s.getString(SettingsStore.kNsfwMode, 'blur');
      ref.read(nsfwBlurProvider.notifier).state =
          await s.getDouble('nsfw.blur', 12);
      ref.read(detailBgBlurProvider.notifier).state =
          await s.getDouble('detail.bg_blur', 14);
      await applyCloseBehavior();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final behavior = await AppServices.I.settings
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

  /// 应用退出前的资源收尾（幂等）。
  Future<void> _shutdown() async {
    try {
      await AppServices.I.dispose();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'quit':
        await _shutdown();
        await trayManager.destroy();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pref = ref.watch(themeProvider);
    return MaterialApp(
      title: 'KisakiGals',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: switch (pref) {
        ThemeModePref.system => ThemeMode.system,
        ThemeModePref.light => ThemeMode.light,
        ThemeModePref.dark => ThemeMode.dark,
      },
      builder: (context, child) => Stack(
        children: [
          RepaintBoundary(
            key: shotBoundaryKey,
            child: child ?? const SizedBox.shrink(),
          ),
          const NoticeOverlay(child: SizedBox.shrink()),
        ],
      ),
      home: const ShellPage(),
    );
  }
}
