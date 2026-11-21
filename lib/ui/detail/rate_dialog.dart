import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../services/upload/upload.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import '../library/game_actions.dart';

const _uploadableSources = <String>{
  KisakiSources.bangumi,
  KisakiSources.vndb,
  KisakiSources.hikarinagi,
  KisakiSources.kun,
};

/// 打开 Fluent 2 作品评分与短评同步对话框。
Future<bool> showRateGameDialog(
  BuildContext context,
  WidgetRef ref,
  Game game, {
  List<SourceRecord>? sources,
  Future<void> Function(Game game)? onSave,
}) async {
  final hasTheme = FluentTheme.maybeOf(context) != null;
  final hasLoc =
      Localizations.of<FluentLocalizations>(context, FluentLocalizations) !=
          null;

  if (hasTheme && hasLoc) {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RateGameDialog(
        ref: ref,
        game: game,
        initialSources: sources,
        onSave: onSave,
      ),
    );
    return result ?? false;
  }

  final result = await Navigator.of(context).push<bool>(
    RawDialogRoute<bool>(
      barrierDismissible: true,
      barrierLabel: '关闭评分弹窗',
      barrierColor: const Color(0x7A000000),
      pageBuilder: (dialogCtx, _, __) => ensureFluentScope(
        context,
        Center(
          child: _RateGameDialog(
            ref: ref,
            game: game,
            initialSources: sources,
            onSave: onSave,
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

class _RateGameDialog extends StatefulWidget {
  const _RateGameDialog({
    required this.ref,
    required this.game,
    this.initialSources,
    this.onSave,
  });

  final WidgetRef ref;
  final Game game;
  final List<SourceRecord>? initialSources;
  final Future<void> Function(Game game)? onSave;

  @override
  State<_RateGameDialog> createState() => _RateGameDialogState();
}

class _RateGameDialogState extends State<_RateGameDialog> {
  late double _rating;
  late double _initialRating;
  late final TextEditingController _reviewCtrl;
  late bool _markAsPlayed;
  List<SourceRecord> _sources = const [];
  final Map<String, String> _tokens = {};
  final Map<String, bool> _syncEnabled = {};
  bool _loadingSources = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initialRating = (widget.game.userRating * 10).round() / 10.0;
    _rating = _initialRating;
    _reviewCtrl = TextEditingController(text: widget.game.userReview);
    _markAsPlayed = widget.game.playStatus == PlayStatus.wish;
    if (widget.initialSources != null) {
      _applySources(widget.initialSources!);
    } else {
      _loadSources();
    }
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _rating != _initialRating || _reviewCtrl.text != widget.game.userReview;

  Future<void> _requestCancel() async {
    if (_saving) return;
    if (_isDirty) {
      final discard = await showFluentConfirmDialog(
        context,
        title: '放弃未保存的评价',
        content: '评分或短评尚未保存，确定放弃吗？',
        confirmLabel: '放弃',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    Navigator.of(context).pop(false);
  }

  Future<void> _loadSources() async {
    final services = tryAppServices();
    final gameId = widget.game.id;
    if (services == null || gameId == null) return;
    setState(() => _loadingSources = true);
    try {
      final loaded = await services.repo.sourcesOf(gameId);
      await _applySources(loaded);
      if (mounted) setState(() => _loadingSources = false);
    } catch (_) {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  Future<void> _applySources(List<SourceRecord> list) async {
    final services = tryAppServices();
    final tokens = <String, String>{};
    final syncMap = <String, bool>{};
    for (final s in list) {
      if (!_uploadableSources.contains(s.source)) continue;
      final token =
          services != null ? await services.accounts.token(s.source) : null;
      if (token != null && token.isNotEmpty) {
        tokens[s.source] = token;
        syncMap[s.source] = true;
      } else {
        syncMap[s.source] = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _sources = list;
      _tokens
        ..clear()
        ..addAll(tokens);
      _syncEnabled
        ..clear()
        ..addAll(syncMap);
    });
  }

  void _nudge(double delta) {
    setState(() {
      final next = ((_rating + delta) * 10).round() / 10.0;
      _rating = next.clamp(0.0, 10.0);
    });
  }

  String _scoreText() {
    if (_rating <= 0) return '未评分';
    return '${_rating.toStringAsFixed(1)} / 10';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final services = tryAppServices();
    final rounded = (_rating * 10).round() / 10.0;
    final double finalRating = rounded <= 0 ? 0.0 : rounded;
    final String finalReview = _reviewCtrl.text.trim();

    final nextStatus = (finalRating > 0 &&
            widget.game.playStatus == PlayStatus.wish &&
            _markAsPlayed)
        ? PlayStatus.played
        : widget.game.playStatus;
    final updated = Game(
      id: widget.game.id,
      name: widget.game.name,
      nameCn: widget.game.nameCn,
      aliases: List<String>.of(widget.game.aliases),
      coverPath: widget.game.coverPath,
      developer: widget.game.developer,
      releaseDate: widget.game.releaseDate,
      summary: widget.game.summary,
      nsfw: widget.game.nsfw,
      playStatus: nextStatus,
      userRating: finalRating,
      userReview: finalReview,
      exePath: widget.game.exePath,
      directory: widget.game.directory,
      launchType: widget.game.launchType,
      isFavorite: widget.game.isFavorite,
      totalSeconds: widget.game.totalSeconds,
      createdAt: widget.game.createdAt,
      updatedAt: widget.game.updatedAt,
      firstPlayedAt: widget.game.firstPlayedAt,
      lastPlayedAt: widget.game.lastPlayedAt,
      screenshots: List<String>.of(widget.game.screenshots),
      backgroundUrl: widget.game.backgroundUrl,
      localeMode: widget.game.localeMode,
      savePath: widget.game.savePath,
      deviceId: widget.game.deviceId,
      relPath: widget.game.relPath,
      dirName: widget.game.dirName,
    )..sessionCount = widget.game.sessionCount;

    try {
      if (widget.onSave != null) {
        await widget.onSave!(updated);
      } else if (services != null) {
        await services.repo.updateGame(updated);
      }

      widget.game
        ..userRating = finalRating
        ..userReview = finalReview
        ..playStatus = nextStatus;

      final synced = <String>[];
      final failed = <String>[];

      if (services != null && finalRating > 0 && _syncEnabled.isNotEmpty) {
        final uploader = ReviewUploader(proxy: services.fetcher.proxy);
        for (final s in _sources) {
          if (_syncEnabled[s.source] != true) continue;
          final token =
              _tokens[s.source] ?? await services.accounts.token(s.source);
          if (token == null || token.isEmpty) continue;
          final res = await uploader.upload(
            platform: s.source,
            token: token,
            source: s,
            rating: finalRating,
            comment: finalReview,
          );
          final label = KisakiSources.labels[s.source] ?? s.source;
          if (res.ok) {
            synced.add(label);
          } else {
            failed.add('$label(${res.message})');
          }
        }
      }

      if (mounted) {
        if (updated.id != null) {
          widget.ref.invalidate(gameProvider(updated.id!));
          widget.ref.invalidate(gameSourcesProvider(updated.id!));
        }
        bumpLibrary(widget.ref);
      }

      final buffer = StringBuffer('已保存评分');
      if (synced.isNotEmpty) {
        buffer.write('，已同步到 ${synced.join('、')}');
      }
      if (failed.isNotEmpty) {
        buffer.write('；同步失败: ${failed.join('、')}');
      }
      showNotice(buffer.toString(), error: failed.isNotEmpty);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      showNotice('保存评分失败: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final mutedColor = theme.textSecondary;
    final syncable =
        _sources.where((s) => _uploadableSources.contains(s.source)).toList();

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 540),
      title: Row(
        children: [
          Icon(FluentIcons.star_20_regular, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '为《${widget.game.displayName}》评分',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FluentSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '我的评分',
                              style: theme.typography.caption?.copyWith(
                                color: mutedColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _scoreText(),
                              style: theme.typography.title?.copyWith(
                                color: _rating > 0 ? accent : mutedColor,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: '减少 0.1 分',
                        child: Button(
                          key: const ValueKey('rate-dec-btn'),
                          onPressed:
                              _rating <= 0 ? null : () => _nudge(-0.1),
                          child: const Text('-0.1'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: '增加 0.1 分',
                        child: Button(
                          key: const ValueKey('rate-inc-btn'),
                          onPressed:
                              _rating >= 10 ? null : () => _nudge(0.1),
                          child: const Text('+0.1'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 固定常驻防止从 0 -> 0.1 时按钮水平跳位误触清零
                      Tooltip(
                        message: '清除评分恢复未评状态',
                        child: Button(
                          onPressed: _rating > 0
                              ? () => setState(() => _rating = 0.0)
                              : null,
                          child: const Text('清零评分'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in const [6.0, 7.0, 8.0, 9.0, 10.0])
                        FluentBadge(
                          text: preset.toStringAsFixed(0),
                          selected: (_rating - preset).abs() < 0.05,
                          foreground: (_rating - preset).abs() < 0.05
                              ? theme.onAccentInk
                              : theme.textSecondary,
                          background: (_rating - preset).abs() < 0.05
                              ? accent
                              : null,
                          onTap: () => setState(() => _rating = preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Slider(
                    value: _rating.clamp(0.0, 10.0),
                    min: 0.0,
                    max: 10.0,
                    divisions: 100,
                    label: _scoreText(),
                    onChanged: (v) =>
                        setState(() => _rating = (v * 10).round() / 10.0),
                  ),
                  const SizedBox(height: 4),
                  // 按滑块真实比例 (0% / 50% / 80% / 100%) 对齐刻度标签
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final tickStyle = theme.typography.caption?.copyWith(
                        color: mutedColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      );
                      return SizedBox(
                        height: 18,
                        width: w,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              child: Text('0.0 未评', style: tickStyle),
                            ),
                            Positioned(
                              left: (w * 0.50 - 24).clamp(0.0, w - 56),
                              child: Text('5.0 及格', style: tickStyle),
                            ),
                            Positioned(
                              left: (w * 0.80 - 24).clamp(0.0, w - 56),
                              child: Text('8.0 佳作', style: tickStyle),
                            ),
                            Positioned(
                              right: 0,
                              child: Text('10.0 神作', style: tickStyle),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (widget.game.playStatus == PlayStatus.wish && _rating > 0) ...[
              const SizedBox(height: 10),
              Checkbox(
                checked: _markAsPlayed,
                onChanged: (v) => setState(() => _markAsPlayed = v ?? true),
                content: const Text('保存评分后同时将游玩状态设为「已玩过」'),
              ),
            ],
            const SizedBox(height: 14),
            InfoLabel(
              label: '短评 / 游玩感想',
              child: TextBox(
                controller: _reviewCtrl,
                placeholder: '记录通关后的核心感受、剧本亮点或避雷点…',
                minLines: 3,
                maxLines: 5,
              ),
            ),
            if (_loadingSources) ...[
              const SizedBox(height: 14),
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: ProgressRing(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('正在加载平台关联状态…'),
                ],
              ),
            ] else if (syncable.isNotEmpty) ...[
              const SizedBox(height: 14),
              FluentSurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '同步评分到外部平台',
                          style: theme.typography.bodyStrong,
                        ),
                        if (_rating <= 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(请先拖动滑块评分)',
                            style: theme.typography.caption?.copyWith(
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...syncable.map((s) {
                      final token = _tokens[s.source];
                      final loggedIn = token != null && token.isNotEmpty;
                      final checked = _syncEnabled[s.source] ?? false;
                      final label = KisakiSources.labels[s.source] ?? s.source;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Checkbox(
                                checked: loggedIn && checked && _rating > 0,
                                onChanged: loggedIn && _rating > 0
                                    ? (val) => setState(
                                          () => _syncEnabled[s.source] =
                                              val ?? false,
                                        )
                                    : null,
                                content: Text(
                                  '$label (${s.sourceId})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (!loggedIn) ...[
                              const SizedBox(width: 8),
                              Text(
                                '未登录',
                                style: theme.typography.caption?.copyWith(
                                  color: mutedColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
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
              : const Text('保存评分'),
        ),
      ],
    );
  }
}
