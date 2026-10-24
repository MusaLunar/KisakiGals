/// 添加游戏：搜刮添加 / 自定义添加（支持拖拽 exe 或文件夹）。
///
/// 全屏路由页：保留 Scaffold + WindowDragBar（拖动条横跨整宽）；
/// 卡片、分区标题、表单行统一走 ui/kit.dart，间距/字号取 design.dart token。
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/title_bar.dart';
import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../scraping/apply.dart';
import '../../services/game_launcher.dart';
import '../../scraping/scraped_game.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/image_picker.dart';
import '../widgets/notifications.dart';
import '../widgets/scrape_search_sheet.dart';

class AddGamePage extends ConsumerStatefulWidget {
  /// 进入页面时预填的搜索关键词（例如从资源搜索「入库」跳转而来）
  final String initialQuery;
  const AddGamePage({super.key, this.initialQuery = ''});

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

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _nameController.text = widget.initialQuery;
      // 从资源搜索「入库」跳转而来：自动发起一次跨源搜索
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startSearch();
      });
    }
  }

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: dark
            ? KisakiColors.nightBg.withValues(alpha: 0.92)
            : KisakiColors.cream.withValues(alpha: 0.96),
        child: DragDropRegion(
          onFileDrop: (paths) {
            // 拖入的可能是 exe，也可能是游戏目录 → 目录则自动识别 exe
            var exe = paths
                .where((p) => p.toLowerCase().endsWith('.exe'))
                .firstOrNull;
            if (exe == null) {
              final dir = paths.firstWhere(
                  (p) => Directory(p).existsSync(),
                  orElse: () => '');
              if (dir.isNotEmpty) {
                final found = GameLauncher.detectExecutable(dir);
                if (found.isNotEmpty) exe = found;
              }
            }
            if (exe != null) _useExe(exe);
          },
          child: SafeArea(
            child: Column(
              children: [
                // 顶部拖动条：横跨整宽，空白处即可拖动窗口
                const AppTitleBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 2, 24, 6),
                  child: _header(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                    child: _mode == AddMode.scrape
                        ? _buildScrape()
                        : _buildCustom(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 顶栏：返回（结果页返回上一步）/ 标题 / 模式切换。
  Widget _header() {
    final inFlow = _stage == ScrapeStage.choose ||
        _stage == ScrapeStage.merging ||
        _stage == ScrapeStage.confirm;
    return Row(
      children: [
        KIconAction(
          icon: Icons.arrow_back_rounded,
          tooltip: inFlow ? '返回上一步' : '返回',
          onTap: () {
            if (inFlow) {
              setState(() => _stage = ScrapeStage.pick);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        const SizedBox(width: Gap.sm),
        Text('添加游戏', style: Type.display),
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
          onSelectionChanged:
              _adding ? null : (s) => setState(() => _mode = s.first),
        ),
      ],
    );
  }

  // ================= 搜刮添加 =================

  Widget _buildScrape() {
    return switch (_stage) {
      ScrapeStage.pick => _scrapePick(),
      ScrapeStage.searching =>
        const _StageLoading(message: '正在从多个数据源搜刮…'),
      ScrapeStage.choose => _scrapeChoose(),
      ScrapeStage.merging =>
        const _StageLoading(message: '正在整合所有数据源的元数据…'),
      ScrapeStage.confirm => _scrapeConfirm(),
    };
  }

  Widget _scrapePick() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽区（点击也可选择文件）
              KCard(
                onTap: _pickExe,
                child: SizedBox(
                  height: 148,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.file_upload_rounded,
                          size: 42, color: KisakiColors.pink),
                      const SizedBox(height: Gap.md),
                      Text('拖拽游戏 exe 到此处，或点击选择',
                          style: Type.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      const SizedBox(height: Gap.xs),
                      Text('也可以直接拖入游戏文件夹（自动识别启动程序）',
                          style: Type.caption
                              .copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              KCard(
                child: Column(
                  children: [
                    KRow(
                      title: '游戏名称',
                      subtitle: '拖入 exe 后会自动填入，可手动修改',
                      trailing: SizedBox(
                        width: 320,
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                              isDense: true,
                              hintText: '例：ATRI -My Dear Moments-'),
                        ),
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                    KRow(
                      title: '数据源',
                      subtitle: '默认并发查询全部已启用源',
                      trailing: SizedBox(
                        width: 320,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedSource,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: 'auto', child: Text('全部启用源（推荐）')),
                            ...KisakiSources.defaultEnabled.map((s) =>
                                DropdownMenuItem(
                                    value: s,
                                    child:
                                        Text(KisakiSources.labels[s] ?? s))),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedSource = v ?? 'auto'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),
              KPill(
                label: '开始搜刮',
                icon: Icons.travel_explore_rounded,
                onTap: _startSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scrapeChoose() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('「${_nameController.text}」的搜索结果（${_groups.length}）',
            style: Type.title),
        const SizedBox(height: Gap.md),
        Expanded(
          child: _groups.isEmpty
              ? const KEmpty(
                  icon: Icons.search_off_rounded,
                  title: '没有找到匹配的游戏',
                  subtitle: '试试更换名称或数据源，也可以切换到「自定义添加」',
                )
              : GridView(
                  padding: const EdgeInsets.only(bottom: Gap.xl),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    mainAxisSpacing: Gap.lg,
                    crossAxisSpacing: Gap.lg,
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
        if (_groups.isNotEmpty)
          Text('选择一条以整合各平台元数据（简介 / 标签 / 评分 / 图片）',
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  /// 封面候选：各平台自己的封面图（不是 VNDB 的截图）
  List<ImageOption> get _coverOptions {
    final out = <ImageOption>[];
    final seen = <String>{};
    for (final m in _mergedAll) {
      final url = m.coverUrl;
      if (url.isEmpty || !seen.add(url)) continue;
      out.add(ImageOption(
        label: KisakiSources.labels[m.source] ?? m.source,
        url: url,
      ));
    }
    return out;
  }

  /// 选中分组 → 组内多源合并（含各源详情补全）→ 进入确认页。
  Future<void> _mergeAndConfirm(ScrapeHitGroup group) async {
    setState(() {
      _stage = ScrapeStage.merging;
      _bgChoice = '';
      _coverLocal = '';
      for (final c in _memberIds.values) {
        c.dispose();
      }
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

  Widget _scrapeConfirm() {
    final game = _mergedAll.first;
    final contributors = _mergedAll;
    final shots = game.screenshots;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- 合并结果预览 ----------
              KCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoverImage(
                      path: _coverLocal,
                      networkUrl: _coverLocal.isEmpty
                          ? (_coverChoice == null || _coverChoice!.isEmpty
                              ? game.coverUrl
                              : _coverChoice)
                          : '',
                      nsfw: game.nsfw,
                      width: 160,
                      height: 226,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    const SizedBox(width: Gap.xl),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _editNameCn.text.trim().isNotEmpty
                                  ? _editNameCn.text.trim()
                                  : _editName.text.trim(),
                              style: Type.title),
                          const SizedBox(height: Gap.sm),
                          Wrap(
                            spacing: Gap.sm,
                            runSpacing: Gap.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final c in contributors)
                                SourceBadge(source: c.source),
                              if (game.rating > 0)
                                PlatformRatingChip(
                                    label:
                                        KisakiSources.labels[game.source] ?? '',
                                    rating: game.rating,
                                    votes: game.voteCount),
                              if (game.releaseDate.isNotEmpty)
                                KBadge(
                                    text: '发售 ${game.releaseDate}',
                                    color: KisakiColors.lavender),
                            ],
                          ),
                          if (contributors.length > 1) ...[
                            const SizedBox(height: Gap.sm),
                            Text(
                              '已整合 ${contributors.length} 个数据源的元数据（简介/标签/评分取各源所长）',
                              style: Type.caption
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: Gap.sm),
                          Text(
                            [
                              if (game.developer.isNotEmpty)
                                '开发商：${game.developer}',
                              if (game.releaseDate.isNotEmpty)
                                '发售日期：${game.releaseDate}',
                            ].join('\n'),
                            style: Type.caption
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (game.tags.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            Wrap(
                              spacing: Gap.sm,
                              runSpacing: Gap.sm,
                              children: [
                                for (final t in game.tags.take(12))
                                  KChip(
                                      label: t.name,
                                      color: KisakiColors.lavender,
                                      selected: true),
                              ],
                            ),
                          ],
                          if (game.summary.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            Text(game.summary,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                style: Type.body.copyWith(height: 1.55)),
                          ],
                          if (_exeController.text.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            Row(
                              children: [
                                Icon(Icons.terminal_rounded,
                                    size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: Gap.sm),
                                Expanded(
                                  child: Text(_exeController.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Type.caption.copyWith(
                                          color: scheme.onSurfaceVariant)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xl),
              // ---------- 信息确认（可手动修改） ----------
              const KSectionTitle('信息确认（可修改）'),
              KCard(
                child: Row(
                  children: [
                    Expanded(
                      child: KRow(
                        title: '中文名称',
                        trailing: SizedBox(
                          width: 280,
                          child: TextField(
                            controller: _editNameCn,
                            decoration: const InputDecoration(isDense: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.lg),
                    Expanded(
                      child: KRow(
                        title: '原始名称',
                        trailing: SizedBox(
                          width: 280,
                          child: TextField(
                            controller: _editName,
                            decoration: const InputDecoration(isDense: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xl),
              // ---------- 图片（封面 + 详情页背景） ----------
              const KSectionTitle('图片'),
              KCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ImagePickerRow(
                      title: '封面',
                      subtitle: '来自各平台的封面图，点击选用（悬停可看平台名）',
                      options: [
                        for (final c in _coverOptions) c,
                        ImageOption(label: '本地文件', localPath: _coverLocal),
                      ],
                      selectedUrl: _coverChoice,
                      selectedLocal: _coverLocal,
                      onPick: (o) => setState(() {
                        if (o.localPath.isNotEmpty &&
                            !File(o.localPath).existsSync()) {
                          _pickLocalCover();
                          return;
                        }
                        _coverChoice = o.url;
                        _coverLocal = o.localPath;
                      }),
                    ),
                    const SizedBox(height: Gap.lg),
                    ImagePickerRow(
                      title: '详情页背景',
                      subtitle: shots.isEmpty
                          ? '该游戏暂无可选截图，将使用纯色背景'
                          : '刮削得到的截图（详情页可随时更换）',
                      options: [
                        const ImageOption(label: '纯色', isSolid: true),
                        for (final url in shots)
                          ImageOption(label: '截图', url: url),
                      ],
                      selectedUrl: _bgChoice,
                      onPick: (o) => setState(() => _bgChoice = o.url),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xl),
              // ---------- 各源条目 id ----------
              const KSectionTitle('平台条目 id'),
              KCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: Gap.lg, vertical: Gap.xs),
                child: Column(
                  children: [
                    for (var i = 0; i < _mergedAll.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      KRow(
                        leading: SourceBadge(source: _mergedAll[i].source),
                        title: '条目 id',
                        subtitle: KisakiSources.labels[_mergedAll[i].source] ??
                            _mergedAll[i].source,
                        trailing: SizedBox(
                          width: 200,
                          child: TextField(
                            controller: _memberIds[_mergedAll[i].source],
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Gap.xl),
              Row(
                children: [
                  KPill(
                    label: '重新选择',
                    filled: false,
                    onTap: () => setState(() => _stage = ScrapeStage.choose),
                  ),
                  const Spacer(),
                  KPill(
                    label: _adding ? '添加中…' : '加入游戏库',
                    icon: _adding ? null : Icons.check_rounded,
                    onTap: _adding ? null : _addToLibrary,
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

  Widget _buildCustom() {
    final scheme = Theme.of(context).colorScheme;
    final hasCover = _customCover.text.isNotEmpty &&
        File(_customCover.text).existsSync();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 本地封面：无图时给一个可点击的空态卡
                    if (hasCover)
                      GestureDetector(
                        onTap: _pickCoverImage,
                        child: CoverImage(
                          path: _customCover.text,
                          width: 130,
                          height: 183,
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                      )
                    else
                      KCard(
                        onTap: _pickCoverImage,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(Radii.md)),
                        padding: EdgeInsets.zero,
                        child: SizedBox(
                          width: 130,
                          height: 183,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.image_rounded,
                                  color: KisakiColors.pink, size: 32),
                              const SizedBox(height: Gap.sm),
                              Text('选择封面',
                                  style: Type.caption
                                      .copyWith(color: KisakiColors.pink)),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: Gap.lg),
                    Expanded(
                      child: Column(
                        children: [
                          KRow(
                            title: '游戏名称',
                            subtitle: '必填',
                            trailing: SizedBox(
                              width: 300,
                              child: TextField(
                                controller: _customName,
                                decoration:
                                    const InputDecoration(isDense: true),
                              ),
                            ),
                          ),
                          const SizedBox(height: Gap.sm),
                          KRow(
                            title: '开发商',
                            trailing: SizedBox(
                              width: 300,
                              child: TextField(
                                controller: _customDeveloper,
                                decoration:
                                    const InputDecoration(isDense: true),
                              ),
                            ),
                          ),
                          const SizedBox(height: Gap.sm),
                          KRow(
                            title: '游戏 exe',
                            subtitle: '可选，用于启动与计时',
                            trailing: SizedBox(
                              width: 300,
                              child: TextField(
                                controller: _exeController,
                                readOnly: true,
                                onTap: _pickExe,
                                decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '点击选择可执行文件',
                                    suffixIcon:
                                        Icon(Icons.folder_open_rounded, size: 18)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),
              KCard(
                child: Column(
                  children: [
                    KRow(
                      title: '简介',
                      trailing: SizedBox(
                        width: 520,
                        child: TextField(
                          controller: _customSummary,
                          maxLines: 4,
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                    Row(
                      children: [
                        Expanded(
                          child: KRow(
                            title: '封面图片路径',
                            trailing: SizedBox(
                              width: 260,
                              child: TextField(
                                controller: _customCover,
                                decoration:
                                    const InputDecoration(isDense: true),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.lg),
                        Expanded(
                          child: KRow(
                            title: '平台 ID',
                            subtitle: '可选，如 v12345',
                            trailing: SizedBox(
                              width: 260,
                              child: TextField(
                                controller: _customId,
                                decoration:
                                    const InputDecoration(isDense: true),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  Expanded(
                    child: Text('自定义添加不会联网搜刮，仅登记你填写的信息。',
                        style: Type.caption
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  KPill(
                    label: '加入游戏库',
                    icon: Icons.check_rounded,
                    onTap: _addCustom,
                  ),
                ],
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
        _nameController.text =
            cleanExeName(path.split(Platform.pathSeparator).last);
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
    if (name.isEmpty) {
      showNotice('请输入要搜刮的游戏名称', error: true);
      return;
    }
    setState(() => _stage = ScrapeStage.searching);
    final only = _selectedSource == 'auto' ? null : [_selectedSource];
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
    await AppServices.I.relocator.stamp(g);
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
      final local = await AppServices.I.fetcher
          .downloadImage(_coverChoice!, 'game_${g.id}');
      if (local.isNotEmpty) g.coverPath = local;
    }
    // 各源条目 id 手动编辑
    for (final m in _mergedAll) {
      final c = _memberIds[m.source];
      if (c == null) continue;
      final newId = c.text.trim();
      if (newId.isNotEmpty && newId != m.sourceId) {
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
      showNotice('请填写游戏名称', error: true);
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
    // 与搜刮入库一致：登记设备指纹与相对路径，换机后可重定位
    await AppServices.I.relocator.stamp(g);
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

/// 阶段加载态（搜刮中 / 合并中）。
class _StageLoading extends StatelessWidget {
  final String message;
  const _StageLoading({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KLoading(size: 28),
          const SizedBox(height: Gap.lg),
          Text(message,
              style: Type.body.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
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
      onDragDone: (details) =>
          onFileDrop(details.files.map((f) => f.path).toList()),
      child: child,
    );
  }
}
