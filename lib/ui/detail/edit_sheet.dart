/// 编辑游戏信息底部抽屉：基本信息 / 封面 / 背景 / 元数据 id / 重新刮削。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scrape_search_sheet.dart';

class EditSheet extends riverpod.ConsumerStatefulWidget {
  final Game game;
  const EditSheet({super.key, required this.game});

  @override
  riverpod.ConsumerState<EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends riverpod.ConsumerState<EditSheet> {
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
  late bool _nsfw = widget.game.nsfw;
  late PlayStatus _status = widget.game.playStatus;
  late String _coverPath = widget.game.coverPath;

  List<SourceRecord> _sources = [];
  final _idControllers = <String, TextEditingController>{};

  /// null = 保持不变；'' = 纯色；其他 = 背景图 URL
  String? _bgPick;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _nameCn,
      _developer,
      _release,
      _exe,
      _summary,
      ..._idControllers.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSources() async {
    final sources = await AppServices.I.repo.sourcesOf(widget.game.id!);
    if (!mounted) return;
    setState(() {
      _sources = sources;
      for (final s in sources) {
        _idControllers[s.source] = TextEditingController(text: s.sourceId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: BoxDecoration(
          color: dark ? KisakiColors.nightCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: dark ? Colors.white24 : Colors.black12,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('编辑「${widget.game.displayName}」',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(context, '基本信息', [
                      Row(children: [
                        Expanded(
                          child: TextField(
                              controller: _nameCn,
                              decoration:
                                  const InputDecoration(labelText: '中文名称')),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                              controller: _name,
                              decoration:
                                  const InputDecoration(labelText: '原始名称')),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: TextField(
                              controller: _developer,
                              decoration:
                                  const InputDecoration(labelText: '开发商')),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                              controller: _release,
                              decoration: const InputDecoration(
                                  labelText: '发售日期（YYYY-MM-DD）')),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _exe,
                        decoration: InputDecoration(
                            labelText: '游戏可执行文件（可粘贴路径）',
                            suffixIcon: IconButton(
                                icon: const Icon(Icons.folder_open_rounded,
                                    size: 18),
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
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in PlayStatus.values)
                            ChoiceChip(
                              label: Text(s.label),
                              selected: _status == s,
                              onSelected: (_) =>
                                  setState(() => _status = s),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('NSFW（R-18）'),
                        subtitle: const Text('启用后封面按设置模糊或替换'),
                        value: _nsfw,
                        onChanged: (v) => setState(() => _nsfw = v),
                      ),
                    ]),
                    _section(context, '封面', [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CoverImage(
                            path: _coverPath,
                            nsfw: _nsfw,
                            width: 90,
                            height: 127,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickCover,
                                  icon: const Icon(Icons.image_rounded, size: 18),
                                  label: const Text('选择本地封面'),
                                ),
                                const SizedBox(height: 8),
                                if (_coverPath.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _coverPath = ''),
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        size: 18),
                                    label: const Text('清除封面'),
                                  )
                                else
                                  Text('当前无本地封面；重新刮削可自动下载',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ]),
                    _section(context, '详情页背景', _buildBackgroundPicker(dark)),
                    _section(context, '元数据（平台条目 id）', _buildSources(dark)),
                    const SizedBox(height: 8),
                    // 底部操作：重刮 / 取消 / 保存
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _rescan,
                          icon: const Icon(Icons.travel_explore_rounded,
                              size: 18),
                          label: const Text('重新刮削'),
                        ),
                        const Spacer(),
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消')),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
      BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        ...children,
      ],
    );
  }

  List<Widget> _buildBackgroundPicker(bool dark) {
    final shots = widget.game.screenshots;
    return [
      if (shots.isEmpty)
        Text('暂无刮削截图；使用「重新刮削」获取截图后可在此选择背景。',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant))
      else
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _bgTile(
                selected: _bgPick == '' || (_bgPick == null && widget.game.backgroundUrl.isEmpty),
                onTap: () => setState(() => _bgPick = ''),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.format_color_fill_rounded, size: 22),
                    SizedBox(height: 4),
                    Text('纯色', style: TextStyle(fontSize: 11.5)),
                  ],
                ),
              ),
              for (final url in shots.take(8))
                _bgTile(
                  selected: _bgPick == url ||
                      (_bgPick == null &&
                          widget.game.backgroundUrl.isNotEmpty &&
                          _isCurrentBg(url)),
                  onTap: () => setState(() => _bgPick = url),
                  child: _bgImage(url),
                ),
            ],
          ),
        ),
    ];
  }

  bool _isCurrentBg(String url) =>
      widget.game.backgroundUrl.endsWith(url.split('/').last);

  Widget _bgTile(
      {required bool selected,
      required VoidCallback onTap,
      required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 148,
          height: 86,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _bgImage(String url) {
    if (url.startsWith('http')) {
      return Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded,
              size: 18));
    }
    return Image.file(File(url), fit: BoxFit.cover);
  }

  List<Widget> _buildSources(bool dark) {
    if (_sources.isEmpty) {
      return [
        Text('暂无平台数据记录；重新刮削后自动登记。',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant))
      ];
    }
    return [
      for (final s in _sources) ...[
        Row(
          children: [
            SizedBox(
              width: 92,
              child: SourceBadge(source: s.source),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _idControllers[s.source],
                decoration: const InputDecoration(
                    hintText: '条目 id', isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 86,
              child: Text(
                s.rating > 0
                    ? '${s.rating.toStringAsFixed(1)} · ${s.voteCount} 评'
                    : '无评分',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: '删除该平台记录',
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: () async {
                await AppServices.I.repo.deleteSource(widget.game.id!, s.source);
                await _loadSources();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  // ---------- 动作 ----------

  Future<void> _pickExe() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: '选择游戏可执行文件',
    );
    if (result?.files.single.path != null) {
      setState(() => _exe.text = result!.files.single.path!);
    }
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result?.files.single.path != null) {
      setState(() => _coverPath = result!.files.single.path!);
    }
  }

  /// 重新刮削：搜索 → 选择 → 多源合并 → 应用（与添加页同一流程）。
  Future<void> _rescan() async {
    final all = await showScrapeSearchSheet(
      context,
      initialQuery: widget.game.displayName,
    );
    if (all == null || !mounted) return;
    await ScrapeApplier(AppServices.I.repo, AppServices.I.fetcher)
        .apply(widget.game, all, backgroundPick: _bgPick);
    ref.read(libraryVersionProvider.notifier).state++;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已重新刮削：${all.first.displayName}（${all.length} 个数据源）')));
    Navigator.pop(context);
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
    g.coverPath = _coverPath;
    await AppServices.I.repo.updateGame(g);

    // 平台条目 id 更新
    for (final s in _sources) {
      final c = _idControllers[s.source];
      if (c == null) continue;
      final newId = c.text.trim();
      if (newId != s.sourceId) {
        s.sourceId = newId;
        await AppServices.I.repo.upsertSource(g.id!, s);
      }
    }

    // 背景更新
    if (_bgPick != null) {
      if (_bgPick!.isEmpty) {
        g.backgroundUrl = '';
      } else {
        final local = await AppServices.I.fetcher.downloadImage(
            _bgPick!, 'bg_${g.id}');
        if (local.isNotEmpty) g.backgroundUrl = local;
      }
      await AppServices.I.repo.updateGame(g);
    }

    ref.read(libraryVersionProvider.notifier).state++;
    if (!mounted) return;
    Navigator.pop(context);
  }
}
