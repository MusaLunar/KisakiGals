import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../library/game_actions.dart';

/// Fluent 2 Play Path timeline tab allowing screenshot import, F12 hotkey
/// hint display, note authoring, inline node editing, lightbox preview, and
/// deletion confirmation.
class PlayPathTab extends ConsumerStatefulWidget {
  const PlayPathTab({
    super.key,
    required this.game,
    this.pickImageFile,
    this.onAddNode,
    this.onUpdateNode,
    this.onDeleteNode,
  });

  final Game game;
  final Future<String?> Function()? pickImageFile;
  final Future<void> Function(String? note, String? imagePath)? onAddNode;
  final Future<void> Function(PlayPathNode node)? onUpdateNode;
  final Future<void> Function(int nodeId)? onDeleteNode;

  @override
  ConsumerState<PlayPathTab> createState() => _PlayPathTabState();
}

class _PlayPathTabState extends ConsumerState<PlayPathTab> {
  final _noteCtrl = TextEditingController();
  String? _pendingImage;
  String _hotkey = 'F12';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadHotkey();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHotkey() async {
    final services = tryAppServices();
    if (services == null) return;
    try {
      final raw = await services.settings.getString(
        SettingsStore.kScreenshotHotkey,
        'F12',
      );
      if (mounted) {
        setState(() => _hotkey = raw.trim().isEmpty ? 'F12' : raw.trim());
      }
    } catch (_) {}
  }

  String _hotkeyBannerText() {
    if (_hotkey.toLowerCase() == 'disabled' || _hotkey == '无') {
      return '全局自动截屏快捷键已关闭，仍可手动导入截图与笔记';
    }
    return '游戏中按 $_hotkey 自动截屏保存至此处';
  }

  String _resolveNodeImage(PlayPathNode node) {
    if (node.imagePath.isEmpty) return '';
    try {
      return node.resolvedImagePath;
    } catch (_) {
      return node.imagePath;
    }
  }

  Future<String?> _pickImage() async {
    String? picked;
    if (widget.pickImageFile != null) {
      picked = await widget.pickImageFile!();
    } else {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: '导入游玩截图',
        type: FileType.image,
      );
      picked = res?.files.single.path;
    }
    if (picked == null || picked.isEmpty || !mounted) return null;

