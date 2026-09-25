/// 存档目录候选选择对话框。
///
/// 由 [SaveDirDetector] 汇总多个来源（游戏目录关键词 / 用户目录同名 / 注册表 /
/// 游玩期间写入）给出候选，按可信度降序排列，用户点一行即选中。
/// 存在失效路径（注册表记录但目录已不存在）时置灰不可选，避免误选。
///
/// 视觉全部走 ui/kit.dart 原语：外层 `showKisakiDialog`、候选行 KCard(flat)
/// + KRow、徽标 KBadge、按钮 KPill、空态 KEmpty、加载 KLoading。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/save_dir_detector.dart';
import '../../services/save_write_watcher.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';

class SaveDirPickerDialog extends StatefulWidget {
  final Game game;
  const SaveDirPickerDialog({super.key, required this.game});

  /// 打开对话框；返回用户选中的路径（取消 / 关闭返回 null）。
  static Future<String?> show(BuildContext context, Game game) =>
      showKisakiDialog<String>(
        context: context,
        builder: (_) => SaveDirPickerDialog(game: game),
      );

  @override
  State<SaveDirPickerDialog> createState() => _SaveDirPickerDialogState();
}

class _SaveDirPickerDialogState extends State<SaveDirPickerDialog> {
  List<SaveDirCandidate> _items = const [];
  bool _loading = true;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _scan();
  }

  /// 检测窗口的起点 [since]：晚于它被改动过的候选会得到小幅加分。
  /// 优先用「当前会话开始时间」（游戏正在跑或刚跑完），否则退回最近 30 分钟。
  DateTime _since() {
    try {
      final tracker = AppServices.I.tracker;
      if (widget.game.id != null && tracker.trackedGameId == widget.game.id) {
        // liveSeconds 是已计入的秒数，反推即可得到会话开始时间
        return DateTime.now().subtract(Duration(seconds: tracker.liveSeconds));
      }
    } catch (_) {
      // AppServices 未初始化（例如单测里直接构造对话框）：退回默认窗口
    }
    return DateTime.now().subtract(const Duration(minutes: 30));
  }

  /// 重新扫描：拿写入线索 → 汇总所有来源。
  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _note = '';
    });
    final game = widget.game;
    final since = _since();

    // 写入线索优先取监视器记录的（游戏运行期间的真实写入）；
    // 没有记录（本次进程没跑过该游戏）时做一次一次性扫描兜底，
    // 这样「先玩一把 → 再来识别」在没有会话记录的情况下也能生效。
    var hits = SaveWriteWatcher.lastHits(game.id ?? -1);
    if (hits.isEmpty) {
      try {
        hits = await SaveWriteWatcher.scanNow(
          gameDir: game.directory,
          since: since,
          budget: const Duration(milliseconds: 900),
        );
      } catch (_) {}
    }

    List<SaveDirCandidate> list;
    try {
      list = await SaveDirDetector.detect(game, writeHits: hits, since: since);
    } catch (_) {
      list = const [];
    }
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
      _note = hits.isEmpty ? '' : '其中 ${hits.length} 个目录在最近一次运行中被写入';
    });
  }

  /// 手动选择：绕开自动识别，直接选目录。
  Future<void> _pickManual() async {
    final dir = await FilePicker.platform
        .getDirectoryPath(dialogTitle: '选择存档目录');
    if (dir == null || dir.isEmpty || !mounted) return;
    Navigator.pop(context, dir);
  }

  Color _badgeColor(SaveDirCandidate c, ColorScheme scheme) {
    if (c.confidence >= 90) return KisakiColors.success;
    if (c.confidence >= 70) return KisakiColors.warning;
    return scheme.onSurfaceVariant;
  }

  /// 副标题：来源说明 + 文件数 / 最后修改时间；失效路径改为灰色说明。
  String _subtitle(SaveDirCandidate c) {
    if (!c.exists) return '${c.reason} · 目录不存在，已失效';
    final parts = <String>['${c.fileCount} 个文件'];
    final last = c.lastModified;
    if (last != null) parts.add('最后修改 ${fmtDateTime(last)}');
    return '${c.reason} · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('选择存档目录'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已按可信度排序；建议选「游玩期间检测到文件写入」的目录',
                style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                KPill(
                  label: '重新扫描',
                  icon: Icons.refresh_rounded,
                  filled: false,
                  onTap: _loading ? null : _scan,
                ),
                const SizedBox(width: Gap.sm),
                KPill(
                  label: '手动选择目录…',
                  icon: Icons.folder_open_rounded,
                  filled: false,
                  onTap: _pickManual,
                ),
                if (_note.isNotEmpty) ...[
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(_note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.caption
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ],
              ],
            ),
            const Divider(height: 24),
            Expanded(child: _body()),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const KLoading();
    if (_items.isEmpty) {
      return const KEmpty(
        icon: Icons.search_off_rounded,
        title: '没有找到疑似存档目录',
        subtitle: '可以先运行一次游戏，让「游玩期间写入检测」生效；\n'
            '也可以用上方「手动选择目录…」直接指定',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: _row(_items[i]),
      ),
    );
  }

  /// 单个候选：主标题是路径末两段（完整路径在 Tooltip 里），
  /// 副标题是来源说明与文件信息，右侧是可置信度徽标。
  Widget _row(SaveDirCandidate c) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: c.path,
      child: KCard(
        flat: true,
        dense: true,
        // 路径已不存在时禁用选择（注册表/写入线索可能指向已删除的目录）
        onTap: c.exists ? () => Navigator.pop(context, c.path) : null,
        child: KRow(
          leading: Icon(
            c.exists ? Icons.folder_rounded : Icons.folder_off_rounded,
            size: 20,
            color: c.exists
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
          title: c.shortPath,
          subtitle: _subtitle(c),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KBadge(
                text: '${c.confidenceLevel} ${c.confidence}',
                color: _badgeColor(c, scheme),
              ),
              if (!c.exists) ...[
                const SizedBox(width: Gap.xs),
                KBadge(text: '目录不存在', color: scheme.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
