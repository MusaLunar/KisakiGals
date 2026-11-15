import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../services/upload/upload.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../library/game_actions.dart';

const _uploadableSources = <String>{
  KisakiSources.bangumi,
  KisakiSources.vndb,
  KisakiSources.hikarinagi,
  KisakiSources.kun,
};

/// Opens a Fluent 2 dialog to rate [game], edit its short review, and optionally
/// sync the rating/comment to logged-in remote platforms.
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
      barrierColor: const Color(0x66000000),
      pageBuilder: (dialogCtx, _, __) => ensureFluentTheme(
        context,
        Localizations.override(
          context: dialogCtx,
          delegates: const [FluentLocalizations.delegate],
          child: Center(
            child: _RateGameDialog(
              ref: ref,
              game: game,
              initialSources: sources,
              onSave: onSave,
            ),
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
  late final TextEditingController _reviewCtrl;
  List<SourceRecord> _sources = const [];
  final Map<String, String> _tokens = {};
  final Map<String, bool> _syncEnabled = {};
  bool _loadingSources = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rating = (widget.game.userRating * 10).round() / 10.0;
    _reviewCtrl = TextEditingController(text: widget.game.userReview);
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
      final token = services != null ? await services.accounts.token(s.source) : null;
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

    final updated = widget.game
      ..userRating = finalRating
      ..userReview = finalReview
      ..playStatus = (finalRating > 0 && widget.game.playStatus == PlayStatus.wish)
          ? PlayStatus.played
          : widget.game.playStatus;

    try {
      if (widget.onSave != null) {
        await widget.onSave!(updated);
      } else if (services != null) {
        await services.repo.updateGame(updated);
      }

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

      if (updated.id != null) {
        widget.ref.invalidate(gameProvider(updated.id!));
        widget.ref.invalidate(gameSourcesProvider(updated.id!));
      }
      bumpLibrary(widget.ref);

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
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final mutedColor = theme.inactiveColor;
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
                      Button(
                        key: const ValueKey('rate-dec-btn'),
                        onPressed: _rating <= 0 ? null : () => _nudge(-0.1),
                        child: const Text('-0.1'),
                      ),
                      const SizedBox(width: 6),
                      Button(
                        key: const ValueKey('rate-inc-btn'),
                        onPressed: _rating >= 10 ? null : () => _nudge(0.1),
                        child: const Text('+0.1'),
                      ),
                      if (_rating > 0) ...[
                        const SizedBox(width: 6),
                        Button(
                          onPressed: () => setState(() => _rating = 0.0),
                          child: const Text('清零评分'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0.0 未评', style: theme.typography.caption),
                      Text('5.0 及格', style: theme.typography.caption),
                      Text('8.0 佳作', style: theme.typography.caption),
                      Text('10.0 神作', style: theme.typography.caption),
                    ],
                  ),
                ],
              ),
            ),
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
                    Text(
                      '同步评分到外部平台',
                      style: theme.typography.bodyStrong,
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
                            Checkbox(
                              checked: loggedIn && checked,
                              onChanged: loggedIn && _rating > 0
                                  ? (val) => setState(
                                        () =>
                                            _syncEnabled[s.source] = val ?? false,
                                      )
                                  : null,
                              content: Text('$label (${s.sourceId})'),
                            ),
                            const Spacer(),
                            if (!loggedIn)
                              Text(
                                '未登录',
                                style: theme.typography.caption?.copyWith(
                                  color: mutedColor,
                                ),
                              ),
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
