/// 评分评价页：本地保存 + 可选同步上传到 Bangumi / VNDB / Hikarinagi。
///
/// 全屏路由页：保留 Scaffold + WindowDragBar（桌面拖动），内容卡片统一走
/// kit 的 KCard / KSectionTitle / KRow，视觉与其它页面一致。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/title_bar.dart';
import '../../app_services.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../services/upload/upload.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/notifications.dart';

class RateDialog extends ConsumerStatefulWidget {
  final Game game;
  final List<SourceRecord> sources;
  const RateDialog({super.key, required this.game, required this.sources});

  @override
  ConsumerState<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends ConsumerState<RateDialog> {
  /// 0-10（5 星 × 2 分），0 = 未评分
  late double _rating = widget.game.userRating;
  late final TextEditingController _review =
      TextEditingController(text: widget.game.userReview);
  final Map<String, bool> _uploadTo = {};

  /// 各平台是否已配置 Token（预取一次，避免每帧发 FutureBuilder）
  final Map<String, bool> _logged = {};
  bool _uploading = false;
  final List<String> _results = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    for (final (platform, _, _) in _uploadable) {
      final token = await AppServices.I.accounts.token(platform);
      if (!mounted) return;
      setState(() => _logged[platform] = token != null);
    }
  }

  /// 可上传平台：本地已登记该平台条目（才有 sourceId 可写）
  List<(String, String, SourceRecord)> get _uploadable {
    final out = <(String, String, SourceRecord)>[];
    for (final (platform, label) in [
      (KisakiSources.bangumi, 'Bangumi'),
      (KisakiSources.vndb, 'VNDB'),
      (KisakiSources.hikarinagi, 'Hikarinagi'),
    ]) {
      final src = _sourceFor(platform);
      if (src != null) out.add((platform, label, src));
    }
    return out;
  }

