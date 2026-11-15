/// Fluent 2 添加游戏页：全域 DropTarget 拖拽导入 + 本地/在线双入口卡 + 内联 Expander 搜索结果一键入库 + 自定义添加。
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../../services/game_launcher.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../library/game_actions.dart';
import '../widgets/image_picker_dialog.dart';

enum _AddMode { scrape, custom }

class AddGamePage extends ConsumerStatefulWidget {
  /// 进入页面时预填的搜索关键词（例如从游戏库拖拽或探索页跳转而来）。
  final String initialQuery;

  /// 进入页面时预先传入的本地游戏路径（.exe / .lnk / 游戏目录）。
  final String? initialDropPath;

  /// 可选测试注入钩子；未传时默认调用 [AppServices]。
  final Future<List<ScrapeHitGroup>> Function(String query, List<String> sources)?
      onSearch;
  final Future<List<ScrapedGame>> Function(ScrapeHitGroup group)? onMergeGroup;
  final Future<void> Function(
    List<ScrapedGame> all, {
    String exePath,
    String directory,
  })? onAddScraped;
  final Future<void> Function(Game game, String customSourceId)? onAddCustom;
  final Future<String?> Function()? onPickExe;
  final Future<String?> Function()? onPickDir;
  final Future<String?> Function()? onPickCover;

  const AddGamePage({
    super.key,
    this.initialQuery = '',
    this.initialDropPath,
    this.onSearch,
    this.onMergeGroup,
    this.onAddScraped,
    this.onAddCustom,
    this.onPickExe,
    this.onPickDir,
    this.onPickCover,
  });

  @override
  ConsumerState<AddGamePage> createState() => _AddGamePageState();
}

class _AddGamePageState extends ConsumerState<AddGamePage> {
  final _scrollCtrl = ScrollController();
  final _nameController = TextEditingController();
  final _exeController = TextEditingController();
  final _customName = TextEditingController();
  final _customDeveloper = TextEditingController();
  final _customCover = TextEditingController();
  final _customSummary = TextEditingController();
  final _customId = TextEditingController();

  final Set<String> _selectedSources = {...KisakiSources.defaultEnabled};
  final Set<String> _addedGroupKeys = {};

  _AddMode _mode = _AddMode.scrape;
  bool _draggingOver = false;
  bool _searching = false;
  bool _hasSearched = false;
  bool _addingCustom = false;
  String? _addingGroupKey;
  String _exeDir = '';
  List<ScrapeHitGroup> _groups = const [];

  static Iterable<MapEntry<String, String>> get _filterableSources =>
      KisakiSources.labels.entries
          .where((e) => e.key != KisakiSources.custom);

  @override
  void initState() {
    super.initState();
    final dropPath = widget.initialDropPath?.trim() ?? '';
    if (dropPath.isNotEmpty) {
      _applyLocalPaths([dropPath], notify: false);
    }
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _nameController.text = initial;
      if (_customName.text.isEmpty) {
        _customName.text = initial;
      }
      if (widget.onSearch != null || tryAppServices() != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startSearch();
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _nameController.dispose();
    _exeController.dispose();
    _customName.dispose();
    _customDeveloper.dispose();
    _customCover.dispose();
    _customSummary.dispose();
    _customId.dispose();
    super.dispose();
  }

  String _groupKey(ScrapeHitGroup g) =>
      '${g.merged.source}:${g.merged.sourceId}:${g.merged.displayName}';

  void _applyLocalPaths(List<String> paths, {bool notify = true}) {
    if (paths.isEmpty) return;

    String? exePath;
    String? lnkPath;
    String dirPath = '';

    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      final lower = path.toLowerCase();
      if (lower.endsWith('.exe') && exePath == null) {
        exePath = path;
      } else if (lower.endsWith('.lnk') && lnkPath == null) {
        lnkPath = path;
      } else if (dirPath.isEmpty && Directory(path).existsSync()) {
        dirPath = path;
      }
    }

    if (exePath == null && dirPath.isNotEmpty) {
      final detected = GameLauncher.detectExecutable(dirPath);
      if (detected.isNotEmpty) {
        exePath = detected;
      }
    }

    final resolvedExe = exePath ?? lnkPath ?? '';
    final resolvedDir = dirPath.isNotEmpty
        ? dirPath
        : (resolvedExe.isNotEmpty ? p.dirname(resolvedExe) : '');

    var guessedName = '';
    if (resolvedExe.isNotEmpty) {
      guessedName = cleanExeName(p.basenameWithoutExtension(resolvedExe));
    } else if (resolvedDir.isNotEmpty) {
      guessedName = cleanExeName(p.basename(resolvedDir));
    } else {
      guessedName = cleanExeName(p.basenameWithoutExtension(paths.first));
    }

    void updateFields() {
      if (resolvedExe.isNotEmpty) {
        _exeController.text = resolvedExe;
      } else if (resolvedDir.isNotEmpty) {
        _exeController.text = resolvedDir;
      }
      _exeDir = resolvedDir;
      if (guessedName.isNotEmpty) {
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = guessedName;
        }
        if (_customName.text.trim().isEmpty) {
          _customName.text = guessedName;
        }
      }
    }

