/// Fluent 2 存档备份与恢复管理对话框。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../services/save_backup.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../widgets/save_dir_picker_dialog.dart';

/// 打开存档备份管理对话框，支持创建备份、目录识别、恢复（含运行检查与快照）及破坏性删除确认。
Future<void> showSaveBackupDialog(
  BuildContext context,
  WidgetRef ref,
  Game game, {
  SaveBackupService? backupService,
  Future<int> Function()? readKeepCount,
  Future<void> Function(Game game)? saveGamePath,
  bool Function(int? gameId)? isGameRunning,
  Future<String?> Function(BuildContext context, Game game)? pickSaveDir,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _SaveBackupDialog(
      ref: ref,
      game: game,
      backupService: backupService,
      readKeepCount: readKeepCount,
      saveGamePath: saveGamePath,
      isGameRunning: isGameRunning,
      pickSaveDir: pickSaveDir,
    ),
  );
}

class _SaveBackupDialog extends StatefulWidget {
  final WidgetRef ref;
  final Game game;
  final SaveBackupService? backupService;
  final Future<int> Function()? readKeepCount;
  final Future<void> Function(Game game)? saveGamePath;
  final bool Function(int? gameId)? isGameRunning;
  final Future<String?> Function(BuildContext context, Game game)? pickSaveDir;

  const _SaveBackupDialog({
    required this.ref,
    required this.game,
    this.backupService,
    this.readKeepCount,
    this.saveGamePath,
    this.isGameRunning,
    this.pickSaveDir,
  });

  @override
  State<_SaveBackupDialog> createState() => _SaveBackupDialogState();
}

class _SaveBackupDialogState extends State<_SaveBackupDialog> {
  late String _savePath = widget.game.savePath;
  List<SaveBackupEntry> _entries = const [];
  bool _busy = false;
  String _status = '';
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  SaveBackupService _store() =>
      widget.backupService ?? SaveBackupService(AppServices.I.paths.root);

