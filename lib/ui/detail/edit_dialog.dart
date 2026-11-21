import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/media_paths.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../scraping/cover_candidates.dart';
import '../../services/game_launcher.dart';
import '../add/scrape_search_dialog.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import '../library/game_actions.dart';
import '../widgets/image_picker_dialog.dart';
import '../widgets/save_dir_picker_dialog.dart';
import 'save_backup_dialog.dart';

/// 打开 Fluent 2 分区编辑弹窗，修改作品元数据、启动方式、存档目录、标签与封面图。
Future<bool> showEditGameDialog(
  BuildContext context,
  WidgetRef ref,
  Game game, {
  Future<void> Function(Game game)? onSave,
  Future<List<SourceRecord>> Function(int gameId)? loadSources,
  Future<List<TagItem>> Function(int gameId)? loadTags,
  Future<bool> Function(BuildContext context, Game game)? onScrape,
}) async {
  final hasTheme = FluentTheme.maybeOf(context) != null;
  final hasLoc =
      Localizations.of<FluentLocalizations>(context, FluentLocalizations) !=
          null;

  if (hasTheme && hasLoc) {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditGameDialog(
        ref: ref,
        game: game,
        onSave: onSave,
        loadSources: loadSources,
        loadTags: loadTags,
        onScrape: onScrape,
      ),
    );
    return res ?? false;
  }

  final res = await Navigator.of(context).push<bool>(
    RawDialogRoute<bool>(
      barrierDismissible: false,
      barrierLabel: '关闭编辑弹窗',
      barrierColor: const Color(0x7A000000),
      pageBuilder: (dialogCtx, _, __) => ensureFluentScope(
        context,
        Center(
          child: _EditGameDialog(
            ref: ref,
            game: game,
            onSave: onSave,
            loadSources: loadSources,
            loadTags: loadTags,
            onScrape: onScrape,
          ),
        ),
      ),
    ),
  );
  return res ?? false;
}

class _EditGameDialog extends StatefulWidget {
  const _EditGameDialog({
    required this.ref,
    required this.game,
    this.onSave,
    this.loadSources,
    this.loadTags,
    this.onScrape,
  });

  final WidgetRef ref;
  final Game game;
  final Future<void> Function(Game game)? onSave;
  final Future<List<SourceRecord>> Function(int gameId)? loadSources;
  final Future<List<TagItem>> Function(int gameId)? loadTags;
  final Future<bool> Function(BuildContext context, Game game)? onScrape;

  @override
  State<_EditGameDialog> createState() => _EditGameDialogState();
}

class _EditGameDialogState extends State<_EditGameDialog> {
  static const _sections = [
    ('基本信息', FluentIcons.info_16_regular, null),
    ('启动与目录', FluentIcons.play_16_regular, null),
    ('存档与备份', FluentIcons.archive_16_regular, null),
    ('视觉封面', FluentIcons.image_16_regular, ValueKey('edit-anchor-media')),
  ];

  final _scrollCtrl = ScrollController();
  final _sectionKeys = List.generate(4, (_) => GlobalKey());
  final _nameFocus = FocusNode();
  int _activeSection = 0;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameCnCtrl;
  late final TextEditingController _aliasesCtrl;
  late final TextEditingController _devCtrl;
  late final TextEditingController _releaseCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _exeCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _saveCtrl;
  late final TextEditingController _coverCtrl;
  late final TextEditingController _bgCtrl;
  late final TextEditingController _tagInputCtrl;

  late PlayStatus _playStatus;
  late bool _nsfw;
  late bool _isFavorite;
  late String _initialSnapshot;

