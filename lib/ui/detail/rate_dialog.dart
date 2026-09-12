/// 评分评价弹窗：本地保存 + 可选同步上传到 Bangumi / VNDB / Hikarinagi。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../services/upload/upload.dart';
import '../theme.dart';
import '../widgets/common.dart';

class RateDialog extends ConsumerStatefulWidget {
  final Game game;
  final List<SourceRecord> sources;
  const RateDialog({super.key, required this.game, required this.sources});

  @override
  ConsumerState<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends ConsumerState<RateDialog> {
  late double _rating = widget.game.userRating;
  late final TextEditingController _review =
      TextEditingController(text: widget.game.userReview);
  final Map<String, bool> _uploadTo = {};
  bool _uploading = false;
  final List<String> _results = [];

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  SourceRecord? _sourceFor(String platform) {
    try {
      return widget.sources.firstWhere((s) => s.source == platform);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final uploadTargets = [
      (KisakiSources.bangumi, 'Bangumi', _sourceFor(KisakiSources.bangumi)),
      (KisakiSources.vndb, 'VNDB', _sourceFor(KisakiSources.vndb)),
      (KisakiSources.hikarinagi, 'Hikarinagi', _sourceFor(KisakiSources.hikarinagi)),
    ].where((t) => t.$3 != null).toList();

    // 全屏页面：评分/评价输入区域更大（不再是底部抽屉）
    return Scaffold(
      backgroundColor: dark ? KisakiColors.nightBg : KisakiColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            const WindowDragBar(height: 24),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: dark ? KisakiColors.nightCard : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: EdgeInsets.only(
                    left: 28,
                    right: 28,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('评价「${widget.game.displayName}」',
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
                      const SizedBox(height: 12),
            Center(
              child: Column(
                children: [
                  RatingBar(
                    value: _rating,
                    size: 40,
                    onChanged: (v) => setState(() => _rating = v),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rating <= 0 ? '未评分' : '${_rating.toStringAsFixed(0)} / 10',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: scheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _review,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                  hintText: '写下你的游玩感受…',
                  alignLabelWithHint: true),
            ),
            if (uploadTargets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('同步上传到',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (platform, label, _) in uploadTargets)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: FutureBuilder<bool>(
                        future: _hasAccount(platform),
                        builder: (context, snap) {
                          final logged = snap.data ?? false;
                          return FilterChip(
                            label: Text(label),
                            selected: _uploadTo[platform] ?? false,
                            onSelected: logged
                                ? (v) => setState(
                                    () => _uploadTo[platform] = v)
                                : null,
                            avatar: Icon(
                              logged
                                  ? Icons.check_circle_rounded
                                  : Icons.person_off_rounded,
                              size: 15,
                              color: logged
                                  ? KisakiColors.pink
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            labelStyle: TextStyle(
                                fontSize: 12.5,
                                color: logged
                                    ? null
                                    : Theme.of(context).colorScheme.onSurfaceVariant),
                          );
                        },
                      ),
                    ),
                ],
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final r in _results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(r,
                                style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  ),
              ],
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消')),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _uploading ? null : _save,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<bool> _hasAccount(String platform) async =>
      await AppServices.I.accounts.token(platform) != null;

  Future<void> _save() async {
    final game = widget.game;
    game.userRating = _rating;
    game.userReview = _review.text.trim();
    if (_rating > 0 && game.playStatus == PlayStatus.wish) {
      game.playStatus = PlayStatus.played;
    }
    await AppServices.I.repo.updateGame(game);

    // 同步上传
    final targets =
        _uploadTo.entries.where((e) => e.value).map((e) => e.key).toList();
    if (targets.isNotEmpty) {
      setState(() => _uploading = true);
      final uploader = ReviewUploader(proxy: AppServices.I.fetcher.proxy);
      for (final platform in targets) {
        final token = await AppServices.I.accounts.token(platform);
        final src = _sourceFor(platform);
        if (token == null || src == null) continue;
        final result = await uploader.upload(
          platform: platform,
          token: token,
          source: src,
          rating: _rating,
          comment: _review.text.trim(),
        );
        _results
            .add('${KisakiSources.labels[platform] ?? platform}：${result.message}');
      }
      if (mounted) setState(() => _uploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_results.isEmpty
              ? '已保存评分'
              : _results.join('；'))));
      if (context.mounted) Navigator.of(context).pop();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('评分已保存')));
      Navigator.of(context).pop();
    }
  }
}