  void _setStatus(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusError = error;
    });
  }

  void _reload() {
    if (!mounted) return;
    final gameId = widget.game.id;
    setState(() {
      _entries = gameId == null ? const [] : _store().list(gameId);
      if (_savePath.isEmpty && widget.game.directory.isNotEmpty) {
        final guess = SaveScanner.detectSaveDir(
          widget.game.directory,
          widget.game.displayName,
        );
        if (guess.isNotEmpty) {
          _savePath = guess;
          _status = '已自动识别存档目录（点击「保存目录」以记住）';
          _statusError = false;
        }
      }
    });
  }

  Future<void> _saveDirToGame() async {
    widget.game.savePath = _savePath;
    if (widget.saveGamePath != null) {
      await widget.saveGamePath!(widget.game);
    } else {
      await AppServices.I.repo.updateGame(widget.game);
    }
    bumpLibrary(widget.ref);
    if (!mounted) return;
    _setStatus('存档目录已保存');
    showNotice('存档目录已保存');
  }

  Future<void> _pickCandidate() async {
    final picker = widget.pickSaveDir ?? showSaveDirPickerDialog;
    final picked = await picker(context, widget.game);
    if (picked == null || picked.trim().isEmpty || !mounted) return;
    setState(() => _savePath = picked.trim());
    await _saveDirToGame();
  }

  Future<int> _keepLimit() async {
    if (widget.readKeepCount != null) {
      return widget.readKeepCount!();
    }
    try {
      return await AppServices.I.settings
          .getInt(SettingsStore.kSaveBackupKeep, 10);
    } catch (_) {
      return 10;
    }
  }

  bool _running() {
    if (widget.isGameRunning != null) {
      return widget.isGameRunning!(widget.game.id);
    }
    try {
      return widget.game.id != null &&
          AppServices.I.tracker.trackedGameId == widget.game.id;
    } catch (_) {
      return false;
    }
  }

  Future<void> _createBackup() async {
    if (_busy) return;
    final gameId = widget.game.id;
    if (gameId == null) {
      _setStatus('作品尚未入库，无法创建备份', error: true);
      showNotice('作品尚未入库，无法创建备份', error: true);
      return;
    }
    if (_savePath.isEmpty || !Directory(_savePath).existsSync()) {
      _setStatus('请先指定有效的存档目录', error: true);
      showNotice('请先指定有效的存档目录', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在备份…';
      _statusError = false;
    });
    try {
      final keep = await _keepLimit();
      if (!mounted) return;
      final name = await _store().backup(gameId, _savePath, keep: keep);
      if (!mounted) return;
      _reload();
      _setStatus('备份完成：$name');
      showNotice('存档已备份：$name');
    } catch (e) {
      if (!mounted) return;
      _setStatus('备份失败：$e', error: true);
      showNotice('备份失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(SaveBackupEntry e) async {
    if (_busy) return;
    final gameId = widget.game.id;
    if (gameId == null) return;
    if (_running()) {
      showNotice('该游戏正在运行中，建议退出后再恢复存档', error: true);
      return;
    }
    final ok = await showFluentConfirmDialog(
      context,
      title: '恢复存档',
      content: '将用备份「${e.name}」覆盖当前存档目录：\n$_savePath\n\n'
          '恢复前会自动创建一份快照。继续吗？',
      confirmLabel: '恢复',
    );
    if (!ok || !mounted) return;
    if (_running()) {
      showNotice('该游戏正在运行中，建议退出后再恢复存档', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在恢复…';
      _statusError = false;
    });
    try {
      final (done, total) = await _store().restore(gameId, e.name);
      if (!mounted) return;
      _reload();
      _setStatus('已恢复 $done / $total 个文件');
      showNotice('存档恢复完成（$done/$total）');
    } catch (err) {
      if (!mounted) return;
      _setStatus('恢复失败：$err', error: true);
      showNotice('恢复失败：$err', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SaveBackupEntry e) async {
    if (_busy) return;
    final gameId = widget.game.id;
    if (gameId == null) return;
    final ok = await showFluentConfirmDialog(
      context,
      title: '删除备份',
      content: '确定要永久删除备份「${e.name}」吗？该操作不可撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _status = '正在删除…';
      _statusError = false;
    });
    try {
      _store().remove(gameId, e.name);
      if (!mounted) return;
      _reload();
      _setStatus('已删除备份：${e.name}');
      showNotice('已删除备份：${e.name}');
    } catch (err) {
      if (!mounted) return;
      _setStatus('删除失败：$err', error: true);
      showNotice('删除失败：$err', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final dirMissing = _savePath.isEmpty || !Directory(_savePath).existsSync();
    const errorRed = Color(0xFFD13438);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 580),
      title: Row(
        children: [
          const Icon(FluentIcons.archive_24_regular, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '存档备份 · ${widget.game.displayName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 590,
        height: 410,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FluentSurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.folder_20_regular,
                    size: 18,
                    color: dirMissing ? errorRed : accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _savePath.isEmpty ? '未指定存档目录' : _savePath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption?.copyWith(
                        color: dirMissing ? errorRed : theme.inactiveColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: _busy ? null : _pickCandidate,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.wand_20_regular, size: 15),
                        SizedBox(width: 5),
                        Text('识别候选…'),
                      ],
                    ),
                  ),
                  if (_savePath.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Button(
                      onPressed: _busy ? null : _saveDirToGame,
                      child: const Text('保存目录'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: _busy ? null : _createBackup,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.save_20_regular, size: 16),
                      SizedBox(width: 6),
                      Text('立即备份'),
                    ],
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: ProgressRing(strokeWidth: 2.5),
                  ),
                ],
                if (_status.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption?.copyWith(
                        color: _statusError ? errorRed : theme.inactiveColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Expanded(
              child: _entries.isEmpty
                  ? const FluentEmptyState(
                      icon: FluentIcons.archive_24_regular,
                      title: '暂无备份',
                      message: '点击「立即备份」创建第一份存档快照',
                    )
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final e = _entries[i];
                        return FluentSurfaceCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                e.auto
                                    ? FluentIcons.clock_20_regular
                                    : FluentIcons.archive_24_regular,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            e.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.typography.bodyStrong,
                                          ),
                                        ),
                                        if (e.auto) ...[
                                          const SizedBox(width: 8),
                                          FluentBadge(
                                            text: '自动',
                                            foreground: accent,
                                            background: accent.withValues(
                                              alpha: isDark ? 0.2 : 0.12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${fmtDateTime(e.time)} · ${e.fileCount} 个文件 · ${e.displaySize}',
                                      style: theme.typography.caption?.copyWith(
                                        color: theme.inactiveColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Button(
                                onPressed: _busy ? null : () => _restore(e),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(FluentIcons.history_20_regular, size: 15),
                                    SizedBox(width: 4),
                                    Text('恢复'),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Button(
                                onPressed: _busy ? null : () => _delete(e),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(FluentIcons.delete_20_regular, size: 15),
                                    SizedBox(width: 4),
                                    Text('删除'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
