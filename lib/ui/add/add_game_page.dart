/// 添加游戏：搜刮添加 / 自定义添加（支持拖拽 exe）。
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
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
  List<ScrapeHit> _hits = [];
  List<ScrapedGame> _mergedAll = const []; // [0]=合并结果, 其余=各源原始条目
  String _bgChoice = ''; // ''=纯色背景；非空=截图 URL

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _exeController,
      _customName,
      _customDeveloper,
      _customCover,
      _customSummary,
      _customId
    ]) {
      c.dispose();
    }
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
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (_stage == ScrapeStage.choose ||
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
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                    ),
                  ],
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
        Text('「${_nameController.text}」的搜索结果（${_hits.length}）',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        Expanded(
          child: _hits.isEmpty
              ? EmptyState(
                  title: '没有找到匹配的游戏',
                  subtitle: '试试更换名称或数据源，也可以切换到「自定义添加」',
                )
              : GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 3.4,
                  ),
                  children: [
                    for (final hit in _hits)
                      _HitTile(
                        hit: hit,
                        onPick: () => _mergeAndConfirm(hit),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 选中候选 → 整合所有数据源 → 进入确认页。
  Future<void> _mergeAndConfirm(ScrapeHit hit) async {
    setState(() {
      _stage = ScrapeStage.merging;
      _bgChoice = '';
    });
    try {
      final all = await AppServices.I.fetcher.mergeAcrossSources(
        hit.game,
        kw: _nameController.text.trim(),
        only: _selectedSource == 'auto' ? null : [_selectedSource],
      );
      if (!mounted) return;
      setState(() {
        _mergedAll = all;
        _stage = ScrapeStage.confirm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mergedAll = [hit.game];
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
                    path: '',
                    networkUrl: game.coverUrl,
                    nsfw: game.nsfw,
                    width: 160,
                    height: 226,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(game.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (game.nameCn.isNotEmpty && game.nameCn != game.displayName)
                          Text(game.name,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                SizedBox(
                  height: 92,
                  child: ListView(
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
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton(
                      onPressed: () =>
                          setState(() => _stage = ScrapeStage.choose),
                      child: const Text('重新选择')),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _addToLibrary,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('加入游戏库'),
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
      final hits = await AppServices.I.fetcher.searchRanked(name, only: only);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _stage = ScrapeStage.choose;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hits = [];
        _stage = ScrapeStage.choose;
      });
    }
  }

  Future<void> _addToLibrary() async {
    final game = _mergedAll.first;
    final repo = AppServices.I.repo;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '已添加「${g.displayName}」到游戏库（${_mergedAll.length} 个数据源）')));
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已添加「$name」到游戏库')));
    Navigator.of(context).pop();
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

/// 搜索结果条目。
class _HitTile extends StatelessWidget {
  final ScrapeHit hit;
  final VoidCallback onPick;
  const _HitTile({required this.hit, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final g = hit.game;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? KisakiColors.nightCard : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              CoverImage(
                path: '',
                networkUrl: g.coverUrl,
                nsfw: g.nsfw,
                width: 46,
                height: 64,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(g.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        SourceBadge(source: g.source),
                        const SizedBox(width: 6),
                        if (g.rating > 0)
                          Text(
                              '${g.rating.toStringAsFixed(1)} · ${g.voteCount} 评',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        if (g.releaseDate.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(g.releaseDate,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
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