  List<SourceRecord> _sources = const [];
  List<TagItem> _tags = [];
  bool _tagsDirty = false;
  bool _saving = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final g = widget.game;
    _nameCtrl = TextEditingController(text: g.name);
    _nameCnCtrl = TextEditingController(text: g.nameCn);
    _aliasesCtrl = TextEditingController(text: g.aliases.join(', '));
    _devCtrl = TextEditingController(text: g.developer);
    _releaseCtrl = TextEditingController(text: g.releaseDate);
    _summaryCtrl = TextEditingController(text: g.summary);
    _exeCtrl = TextEditingController(text: g.exePath);
    _dirCtrl = TextEditingController(text: g.directory);
    _saveCtrl = TextEditingController(text: g.savePath);
    _coverCtrl = TextEditingController(text: g.coverPath);
    _bgCtrl = TextEditingController(text: g.backgroundUrl);
    _tagInputCtrl = TextEditingController();

    _playStatus = g.playStatus;
    _nsfw = g.nsfw;
    _isFavorite = g.isFavorite;
    _initialSnapshot = _snapshotSignature();

    _nameCtrl.addListener(() {
      if (_nameError != null && _nameCtrl.text.trim().isNotEmpty) {
        setState(() => _nameError = null);
      }
    });
    _scrollCtrl.addListener(_onScrollSpy);

