/// 编辑游戏信息底部抽屉。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';

class EditSheet extends StatefulWidget {
  final Game game;
  const EditSheet({super.key, required this.game});

  @override
  State<EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<EditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.game.name);
  late final TextEditingController _nameCn =
      TextEditingController(text: widget.game.nameCn);
  late final TextEditingController _developer =
      TextEditingController(text: widget.game.developer);
  late final TextEditingController _release =
      TextEditingController(text: widget.game.releaseDate);
  late final TextEditingController _exe =
      TextEditingController(text: widget.game.exePath);
  late final TextEditingController _summary =
      TextEditingController(text: widget.game.summary);
  late PlayStatus _status = widget.game.playStatus;
  late bool _nsfw = widget.game.nsfw;

  @override
  void dispose() {
    for (final c in [_name, _nameCn, _developer, _release, _exe, _summary]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF251E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
          left: 28, right: 28, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('编辑「${widget.game.displayName}」',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                      controller: _nameCn,
                      decoration: const InputDecoration(labelText: '中文名称')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: '原始名称')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                      controller: _developer,
                      decoration: const InputDecoration(labelText: '开发商')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                      controller: _release,
                      decoration: const InputDecoration(
                          labelText: '发售日期（YYYY-MM-DD）')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _exe,
              // 允许直接粘贴路径；右侧按钮打开文件选择器
              decoration: InputDecoration(
                  labelText: '游戏可执行文件（可粘贴路径）',
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      tooltip: '浏览…',
                      onPressed: _pickExe)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summary,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: '简介', alignLabelWithHint: true),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in PlayStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('NSFW（R-18）'),
              subtitle: const Text('启用后封面可能按设置模糊或替换'),
              value: _nsfw,
              onChanged: (v) => setState(() => _nsfw = v),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消')),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExe() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path != null) {
      setState(() {
        _exe.text = path;
        widget.game.directory = File(path).parent.path;
      });
    }
  }

  Future<void> _save() async {
    final g = widget.game;
    g.name = _name.text.trim();
    g.nameCn = _nameCn.text.trim();
    g.developer = _developer.text.trim();
    g.releaseDate = _release.text.trim();
    g.exePath = _exe.text.trim();
    if (g.exePath.isNotEmpty && File(g.exePath).existsSync()) {
      g.directory = File(g.exePath).parent.path;
    }
    g.summary = _summary.text.trim();
    g.playStatus = _status;
    g.nsfw = _nsfw;
    await AppServices.I.repo.updateGame(g);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