  SourceRecord? _sourceFor(String platform) {
    for (final s in widget.sources) {
      if (s.source == platform) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final targets = _uploadable;

    return Scaffold(
      backgroundColor: dark ? KisakiColors.nightBg : KisakiColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部拖动条：横跨整宽，空白处即可拖动窗口
            const AppTitleBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    28, 0, 28, MediaQuery.of(context).viewInsets.bottom + 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---------- 标题栏 ----------
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('评分与评价', style: Type.display),
                              SizedBox(height: Gap.xxs),
                              Text(widget.game.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Type.caption
                                      .copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        KIconAction(
                          icon: Icons.close_rounded,
                          tooltip: '关闭',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    SizedBox(height: Gap.xl),
                    // ---------- 评分 + 评价 ----------
                    KCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Column(
                              children: [
                                RatingBar(
                                  value: _rating,
                                  size: 40,
                                  onChanged: (v) =>
                                      setState(() => _rating = v.clamp(0, 10)),
                                ),
                                SizedBox(height: Gap.xs),
                                AnimatedCount(
                                  text: _rating <= 0
                                      ? '未评分'
                                      // 精确到 0.1（存储为 REAL，无需迁移）
                                      : '${_rating.toStringAsFixed(1)} / 10',
                                  style: Type.numeric.copyWith(
                                      fontSize: 18, color: scheme.primary),
                                ),
                                SizedBox(height: Gap.xs),
                                // 0.1 精度的微调：滑块 + ±0.1 按钮
                                Row(
                                  children: [
                                    KIconAction(
                                      icon: Icons.remove_rounded,
                                      tooltip: '减 0.1',
                                      onTap: () => setState(() =>
                                          _rating =
                                              (_rating - 0.1).clamp(0, 10)),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        value: _rating.clamp(0, 10),
                                        min: 0,
                                        max: 10,
                                        // 100 段 = 0.1 步进
                                        divisions: 100,
                                        label: _rating.toStringAsFixed(1),
                                        onChanged: (v) => setState(() =>
                                            _rating =
                                                (v * 10).round() / 10),
                                      ),
                                    ),
                                    KIconAction(
                                      icon: Icons.add_rounded,
                                      tooltip: '加 0.1',
                                      onTap: () => setState(() =>
                                          _rating =
                                              (_rating + 0.1).clamp(0, 10)),
                                    ),
                                  ],
                                ),
                                SizedBox(height: Gap.xxs),
                                Text(
                                  _rating <= 0
                                      ? '点星星快速评分，或拖动滑块 / 用 ± 微调（精确到 0.1）'
                                      : '精确到 0.1；再次点击同一颗星可清零',
                                  style: Type.caption.copyWith(
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: Gap.lg),
                          TextField(
                            controller: _review,
                            maxLines: 5,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                                hintText: '写下你的游玩感受…',
                                alignLabelWithHint: true),
                          ),
                        ],
                      ),
                    ),
                    // ---------- 同步上传 ----------
                    if (targets.isNotEmpty) ...[
                      SizedBox(height: Gap.xl),
                      const KSectionTitle('同步上传到'),
                      KCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Gap.lg, vertical: Gap.xs),
                        child: Column(
                          children: [
                            for (var i = 0; i < targets.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _UploadSwitch(
                                label: targets[i].$2,
                                logged: _logged[targets[i].$1] ?? false,
                                value: _uploadTo[targets[i].$1] ?? false,
                                onChanged: (v) => setState(
                                    () => _uploadTo[targets[i].$1] = v),
                              ),
                            ],
                            if (_results.isNotEmpty) ...[
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: Gap.sm),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final r in _results)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          children: [
                                            Icon(
                                                Icons.info_outline_rounded,
                                                size: 14,
                                                color: scheme.onSurfaceVariant),
                                            SizedBox(width: Gap.sm),
                                            Expanded(
                                              child: Text(r,
                                                  style: Type.caption.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant)),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                            top: Gap.sm, left: Gap.xs),
                        child: Text(
                          '未配置 Token 的平台无法勾选，可到「设置 → 账号」填入后重试；'
                          '评分会先保存在本地，再上传到勾选的平台。',
                          style: Type.caption
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                    SizedBox(height: Gap.xl),
                    // ---------- 操作 ----------
                    Row(
                      children: [
                        KPill(
                          label: '取消',
                          filled: false,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        KPill(
                          label: _uploading ? '上传中…' : '保存',
                          icon: _uploading ? null : Icons.check_rounded,
                          onTap: _uploading ? null : _save,
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
    );
  }

  Future<void> _save() async {
    final game = widget.game;
    // 评分范围保护（0-10）
    // 保留 0.1 精度：四舍五入到 1 位小数，避免浮点尾数（如 7.300000000001）
    game.userRating = ((_rating.clamp(0, 10)) * 10).round() / 10;
    game.userReview = _review.text.trim();
    if (game.userRating > 0 && game.playStatus == PlayStatus.wish) {
      game.playStatus = PlayStatus.played;
    }
    await AppServices.I.repo.updateGame(game);

    // 同步上传（勾选且已配置 Token 的平台）
    final targets =
        _uploadTo.entries.where((e) => e.value).map((e) => e.key).toList();
    if (targets.isEmpty) {
      if (!mounted) return;
      showNotice('评分已保存');
      Navigator.of(context).pop();
      return;
    }

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
        rating: game.userRating,
        comment: game.userReview,
      );
      _results
          .add('${KisakiSources.labels[platform] ?? platform}：${result.message}');
    }
    if (mounted) setState(() => _uploading = false);
    if (!mounted) return;
    showNotice(_results.isEmpty ? '已保存评分' : _results.join('；'));
    Navigator.of(context).pop();
  }
}

/// 单个平台的同步开关：未配置 Token 时禁用并给出说明。
class _UploadSwitch extends StatelessWidget {
  final String label;
  final bool logged;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _UploadSwitch({
    required this.label,
    required this.logged,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      secondary: Icon(
        logged ? Icons.check_circle_rounded : Icons.person_off_rounded,
        size: 18,
        color: logged ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(label,
          style: Type.body.copyWith(
              fontWeight: FontWeight.w600,
              color: logged ? null : scheme.onSurfaceVariant)),
      subtitle: Text(
        logged ? '保存后同步评分与评价' : '未配置 Token（设置 → 账号）',
        style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
      ),
      value: logged && value,
      onChanged: logged ? onChanged : null,
    );
  }
}