    _loadMeta();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScrollSpy);
    _scrollCtrl.dispose();
    _nameFocus.dispose();
    _nameCtrl.dispose();
    _nameCnCtrl.dispose();
    _aliasesCtrl.dispose();
    _devCtrl.dispose();
    _releaseCtrl.dispose();
    _summaryCtrl.dispose();
    _exeCtrl.dispose();
    _dirCtrl.dispose();
    _saveCtrl.dispose();
    _coverCtrl.dispose();
    _bgCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  String _snapshotSignature() => [
        _nameCtrl.text,
        _nameCnCtrl.text,
        _aliasesCtrl.text,
        _devCtrl.text,
        _releaseCtrl.text,
        _summaryCtrl.text,
        _exeCtrl.text,
        _dirCtrl.text,
        _saveCtrl.text,
        _coverCtrl.text,
        _bgCtrl.text,
        _playStatus.name,
        _nsfw.toString(),
        _isFavorite.toString(),
      ].join('\u0000');

  bool get _isDirty => _tagsDirty || _snapshotSignature() != _initialSnapshot;

  void _onScrollSpy() {
    if (!mounted) return;
    var bestIdx = _activeSection;
    var bestDelta = double.infinity;
    final viewportBox =
        _scrollCtrl.position.context.notificationContext?.findRenderObject()
            as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return;
    final topY = viewportBox.localToGlobal(Offset.zero).dy;

    for (var i = 0; i < _sectionKeys.length; i++) {
      final ro =
          _sectionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (ro == null || !ro.hasSize) continue;
      final dy = ro.localToGlobal(Offset.zero).dy - topY;
      final score = dy <= 48 ? (48 - dy) : (dy - 48) * 1.4;
      if (score < bestDelta) {
        bestDelta = score;
        bestIdx = i;
      }
    }
    if (bestIdx != _activeSection) {
      setState(() => _activeSection = bestIdx);
    }
  }

  Future<void> _loadMeta() async {
    final gameId = widget.game.id;
    if (gameId == null) return;
    final services = tryAppServices();
    try {
      final loadedSources = widget.loadSources != null
          ? await widget.loadSources!(gameId)
          : (services != null
              ? await services.repo.sourcesOf(gameId)
              : const <SourceRecord>[]);
      final loadedTags = widget.loadTags != null
          ? await widget.loadTags!(gameId)
          : (services != null
              ? await services.repo.tagsOf(gameId)
              : const <TagItem>[]);
      if (!mounted) return;
      setState(() {
        _sources = loadedSources;
        if (!_tagsDirty) {
          _tags = List<TagItem>.from(loadedTags);
        } else {
          for (final t in loadedTags) {
            if (!_tags.any(
                (cur) => cur.name.toLowerCase() == t.name.toLowerCase())) {
              _tags.add(t);
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _reloadAfterScrape() async {
    final gameId = widget.game.id;
    final services = tryAppServices();
    if (gameId == null || services == null) return;
    final fresh = await services.repo.getGame(gameId);
    if (fresh == null || !mounted) return;
    _nameCtrl.text = fresh.name;
    _nameCnCtrl.text = fresh.nameCn;
    _aliasesCtrl.text = fresh.aliases.join(', ');
    _devCtrl.text = fresh.developer;
    _releaseCtrl.text = fresh.releaseDate;
    _summaryCtrl.text = fresh.summary;
    _coverCtrl.text = fresh.coverPath;
    _bgCtrl.text = fresh.backgroundUrl;
    setState(() {
      _nsfw = fresh.nsfw;
      _tagsDirty = false;
      _initialSnapshot = _snapshotSignature();
    });
    await _loadMeta();
  }

  void _scrollToSection(int index) {
    setState(() => _activeSection = index);
    final ctx = _sectionKeys[index].currentContext;
    if (ctx != null) {
      final disableAnim = fluentAnimationsDisabled(context);
      Scrollable.ensureVisible(
        ctx,
        duration: disableAnim ? Duration.zero : FluentMotion.standard,
        curve: FluentMotion.enterCurve,
        alignment: 0.04,
      );
    }
  }

  String _toStoredMediaPath(String picked) {
    try {
      if (tryAppServices() != null) {
        return MediaPaths.instance.toStored(picked);
      }
    } catch (_) {}
    return picked;
  }

  List<String> _imageCandidates() {
    final urls =
        CoverCandidates.fromSources(_sources).map((c) => c.url).toList();
    for (final v in [_coverCtrl.text.trim(), _bgCtrl.text.trim()]) {
      if (v.isNotEmpty && !urls.contains(v)) {
        urls.add(v);
      }
    }
    return urls;
  }

  List<String> _parseAliases(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[,，、\r\n]+'))) {
      final t = part.trim();
      if (t.isNotEmpty && seen.add(t)) {
        out.add(t);
      }
    }
    return out;
  }

  void _addTag() {
    final raw = _tagInputCtrl.text.trim();
    if (raw.isEmpty) return;
    final exists =
        _tags.any((t) => t.name.toLowerCase() == raw.toLowerCase());
    if (exists) {
      showNotice('标签「#$raw」已存在');
    } else {
      setState(() {
        _tags.add(TagItem(name: raw, weight: 1.0, source: 'manual'));
        _tagsDirty = true;
      });
    }
    _tagInputCtrl.clear();
  }

  void _removeTag(TagItem tag) {
    setState(() {
      _tags.removeWhere((t) => t.name == tag.name && t.source == tag.source);
      _tagsDirty = true;
    });
  }

  Future<void> _pickExe() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: '选择游戏可执行文件',
      type: FileType.custom,
      allowedExtensions: const ['exe', 'bat', 'cmd', 'lnk'],
    );
    final path = res?.files.single.path;
    if (path != null && path.isNotEmpty && mounted) {
      setState(() {
        _exeCtrl.text = path;
        if (_dirCtrl.text.trim().isEmpty) {
          final sep = path.contains('\\') ? '\\' : '/';
          final idx = path.lastIndexOf(sep);
          if (idx > 0) {
            _dirCtrl.text = path.substring(0, idx);
          }
        }
      });
    }
  }

  Future<void> _pickDirectory(TextEditingController target, String title) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: title);
    if (dir != null && dir.isNotEmpty && mounted) {
      setState(() => target.text = dir);
    }
  }

  void _autoDetectExe() {
    final dir = _dirCtrl.text.trim();
    if (dir.isEmpty) {
      showNotice('请先设置游戏目录', error: true);
      return;
    }
    final detected = GameLauncher.detectExecutable(dir);
    if (!mounted) return;
    if (detected.isEmpty) {
      showNotice('未在该目录中找到可识别的启动程序', error: true);
    } else {
      setState(() => _exeCtrl.text = detected);
      showNotice('已识别启动程序: $detected');
    }
  }

  Future<void> _detectSaveDir() async {
    final draft = _buildDraftGame();
    final picked = await showSaveDirPickerDialog(context, draft);
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _saveCtrl.text = picked);
    }
  }

  Future<void> _pickCoverImage() async {
    final picked = await showImagePickerDialog(
      context,
      title: '选择作品封面',
      candidates: _imageCandidates(),
      initialValue: _coverCtrl.text.trim().isEmpty ? null : _coverCtrl.text.trim(),
      aspectRatio: 2 / 3,
    );
    if (picked != null && mounted) {
      _coverCtrl.text = _toStoredMediaPath(picked);
    }
  }

  Future<void> _pickBgImage() async {
    final picked = await showImagePickerDialog(
      context,
      title: '选择详情背景图',
      candidates: _imageCandidates(),
      initialValue: _bgCtrl.text.trim().isEmpty ? null : _bgCtrl.text.trim(),
      aspectRatio: 16 / 9,
    );
    if (picked != null && mounted) {
      _bgCtrl.text = _toStoredMediaPath(picked);
    }
  }

  Future<void> _openScrape() async {
    if (_isDirty) {
      final proceed = await showFluentConfirmDialog(
        context,
        title: '重新搜刮元信息',
        content: '搜刮结果将覆盖当前弹窗中的名称、简介、标签与封面。是否继续？',
        confirmLabel: '继续搜刮',
      );
      if (!proceed || !mounted) return;
    }
    final draft = _buildDraftGame();
    final ok = widget.onScrape != null
        ? await widget.onScrape!(context, draft)
        : await showScrapeSearchDialog(context, widget.ref, draft);
    if (ok && mounted) {
      await _reloadAfterScrape();
    }
  }

  Future<void> _openSaveBackups() async {
    final draft = _buildDraftGame();
    await showSaveBackupDialog(context, widget.ref, draft);
    if (mounted && draft.savePath != _saveCtrl.text.trim()) {
      setState(() => _saveCtrl.text = draft.savePath);
    }
  }

  Future<void> _requestCancel() async {
    if (_saving) return;
    if (_isDirty) {
      final discard = await showFluentConfirmDialog(
        context,
        title: '放弃未保存的修改',
        content: '当前表单有尚未保存的更改，确定放弃并关闭吗？',
        confirmLabel: '放弃修改',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    Navigator.of(context).pop(false);
  }

  Game _buildDraftGame() {
    return Game(
      id: widget.game.id,
      name: _nameCtrl.text.trim(),
      nameCn: _nameCnCtrl.text.trim(),
      aliases: _parseAliases(_aliasesCtrl.text),
      coverPath: _coverCtrl.text.trim(),
      developer: _devCtrl.text.trim(),
      releaseDate: _releaseCtrl.text.trim(),
      summary: _summaryCtrl.text.trim(),
      nsfw: _nsfw,
      playStatus: _playStatus,
      userRating: widget.game.userRating,
      userReview: widget.game.userReview,
      exePath: _exeCtrl.text.trim(),
      directory: _dirCtrl.text.trim(),
      isFavorite: _isFavorite,
      totalSeconds: widget.game.totalSeconds,
      firstPlayedAt: widget.game.firstPlayedAt,
      lastPlayedAt: widget.game.lastPlayedAt,
      screenshots: widget.game.screenshots,
      backgroundUrl: _bgCtrl.text.trim(),
      localeMode: widget.game.localeMode,
      savePath: _saveCtrl.text.trim(),
    )..sessionCount = widget.game.sessionCount;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '作品原名不能为空');
      _scrollToSection(0);
      _nameFocus.requestFocus();
      showNotice('作品原名不能为空', error: true);
      return;
    }

    setState(() => _saving = true);
    final updated = _buildDraftGame();
    final services = tryAppServices();

    try {
      if (widget.onSave != null) {
        await widget.onSave!(updated);
      } else if (services != null) {
        await services.repo.updateGame(updated);
      }

      if (services != null &&
          updated.id != null &&
          _tagsDirty &&
          widget.onSave == null) {
        await services.repo.setTags(updated.id!, _tags);
      }

      if (updated.id != null) {
        widget.ref.invalidate(gameProvider(updated.id!));
        widget.ref.invalidate(gameTagsProvider(updated.id!));
        widget.ref.invalidate(gameSourcesProvider(updated.id!));
      }
      bumpLibrary(widget.ref);
      showNotice('已保存作品信息');

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      showNotice('保存失败: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): _requestCancel,
      },
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 720),
        title: Row(
          children: [
            Icon(FluentIcons.edit_16_regular, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '编辑作品信息 · ${widget.game.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: _saving ? null : _openScrape,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.search_16_regular, size: 14),
                  SizedBox(width: 6),
                  Text('重新搜刮'),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAnchorBar(theme, accent),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expander(
                      key: _sectionKeys[0],
                      initiallyExpanded: true,
                      leading: const Icon(FluentIcons.info_16_regular, size: 16),
                      header: const Text('基本信息'),
                      content: _buildBasicInfoSection(theme),
                    ),
                    const SizedBox(height: 10),
                    Expander(
                      key: _sectionKeys[1],
                      initiallyExpanded: true,
                      leading: const Icon(FluentIcons.play_16_regular, size: 16),
                      header: const Text('启动与目录'),
                      content: _buildLaunchSection(),
                    ),
                    const SizedBox(height: 10),
                    Expander(
                      key: _sectionKeys[2],
                      initiallyExpanded: true,
                      leading:
                          const Icon(FluentIcons.archive_16_regular, size: 16),
                      header: const Text('存档与备份'),
                      content: _buildSaveSection(),
                    ),
                    const SizedBox(height: 10),
                    Expander(
                      key: _sectionKeys[3],
                      initiallyExpanded: true,
                      leading: const Icon(FluentIcons.image_16_regular, size: 16),
                      header: const Text('视觉封面'),
                      content: _buildMediaSection(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          Button(
            onPressed: _saving ? null : _requestCancel,
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text('保存中…'),
                    ],
                  )
                : const Text('保存修改'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnchorBar(FluentThemeData theme, Color accent) {
    final res = theme.resources;
    final disableAnim = fluentAnimationsDisabled(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: res.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: res.cardStrokeColorDefault),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _sections.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Semantics(
                button: true,
                selected: _activeSection == i,
                label: _sections[i].$1,
                child: HoverButton(
                  key: _sections[i].$3,
                  cursor: SystemMouseCursors.click,
                  onPressed: () => _scrollToSection(i),
                  builder: (context, states) {
                    final active = _activeSection == i;
                    final bg = active
                        ? accent.withValues(alpha: 0.14)
                        : states.isPressed
                            ? theme.subtlePressed
                            : states.isHovered
                                ? theme.subtleHover
                                : Colors.transparent;
                    return FocusBorder(
                      focused: states.isFocused,
                      renderOutside: false,
                      child: AnimatedContainer(
                        duration:
                            disableAnim ? Duration.zero : FluentMotion.fast,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: active
                                ? accent.withValues(alpha: 0.45)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _sections[i].$2,
                              size: 14,
                              color: active ? accent : theme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _sections[i].$1,
                              style: theme.typography.body?.copyWith(
                                fontSize: 13,
                                fontWeight:
                                    active ? FontWeight.w600 : FontWeight.w400,
                                color: active ? accent : theme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection(FluentThemeData theme) {
    final res = theme.resources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InfoLabel(
                label: '原名 *',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextBox(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      placeholder: '日语 / 英语原名',
                      highlightColor: _nameError != null ? theme.dangerInk : null,
                      unfocusedColor:
                          _nameError != null ? theme.dangerInk : null,
                    ),
                    if (_nameError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _nameError!,
                        style: theme.typography.caption?.copyWith(
                          color: theme.dangerInk,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InfoLabel(
                label: '中文译名',
                child: TextBox(
                  key: const ValueKey('edit-name-cn'),
                  controller: _nameCnCtrl,
                  placeholder: '中文译名',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InfoLabel(
          label: '别名（逗号 / 顿号 / 换行分隔）',
          child: TextBox(
            key: const ValueKey('edit-aliases'),
            controller: _aliasesCtrl,
            placeholder: '例如：CLANNAD, クラナド',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InfoLabel(
                label: '开发商 / 社团',
                child: TextBox(
                  controller: _devCtrl,
                  placeholder: '开发商名称',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InfoLabel(
                label: '发售日期',
                child: TextBox(
                  controller: _releaseCtrl,
                  placeholder: 'YYYY-MM-DD',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InfoLabel(
                label: '游玩状态',
                child: ComboBox<PlayStatus>(
                  isExpanded: true,
                  value: _playStatus,
                  items: PlayStatus.values
                      .map(
                        (s) => ComboBoxItem<PlayStatus>(
                          value: s,
                          child: Text(s.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _playStatus = v);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            ToggleSwitch(
              key: const ValueKey('edit-nsfw-switch'),
              checked: _nsfw,
              content: const Text('R18 / 成人内容'),
              onChanged: (v) => setState(() => _nsfw = v),
            ),
            ToggleSwitch(
              checked: _isFavorite,
              content: const Text('收藏作品'),
              onChanged: (v) => setState(() => _isFavorite = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InfoLabel(
          label: '作品简介',
          child: TextBox(
            controller: _summaryCtrl,
            placeholder: '剧情介绍、版本说明或个人备注…',
            minLines: 3,
            maxLines: 6,
          ),
        ),
        const SizedBox(height: 12),
        Text('标签管理', style: theme.typography.bodyStrong),
        const SizedBox(height: 6),
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _tags
                  .map(
                    (t) => Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        10,
                        2,
                        2,
                        2,
                      ),
                      decoration: BoxDecoration(
                        color: res.controlFillColorDefault,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: res.cardStrokeColorDefault),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '#${t.name}',
                            style: theme.typography.caption,
                          ),
                          Tooltip(
                            message: '移除标签「#${t.name}」',
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: IconButton(
                                icon: Icon(
                                  FluentIcons.dismiss_12_regular,
                                  size: 11,
                                  color: theme.textSecondary,
                                ),
                                onPressed: () => _removeTag(t),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextBox(
                controller: _tagInputCtrl,
                placeholder: '新增标签（回车或点击添加）',
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: _addTag,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.add_16_regular, size: 14),
                  SizedBox(width: 4),
                  Text('添加标签'),
                ],
              ),
            ),
          ],
        ),
        if (_sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '已关联数据源',
            style:
                theme.typography.caption?.copyWith(color: theme.textSecondary),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _sources
                .map(
                  (s) => FluentBadge(
                    text:
                        '${KisakiSources.labels[s.source] ?? s.source}: ${s.sourceId}',
                    icon: FluentIcons.database_16_regular,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildLaunchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoLabel(
          label: '游戏目录',
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _dirCtrl,
                  placeholder: r'例如：D:\Games\Clannad',
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: () => _pickDirectory(_dirCtrl, '选择游戏安装目录'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.folder_open_16_regular, size: 14),
                    SizedBox(width: 4),
                    Text('选择目录'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        InfoLabel(
          label: '可执行文件 (EXE)',
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _exeCtrl,
                  placeholder: r'例如：D:\Games\Clannad\SiglusEngine.exe',
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _pickExe,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.document_16_regular, size: 14),
                    SizedBox(width: 4),
                    Text('浏览 EXE'),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Button(
                onPressed: _autoDetectExe,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.wand_16_regular, size: 14),
                    SizedBox(width: 4),
                    Text('自动识别'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaveSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoLabel(
          label: '存档目录路径',
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _saveCtrl,
                  placeholder: '定位游戏本地存档所在目录，用于一键备份与恢复',
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: () => _pickDirectory(_saveCtrl, '选择存档目录'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.folder_open_16_regular, size: 14),
                    SizedBox(width: 4),
                    Text('浏览目录'),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Button(
                onPressed: _detectSaveDir,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.wand_16_regular, size: 14),
                    SizedBox(width: 4),
                    Text('智能探测'),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.game.id != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Button(
              onPressed: _openSaveBackups,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.archive_16_regular, size: 14),
                  SizedBox(width: 6),
                  Text('打开存档快照管理'),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MediaFieldRow(
          label: '封面图片路径 / URL',
          controller: _coverCtrl,
          previewWidth: 56,
          previewHeight: 80,
          buttonLabel: '选择封面',
          onPick: _pickCoverImage,
        ),
        const SizedBox(height: 12),
        _MediaFieldRow(
          label: '详情页背景图路径 / URL',
          controller: _bgCtrl,
          previewWidth: 104,
          previewHeight: 62,
          buttonLabel: '选择背景',
          onPick: _pickBgImage,
        ),
      ],
    );
  }
}

class _MediaFieldRow extends StatelessWidget {
  const _MediaFieldRow({
    required this.label,
    required this.controller,
    required this.previewWidth,
    required this.previewHeight,
    required this.buttonLabel,
    required this.onPick,
  });

  final String label;
  final TextEditingController controller;
  final double previewWidth;
  final double previewHeight;
  final String buttonLabel;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final res = theme.resources;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, val, _) {
        final path = val.text.trim();
        final validPreview = path.isNotEmpty &&
            (path.startsWith('http://') ||
                path.startsWith('https://') ||
                (!'http://'.startsWith(path.toLowerCase()) &&
                    !'https://'.startsWith(path.toLowerCase())));

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Tooltip(
                message: path.isEmpty ? '点击选择图片' : '点击查看大图',
                child: HoverButton(
                  cursor: SystemMouseCursors.click,
                  onPressed: path.isEmpty
                      ? onPick
                      : () => showFluentLightboxDialog(
                            context,
                            pathOrUrl: path,
                            title: label,
                          ),
                  builder: (context, states) => FocusBorder(
                    focused: states.isFocused,
                    renderOutside: false,
                    child: Container(
                      width: previewWidth,
                      height: previewHeight,
                      decoration: BoxDecoration(
                        color: res.cardBackgroundFillColorDefault,
                        border: Border.all(
                          color: states.isHovered
                              ? theme.accentInk
                              : res.cardStrokeColorDefault,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: !validPreview
                          ? Icon(
                              FluentIcons.image_24_regular,
                              size: 20,
                              color: theme.textTertiary,
                            )
                          : FluentCoverImage(
                              pathOrUrl: path,
                              width: previewWidth,
                              height: previewHeight,
                              radius: 5,
                              allowRevealOnHover: false,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InfoLabel(
                label: label,
                child: Row(
                  children: [
                    Expanded(
                      child: TextBox(
                        controller: controller,
                        placeholder: '本地路径或 http(s):// 图片链接',
                        suffix: path.isNotEmpty
                            ? Tooltip(
                                message: '清空',
                                child: IconButton(
                                  icon: const Icon(
                                    FluentIcons.dismiss_12_regular,
                                    size: 12,
                                  ),
                                  onPressed: controller.clear,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      onPressed: onPick,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.image_16_regular, size: 14),
                          const SizedBox(width: 4),
                          Text(buttonLabel),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
