/// 编辑游戏信息（全屏页）：
/// 基本信息 / 启动与存档 / 封面 / 详情页背景 / 元数据（平台条目 id） / 重新刮削。
///
/// 视觉全部走 ui/kit.dart：分区用 KSectionTitle + KCard，表单行用 KRow，
/// 开关行用 SwitchListTile，间距与字号取 design.dart 的 token。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;

import '../shell/title_bar.dart';
import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/cover_candidates.dart';
import '../../services/game_launcher.dart';
import '../../services/save_backup.dart';
import '../design.dart';
import '../kit.dart';
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
    return Scaffold(
      backgroundColor: dark ? KisakiColors.nightBg : KisakiColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部拖动条：横跨整宽，空白处即可拖动窗口
            const AppTitleBar(),
            // 标题 + 操作固定在顶部（表单很长，保存入口始终可见）
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: _header(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KSectionTitle('基本信息'),
                    KCard(child: _basicInfo(context)),
                    const SizedBox(height: Gap.xl),
                    const KSectionTitle('启动与存档'),
                    KCard(child: _launchAndSave(context)),
                    const SizedBox(height: Gap.xl),
                    const KSectionTitle('封面'),
                    KCard(child: _coverSection(context)),
                    const SizedBox(height: Gap.xl),
                    const KSectionTitle('详情页背景'),
                    KCard(child: _backgroundSection(context)),
                    const SizedBox(height: Gap.xl),
                    const KSectionTitle('元数据（平台条目 id）'),
                    KCard(child: _sourceSection(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏：标题 + 重新刮削 / 取消 / 保存。
  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑信息', style: Type.display),
              const SizedBox(height: Gap.xxs),
              Text(widget.game.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        KPill(
          label: '重新刮削',
          icon: Icons.travel_explore_rounded,
          filled: false,
          onTap: _rescan,
        ),
        const SizedBox(width: Gap.sm),
        KPill(
          label: '取消',
          filled: false,
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: Gap.sm),
        KPill(label: '保存', icon: Icons.check_rounded, onTap: _save),
      ],
    );
  }

  /// 表单行：左标签 + 右控件（与设置页同一套 KRow 版式）。
  Widget _row(String label, Widget field, {String? hint, double width = 340}) {
    return KRow(
      title: label,
      subtitle: hint,
      trailing: SizedBox(width: width, child: field),
    );
  }

  Widget _basicInfo(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _row(
                '中文名称',
                TextField(
                  controller: _nameCn,
                  decoration: const InputDecoration(isDense: true),
                ),
                hint: '列表与详情页的显示名',
              ),
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: _row(
                '原始名称',
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(isDense: true),
                ),
                hint: '日文 / 英文原名',
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(
              child: _row(
                '开发商',
                TextField(
                  controller: _developer,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: _row(
                '发售日期',
                TextField(
                  controller: _release,
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'YYYY-MM-DD'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        KRow(
          title: '可执行文件',
          subtitle: '可粘贴路径；设置后自动同步游戏目录',
          trailing: SizedBox(
            width: 420,
            child: TextField(
              controller: _exe,
              decoration: InputDecoration(
                isDense: true,
                hintText: r'例：D:\Games\ATRI\ATRI.exe',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KIconAction(
                      icon: Icons.auto_fix_high_rounded,
                      tooltip: '从游戏目录自动识别',
                      onTap: _detectExe,
                    ),
                    KIconAction(
                      icon: Icons.folder_open_rounded,
                      tooltip: '浏览…',
                      onTap: _pickExe,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        KRow(
          title: '简介',
          subtitle: '来自刮削，可手动修改',
          trailing: SizedBox(
            width: 560,
            child: TextField(
              controller: _summary,
              maxLines: 4,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        // 游玩状态：KChip 多选一
        Text('游玩状态',
            style: Type.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final s in PlayStatus.values)
              KChip(
                label: s.label,
                selected: _status == s,
                onTap: () => setState(() => _status = s),
              ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('NSFW（R-18）',
              style: Type.body.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text('启用后封面按设置模糊或替换',
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
          value: _nsfw,
          onChanged: (v) => setState(() => _nsfw = v),
        ),
      ],
    );
  }

  Widget _launchAndSave(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Locale Emulator 转区启动',
              style: Type.body.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            _leConfigured
                ? '日文原版游戏可避免乱码；LE 路径已配置'
                : '需要先在「设置 → 系统」配置 LEProc.exe 路径',
            style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          value: _localeMode == 'japanese',
          onChanged: (v) =>
              setState(() => _localeMode = v ? 'japanese' : 'none'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('退出游戏后自动备份存档',
              style: Type.body.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text('需要在下方指定存档目录',
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
          value: _autoSave,
          onChanged: _savePathCtrl.text.trim().isEmpty
              ? null
              : (v) => setState(() => _autoSave = v),
        ),
        const SizedBox(height: Gap.sm),
        KRow(
          title: '存档目录',
          subtitle: '用于备份 / 恢复（可自动识别）',
          trailing: SizedBox(
            width: 420,
            child: TextField(
              controller: _savePathCtrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: r'例：游戏目录下的 savedata 文件夹',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KIconAction(
                      icon: Icons.auto_fix_high_rounded,
                      tooltip: '自动识别存档目录',
                      onTap: _detectSavePath,
                    ),
                    KIconAction(
                      icon: Icons.folder_open_rounded,
                      tooltip: '浏览…',
                      onTap: _pickSavePath,
                    ),
                  ],
                ),
              ),
              onChanged: (v) => setState(() {}),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coverSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCover = _coverPath.isNotEmpty || _coverPickUrl != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverImage(
          path: _coverLocal.isNotEmpty ? _coverLocal : _coverPath,
          networkUrl:
              (_coverPickUrl != null && _coverPickUrl!.isNotEmpty)
                  ? _coverPickUrl
                  : null,
          nsfw: _nsfw,
          width: 90,
          height: 135,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _covers.isEmpty
                    ? '未找到平台封面；可重新刮削或选择本地图片'
                    : '点击下方缩略图切换为对应平台的封面（按 2:3 展示）',
                style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (_covers.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                ImagePickerRow(
                  title: '平台封面',
                  subtitle: '点击选用；候选多时点右侧「查看全部」',
                  options: [
                    for (final c in _covers)
                      ImageOption(label: c.label, url: c.url),
                    ImageOption(label: '本地文件', localPath: _coverLocal),
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
              ],
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  KPill(
                    label: '选择本地封面',
                    icon: Icons.image_rounded,
                    filled: false,
                    onTap: _pickCover,
                  ),
                  if (hasCover)
                    KPill(
                      label: '清除封面',
                      icon: Icons.delete_outline_rounded,
                      filled: false,
                      onTap: () => setState(() {
                        _coverPath = '';
                        _coverPickUrl = null;
                        _coverLocal = '';
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _backgroundSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shots = widget.game.screenshots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: Gap.xs),
        Text('「纯色」= 详情页不显示背景图；其余选项会把截图缓存到本地。',
            style: Type.caption.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _sourceSection(BuildContext context) {
    if (_sources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: KEmpty(
          icon: Icons.dataset_outlined,
          title: '暂无平台数据记录',
          subtitle: '重新刮削后会自动登记各平台条目 id',
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _sources.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          KRow(
            leading: SourceBadge(source: _sources[i].source),
            title: '条目 id',
            subtitle: _sources[i].rating > 0
                ? '${_sources[i].rating.toStringAsFixed(1)} · ${_sources[i].voteCount} 评'
                : '无评分',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _idControllers[_sources[i].source],
                    decoration:
                        const InputDecoration(hintText: '条目 id', isDense: true),
                  ),
                ),
                KIconAction(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '删除该平台记录',
                  onTap: () async {
                    await AppServices.I.repo
                        .deleteSource(widget.game.id!, _sources[i].source);
                    await _loadSources();
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
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
    // 路径存在性检查：仅当 exe 真实存在时才回写游戏目录
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
    // 设备指纹 + 相对路径（MediaPaths 在 toRow 中把数据目录内的路径存成相对路径）
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
