/// 存档备份对话框：创建备份、查看备份列表、恢复、删除。
///
/// 存档目录来自「编辑信息 → 启动与存档」中的设置；支持自动识别。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/models.dart';
import '../../services/save_backup.dart';
import '../theme.dart';
import 'notifications.dart';

class SaveBackupDialog extends StatefulWidget {
  final Game game;
  const SaveBackupDialog({super.key, required this.game});

  static Future<void> show(BuildContext context, Game game) => showDialog(
        context: context,
        builder: (_) => SaveBackupDialog(game: game),
      );

  @override
  State<SaveBackupDialog> createState() => _SaveBackupDialogState();
}

class _SaveBackupDialogState extends State<SaveBackupDialog> {
  late String _savePath = widget.game.savePath;
  List<SaveBackupEntry> _entries = const [];
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  SaveBackupService _store() =>
      SaveBackupService(AppServices.I.paths.root);

  void _reload() {
    setState(() {
      _entries = _store().list(widget.game.id!);
      if (_savePath.isEmpty) {
        final guess = SaveScanner.detectSaveDir(
            widget.game.directory, widget.game.displayName);
        if (guess.isNotEmpty) {
          _savePath = guess;
          _status = '已自动识别存档目录（点击「保存目录」以记住）';
        }
      }
    });
  }

  Future<void> _saveDirToGame() async {
    final g = widget.game;
    g.savePath = _savePath;
    await AppServices.I.repo.updateGame(g);
    if (mounted) setState(() => _status = '存档目录已保存');
  }

  Future<void> _createBackup() async {
    if (_savePath.isEmpty || !Directory(_savePath).existsSync()) {
      setState(() => _status = '请先指定有效的存档目录');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在备份…';
    });
    try {
      final name = await _store().backup(widget.game.id!, _savePath);
      _reload();
      setState(() => _status = '备份完成：$name');
      showNotice('存档已备份：$name');
    } catch (e) {
      setState(() => _status = '备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(SaveBackupEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复存档'),
        content: Text('将用备份「${e.name}」覆盖当前存档目录：\n$_savePath\n\n'
            '恢复前会自动创建一份快照。继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true) return;
    if (AppServices.I.tracker.trackedGameId == widget.game.id) {
      showNotice('该游戏正在运行中，建议退出后再恢复存档', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final (done, total) =
          await _store().restore(widget.game.id!, e.name);
      _reload();
      setState(() => _status = '已恢复 $done / $total 个文件');
      showNotice('存档恢复完成（$done/$total）');
    } catch (err) {
      setState(() => _status = '恢复失败：$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Text('存档备份 · ${widget.game.displayName}'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(_savePath.isEmpty ? '未指定存档目录' : _savePath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: _savePath.isEmpty ? null : _saveDirToGame,
                  child: const Text('保存目录')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _createBackup,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('立即备份'),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ]),
            const Divider(height: 24),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text('暂无备份',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, i) {
                        final e = _entries[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              e.auto
                                  ? Icons.schedule_rounded
                                  : Icons.inventory_2_rounded,
                              size: 20,
                              color: e.auto
                                  ? KisakiColors.lavender
                                  : KisakiColors.pink),
                          title: Text(e.name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              '${e.fileCount} 个文件 · ${e.displaySize}'
                              '${e.auto ? ' · 自动' : ''}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '恢复此备份',
                                icon: const Icon(Icons.restore_rounded, size: 18),
                                onPressed: _busy ? null : () => _restore(e),
                              ),
                              IconButton(
                                tooltip: '删除备份',
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                onPressed: _busy
                                    ? null
                                    : () {
                                        _store().remove(
                                            widget.game.id!, e.name);
                                        _reload();
                                      },
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭')),
      ],
      backgroundColor: dark ? KisakiColors.nightCard : null,
    );
  }
}