    if (notify && mounted) {
      setState(updateFields);
      if (guessedName.isNotEmpty) {
        showNotice('已识别本地路径：$guessedName');
      }
    } else {
      updateFields();
    }
  }

  Future<void> _pickExe() async {
    String? path;
    if (widget.onPickExe != null) {
      path = await widget.onPickExe!();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: '选择游戏可执行文件（.exe / .lnk）',
      );
      path = result?.files.single.path;
    }
    if (!mounted || path == null || path.trim().isEmpty) return;
    _applyLocalPaths([path.trim()]);
  }

  Future<void> _pickDirectory() async {
    String? dir;
    if (widget.onPickDir != null) {
      dir = await widget.onPickDir!();
    } else {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择游戏目录',
      );
    }
    if (!mounted || dir == null || dir.trim().isEmpty) return;
    _applyLocalPaths([dir.trim()]);
  }

  Future<void> _pickCustomCover() async {
    String? path;
    if (widget.onPickCover != null) {
      path = await widget.onPickCover!();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: '选择本地封面图',
      );
      path = result?.files.single.path;
    }
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() => _customCover.text = path!.trim());
  }

  void _clearLocalSelection() {
    setState(() {
      _exeController.clear();
      _exeDir = '';
    });
  }

  void _toggleSource(String sourceId, bool selected) {
    setState(() {
      if (selected) {
        _selectedSources.add(sourceId);
      } else {
        _selectedSources.remove(sourceId);
      }
    });
  }

  Future<void> _startSearch() async {
    final kw = _nameController.text.trim();
    if (kw.isEmpty) {
      showNotice('请输入要搜索的游戏名称', error: true);
      return;
    }
    if (_selectedSources.isEmpty) {
      showNotice('请至少选择一个数据源', error: true);
      return;
    }
    final services = tryAppServices();
    if (widget.onSearch == null && services == null) {
      showNotice('服务尚未初始化，无法在线刮削', error: true);
      return;
    }

    setState(() {
      _searching = true;
      _hasSearched = true;
    });

    try {
      final sources = _selectedSources.toList();
      final groups = widget.onSearch != null
          ? await widget.onSearch!(kw, sources)
          : await services!.fetcher.searchGrouped(kw, only: sources);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _searching = false;
      });
      showNotice('刮削搜索失败：$e', error: true);
    }
  }

  Future<List<ScrapedGame>> _mergeGroup(ScrapeHitGroup group) async {
    if (widget.onMergeGroup != null) {
      return widget.onMergeGroup!(group);
    }
    final services = tryAppServices();
    if (services == null) {
      return [group.merged, ...group.members.skip(1)];
    }
    try {
      return await services.fetcher.mergeGroup(group);
    } catch (_) {
      return [group.merged, ...group.members.skip(1)];
    }
  }

  Future<void> _quickAddGroup(ScrapeHitGroup group) async {
    final key = _groupKey(group);
    if (_addingGroupKey != null) return;
    setState(() => _addingGroupKey = key);
    try {
      final all = await _mergeGroup(group);
      if (!mounted) return;
      final added = await _persistScrapedGame(all);
      if (!mounted) return;
      if (added) {
        setState(() => _addedGroupKeys.add(key));
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        showNotice('入库失败：$e', error: true);
      }
    } finally {
      if (mounted) setState(() => _addingGroupKey = null);
    }
  }

  Future<void> _openConfirmDialog(ScrapeHitGroup group) async {
    final key = _groupKey(group);
    if (_addingGroupKey != null) return;
    setState(() => _addingGroupKey = key);
    List<ScrapedGame> all;
    try {
      all = await _mergeGroup(group);
    } catch (_) {
      all = [group.merged, ...group.members.skip(1)];
    } finally {
      if (mounted) setState(() => _addingGroupKey = null);
    }
    if (!mounted) return;

    final customized = await showDialog<_ScrapedCustomizeResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ScrapeConfirmDialog(
        mergedAll: all,
        exePath: _exeController.text.trim(),
      ),
    );
    if (!mounted || customized == null) return;

    setState(() => _addingGroupKey = key);
    try {
      final added = await _persistScrapedGame(
        all,
        overrideNameCn: customized.nameCn,
        overrideName: customized.name,
        coverPick: customized.coverPick,
        bgPick: customized.bgPick,
        editedSourceIds: customized.sourceIds,
      );
      if (!mounted) return;
      if (added) {
        setState(() => _addedGroupKeys.add(key));
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        showNotice('入库失败：$e', error: true);
      }
    } finally {
      if (mounted) setState(() => _addingGroupKey = null);
    }
  }

  Future<bool> _persistScrapedGame(
    List<ScrapedGame> all, {
    String? overrideNameCn,
    String? overrideName,
    String? coverPick,
    String? bgPick,
    Map<String, String> editedSourceIds = const {},
  }) async {
    final exePath = _exeController.text.trim();
    final directory = _exeDir.trim();

    if (widget.onAddScraped != null) {
      await widget.onAddScraped!(
        all,
        exePath: exePath,
        directory: directory,
      );
      if (mounted) bumpLibrary(ref);
      showNotice('已添加「${all.first.displayName}」到游戏库');
      return true;
    }

    final services = tryAppServices();
    if (services == null) {
      showNotice('服务尚未初始化，无法写入游戏库', error: true);
      return false;
    }

    final repo = services.repo;
    final lead = all.first;
    final existing = await repo.findGameByTitle(lead.displayName);
    if (existing != null) {
      showNotice('「${existing.displayName}」已在游戏库中，未重复添加');
      return false;
    }
    if (exePath.isNotEmpty) {
      final lowerExe = exePath.toLowerCase();
      for (final g in await repo.listGames()) {
        if (g.exePath.toLowerCase() == lowerExe) {
          showNotice('该可执行文件已对应「${g.displayName}」，未重复添加');
          return false;
        }
      }
    }

    final game = Game(
      name: lead.name,
      nameCn: lead.nameCn,
      aliases: lead.aliases,
      developer: lead.developer,
      releaseDate: lead.releaseDate,
      summary: lead.summary,
      nsfw: lead.nsfw,
      screenshots: lead.screenshots,
      exePath: exePath,
      directory: directory,
    );
    await services.relocator.stamp(game);
    await repo.insertGame(game);
    await ScrapeApplier(repo, services.fetcher)
        .apply(game, all, backgroundPick: bgPick);

    if (overrideNameCn != null && overrideNameCn.trim().isNotEmpty) {
      game.nameCn = overrideNameCn.trim();
    }
    if (overrideName != null && overrideName.trim().isNotEmpty) {
      game.name = overrideName.trim();
    }
    if (coverPick != null && coverPick.trim().isNotEmpty) {
      final picked = coverPick.trim();
      if (picked.startsWith('http://') || picked.startsWith('https://')) {
        final local =
            await services.fetcher.downloadImage(picked, 'game_${game.id}');
        if (local.isNotEmpty) game.coverPath = local;
      } else {
        game.coverPath = await _cacheLocalCover(picked, game.id!);
      }
    }

    for (final m in all) {
      final newId = editedSourceIds[m.source]?.trim() ?? '';
      if (newId.isNotEmpty && newId != m.sourceId) {
        await repo.upsertSource(
          game.id!,
          SourceRecord(
            gameId: game.id!,
            source: m.source,
            sourceId: newId,
            rating: m.rating,
            voteCount: m.voteCount,
            raw: m.toJson(),
          ),
        );
      }
    }

    await repo.updateGame(game);
    if (!mounted) return true;
    bumpLibrary(ref);
    showNotice('已添加「${game.displayName}」到游戏库（${all.length} 个数据源）');
    return true;
  }

  Future<void> _addCustom() async {
    if (_addingCustom) return;
    final name = _customName.text.trim();
    if (name.isEmpty) {
      showNotice('请填写游戏名称', error: true);
      return;
    }

    setState(() => _addingCustom = true);
    try {
      final game = Game(
        name: name,
        nameCn: name,
        developer: _customDeveloper.text.trim(),
        summary: _customSummary.text.trim(),
        coverPath: _customCover.text.trim(),
        exePath: _exeController.text.trim(),
        directory: _exeDir.trim(),
      );
      final customId = _customId.text.trim();

      if (widget.onAddCustom != null) {
        await widget.onAddCustom!(game, customId);
      } else {
        final services = tryAppServices();
        if (services == null) {
          showNotice('服务尚未初始化，无法写入游戏库', error: true);
          return;
        }
        await services.relocator.stamp(game);
        final id = await services.repo.insertGame(game);
        if (game.coverPath.isNotEmpty && File(game.coverPath).existsSync()) {
          game.coverPath = await _cacheLocalCover(game.coverPath, id);
          await services.repo.updateGame(game);
        }
        await services.repo.upsertSource(
          id,
          SourceRecord(
            gameId: id,
            source: KisakiSources.custom,
            sourceId: customId,
          ),
        );
      }

      if (!mounted) return;
      bumpLibrary(ref);
      showNotice('已添加「$name」到游戏库');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showNotice('添加失败：$e', error: true);
      }
    } finally {
      if (mounted) setState(() => _addingCustom = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ensureFluentScope(
      context,
      Builder(builder: _buildScaffold),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final busy = _searching || _addingGroupKey != null || _addingCustom;

    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingOver = true),
      onDragExited: (_) => setState(() => _draggingOver = false),
      onDragDone: (details) {
        setState(() => _draggingOver = false);
        _applyLocalPaths(details.files.map((f) => f.path).toList());
      },
      child: Stack(
        children: [
          ScaffoldPage(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (Navigator.of(context).canPop()) ...[
                    Tooltip(
                      message: '返回',
                      child: IconButton(
                        icon: const Icon(
                          FluentIcons.arrow_left_16_regular,
                          size: 16,
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('添加游戏', style: theme.typography.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '拖拽 .exe / .lnk / 游戏目录导入，或搜索多平台元信息一键入库',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.caption?.copyWith(
                            color: theme.inactiveColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ToggleButton(
                    checked: _mode == _AddMode.scrape,
                    onChanged: busy
                        ? null
                        : (_) => setState(() => _mode = _AddMode.scrape),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.search_16_regular, size: 15),
                        SizedBox(width: 6),
                        Text('搜刮入库'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ToggleButton(
                    checked: _mode == _AddMode.custom,
                    onChanged: busy
                        ? null
                        : (_) => setState(() => _mode = _AddMode.custom),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.edit_16_regular, size: 15),
                        SizedBox(width: 6),
                        Text('自定义添加'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            content: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(bottom: 24),
              child: _mode == _AddMode.scrape
                  ? _buildScrapeWorkspace(context)
                  : _buildCustomWorkspace(context),
            ),
          ),
          if (_draggingOver)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: accent.withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: FluentAcrylicPanel(
                    radius: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FluentIcons.folder_add_24_regular,
                          size: 42,
                          color: accent,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '松开鼠标导入 .exe / .lnk / 游戏目录',
                          style: theme.typography.subtitle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScrapeWorkspace(BuildContext context) {
    final disableAnim = fluentAnimationsDisabled(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final localCard = _buildLocalImportCard(context);
            final onlineCard = _buildOnlineScrapeCard(context);
            if (constraints.maxWidth >= 760) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: localCard),
                    const SizedBox(width: 14),
                    Expanded(child: onlineCard),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                localCard,
                const SizedBox(height: 14),
                onlineCard,
              ],
            );
          },
        ).fluentEntrance(index: 0, disable: disableAnim),
        const SizedBox(height: 18),
        _buildResultsSection(context, disableAnim),
      ],
    );
  }

  Widget _buildLocalImportCard(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final isDark = theme.brightness == Brightness.dark;
    final hasLocal = _exeController.text.trim().isNotEmpty || _exeDir.isNotEmpty;

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            icon: FluentIcons.folder_add_24_regular,
            title: '本地游戏导入',
            subtitle: '可选关联启动程序或游戏目录',
            trailing: hasLocal
                ? FluentStatusPill.label(
                    label: '已关联',
                    icon: FluentIcons.checkmark_circle_16_filled,
                    color: isDark
                        ? const Color(0xFF6CCB5F)
                        : const Color(0xFF107C10),
                  )
                : const FluentBadge(text: '可选'),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accent.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(FluentIcons.folder_add_24_regular, size: 28, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '拖入 .exe / .lnk / 游戏文件夹到窗口',
                        style: theme.typography.bodyStrong,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '自动识别启动程序并提取游戏名用于刮削',
                        style: theme.typography.caption?.copyWith(
                          color: theme.inactiveColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextBox(
            controller: _exeController,
            readOnly: true,
            placeholder: '未选择可执行文件或目录',
            suffix: hasLocal
                ? IconButton(
                    icon: const Icon(FluentIcons.dismiss_16_regular, size: 13),
                    onPressed: _clearLocalSelection,
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                onPressed: _pickExe,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.folder_open_16_regular, size: 15),
                    SizedBox(width: 6),
                    Text('选择 .exe'),
                  ],
                ),
              ),
              Button(
                onPressed: _pickDirectory,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.folder_20_regular, size: 15),
                    SizedBox(width: 6),
                    Text('选择目录'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineScrapeCard(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FluentSectionHeader(
            icon: FluentIcons.search_24_regular,
            title: '在线元信息刮削',
            subtitle: '并发查询多平台并合并封面、简介、评分与标签',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextBox(
                  key: const ValueKey('add-search-box'),
                  controller: _nameController,
                  enabled: !_searching,
                  placeholder: '输入游戏名（例：ATRI -My Dear Moments-）',
                  onSubmitted: (_) => _startSearch(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _startSearch,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searching) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      const Text('搜索中…'),
                    ] else ...[
                      const Icon(FluentIcons.search_16_regular, size: 15),
                      const SizedBox(width: 6),
                      const Text('搜索'),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '数据源',
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              HyperlinkButton(
                onPressed: _searching
                    ? null
                    : () => setState(() {
                          _selectedSources
                            ..clear()
                            ..addAll(_filterableSources.map((e) => e.key));
                        }),
                child: const Text('全选'),
              ),
              HyperlinkButton(
                onPressed: _searching
                    ? null
                    : () => setState(() {
                          _selectedSources
                            ..clear()
                            ..addAll(KisakiSources.defaultEnabled);
                        }),
                child: const Text('默认'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in _filterableSources)
                ToggleButton(
                  checked: _selectedSources.contains(entry.key),
                  onChanged: _searching
                      ? null
                      : (v) => _toggleSource(entry.key, v),
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection(BuildContext context, bool disableAnim) {
    final theme = FluentTheme.of(context);
    if (_searching) {
      return FluentSurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: ProgressRing(strokeWidth: 2.2),
                ),
                SizedBox(width: 10),
                Text('正在并发搜索各平台元数据…'),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Container(
                height: 68,
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
              ).fluentShimmer(disable: disableAnim),
            ],
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return const FluentSurfaceCard(
        padding: EdgeInsets.all(16),
        child: FluentEmptyState(
          icon: FluentIcons.search_24_regular,
          title: '输入关键词开始搜刮',
          message: '支持按中文名、原名或别名跨平台检索；也可先在左侧关联本地游戏文件',
        ),
      );
    }

    if (_groups.isEmpty) {
      return FluentSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: FluentEmptyState(
          icon: FluentIcons.search_24_regular,
          title: '没有找到匹配的游戏',
          message: '试试更换名称或勾选更多数据源，也可以切换到「自定义添加」',
          action: Button(
            onPressed: () => setState(() => _mode = _AddMode.custom),
            child: const Text('切换到自定义添加'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluentSectionHeader(
          icon: FluentIcons.games_24_regular,
          title: '搜索结果（${_groups.length}）',
          subtitle: '展开条目可核对简介、标签与来源，点击「一键入库」即刻合并保存',
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ScrapeResultExpander(
            group: _groups[i],
            initiallyExpanded: i == 0,
            busy: _addingGroupKey != null,
            addingThis: _addingGroupKey == _groupKey(_groups[i]),
            added: _addedGroupKeys.contains(_groupKey(_groups[i])),
            onQuickAdd: () => _quickAddGroup(_groups[i]),
            onCustomizeAdd: () => _openConfirmDialog(_groups[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildCustomWorkspace(BuildContext context) {
    final theme = FluentTheme.of(context);
    final coverPath = _customCover.text.trim();
    final hasCover = coverPath.isNotEmpty && File(coverPath).existsSync();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FluentSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _pickCustomCover,
                      child: hasCover
                          ? FluentCoverImage(
                              pathOrUrl: coverPath,
                              width: 132,
                              height: 186,
                              radius: 6,
                            )
                          : Container(
                              width: 132,
                              height: 186,
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.resources.cardStrokeColorDefault,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    FluentIcons.image_24_regular,
                                    size: 32,
                                    color: theme.inactiveColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '选择封面',
                                    style: theme.typography.caption?.copyWith(
                                      color: theme.inactiveColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InfoLabel(
                          label: '游戏名称（必填）',
                          child: TextBox(
                            controller: _customName,
                            placeholder: '输入作品名称',
                          ),
                        ),
                        const SizedBox(height: 10),
                        InfoLabel(
                          label: '开发商 / 社团',
                          child: TextBox(
                            controller: _customDeveloper,
                            placeholder: '可选',
                          ),
                        ),
                        const SizedBox(height: 10),
                        InfoLabel(
                          label: '可执行文件或目录（可选）',
                          child: Row(
                            children: [
                              Expanded(
                                child: TextBox(
                                  controller: _exeController,
                                  readOnly: true,
                                  placeholder: '用于启动与时长追踪',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Button(
                                onPressed: _pickExe,
                                child: const Text('选择 .exe'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FluentSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InfoLabel(
                    label: '作品简介',
                    child: TextBox(
                      controller: _customSummary,
                      maxLines: 4,
                      placeholder: '可选填写故事简介或备注',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InfoLabel(
                          label: '封面路径',
                          child: TextBox(
                            controller: _customCover,
                            placeholder: '本地图片路径',
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InfoLabel(
                          label: '自定义 ID（可选）',
                          child: TextBox(
                            controller: _customId,
                            placeholder: '例：custom-001',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '自定义添加不会联网刮削，仅登记你填写的作品信息。',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _addingCustom ? null : _addCustom,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_addingCustom) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: ProgressRing(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        const Text('添加中…'),
                      ] else ...[
                        const Icon(FluentIcons.save_20_regular, size: 15),
                        const SizedBox(width: 6),
                        const Text('加入游戏库'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrapeResultExpander extends StatelessWidget {
  final ScrapeHitGroup group;
  final bool initiallyExpanded;
  final bool busy;
  final bool addingThis;
  final bool added;
  final VoidCallback onQuickAdd;
  final VoidCallback onCustomizeAdd;

  const _ScrapeResultExpander({
    required this.group,
    required this.initiallyExpanded,
    required this.busy,
    required this.addingThis,
    required this.added,
    required this.onQuickAdd,
    required this.onCustomizeAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final g = group.merged;
    final scoreText = g.rating > 0 ? g.rating.toStringAsFixed(1) : null;
    final voteText = g.voteCount > 0 ? '${g.voteCount} 票' : null;

    return Expander(
      initiallyExpanded: initiallyExpanded,
      leading: FluentCoverImage(
        pathOrUrl: g.coverUrl,
        nsfw: g.nsfw,
        width: 40,
        height: 56,
        radius: 4,
        allowRevealOnHover: false,
      ),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 4),
          FluentR18ScoreRow(
            nsfw: g.nsfw,
            scoreText: scoreText,
            voteText: voteText,
            trailing: [
              for (final s in group.sources)
                FluentBadge(text: KisakiSources.labels[s] ?? s),
              if (g.releaseDate.isNotEmpty) FluentBadge(text: g.releaseDate),
            ],
          ),
        ],
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentCoverImage(
            pathOrUrl: g.coverUrl,
            nsfw: g.nsfw,
            width: 88,
            height: 126,
            radius: 6,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (g.name.isNotEmpty && g.name != g.displayName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '原名：${g.name}',
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                    ),
                  ),
                if (g.developer.isNotEmpty || g.releaseDate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      [
                        if (g.developer.isNotEmpty) '开发商：${g.developer}',
                        if (g.releaseDate.isNotEmpty) '发售：${g.releaseDate}',
                      ].join(' · '),
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                    ),
                  ),
                if (g.summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      g.summary,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body,
                    ),
                  ),
                if (g.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in g.tags.take(10))
                          FluentBadge(text: '#${t.name}'),
                      ],
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (added)
                      FluentStatusPill.label(
                        label: '已入库',
                        icon: FluentIcons.checkmark_circle_16_filled,
                        color: isDark
                            ? const Color(0xFF6CCB5F)
                            : const Color(0xFF107C10),
                      )
                    else ...[
                      Button(
                        onPressed: busy ? null : onCustomizeAdd,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.edit_16_regular, size: 14),
                            SizedBox(width: 6),
                            Text('核对详情并入库'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: busy ? null : onQuickAdd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (addingThis) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: ProgressRing(strokeWidth: 2),
                              ),
                              const SizedBox(width: 6),
                              const Text('入库中…'),
                            ] else ...[
                              const Icon(
                                FluentIcons.arrow_download_20_regular,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              const Text('一键入库'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrapedCustomizeResult {
  final String nameCn;
  final String name;
  final String? coverPick;
  final String? bgPick;
  final Map<String, String> sourceIds;

  const _ScrapedCustomizeResult({
    required this.nameCn,
    required this.name,
    this.coverPick,
    this.bgPick,
    required this.sourceIds,
  });
}

class _ScrapeConfirmDialog extends StatefulWidget {
  final List<ScrapedGame> mergedAll;
  final String exePath;

  const _ScrapeConfirmDialog({
    required this.mergedAll,
    required this.exePath,
  });

  @override
  State<_ScrapeConfirmDialog> createState() => _ScrapeConfirmDialogState();
}

class _ScrapeConfirmDialogState extends State<_ScrapeConfirmDialog> {
  late final TextEditingController _nameCnCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _coverCtrl;
  late final TextEditingController _bgCtrl;
  final Map<String, TextEditingController> _sourceIdCtrls = {};

  @override
  void initState() {
    super.initState();
    final lead = widget.mergedAll.first;
    _nameCnCtrl = TextEditingController(text: lead.nameCn);
    _nameCtrl = TextEditingController(text: lead.name);
    _coverCtrl = TextEditingController(text: lead.coverUrl);
    _bgCtrl = TextEditingController(
      text: lead.screenshots.isNotEmpty ? lead.screenshots.first : '',
    );
    for (final m in widget.mergedAll) {
      _sourceIdCtrls[m.source] ??= TextEditingController(text: m.sourceId);
    }
  }

  @override
  void dispose() {
    _nameCnCtrl.dispose();
    _nameCtrl.dispose();
    _coverCtrl.dispose();
    _bgCtrl.dispose();
    for (final c in _sourceIdCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _coverCandidates => [
        for (final m in widget.mergedAll)
          if (m.coverUrl.isNotEmpty) m.coverUrl,
      ];

  Future<void> _pickCover() async {
    final picked = await showImagePickerDialog(
      context,
      title: '选择封面图',
      candidates: _coverCandidates,
      initialValue: _coverCtrl.text,
    );
    if (!mounted || picked == null) return;
    setState(() => _coverCtrl.text = picked);
  }

  Future<void> _pickBackground() async {
    final picked = await showImagePickerDialog(
      context,
      title: '选择详情页背景',
      candidates: widget.mergedAll.first.screenshots,
      initialValue: _bgCtrl.text,
    );
    if (!mounted || picked == null) return;
    setState(() => _bgCtrl.text = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final lead = widget.mergedAll.first;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
      title: Text('核对入库信息 · ${lead.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FluentCoverImage(
                  pathOrUrl: _coverCtrl.text.trim(),
                  nsfw: lead.nsfw,
                  width: 96,
                  height: 136,
                  radius: 6,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InfoLabel(
                        label: '中文名称',
                        child: TextBox(controller: _nameCnCtrl),
                      ),
                      const SizedBox(height: 10),
                      InfoLabel(
                        label: '原始名称',
                        child: TextBox(controller: _nameCtrl),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '封面图片',
              child: Row(
                children: [
                  Expanded(child: TextBox(controller: _coverCtrl)),
                  const SizedBox(width: 8),
                  Button(onPressed: _pickCover, child: const Text('挑选封面…')),
                ],
              ),
            ),
            const SizedBox(height: 10),
            InfoLabel(
              label: '详情背景（留空则纯色背景）',
              child: Row(
                children: [
                  Expanded(child: TextBox(controller: _bgCtrl)),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: _pickBackground,
                    child: const Text('挑选背景…'),
                  ),
                ],
              ),
            ),
            if (widget.exePath.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '关联程序：${widget.exePath}',
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('各数据源条目 ID', style: theme.typography.bodyStrong),
            const SizedBox(height: 6),
            for (final entry in _sourceIdCtrls.entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: FluentBadge(
                        text: KisakiSources.labels[entry.key] ?? entry.key,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: TextBox(controller: entry.value)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ScrapedCustomizeResult(
              nameCn: _nameCnCtrl.text.trim(),
              name: _nameCtrl.text.trim(),
              coverPick: _coverCtrl.text.trim(),
              bgPick: _bgCtrl.text.trim(),
              sourceIds: {
                for (final e in _sourceIdCtrls.entries)
                  e.key: e.value.text.trim(),
              },
            ),
          ),
          child: const Text('确认入库'),
        ),
      ],
    );
  }
}

Future<String> _cacheLocalCover(String localPath, int gameId) async {
  try {
    final services = tryAppServices();
    if (services == null) return localPath;
    final covers = services.paths.covers;
    Directory(covers).createSync(recursive: true);
    final ext = p.extension(localPath).isNotEmpty
        ? p.extension(localPath)
        : '.jpg';
    final target = p.join(covers, 'game_$gameId$ext');
    File(localPath).copySync(target);
    return target;
  } catch (_) {
    return localPath;
  }
}
