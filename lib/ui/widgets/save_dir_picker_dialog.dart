/// Fluent 2 存档目录识别与候选选择对话框。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/save_dir_detector.dart';
import '../../services/save_write_watcher.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';

/// 打开存档目录选择对话框，返回用户选中或手动浏览的目录路径；取消返回 null。
Future<String?> showSaveDirPickerDialog(
  BuildContext context,
  Game game, {
  Future<List<SaveDirCandidate>> Function(Game game)? detectCandidates,
  Future<String?> Function()? pickManualDir,
}) {
  final hasTheme = FluentTheme.maybeOf(context) != null;
  final hasL10n =
      Localizations.of<FluentLocalizations>(context, FluentLocalizations) !=
          null;
  if (hasTheme && hasL10n) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SaveDirPickerDialog(
        game: game,
        detectCandidates: detectCandidates,
        pickManualDir: pickManualDir,
      ),
    );
  }

  return Navigator.of(context, rootNavigator: true).push<String>(
    RawDialogRoute<String>(
      barrierDismissible: true,
      barrierLabel: '选择存档目录',
      barrierColor: const Color(0x8A000000),
      pageBuilder: (ctx, _, __) => ensureFluentScope(
        context,
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(ctx).maybePop(),
          },
          child: SafeArea(
            child: SaveDirPickerDialog(
              game: game,
              detectCandidates: detectCandidates,
              pickManualDir: pickManualDir,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 兼容旧调用点 `SaveDirPickerDialog.show(...)` 的 Fluent 对话框组件。
class SaveDirPickerDialog extends StatefulWidget {
  final Game game;
  final Future<List<SaveDirCandidate>> Function(Game game)? detectCandidates;
  final Future<String?> Function()? pickManualDir;

  const SaveDirPickerDialog({
    super.key,
    required this.game,
    this.detectCandidates,
    this.pickManualDir,
  });

  static Future<String?> show(BuildContext context, Game game) =>
      showSaveDirPickerDialog(context, game);

  @override
  State<SaveDirPickerDialog> createState() => _SaveDirPickerDialogState();
}

class _SaveDirPickerDialogState extends State<SaveDirPickerDialog> {
  final TextEditingController _filterCtrl = TextEditingController();
  List<SaveDirCandidate> _items = const [];
  bool _loading = true;
  String? _error;
  String _note = '';
  String? _selectedPath;
  DateTime? _lastTapAt;
  String? _lastTapPath;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  DateTime _since() {
    try {
      final tracker = AppServices.I.tracker;
      if (widget.game.id != null && tracker.trackedGameId == widget.game.id) {
        return DateTime.now().subtract(Duration(seconds: tracker.liveSeconds));
      }
    } catch (_) {}
    return DateTime.now().subtract(const Duration(minutes: 30));
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
      _note = '';
      _selectedPath = null;
    });

    List<SaveDirCandidate> list = const [];
    var note = '';
    String? scanErr;
    if (widget.detectCandidates != null) {
      try {
        list = await widget.detectCandidates!(widget.game);
      } catch (e) {
        scanErr = '候选目录扫描失败：$e';
      }
    } else {
      final since = _since();
      var hits = SaveWriteWatcher.lastHits(widget.game.id ?? -1);
      if (hits.isEmpty) {
        try {
          hits = await SaveWriteWatcher.scanNow(
            gameDir: widget.game.directory,
            since: since,
            budget: const Duration(milliseconds: 900),
          );
        } catch (_) {}
      }
      if (hits.isNotEmpty) {
        note = '其中 ${hits.length} 个目录在最近一次运行中被写入';
      }
      try {
        list = await SaveDirDetector.detect(
          widget.game,
          writeHits: hits,
          since: since,
        );
      } catch (e) {
        scanErr = '自动探测存档目录失败：$e';
      }
    }

    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
      _error = scanErr;
      _note = note;
      if (widget.game.savePath.isNotEmpty &&
          list.any((c) => c.exists && c.path == widget.game.savePath)) {
        _selectedPath = widget.game.savePath;
      }
    });
  }

  Future<void> _pickManual() async {
    final dir = widget.pickManualDir != null
        ? await widget.pickManualDir!()
        : await FilePicker.platform.getDirectoryPath(dialogTitle: '选择存档目录');
    if (dir == null || dir.trim().isEmpty || !mounted) return;
    Navigator.pop(context, dir.trim());
  }

  Future<void> _openCandidateDir(String path) async {
    try {
      await Process.run('explorer.exe', [path.replaceAll('/', r'\')]);
    } catch (e) {
      showNotice('打开目录失败：$e', error: true);
    }
  }

  Color _badgeColor(SaveDirCandidate c, FluentThemeData theme) {
    if (!c.exists) return theme.textTertiary;
    if (c.confidence >= 90) return theme.successInk;
    if (c.confidence >= 70) return theme.warningInk;
    return theme.textSecondary;
  }

  String _subtitle(SaveDirCandidate c) {
    if (!c.exists) return c.reason;
    final parts = <String>['${c.fileCount} 个文件'];
    if (c.lastModified != null) {
      parts.add('最后修改 ${fmtDateTime(c.lastModified!)}');
    }
    return '${c.reason} · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 660, maxHeight: 620),
      title: const Row(
        children: [
          Icon(FluentIcons.folder_open_20_regular, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text('选择存档目录')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 610, maxHeight: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已按可信度排序；建议优先选择「游玩期间检测到文件写入」的目录',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Button(
                  onPressed: _loading ? null : _scan,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.arrow_clockwise_20_regular, size: 16),
                      SizedBox(width: 6),
                      Text('重新扫描'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: _pickManual,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.folder_open_20_regular, size: 16),
                      SizedBox(width: 6),
                      Text('手动浏览目录'),
                    ],
                  ),
                ),
                if (_note.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption?.copyWith(
                        color: theme.accentInk,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!_loading && _items.length > 4) ...[
              const SizedBox(height: 10),
              FluentSearchBox(
                controller: _filterCtrl,
                compact: true,
                placeholder: '过滤候选目录路径或来源说明…',
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedPath == null
              ? null
              : () => Navigator.pop(context, _selectedPath),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildBody(FluentThemeData theme) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(),
            SizedBox(height: 12),
            Text('正在扫描疑似存档目录…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return FluentEmptyState(
        icon: FluentIcons.error_circle_24_regular,
        title: '扫描目录失败',
        message: _error!,
        action: Button(
          onPressed: _scan,
          child: const Text('重试'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const FluentEmptyState(
        icon: FluentIcons.folder_search_24_regular,
        title: '没有找到疑似存档目录',
        message: '可以先运行一次游戏让「游玩期间写入检测」生效；\n'
            '也可以点击上方「手动浏览目录」直接指定',
      );
    }

    final q = _filterCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _items
        : _items
            .where((c) =>
                c.path.toLowerCase().contains(q) ||
                c.reason.toLowerCase().contains(q))
            .toList();
    if (filtered.isEmpty) {
      return const FluentEmptyState(
        icon: FluentIcons.search_24_regular,
        title: '没有匹配的候选目录',
        message: '清空筛选词即可查看全部探测结果',
      );
    }

    final isDark = theme.isDark;
    final accent = theme.accentInk;
    return RadioGroup<String>(
      groupValue: _selectedPath,
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedPath = value);
      },
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final c = filtered[index];
          final selected = c.exists && _selectedPath == c.path;
          final badgeColor = _badgeColor(c, theme);
          return Tooltip(
            message: c.path,
            child: FluentSurfaceCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              selected: selected,
              semanticLabel: '${c.shortPath}，${c.reason}',
              onTap: c.exists
                  ? () {
                      final now = DateTime.now();
                      final isDouble = _lastTapPath == c.path &&
                          _lastTapAt != null &&
                          now.difference(_lastTapAt!) <
                              const Duration(milliseconds: 350);
                      _lastTapPath = c.path;
                      _lastTapAt = now;
                      if (isDouble) {
                        Navigator.pop(context, c.path);
                      } else {
                        setState(() => _selectedPath = c.path);
                      }
                    }
                  : null,
              child: Row(
                  children: [
                    RadioButton<String>(
                      value: c.path,
                      enabled: c.exists,
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      c.exists
                          ? FluentIcons.folder_20_regular
                          : FluentIcons.folder_prohibited_20_regular,
                      size: 18,
                      color: c.exists ? accent : theme.textTertiary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.shortPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.bodyStrong?.copyWith(
                              color: c.exists ? null : theme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(c),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.caption?.copyWith(
                              color: theme.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (c.exists)
                      FluentBadge(
                        text: '${c.confidenceLevel} ${c.confidence}',
                        foreground: badgeColor,
                        background:
                            badgeColor.withValues(alpha: isDark ? 0.18 : 0.11),
                      )
                    else
                      FluentBadge(
                        text: '目录不存在',
                        foreground: theme.textSecondary,
                      ),
                    if (c.exists) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: '在资源管理器中查看该目录',
                        child: IconButton(
                          icon: const Icon(
                            FluentIcons.open_16_regular,
                            size: 14,
                          ),
                          onPressed: () => _openCandidateDir(c.path),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          );
        },
      ),
    );
  }
}
