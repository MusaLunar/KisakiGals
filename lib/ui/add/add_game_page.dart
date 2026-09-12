/// 添加游戏：搜刮添加 / 自定义添加（支持拖拽 exe）。
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/notifications.dart';
import '../widgets/scrape_search_sheet.dart';

class AddGamePage extends ConsumerStatefulWidget {
  const AddGamePage({super.key});

  @override
  ConsumerState<AddGamePage> createState() => _AddGamePageState();
}

enum AddMode { scrape, custom }

enum ScrapeStage { pick, searching, choose, merging, confirm }

class _AddGamePageState extends ConsumerState<AddGamePage> {
  AddMode _mode = AddMode.scrape;
  ScrapeStage _stage = ScrapeStage.pick;

  final _nameController = TextEditingController();
  final _exeController = TextEditingController();
  final _customName = TextEditingController();
  final _customDeveloper = TextEditingController();
  final _customCover = TextEditingController();
  final _customSummary = TextEditingController();
  final _customId = TextEditingController();

  String _selectedSource = 'auto'; // auto = 全部启用源
  String _exeDir = '';
  List<ScrapeHitGroup> _groups = const []; // 跨源分组结果
  List<ScrapedGame> _mergedAll = const []; // [0]=合并结果, 其余=各源原始条目
  String _bgChoice = ''; // ''=纯色背景；非空=截图 URL
  // 确认页手动编辑
  final _editNameCn = TextEditingController();
  final _editName = TextEditingController();
  final _editCover = TextEditingController();
  String _coverLocal = '';
  String? _coverChoice; // null=默认搜刮封面；''=本地文件(_coverLocal)；URL=指定图
  bool _adding = false;
  final _memberIds = <String, TextEditingController>{};
  final _bgCtrl = ScrollController();
  final _coverCtrl = ScrollController();

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _exeController,
      _customName,
      _customDeveloper,
      _customCover,
      _customSummary,
      _customId,
      _editNameCn,
      _editName,
      _editCover,
      ..._memberIds.values,
    ]) {
      c.dispose();
    }
    _bgCtrl.dispose();
    _coverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: dark
            ? KisakiColors.nightBg.withValues(alpha: 0.92)
            : KisakiColors.cream.withValues(alpha: 0.96),
        child: DragDropRegion(
          onFileDrop: (paths) {
            final exe =
                paths.where((p) => p.toLowerCase().endsWith('.exe')).firstOrNull ??
                    paths.whereType<String>().firstOrNull;
            if (exe != null) _useExe(exe);
          },
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WindowDragBar(
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (_stage == ScrapeStage.choose ||
                              _stage == ScrapeStage.merging ||
                              _stage == ScrapeStage.confirm) {
                            setState(() => _stage = ScrapeStage.pick);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    const SizedBox(width: 6),
                    Text('添加游戏',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    SegmentedButton<AddMode>(
                      segments: const [
                        ButtonSegment(
                            value: AddMode.scrape,
                            icon: Icon(Icons.travel_explore_rounded, size: 18),
                            label: Text('搜刮添加')),
                        ButtonSegment(
                            value: AddMode.custom,
                            icon: Icon(Icons.edit_rounded, size: 18),
                            label: Text('自定义添加')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _adding
                          ? null
                          : (s) => setState(() => _mode = s.first),
                    ),
                  ],
                  ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: _mode == AddMode.scrape
                      ? _buildScrape(scheme)
                      : _buildCustom(scheme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= 搜刮添加 =================

  Widget _buildScrape(ColorScheme scheme) {
    return switch (_stage) {
      ScrapeStage.pick => _scrapePick(scheme),
      ScrapeStage.searching => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('正在从多个数据源搜刮…', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ScrapeStage.choose => _scrapeChoose(scheme),
      ScrapeStage.merging => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('正在整合所有数据源的元数据…', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ScrapeStage.confirm => _scrapeConfirm(scheme),
    };
  }

  Widget _scrapePick(ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽区
            GestureDetector(
              onTap: _pickExe,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: KisakiColors.pink.withValues(alpha: 0.5),
                      width: 1.6,
                      strokeAlign: BorderSide.strokeAlignInside),
                  color: Theme.of(context).brightness == Brightness.dark
                          ? KisakiColors.nightCard
                          : Colors.white,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.file_upload_rounded,
                        size: 44, color: KisakiColors.pink),
                    const SizedBox(height: 10),
                    Text(
                      '拖拽游戏 exe 到此处，或点击选择',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text('将根据文件名自动搜刮元数据',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      labelText: '或直接输入游戏名称', hintText: '例：ATRI -My Dear Moments-'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedSource,
                  decoration: const InputDecoration(labelText: '数据源'),
                  items: [
                    const DropdownMenuItem(
                        value: 'auto', child: Text('全部启用源（推荐）')),
                    ...KisakiSources.defaultEnabled.map((s) => DropdownMenuItem(
                        value: s, child: Text(KisakiSources.labels[s] ?? s))),
                  ],
                  onChanged: (v) => setState(
                      () => _selectedSource = v ?? 'auto'),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _startSearch,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('开始搜刮'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrapeChoose(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('「${_nameController.text}」的搜索结果（${_groups.length}）',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        Expanded(
          child: _groups.isEmpty
              ? EmptyState(
                  title: '没有找到匹配的游戏',
                  subtitle: '试试更换名称或数据源，也可以切换到「自定义添加」',
                )
              : GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 3.4,
                  ),
                  children: [
                    for (final g in _groups)
                      ScrapeGroupTile(
                        group: g,
                        onPick: () => _mergeAndConfirm(g),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 选中分组 → 组内多源合并（含各源详情补全）→ 进入确认页。
  Future<void> _mergeAndConfirm(ScrapeHitGroup group) async {
    setState(() {
      _stage = ScrapeStage.merging;
      _bgChoice = '';
      _coverLocal = '';
      for (final c in _memberIds.values) { c.dispose(); }
      _memberIds.clear();
    });
    try {
      final all = await AppServices.I.fetcher.mergeGroup(group);
      if (!mounted) return;
      setState(() {
        _mergedAll = all;
        final merged = all.first;
        _editNameCn.text = merged.nameCn;
        _editName.text = merged.name;
        _editCover.text = merged.coverUrl;
        for (final m in all) {
          _memberIds[m.source]?.dispose();
          _memberIds[m.source] = TextEditingController(text: m.sourceId);
        }
        _stage = ScrapeStage.confirm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mergedAll = [group.merged, ...group.members.skip(1)];
        _stage = ScrapeStage.confirm;
      });
    }
  }

  Widget _scrapeConfirm(ColorScheme scheme) {
    final game = _mergedAll.first;
    final contributors = _mergedAll;
    final shots = game.screenshots;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverImage(
                    path: _coverLocal,
                    networkUrl: _coverLocal.isEmpty
                        ? (_coverChoice == null
                            ? game.coverUrl
                            : (_coverChoice!.isEmpty ? '' : _coverChoice!))
                        : '',
                    nsfw: game.nsfw,
                    width: 160,
                    height: 226,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_editNameCn.text.trim().isNotEmpty
                            ? _editNameCn.text.trim()
                            : _editName.text.trim(),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final c in contributors)
                              SourceBadge(source: c.source),
                            if (game.rating > 0)
                              PlatformRatingChip(
                                  label: KisakiSources.labels[game.source] ?? '',
                                  rating: game.rating,
                                  votes: game.voteCount),
                            if (game.releaseDate.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: dark
                                      ? KisakiColors.lavender.withValues(alpha: 0.2)
                                      : KisakiColors.lavenderContainer,
                                ),
                                child: Text('发售 ${game.releaseDate}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                        if (contributors.length > 1) ...[
                          const SizedBox(height: 8),
                          Text(
                            '已整合 ${contributors.length} 个数据源的元数据（简介/标签/评分取各源所长）',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          [
                            if (game.developer.isNotEmpty) '开发商：${game.developer}',
                            if (game.releaseDate.isNotEmpty) '发售日期：${game.releaseDate}',
                          ].join('\n'),
                          style: TextStyle(
                              height: 1.6,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        if (game.tags.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in game.tags.take(12))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    color: dark
                                        ? KisakiColors.lavender.withValues(alpha: 0.18)
                                        : KisakiColors.lavenderContainer,
                                  ),
                                  child: Text(t.name,
                                      style: const TextStyle(fontSize: 11.5)),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        if (game.summary.isNotEmpty)
                          Text(game.summary,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(height: 1.55, fontSize: 13)),
                        if (_exeController.text.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.terminal_rounded,
                                  size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(_exeController.text,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 信息确认（可手动修改）
              Text('信息确认（可修改）',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _editNameCn,
                    decoration: const InputDecoration(
                        labelText: '中文名称', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _editName,
                    decoration: const InputDecoration(
                        labelText: '原始名称', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text('封面',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 8),
              _HorizontalWheelScroll(
                  controller: _coverCtrl,
                  child: SizedBox(
                    height: 92,
                    child: ListView(
                      controller: _coverCtrl,
                      scrollDirection: Axis.horizontal,
                      children: [
                        _BgOptionTile(
                          selected: _coverChoice == null,
                          onTap: () => setState(() {
                            _coverChoice = null;
                            _coverLocal = '';
                          }),
                          child: _coverPreview(game.coverUrl),
                        ),
                        for (final url in game.screenshots.take(8))
                          _BgOptionTile(
                            selected: _coverChoice == url,
                            onTap: () => setState(() {
                              _coverChoice = url;
                              _coverLocal = '';
                            }),
                            child: _coverPreview(url),
                          ),
                        _BgOptionTile(
                          selected: _coverChoice == '',
                          onTap: _pickLocalCover,
                          child: _coverLocal.isNotEmpty
                              ? Image.file(File(_coverLocal), fit: BoxFit.cover)
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_rounded, size: 22),
                                    SizedBox(height: 4),
                                    Text('本地文件', style: TextStyle(fontSize: 11.5)),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 10),
              for (final m in _mergedAll)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(width: 92, child: SourceBadge(source: m.source)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _memberIds[m.source],
                        decoration: const InputDecoration(
                            labelText: '条目 id', isDense: true),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),
              // 详情页背景选择：纯色 / 刮削截图
              Text('详情页背景',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 10),
              if (shots.isEmpty)
                Text('该游戏暂无截图，将使用纯色背景；可稍后在详情页更换。',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant))
              else
                _HorizontalWheelScroll(
                  controller: _bgCtrl,
                  child: SizedBox(
                    height: 92,
                    child: ListView(
                      controller: _bgCtrl,
                      scrollDirection: Axis.horizontal,
                      children: [
                        _BgOptionTile(
                          selected: _bgChoice.isEmpty,
                          onTap: () => setState(() => _bgChoice = ''),
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
                          _BgOptionTile(
                            selected: _bgChoice == url,
                            onTap: () => setState(() => _bgChoice = url),
                            child: Image.network(url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_rounded,
                                        size: 18)),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton(
                      onPressed: () =>
                          setState(() => _stage = ScrapeStage.choose),
                      child: const Text('重新选择')),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _adding ? null : _addToLibrary,
                    icon: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded),
                    label: Text(_adding ? '添加中…' : '加入游戏库'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 自定义添加 =================

  Widget _buildCustom(ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _pickCoverImage,
                    child: _customCover.text.isNotEmpty &&
                            File(_customCover.text).existsSync()
                        ? CoverImage(
                            path: _customCover.text,
                            width: 130,
                            height: 183,
                          )
                        : Container(
                            width: 130,
                            height: 183,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: KisakiColors.pink.withValues(alpha: 0.5),
                                  width: 1.5),
                              color: Colors.white,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_rounded,
                                    color: KisakiColors.pink, size: 34),
                                const SizedBox(height: 6),
                                Text('选择封面',
                                    style: TextStyle(
                                        fontSize: 12, color: KisakiColors.pink)),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: _customName,
                          decoration: const InputDecoration(
                              labelText: '游戏名称（必填）'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customDeveloper,
                          decoration:
                              const InputDecoration(labelText: '开发商'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _exeController,
                          readOnly: true,
                          onTap: _pickExe,
                          decoration: const InputDecoration(
                              labelText: '游戏 exe（可选）',
                              suffixIcon: Icon(Icons.folder_open_rounded, size: 18)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _customSummary,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: '简介', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customCover,
                      decoration:
                          const InputDecoration(labelText: '封面图片路径'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _customId,
                      decoration: const InputDecoration(
                          labelText: '平台 ID（可选，如 v12345）'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _addCustom,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('加入游戏库'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 动作 =================

  Future<void> _pickExe() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: '选择游戏可执行文件',
    );
    if (result?.files.single.path != null) {
      _useExe(result!.files.single.path!);
    }
  }

  void _useExe(String path) {
    setState(() {
      _exeController.text = path;
      _exeDir = File(path).parent.path;
      if (_nameController.text.isEmpty) {
        _nameController.text = cleanExeName(path.split(Platform.pathSeparator).last);
      }
    });
  }

  Future<void> _pickCoverImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result?.files.single.path != null) {
      setState(() => _customCover.text = result!.files.single.path!);
    }
  }

  Future<void> _startSearch() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _stage = ScrapeStage.searching);
    final only =
        _selectedSource == 'auto' ? null : [_selectedSource];
    try {
      final groups =
          await AppServices.I.fetcher.searchGrouped(name, only: only);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _stage = ScrapeStage.choose;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _stage = ScrapeStage.choose;
      });
    }
  }

  Future<void> _pickLocalCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result?.files.single.path != null) {
      setState(() {
        _coverLocal = result!.files.single.path!;
        _coverChoice = '';
      });
    }
  }

  Widget _coverPreview(String url) {
    if (url.isEmpty) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_florist_rounded, size: 22),
          SizedBox(height: 4),
          Text('搜刮封面', style: TextStyle(fontSize: 11.5)),
        ],
      );
    }
    return Image.network(url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_rounded, size: 18));
  }

  Future<void> _addToLibrary() async {
    if (_adding) return; // 防重复点击/重复入库
    setState(() => _adding = true);
    try {
      await _doAddToLibrary();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _doAddToLibrary() async {
    final game = _mergedAll.first;
    final repo = AppServices.I.repo;
    // 查重：同名（归一化）或同 exe 已在库 → 不重复添加
    final existing = await repo.findGameByTitle(game.displayName);
    if (existing != null) {
      if (!mounted) return;
      showNotice('「${existing.displayName}」已在游戏库中，未重复添加');
      Navigator.of(context).pop();
      return;
    }
    if (_exeController.text.trim().isNotEmpty) {
      final exe = _exeController.text.trim().toLowerCase();
      for (final g in await repo.listGames()) {
        if (g.exePath.toLowerCase() == exe) {
          if (!mounted) return;
          showNotice('该可执行文件已对应「${g.displayName}」，未重复添加');
          Navigator.of(context).pop();
          return;
        }
      }
    }
    final g = Game(
      name: game.name,
      nameCn: game.nameCn,
      aliases: game.aliases,
      developer: game.developer,
      releaseDate: game.releaseDate,
      summary: game.summary,
      nsfw: game.nsfw,
      screenshots: game.screenshots,
      exePath: _exeController.text,
      directory: _exeDir,
    );
    await repo.insertGame(g);
    // 多源元数据落库（封面下载 + 背景 + 各源评分记录）
    await ScrapeApplier(repo, AppServices.I.fetcher)
        .apply(g, _mergedAll, backgroundPick: _bgChoice);
    // 确认页的手动编辑优先生效
    final manualNameCn = _editNameCn.text.trim();
    final manualName = _editName.text.trim();
    if ((manualNameCn.isNotEmpty && manualNameCn != game.nameCn) ||
        (manualName.isNotEmpty && manualName != game.name)) {
      if (manualNameCn.isNotEmpty) g.nameCn = manualNameCn;
      if (manualName.isNotEmpty) g.name = manualName;
    }
    // 封面选择 → 统一缓存到本地 covers 目录
    if (_coverLocal.isNotEmpty) {
      g.coverPath = await _cacheLocalCover(_coverLocal, g.id!);
    } else if (_coverChoice != null && _coverChoice!.isNotEmpty) {
      final local = await AppServices.I.fetcher.downloadImage(
          _coverChoice!, 'game_${g.id}');
      if (local.isNotEmpty) g.coverPath = local;
    }
    // 各源条目 id 手动编辑
    for (final m in _mergedAll) {
      final c = _memberIds[m.source];
      if (c == null) continue;
      final newId = c.text.trim();
      if (newId.isNotEmpty && newId != m.sourceId) {
        m.sourceId; // 保持成员原样，仅更新记录
        await repo.upsertSource(
            g.id!,
            SourceRecord(
              gameId: g.id!,
              source: m.source,
              sourceId: newId,
              rating: m.rating,
              voteCount: m.voteCount,
              raw: m.toJson(),
            ));
      }
    }
    await repo.updateGame(g);
    if (!mounted) return;
    showNotice('已添加「${g.displayName}」到游戏库（${_mergedAll.length} 个数据源）');
    Navigator.of(context).pop();
  }

  Future<void> _addCustom() async {
    final name = _customName.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写游戏名称')));
      return;
    }
    final repo = AppServices.I.repo;
    final g = Game(
      name: name,
      nameCn: name,
      developer: _customDeveloper.text.trim(),
      summary: _customSummary.text.trim(),
      coverPath: _customCover.text.trim(),
      exePath: _exeController.text,
      directory: _exeDir,
    );
    final id = await repo.insertGame(g);
    await repo.upsertSource(
        id,
        SourceRecord(
          gameId: id,
          source: KisakiSources.custom,
          sourceId: _customId.text.trim(),
        ));
    if (!mounted) return;
    showNotice('已添加「$name」到游戏库');
    Navigator.of(context).pop();
  }
}

/// 横向滚动容器：把鼠标滚轮（垂直）转为横向滚动。
class _HorizontalWheelScroll extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  const _HorizontalWheelScroll(
      {required this.controller, required this.child});

  @override
  State<_HorizontalWheelScroll> createState() => _HorizontalWheelScrollState();
}

class _HorizontalWheelScrollState extends State<_HorizontalWheelScroll> {
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent &&
            widget.controller.hasClients &&
            widget.controller.position.maxScrollExtent > 0) {
          final target = (widget.controller.offset + e.scrollDelta.dy)
              .clamp(0.0, widget.controller.position.maxScrollExtent);
          widget.controller.jumpTo(target);
        }
      },
      child: widget.child,
    );
  }
}

/// 把本地选择的封面复制进 covers 目录统一缓存。
Future<String> _cacheLocalCover(String localPath, int gameId) async {
  try {
    final covers = AppServices.I.paths.covers;
    Directory(covers).createSync(recursive: true);
    final ext = localPath.contains('.')
        ? localPath.substring(localPath.lastIndexOf('.'))
        : '.jpg';
    final target = '$covers/game_$gameId$ext';
    File(localPath).copySync(target);
    return target;
  } catch (_) {
    return localPath;
  }
}

/// 背景选择缩略块。
class _BgOptionTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _BgOptionTile(
      {required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
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
}


/// 拖拽接收区域包装。
class DragDropRegion extends StatelessWidget {
  final Widget child;
  final ValueChanged<List<String>> onFileDrop;

  const DragDropRegion({
    super.key,
    required this.child,
    required this.onFileDrop,
  });

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (details) => onFileDrop(details.files.map((f) => f.path).toList()),
      child: child,
    );
  }
}
