/// 统一的游戏启动流程：校验 → （可选）LE 转区启动 → 时长监控 → 启动后动作。
///
/// 参考 ChronoTide `GameLaunchService`：把原先散落在主页与详情页的重复逻辑
/// 收敛到一处，并保证启动失败时给出可见反馈（旧实现失败后仍显示「游戏中」）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show minimizeToTray;

import '../app_services.dart';
import '../core/constants.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../providers.dart';
import '../ui/widgets/notifications.dart';
import 'game_launcher.dart';

class GameLaunchService {
  /// 启动游戏并开始计时。[ref] 用于刷新「游戏中」状态与库版本。
  static Future<void> launchAndTrack(Game game, WidgetRef ref) async {
    if (game.id == null) return;
    if (game.exePath.isEmpty || !File(game.exePath).existsSync()) {
      showNotice('未找到游戏可执行文件，请先在「编辑信息」中设置', error: true);
      return;
    }

    final settings = AppServices.I.settings;
    final mode = await settings.trackingMode();

    // 转区启动：需要 Locale Emulator 路径；缺失则降级为普通启动并提示
    var lePath = '';
    if (game.useLocaleEmulator) {
      lePath = await settings.getString(SettingsStore.kLePath, '');
      if (lePath.isEmpty || !File(lePath).existsSync()) {
        lePath = '';
        showNotice('未配置 Locale Emulator 路径，本次按普通方式启动（可能显示乱码）',
            error: true);
      }
    }

    final result = await GameLauncher.launch(
      game.exePath,
      directory: game.directory,
      localeEmulatorPath: lePath,
    );
    if (!result.ok) {
      showNotice(result.message.isEmpty ? '启动失败' : result.message, error: true);
      return;
    }
    if (result.message.isNotEmpty) showNotice(result.message);

    AppServices.I.tracker.startTracking(
      gameId: game.id!,
      exePath: game.exePath,
      directory: game.directory,
      mode: mode,
    );
    ref.read(trackingGameProvider.notifier).state = game.id!;
    await settings.setString('runtime.last_game', '${game.id}');

    // 启动后动作：最小化主窗口
    final after = await settings.getString(SettingsStore.kAfterLaunch, 'none');
    if (after == 'minimize') {
      // 启动游戏后最小化到托盘（而不是任务栏），避免挡在游戏前面
      await minimizeToTray();
    }

    // 想玩 → 在玩
    if (game.playStatus == PlayStatus.wish) {
      game.playStatus = PlayStatus.playing;
      await AppServices.I.repo.updateGame(game);
    }
    ref.read(libraryVersionProvider.notifier).state++;
  }
}
