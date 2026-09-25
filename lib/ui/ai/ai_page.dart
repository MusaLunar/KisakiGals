/// AI 助手页：结合游玩数据/词云生成智能总结与作品推荐，
/// 推荐结果以卡片展示，可一键刮削入库。
///
/// 本页只做「展示 + 触发」：生成状态、请求参数、游玩数据聚合全部在
/// `lib/state/ai_state.dart`（app 级 Provider，不 autoDispose）。
/// 因此切到别的页面时 AiPage 被销毁也不影响生成 —— 请求继续跑，完成后
/// 写入状态并弹全局通知，回到本页结果仍在。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../providers.dart';
import '../../scraping/scraped_game.dart';
import '../../services/ai_service.dart';
import '../../state/ai_state.dart';
import '../design.dart';
import '../kit.dart';
import '../theme.dart';

class AiPage extends ConsumerWidget {
  const AiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return KPage(
      title: 'AI 助手',
      subtitle: '基于你的游玩数据与标签词云生成总结与推荐；数据仅用于当次请求，不上传游戏文件',
      actions: [
        KPill(
          label: 'AI 设置',
          icon: Icons.settings_rounded,
          filled: false,
          onTap: () => jumpToSettingsSection(ref, 3), // 设置 → AI 分区
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SummaryCard(),
          const SizedBox(height: Gap.lg),
          const _RecommendCard(),
          const SizedBox(height: Gap.sm),
          Text('提示：AI 输出仅供参考；推荐卡的「加入」会先搜刮元数据再入库。',
              style: Type.micro.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ============================ 智能总结 ============================

/// 游玩智能总结卡：生成按钮 / 生成中进度 / 结果（可选中复制）/ 错误提示。
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ai = ref.watch(aiStateProvider);
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconTile(icon: Icons.insights_rounded),
              const SizedBox(width: Gap.sm),
              Text('游玩智能总结', style: Type.section),
              const Spacer(),
              if (ai.summarizing) ...[
                const SizedBox(width: 16, height: 16, child: KLoading(size: 16)),
                const SizedBox(width: Gap.sm),
              ],
              KPill(
                label: ai.summarizing ? '生成中…' : '生成总结',
                icon: Icons.auto_awesome_rounded,
                onTap: ai.summarizing
                    ? null
                    : () => ref.read(aiStateProvider.notifier).generateSummary(),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (ai.summarizing) const _ProgressLine('正在结合游玩数据生成总结…'),
          if (ai.summarizing) const SizedBox(height: Gap.md),
          // 失败时把原因放在结果上方：既保留上一次的结果，也不会让错误被吞掉
          if (ai.summaryError != null) _ErrorBox(ai.summaryError!),
          if (ai.summaryError != null && ai.hasSummary)
            const SizedBox(height: Gap.md),
          if (ai.hasSummary)
            SizedBox(
              width: double.infinity,
              child: KCard(
                flat: true,
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(Radii.md),
                padding: const EdgeInsets.all(16),
                child: SelectableText(ai.summary,
                    style: Type.body.copyWith(height: 1.75)),
              ),
            ),
          if (!ai.summarizing && !ai.hasSummary && ai.summaryError == null)
            Text(
              '点击「生成总结」，AI 将结合总时长、活跃天数、最常玩作品与标签词云给出一段点评。',
              style: Type.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

// ============================ 作品推荐 ============================

/// 作品推荐卡：获取按钮 / 加载进度 + 空态骨架 / 推荐条目网格 / 错误提示。
class _RecommendCard extends ConsumerWidget {
  const _RecommendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiStateProvider);
    final recs = ai.recommendations;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.recommend_rounded, color: KisakiColors.lavender),
              const SizedBox(width: Gap.sm),
              Text('作品推荐', style: Type.title),
              const Spacer(),
              if (ai.loadingRecommendations) ...[
                const SizedBox(width: 16, height: 16, child: KLoading(size: 16)),
                const SizedBox(width: Gap.sm),
              ],
              KPill(
                label: ai.loadingRecommendations ? '推荐中…' : '获取推荐',
                icon: Icons.explore_rounded,
                onTap: ai.loadingRecommendations
                    ? null
                    : () => ref
                        .read(aiStateProvider.notifier)
                        .generateRecommendations(),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (ai.loadingRecommendations) ...[
            const _ProgressLine('AI 正在挑选作品，并核对库内是否已有…'),
            const SizedBox(height: Gap.md),
            // 空态骨架：加载时用占位块撑住版面，避免高度跳动
            const KSkeleton(
                width: double.infinity, height: 72, radius: Radii.lg),
            const SizedBox(height: Gap.md),
            const KSkeleton(
                width: double.infinity, height: 72, radius: Radii.lg),
          ] else if (ai.recommendationsError != null)
            _ErrorBox(ai.recommendationsError!)
          else if (recs.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 330,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.6,
              ),
              itemCount: recs.length,
              itemBuilder: (context, i) => _RecCard(rec: recs[i]),
            )
          else
            const KEmpty(
              compact: true,
              icon: Icons.explore_rounded,
              title: '还没有推荐',
              subtitle: '点击右上角「获取推荐」，AI 将结合库内作品与高频标签推荐 6 部新作品；'
                  '点击条目即可搜刮入库。',
            ),
        ],
      ),
    );
  }
}

/// 推荐条目：封面（懒搜刮）+ 标题 + 理由 + 标签 + 右侧入库按钮。
class _RecCard extends ConsumerWidget {
  final AiRecommendation rec;
  const _RecCard({required this.rec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // 只订阅「本条」的入库状态：其他条目/总结的状态变化不会重建这张卡
    final st = ref.watch(aiStateProvider.select((s) => s.addStateOf(rec.title)));
    void add() => ref.read(aiStateProvider.notifier).addRecommendation(rec);
    return KCard(
      flat: true,
      color: dark
          ? KisakiColors.nightBg.withValues(alpha: 0.5)
          : const Color(0xFFFDF6F1),
      padding: const EdgeInsets.all(10),
      onTap: st == RecAddState.working ? null : add,
      child: Row(
        children: [
          _RecCover(title: rec.title),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(rec.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body.copyWith(fontWeight: FontWeight.w700)),
                if (rec.reason.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Text(rec.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Type.caption
                          .copyWith(height: 1.4, color: scheme.onSurfaceVariant)),
                ],
                if (rec.tags.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    children: [
                      for (final t in rec.tags.take(3))
                        KBadge(text: t, color: KisakiColors.lavender),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          _AddControl(state: st, onTap: add),
        ],
      ),
    );
  }
}

/// 推荐封面（懒搜刮）：同一标题复用同一个 Future，避免卡片每次重建都重新
/// 发起多源网络搜索（搜刮结果本身有 24h 磁盘缓存兜底）。
/// 缓存放在文件级而不是页面 State —— 与生成状态同理，切页销毁页面后仍有效。
final Map<String, Future<ScrapedGame?>> _recCoverCache = {};

Future<ScrapedGame?> _coverFuture(String title) =>
    _recCoverCache.putIfAbsent(title, () async {
      try {
        return await AppServices.I.fetcher.fetchBest(title);
      } catch (_) {
        return null; // 搜刮失败：只影响封面，不影响条目本身与入库操作
      }
    });

class _RecCover extends StatelessWidget {
  final String title;
  const _RecCover({required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 64,
      child: FutureBuilder<ScrapedGame?>(
        future: _coverFuture(title),
        builder: (context, snap) {
          final url = snap.data?.coverUrl ?? '';
          if (url.isEmpty) {
            // 未搜到封面（仍在搜刮 / 搜不到）：粉色占位块
            return KCard(
              flat: true,
              padding: EdgeInsets.zero,
              color: KisakiColors.pinkContainer,
              borderRadius: BorderRadius.circular(Radii.thumb),
              child: const Icon(Icons.local_florist_rounded,
                  size: 18, color: KisakiColors.pink),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(Radii.thumb),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (context, url) => const KSkeleton(
                  width: double.infinity, height: 64, radius: Radii.thumb),
              errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image_rounded,
                  size: 18,
                  color: KisakiColors.pink),
            ),
          );
        },
      ),
    );
  }
}

/// 条目右侧的入库按钮：idle「加入」/ working 转圈 / added「已加入」/
/// exists「已在库」/ failed「重试」。用 KChip（kit 里可着色的小按钮原语）
/// 承载，图标 + 短文案同时表达状态（纯图标按钮在 kit 里无法着色）。
class _AddControl extends StatelessWidget {
  final RecAddState state;
  final VoidCallback onTap;
  const _AddControl({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case RecAddState.working:
        return const SizedBox(width: 26, height: 26, child: KLoading(size: 16));
      case RecAddState.added:
        return const KChip(
          label: '已加入',
          icon: Icons.check_circle_rounded,
          color: KisakiColors.pink,
          selected: true,
        );
      case RecAddState.exists:
        return const KChip(label: '已在库', icon: Icons.library_books_rounded);
      case RecAddState.failed:
        return KChip(
          label: '重试',
          icon: Icons.refresh_rounded,
          color: KisakiColors.pink,
          selected: true,
          onTap: onTap,
        );
      case RecAddState.idle:
        return KChip(
          label: '加入',
          icon: Icons.add_circle_rounded,
          color: KisakiColors.pink,
          selected: true,
          onTap: onTap,
        );
    }
  }
}

// ============================ 公用小组件 ============================

/// 卡片标题左侧的图标底（kit 原语拼装，避免裸 Container + BoxDecoration）。
class _IconTile extends StatelessWidget {
  final IconData icon;
  const _IconTile({required this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 36,
        child: KCard(
          flat: true,
          padding: EdgeInsets.zero,
          color: KisakiColors.pink.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Icon(icon, size: 18, color: KisakiColors.pink),
        ),
      );
}

/// 生成中的进度行（小转圈 + 说明文字）。
class _ProgressLine extends StatelessWidget {
  final String text;
  const _ProgressLine(this.text);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(width: 16, height: 16, child: KLoading(size: 16)),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(text,
                style: Type.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      );
}

/// 错误 / 未配置提示（粉色语义底 + 「去配置」入口）。
class _ErrorBox extends ConsumerWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        width: double.infinity,
        child: KCard(
          flat: true,
          color: KisakiColors.pinkContainer,
          borderColor: KisakiColors.pink.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Radii.md),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: KisakiColors.pink),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: KisakiColors.onPinkContainer)),
              ),
              const SizedBox(width: Gap.sm),
              KPill(
                label: '去配置',
                filled: false,
                onTap: () => jumpToSettingsSection(ref, 3), // 设置 → AI 分区
              ),
            ],
          ),
        ),
      );
}