    final services = tryAppServices();
    final gameId = widget.game.id;
    var finalPath = picked;
    if (services != null && gameId != null && widget.onAddNode == null) {
      try {
        final ext = p.extension(picked).isEmpty ? '.png' : p.extension(picked);
        final dir = Directory(p.join(services.paths.playPath, '$gameId'));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final dest = p.join(
          dir.path,
          'playpath_${DateTime.now().millisecondsSinceEpoch}$ext',
        );
        await File(picked).copy(dest);
        finalPath = services.paths.toStored(dest);
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _pendingImage = finalPath);
    }
    return finalPath;
  }

  Future<void> _submitNode() async {
    if (_submitting) return;
    final rawNote = _noteCtrl.text.trim();
    final note = rawNote.isEmpty ? null : rawNote;
    final img = _pendingImage;

    if (note == null && (img == null || img.isEmpty)) {
      showNotice('请输入游玩记录内容或先导入截图', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final gameId = widget.game.id;
      if (widget.onAddNode != null) {
        await widget.onAddNode!(note, img);
      } else {
        final services = tryAppServices();
        if (services != null && gameId != null) {
          await services.repo.addPlayPathNode(
            gameId: gameId,
            imagePath: img ?? '',
            note: note ?? '',
          );
        }
      }

      if (gameId != null) {
        ref.invalidate(playPathProvider(gameId));
        ref.read(playPathVersionProvider.notifier).state++;
      }

      if (mounted) {
        setState(() {
          _noteCtrl.clear();
          _pendingImage = null;
          _submitting = false;
        });
      }
      showNotice('已添加游玩节点');
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      showNotice('添加节点失败: $e', error: true);
    }
  }

  Future<void> _editNode(PlayPathNode node) async {
    final editCtrl = TextEditingController(text: node.note);
    String? savedText;
    try {
      savedText = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => ContentDialog(
          constraints: const BoxConstraints(maxWidth: 460),
          title: const Text('编辑游玩节点'),
          content: InfoLabel(
            label: '节点笔记',
            child: TextBox(
              controller: editCtrl,
              minLines: 3,
              maxLines: 6,
              placeholder: '填写路线分支或通关备忘…',
            ),
          ),
          actions: [
            Button(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(editCtrl.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      editCtrl.dispose();
    }

    if (savedText == null || !mounted) return;
    final trimmed = savedText.trim();
    final updated = PlayPathNode(
      id: node.id,
      gameId: node.gameId,
      imagePath: node.imagePath,
      note: trimmed,
      createdAt: node.createdAt,
    );

    try {
      if (widget.onUpdateNode != null) {
        await widget.onUpdateNode!(updated);
      } else {
        final services = tryAppServices();
        if (services != null) {
          await services.repo.updatePlayPathNode(updated);
        }
      }
      final gameId = widget.game.id;
      if (gameId != null) {
        ref.invalidate(playPathProvider(gameId));
        ref.read(playPathVersionProvider.notifier).state++;
      }
      showNotice('已更新游玩节点');
    } catch (e) {
      showNotice('更新失败: $e', error: true);
    }
  }

  Future<void> _deleteNode(PlayPathNode node) async {
    final nodeId = node.id;
    if (nodeId == null) return;

    final confirmed = await showFluentConfirmDialog(
      context,
      title: '删除游玩路径节点',
      content: '确定删除这条游玩路径记录吗？此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      if (widget.onDeleteNode != null) {
        await widget.onDeleteNode!(nodeId);
      } else {
        final services = tryAppServices();
        if (services != null) {
          await services.repo.deletePlayPathNode(nodeId);
        }
      }
      final gameId = widget.game.id;
      if (gameId != null) {
        ref.invalidate(playPathProvider(gameId));
        ref.read(playPathVersionProvider.notifier).state++;
      }
      showNotice('已删除游玩节点');
    } catch (e) {
      showNotice('删除失败: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final disableAnim = fluentAnimationsDisabled(context);
    final gameId = widget.game.id;

    final nodesAsync = gameId == null
        ? const AsyncValue<List<PlayPathNode>>.data([])
        : ref.watch(playPathProvider(gameId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
          ),
          child: Row(
            children: [
              Icon(FluentIcons.camera_16_regular, size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _hotkeyBannerText(),
                  style: theme.typography.body?.copyWith(fontSize: 13),
                ),
              ),
              const FluentBadge(
                text: '自动归档',
                icon: FluentIcons.keyboard_16_regular,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FluentSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextBox(
                controller: _noteCtrl,
                placeholder: '记录当前路线分支、攻略线索或实时感想…',
                minLines: 2,
                maxLines: 4,
              ),
              if (_pendingImage != null && _pendingImage!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: res.cardBackgroundFillColorDefault,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: res.cardStrokeColorDefault),
                  ),
                  child: Row(
                    children: [
                      const Icon(FluentIcons.image_16_regular, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.basename(_pendingImage!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.caption,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          FluentIcons.dismiss_16_regular,
                          size: 14,
                        ),
                        onPressed: () => setState(() => _pendingImage = null),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Button(
                    onPressed: _submitting ? null : _pickImage,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.camera_16_regular, size: 15),
                        SizedBox(width: 6),
                        Text('导入截图'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _submitting ? null : _submitNode,
                    child: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: ProgressRing(strokeWidth: 2),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.add_16_regular, size: 15),
                              SizedBox(width: 6),
                              Text('添加节点'),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        nodesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: ProgressRing()),
          ),
          error: (e, _) => FluentEmptyState(
            icon: FluentIcons.timeline_24_regular,
            title: '加载游玩路径失败',
            message: e.toString(),
          ),
          data: (nodes) {
            if (nodes.isEmpty) {
              return const FluentEmptyState(
                icon: FluentIcons.timeline_24_regular,
                title: '尚未记录游玩路径',
                message: '在游戏中按下截屏热键，或使用上方编辑器记录第一条分支与截图。',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < nodes.length; i++)
                  _TimelineNodeRow(
                    node: nodes[i],
                    resolvedImage: _resolveNodeImage(nodes[i]),
                    gameTitle: widget.game.displayName,
                    isFirst: i == 0,
                    isLast: i == nodes.length - 1,
                    onEdit: () => _editNode(nodes[i]),
                    onDelete: () => _deleteNode(nodes[i]),
                  ).fluentEntrance(index: i, disable: disableAnim),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TimelineNodeRow extends StatelessWidget {
  const _TimelineNodeRow({
    required this.node,
    required this.resolvedImage,
    required this.gameTitle,
    required this.isFirst,
    required this.isLast,
    required this.onEdit,
    required this.onDelete,
  });

  final PlayPathNode node;
  final String resolvedImage;
  final String gameTitle;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final hasImage = resolvedImage.isNotEmpty;
    final hasNote = node.note.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFirst
                          ? accent
                          : res.cardBackgroundFillColorDefault,
                      border: Border.all(
                        color: isFirst ? accent : theme.inactiveColor,
                        width: 2,
                      ),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        margin: const EdgeInsets.only(top: 6),
                        color: res.cardStrokeColorDefault,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FluentSurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FluentIcons.clock_16_regular,
                          size: 13,
                          color: theme.inactiveColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          fmtDateTime(node.createdAt),
                          style: theme.typography.caption?.copyWith(
                            color: theme.inactiveColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (hasImage) ...[
                          const SizedBox(width: 8),
                          const FluentBadge(
                            text: '截图',
                            icon: FluentIcons.image_16_regular,
                          ),
                        ],
                        const Spacer(),
                        IconButton(
                          key: ValueKey('playpath-edit-${node.id}'),
                          icon: const Icon(
                            FluentIcons.edit_16_regular,
                            size: 14,
                          ),
                          onPressed: onEdit,
                        ),
                        IconButton(
                          key: ValueKey('playpath-delete-${node.id}'),
                          icon: Icon(
                            FluentIcons.delete_16_regular,
                            size: 14,
                            color: Colors.red,
                          ),
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                    if (hasImage) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        key: ValueKey('playpath-thumb-${node.id}'),
                        onTap: () => showFluentLightboxDialog(
                          context,
                          pathOrUrl: resolvedImage,
                          title: gameTitle,
                          caption: node.note,
                        ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _PlayPathThumbImage(
                              resolvedImage: resolvedImage,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (hasNote) ...[
                      SizedBox(height: hasImage ? 10 : 8),
                      Text(
                        node.note,
                        style: theme.typography.body?.copyWith(height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPathThumbImage extends StatelessWidget {
  const _PlayPathThumbImage({
    required this.resolvedImage,
  });

  final String resolvedImage;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    final isUrl = resolvedImage.startsWith('http://') ||
        resolvedImage.startsWith('https://');
    if (isUrl) {
      return FluentCoverImage(
        pathOrUrl: resolvedImage,
        width: 280,
        height: 160,
        radius: 8,
      );
    }
    final file = File(resolvedImage);
    if (!file.existsSync()) {
      return Container(
        width: 280,
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: res.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: res.cardStrokeColorDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.image_24_regular, color: theme.inactiveColor),
            const SizedBox(width: 8),
            Text(
              '截图文件未找到',
              style: TextStyle(color: theme.inactiveColor, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Image.file(
      file,
      width: 280,
      height: 160,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: 280,
        height: 120,
        alignment: Alignment.center,
        color: res.cardBackgroundFillColorDefault,
        child: Icon(FluentIcons.image_24_regular, color: theme.inactiveColor),
      ),
    );
  }
}
