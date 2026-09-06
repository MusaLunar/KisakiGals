import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_services.dart';
import 'providers.dart';
import 'data/settings_store.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

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

/// 应用根：主题切换 + 外壳。
class KisakiApp extends ConsumerWidget {
  const KisakiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      builder: (context, child) => RepaintBoundary(
        key: shotBoundaryKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const ShellPage(),
    );
  }
}
