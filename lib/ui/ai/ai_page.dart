/// Fluent 2 AI 助手页：游玩智能总结 + 个性化作品推荐 + 一键刮削入库。
///
/// 请求生命周期与状态由 app 级 `aiStateProvider`（非 autoDispose）持有，
/// 切换侧栏页签不会中断进行中的请求，也不会丢失已生成内容。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import '../../services/ai_service.dart';
import '../../state/ai_state.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../library/game_actions.dart';

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Widget _wrapFluent(BuildContext context, Widget child) {
    final hasTheme = FluentTheme.maybeOf(context) != null;
    final hasLoc = Localizations.of<FluentLocalizations>(
          context,
          FluentLocalizations,
        ) !=
        null;
    if (hasTheme && hasLoc) return child;
    var wrapped = child;
    if (!hasLoc) {
      wrapped = Localizations.override(
        context: context,
        delegates: const [FluentLocalizations.delegate],
        child: wrapped,
      );
    }
    if (!hasTheme) {
      wrapped = ensureFluentTheme(context, wrapped);
    }
    return wrapped;
  }

  @override
  Widget build(BuildContext context) {
    return _wrapFluent(
      context,
      Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final theme = FluentTheme.of(context);
    final ai = ref.watch(aiStateProvider);
    final disableAnim = fluentAnimationsDisabled(context);
    final notConfigured = ai.summaryError == kAiNotConfiguredMsg ||
        ai.recommendationsError == kAiNotConfiguredMsg;

    return ScaffoldPage(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI 助手', style: theme.typography.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    '基于你的游玩数据与标签词云生成智能总结与作品推荐；数据仅用于当次请求，不上传游戏文件',
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
            Button(
              onPressed: () => jumpToSettingsSection(ref, 3),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.settings_16_regular, size: 15),
                  SizedBox(width: 6),
                  Text('AI 设置'),
                ],
              ),
            ),
          ],
        ),
      ),
      content: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notConfigured) ...[
              InfoBar(
                title: const Text('尚未配置 AI 服务'),
                content: const Text(kAiNotConfiguredMsg),
                severity: InfoBarSeverity.warning,
                isLong: true,
                action: FilledButton(
                  onPressed: () => jumpToSettingsSection(ref, 3),
                  child: const Text('前往设置'),
                ),
              ).fluentEntrance(index: 0, disable: disableAnim),
              const SizedBox(height: 16),
            ],
            _SummaryCard(
              ai: ai,
              disableAnim: disableAnim,
              onGenerate: () =>
                  ref.read(aiStateProvider.notifier).generateSummary(),
              onOpenSettings: () => jumpToSettingsSection(ref, 3),
            ).fluentEntrance(index: 1, disable: disableAnim),
            const SizedBox(height: 16),
            _RecommendCard(
              ai: ai,
              disableAnim: disableAnim,
              onGenerate: () =>
                  ref.read(aiStateProvider.notifier).generateRecommendations(),
              onOpenSettings: () => jumpToSettingsSection(ref, 3),
            ).fluentEntrance(index: 2, disable: disableAnim),
            const SizedBox(height: 10),
            Text(
              '提示：AI 输出仅供参考；推荐卡片点击「加入」会先匹配多源元数据再入库。',
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final AiState ai;
  final bool disableAnim;
  final VoidCallback onGenerate;
  final VoidCallback onOpenSettings;

  const _SummaryCard({
    required this.ai,
    required this.disableAnim,
    required this.onGenerate,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasOtherError =
        ai.summaryError != null && ai.summaryError != kAiNotConfiguredMsg;

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            icon: FluentIcons.sparkle_20_regular,
            title: '游玩智能总结',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ai.hasSummary && !ai.summarizing) ...[
                  Button(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: ai.summary));
                      showNotice('已复制游玩总结');
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.copy_16_regular, size: 15),
                        SizedBox(width: 6),
                        Text('复制'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: ai.summarizing ? null : onGenerate,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ai.summarizing) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: ProgressRing(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        const Text('生成中…'),
                      ] else ...[
                        const Icon(FluentIcons.sparkle_16_regular, size: 15),
                        const SizedBox(width: 6),
                        const Text('生成总结'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (ai.summarizing) ...[
            _ProgressRow(text: '正在结合游玩数据生成总结…'),
            const SizedBox(height: 10),
            _ShimmerSkeletonBox(height: 18, disableAnim: disableAnim),
            const SizedBox(height: 8),
            _ShimmerSkeletonBox(height: 18, widthFactor: 0.85, disableAnim: disableAnim),
            const SizedBox(height: 8),
            _ShimmerSkeletonBox(height: 18, widthFactor: 0.65, disableAnim: disableAnim),
          ],
          if (hasOtherError) ...[
            if (ai.summarizing) const SizedBox(height: 12),
            InfoBar(
              title: const Text('总结生成失败'),
              content: Text(ai.summaryError!),
              severity: InfoBarSeverity.error,
              isLong: true,
              action: Button(
                onPressed: onOpenSettings,
                child: const Text('检查设置'),
              ),
            ),
          ],
          if (ai.hasSummary) ...[
            if (ai.summarizing || hasOtherError) const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.resources.cardStrokeColorDefault,
                ),
              ),
              child: SelectableText(
                ai.summary,
                style: theme.typography.body?.copyWith(height: 1.75),
              ),
            ),
          ],
          if (!ai.summarizing && !ai.hasSummary && ai.summaryError == null)
            Text(
              '点击「生成总结」，AI 将结合总时长、活跃天数、最常玩作品与标签词云生成一段总结点评。',
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendCard extends StatelessWidget {
  final AiState ai;
  final bool disableAnim;
  final VoidCallback onGenerate;
  final VoidCallback onOpenSettings;

  const _RecommendCard({
    required this.ai,
    required this.disableAnim,
    required this.onGenerate,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final recs = ai.recommendations;
    final hasOtherError = ai.recommendationsError != null &&
        ai.recommendationsError != kAiNotConfiguredMsg;

    return FluentSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FluentSectionHeader(
            icon: FluentIcons.wand_20_regular,
            title: '作品推荐',
            trailing: FilledButton(
              onPressed: ai.loadingRecommendations ? null : onGenerate,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ai.loadingRecommendations) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    const Text('推荐中…'),
                  ] else ...[
                    const Icon(
                      FluentIcons.compass_northwest_16_regular,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    const Text('获取推荐'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (ai.loadingRecommendations) ...[
            _ProgressRow(text: 'AI 正在挑选作品，并核对库内是否已有…'),
            const SizedBox(height: 12),
            _ShimmerSkeletonBox(height: 84, disableAnim: disableAnim),
            const SizedBox(height: 10),
            _ShimmerSkeletonBox(height: 84, disableAnim: disableAnim),
          ] else if (hasOtherError)
            InfoBar(
              title: const Text('推荐获取失败'),
              content: Text(ai.recommendationsError!),
              severity: InfoBarSeverity.error,
              isLong: true,
              action: Button(
                onPressed: onOpenSettings,
                child: const Text('检查设置'),
              ),
            )
          else if (recs.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 120,
              ),
              itemCount: recs.length,
              itemBuilder: (context, index) => _RecCard(rec: recs[index]),
            )
          else
            const FluentEmptyState(
              icon: FluentIcons.wand_20_regular,
              title: '还没有推荐结果',
              message: '点击右上角「获取推荐」，AI 将结合库内作品与高频标签推荐 6 部新作品；点击卡片即可搜刮入库。',
            ),
        ],
      ),
    );
  }
}

final Map<String, Future<ScrapedGame?>> _recCoverCache = {};

Future<ScrapedGame?> _coverFuture(String title) {
  final services = tryAppServices();
  if (services == null) return Future<ScrapedGame?>.value(null);
  return _recCoverCache.putIfAbsent(title, () async {
    try {
      return await services.fetcher.fetchBest(title);
    } catch (_) {
      return null;
    }
  });
}

class _RecCard extends ConsumerWidget {
  final AiRecommendation rec;
  const _RecCard({required this.rec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final st = ref.watch(aiStateProvider.select((s) => s.addStateOf(rec.title)));
    void add() => ref.read(aiStateProvider.notifier).addRecommendation(rec);

    return FutureBuilder<ScrapedGame?>(
      future: _coverFuture(rec.title),
      builder: (context, snap) {
        final scraped = snap.data;
        final coverUrl = scraped?.coverUrl ?? '';
        final nsfw = scraped?.nsfw ?? false;
        final rating = scraped?.rating ?? 0.0;
        final scoreText = rating > 0 ? rating.toStringAsFixed(1) : null;

        return FluentSurfaceCard(
          padding: const EdgeInsets.all(10),
          onTap: st == RecAddState.working ? null : add,
          child: Row(
            children: [
              FluentCoverImage(
                pathOrUrl: coverUrl,
                nsfw: nsfw,
                width: 56,
                height: 82,
                radius: 5,
                allowRevealOnHover: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      rec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.bodyStrong,
                    ),
                    if (nsfw || scoreText != null) ...[
                      const SizedBox(height: 3),
                      FluentR18ScoreRow(
                        nsfw: nsfw,
                        scoreText: scoreText,
                      ),
                    ],
                    if (rec.reason.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        rec.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.caption?.copyWith(
                          color: theme.inactiveColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (rec.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final t in rec.tags.take(3)) FluentBadge(text: t),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AddControl(state: st, onTap: add),
            ],
          ),
        );
      },
    );
  }
}

class _AddControl extends StatelessWidget {
  final RecAddState state;
  final VoidCallback onTap;

  const _AddControl({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return switch (state) {
      RecAddState.working => const SizedBox(
          width: 24,
          height: 24,
          child: ProgressRing(strokeWidth: 2.5),
        ),
      RecAddState.added => FluentStatusPill.label(
          label: '已入库',
          icon: FluentIcons.checkmark_circle_16_filled,
          color: isDark ? const Color(0xFF6CCB5F) : const Color(0xFF107C10),
        ),
      RecAddState.exists => FluentStatusPill.label(
          label: '已在库',
          icon: FluentIcons.library_20_regular,
          color: theme.accentColor.defaultBrushFor(theme.brightness),
        ),
      RecAddState.failed => Button(
          onPressed: onTap,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.arrow_clockwise_16_regular, size: 14),
              SizedBox(width: 4),
              Text('重试'),
            ],
          ),
        ),
      RecAddState.idle => FilledButton(
          onPressed: onTap,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.add_16_regular, size: 14),
              SizedBox(width: 4),
              Text('加入'),
            ],
          ),
        ),
    };
  }
}

class _ProgressRow extends StatelessWidget {
  final String text;
  const _ProgressRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: ProgressRing(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerSkeletonBox extends StatelessWidget {
  final double height;
  final double widthFactor;
  final bool disableAnim;

  const _ShimmerSkeletonBox({
    required this.height,
    this.widthFactor = 1.0,
    required this.disableAnim,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
      ).fluentShimmer(disable: disableAnim),
    );
  }
}
