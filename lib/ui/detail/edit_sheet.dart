/// 编辑游戏信息底部抽屉：基本信息 / 封面 / 背景 / 元数据 id / 重新刮削。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/cover_candidates.dart';
import '../../services/game_launcher.dart';
import '../../services/save_backup.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/image_picker.dart';
import '../widgets/notifications.dart';
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
  late final TextEditingController _savePathCtrl =
      TextEditingController(text: widget.game.savePath);
  late bool _nsfw = widget.game.nsfw;
  late PlayStatus _status = widget.game.playStatus;
  late String _coverPath = widget.game.coverPath;
  late String _localeMode = widget.game.localeMode;
  bool _autoSave = false;
  bool _leConfigured = false;
  /// 用户选中的平台封面 URL（null = 保持当前封面）
  String? _coverPickUrl;
  /// 用户选择的本地封面路径
  String _coverLocal = '';
  List<CoverCandidate> _covers = const [];
  final _coverCtrl = ScrollController();
  final _bgCtrl = ScrollController();

  List<SourceRecord> _sources = [];
  final _idControllers = <String, TextEditingController>{};

  /// null = 保持不变；'' = 纯色；其他 = 背景图 URL
  String? _bgPick;

  @override
  void initState() {
    super.initState();
    _loadSources();
    _loadCovers();
    _loadLaunchSettings();
  }

  Future<void> _loadLaunchSettings() async {
    final s = AppServices.I.settings;
    final lePath = await s.getString(SettingsStore.kLePath, '');
    final auto = await s.getBool('save.autosave_${widget.game.id}', def: false);
    if (!mounted) return;
    setState(() {
      _leConfigured = lePath.isNotEmpty && File(lePath).existsSync();
      _autoSave = auto;
    });
  }

  /// 自动识别存档目录（参考 ChronoTide 的关键词扫描思路）。
  Future<void> _detectSavePath() async {
    final dir = widget.game.directory;
    if (dir.isEmpty || !Directory(dir).existsSync()) {
      showNotice('请先设置游戏目录', error: true);
      return;
    }
    final found = SaveScanner.detectSaveDir(dir, widget.game.displayName);
    if (found.isEmpty) {
      showNotice('未在游戏目录中找到 savedata / save / セーブ 之类的存档文件夹', error: true);
      return;
    }
    setState(() => _savePathCtrl.text = found);
  }

  Future<void> _pickSavePath() async {
    final dir = await FilePicker.platform
        .getDirectoryPath(dialogTitle: '选择存档目录');
    if (dir != null && dir.isNotEmpty) {
      setState(() => _savePathCtrl.text = dir);
    }
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
      _savePathCtrl,
      ..._idControllers.values,
      _coverCtrl,
      _bgCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCovers() async {
    try {
      final sources = await AppServices.I.repo.sourcesOf(widget.game.id!);
      final covers = CoverCandidates.fromSources(sources);
      if (!mounted) return;
      setState(() => _covers = covers);
    } catch (_) {}
  }

  Future<void> _loadSources() async {
    final sources = await AppServices.I.repo.sourcesOf(widget.game.id!);
    if (!mounted) return;
    setState(() {
      _sources = sources;
      for (final s in sources) {
        // 重新加载时释放旧控制器，避免重复调用造成泄漏
        _idControllers[s.source]?.dispose();
        _idControllers[s.source] = TextEditingController(text: s.sourceId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 全屏页面（不再是底部抽屉）：编辑区域更大，各分区可充分展开
    return Scaffold(
      backgroundColor: dark ? KisakiColors.nightBg : KisakiColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部拖动条：横跨整宽，空白处即可拖动窗口
            const WindowDragBar(height: 24),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: dark ? KisakiColors.nightCard : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
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
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    icon: const Icon(
                                        Icons.auto_fix_high_rounded,
                                        size: 18),
                                    tooltip: '从游戏目录自动识别',
                                    onPressed: _detectExe),
                                IconButton(
                                    icon: const Icon(
                                        Icons.folder_open_rounded,
                                        size: 18),
                                    tooltip: '浏览…',
                                    onPressed: _pickExe),
                              ],
                            )),
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
                    // 启动方式与存档（参考 ChronoTide / ReinaManager 的每游戏启动设置）
                    _section(context, '启动与存档', [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Locale Emulator 转区启动'),
                        subtitle: Text(_leConfigured
                            ? '日文原版游戏可避免乱码；LE 路径已配置'
                            : '需要先在「设置 → 系统」配置 LEProc.exe 路径'),
                        value: _localeMode == 'japanese',
                        onChanged: (v) => setState(
                            () => _localeMode = v ? 'japanese' : 'none'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('退出游戏后自动备份存档'),
                        subtitle: const Text('需要在下方指定存档目录'),
                        value: _autoSave,
                        onChanged: _savePathCtrl.text.trim().isEmpty
                            ? null
                            : (v) => setState(() => _autoSave = v),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _savePathCtrl,
                        decoration: InputDecoration(
                            labelText: '存档目录（用于备份/恢复）',
                            hintText: r'例：游戏目录下的 savedata 文件夹',
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    icon: const Icon(
                                        Icons.auto_fix_high_rounded,
                                        size: 18),
                                    tooltip: '自动识别存档目录',
                                    onPressed: _detectSavePath),
                                IconButton(
                                    icon: const Icon(
                                        Icons.folder_open_rounded,
                                        size: 18),
                                    tooltip: '浏览…',
                                    onPressed: _pickSavePath),
                              ],
                            )),
                        onChanged: (v) => setState(() {}),
                      ),
                    ]),
                    // 封面：当前封面 + 各平台封面候选（带滚动条）+ 本地选择
                    _section(context, '封面', [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverImage(
                            path: _coverLocal.isNotEmpty
                                ? _coverLocal
                                : _coverPath,
                            networkUrl: (_coverPickUrl != null &&
                                    _coverPickUrl!.isNotEmpty)
                                ? _coverPickUrl
                                : null,
                            nsfw: _nsfw,
                            width: 90,
                            height: 135,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    _covers.isEmpty
                                        ? '未找到平台封面；可重新刮削或选择本地图片'
                                        : '点击下方缩略图切换为对应平台的封面（按 2:3 展示）',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                                const SizedBox(height: 8),
                                if (_covers.isNotEmpty)
                                  ImagePickerRow(
                                    title: '平台封面',
                                    subtitle: '点击选用；候选多时点右侧「查看全部」',
                                    options: [
                                      for (final c in _covers)
                                        ImageOption(
                                            label: c.label, url: c.url),
                                      ImageOption(
                                          label: '本地文件',
                                          localPath: _coverLocal),
                                    ],
                                    selectedUrl: _coverPickUrl,
                                    selectedLocal: _coverLocal,
                                    onPick: (o) {
                                      if (o.localPath.isNotEmpty &&
                                          !File(o.localPath).existsSync()) {
                                        _pickCover();
                                        return;
                                      }
                                      setState(() {
                                        _coverPickUrl = o.url;
                                        _coverLocal = o.localPath;
                                      });
                                    },
                                  ),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, children: [
                                  OutlinedButton.icon(
                                    onPressed: _pickCover,
                                    icon: const Icon(Icons.image_rounded,
                                        size: 18),
                                    label: const Text('选择本地封面'),
                                  ),
                                  if (_coverPath.isNotEmpty ||
                                      _coverPickUrl != null)
                                    TextButton.icon(
                                      onPressed: () => setState(() {
                                        _coverPath = '';
                                        _coverPickUrl = null;
                                      }),
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18),
                                      label: const Text('清除封面'),
                                    ),
                                ]),
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
      ImagePickerRow(
        title: '背景图',
        subtitle: shots.isEmpty
            ? '暂无刮削截图；重新刮削后可在此选择背景图'
            : '点击选用；候选多时点右侧「查看全部」',
        options: [
          const ImageOption(label: '纯色', isSolid: true),
          for (final url in shots) ImageOption(label: '截图', url: url),
        ],
        // null = 未改动：按当前背景高亮
        selectedUrl: _bgPick ??
            (widget.game.backgroundUrl.isEmpty ? '' : _currentBgUrl(shots)),
        onPick: (o) => setState(() => _bgPick = o.url),
      ),
    ];
  }

  /// 当前背景对应的截图 URL（用于高亮）。
  String _currentBgUrl(List<String> shots) {
    for (final u in shots) {
      if (_isCurrentBg(u)) return u;
    }
    return '';
  }

  bool _isCurrentBg(String url) =>
      widget.game.backgroundUrl.endsWith(url.split('/').last);

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

  /// 从游戏目录自动识别可执行文件（汉化补丁 → 体积 → 同名 → 最新）。
  Future<void> _detectExe() async {
    var dir = widget.game.directory;
    if (dir.isEmpty || !Directory(dir).existsSync()) {
      final picked =
          await FilePicker.platform.getDirectoryPath(dialogTitle: '选择游戏目录');
      if (picked == null || picked.isEmpty) return;
      dir = picked;
    }
    final found = GameLauncher.detectExecutable(dir);
    if (found.isEmpty) {
      showNotice('未在目录中找到可执行文件', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _exe.text = found);
    showNotice('已识别：${found.split(Platform.pathSeparator).last}');
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() {
      _coverLocal = path;
      _coverPickUrl = '';
      _coverPath = path;
    });
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
    showNotice('已重新刮削：${all.first.displayName}（${all.length} 个数据源）');
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
    if (_coverPickUrl != null && _coverPickUrl!.isNotEmpty) {
      final local = await AppServices.I.fetcher
          .downloadImage(_coverPickUrl!, 'game_${g.id}');
      if (local.isNotEmpty) {
        _coverPath = local;
      } else {
        showNotice('封面图片下载失败，请检查网络或代理设置（已保留原封面）',
            error: true);
      }
    }
    g.coverPath = _coverPath;
    g.localeMode = _localeMode;
    await AppServices.I.relocator.stamp(g);
    g.savePath = _savePathCtrl.text.trim();
    await AppServices.I.repo.updateGame(g);
    await AppServices.I.settings
        .setBool('save.autosave_${g.id}', _autoSave && g.savePath.isNotEmpty);

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

