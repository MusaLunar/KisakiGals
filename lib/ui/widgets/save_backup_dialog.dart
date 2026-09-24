/// 存档备份对话框：创建备份、查看备份列表、恢复、删除。
///
/// 存档目录来自「编辑信息 → 启动与存档」中的设置；支持自动识别。
/// 视觉统一走基础层：外层用 `showKisakiDialog`（250ms 缩放淡入 + 统一遮罩）、
/// 备份行用 KRow + KIconAction、按钮用 KPill、空态用 KEmpty、
/// 忙碌指示用 KLoading；间距 / 字号 / 颜色全部取 Gap / Type / colorScheme。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/models.dart';
import '../../services/save_backup.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';
import 'notifications.dart';

class SaveBackupDialog extends StatefulWidget {
  final Game game;
  const SaveBackupDialog({super.key, required this.game});

  /// 打开对话框（统一走 showKisakiDialog，与图片选择器等弹窗同一套进场动效）。
  static Future<void> show(BuildContext context, Game game) async {
    await showKisakiDialog<void>(
      context: context,
      builder: (_) => SaveBackupDialog(game: game),
    );
  }

  @override
  State<SaveBackupDialog> createState() => _SaveBackupDialogState();
}

class _SaveBackupDialogState extends State<SaveBackupDialog> {
  late String _savePath = widget.game.savePath;
  List<SaveBackupEntry> _entries = const [];
  bool _busy = false;
  String _status = '';

  /// 状态行是否为错误（错误走语义色，其余为次要信息色）
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  SaveBackupService _store() =>
      SaveBackupService(AppServices.I.paths.root);

  /// 统一的写入点：状态文案与语义色一起更新。
  void _setStatus(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusError = error;
    });
  }

  void _reload() {
    // 备份/恢复是 async：期间对话框可能已被关闭，这里统一兜住
    if (!mounted) return;
    setState(() {
      _entries = _store().list(widget.game.id!);
      if (_savePath.isEmpty) {
        final guess = SaveScanner.detectSaveDir(
            widget.game.directory, widget.game.displayName);
        if (guess.isNotEmpty) {
          _savePath = guess;
          _status = '已自动识别存档目录（点击「保存目录」以记住）';
          _statusError = false;
        }
      }
    });
  }

  Future<void> _saveDirToGame() async {
    final g = widget.game;
    g.savePath = _savePath;
    await AppServices.I.repo.updateGame(g);
    if (mounted) _setStatus('存档目录已保存');
  }

  Future<void> _createBackup() async {
    if (_savePath.isEmpty || !Directory(_savePath).existsSync()) {
      _setStatus('请先指定有效的存档目录', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在备份…';
      _statusError = false;
    });
    try {
      final name = await _store().backup(widget.game.id!, _savePath);
      _reload();
      _setStatus('备份完成：$name');
      showNotice('存档已备份：$name');
    } catch (e) {
      _setStatus('备份失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(SaveBackupEntry e) async {
    final ok = await showKisakiDialog<bool>(
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
    setState(() {
      _busy = true;
      _statusError = false;
    });
    try {
      final (done, total) =
          await _store().restore(widget.game.id!, e.name);
      _reload();
      _setStatus('已恢复 $done / $total 个文件');
      showNotice('存档恢复完成（$done/$total）');
    } catch (err) {
      _setStatus('恢复失败：$err', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                child: Text(
                    _savePath.isEmpty ? '未指定存档目录' : _savePath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.caption.copyWith(
                        color: _savePath.isEmpty
                            ? scheme.error
                            : scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: Gap.sm),
              KPill(
                  label: '保存目录',
                  filled: false,
                  onTap: _savePath.isEmpty ? null : _saveDirToGame),
            ]),
            const SizedBox(height: Gap.md),
            Row(children: [
              KPill(
                  label: '立即备份',
                  icon: Icons.save_rounded,
                  onTap: _busy ? null : _createBackup),
              if (_busy) ...[
                const SizedBox(width: Gap.md),
                // 忙碌指示（原为按钮内的转圈；移到状态行，按钮文案仍可读）
                const SizedBox(
                    width: 14, height: 14, child: KLoading(size: 14)),
              ],
              if (_status.isNotEmpty) ...[
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(_status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Type.caption.copyWith(
                          color: _statusError
                              ? scheme.error
                              : scheme.onSurfaceVariant)),
                ),
              ],
            ]),
            const Divider(height: 24),
            Expanded(
              child: _entries.isEmpty
                  ? const KEmpty(
                      compact: true,
                      icon: Icons.inventory_2_outlined,
                      title: '暂无备份',
                      subtitle: '点击「立即备份」创建第一份存档快照',
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, i) {
                        final e = _entries[i];
                        return KRow(
                          leading: Icon(
                              e.auto
                                  ? Icons.schedule_rounded
                                  : Icons.inventory_2_rounded,
                              size: 20,
                              color: e.auto
                                  ? KisakiColors.lavender
                                  : KisakiColors.pink),
                          title: e.name,
                          subtitle: '${e.fileCount} 个文件 · ${e.displaySize}'
                              '${e.auto ? ' · 自动' : ''}',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              KIconAction(
                                icon: Icons.restore_rounded,
                                tooltip: '恢复此备份',
                                enabled: !_busy,
                                onTap: _busy ? null : () => _restore(e),
                              ),
                              KIconAction(
                                icon: Icons.delete_outline_rounded,
                                tooltip: '删除备份',
                                enabled: !_busy,
                                onTap: _busy
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
    );
  }
}
