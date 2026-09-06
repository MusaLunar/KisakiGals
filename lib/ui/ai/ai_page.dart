/// AI 助手页：结合游玩数据/词云生成智能总结与作品推荐，
/// 推荐结果以卡片展示，可一键刮削入库。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/settings_store.dart';
import '../../providers.dart';
import '../../scraping/apply.dart';
import '../../scraping/scraped_game.dart';
import '../../services/ai_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  String _summary = '';
  String? _summaryError;
  bool _summarizing = false;

  List<AiRecommendation>? _recs;
  String? _recsError;
  bool _recommending = false;
  final _addState = <String, _RecAddState>{};

  Future<AiConfig?> _loadConfig() async {
    final s = AppServices.I.settings;
    final config = AiConfig(
      baseUrl: await s.getString(SettingsStore.kAiBaseUrl, ''),
      apiKey: await s.getString(SettingsStore.kAiApiKey, ''),
      model: await s.getString(SettingsStore.kAiModel, ''),
    );
    if (!mounted) return null;
    if (!config.ready) {
      setState(() {
        _summaryError = '尚未配置 AI：请前往「设置 → AI」填写 Base URL、API Key 与模型名称';
        _recsError = _summaryError;
      });
      return null;
    }
    return config;
  }

  void _jumpSettings() =>
      jumpToSettingsSection(ref, 3); // 设置 → AI 分区

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ListView(
        children: [
          Row(
            children: [
              Text('AI 助手',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              const Icon(Icons.auto_awesome_rounded,
                  size: 20, color: KisakiColors.lavender),
              const Spacer(),
              TextButton.icon(
                onPressed: _jumpSettings,
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('AI 设置'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('基于你的游玩数据与标签词云，由 AI 生成游玩总结与新作推荐。数据仅用于构造当次请求，不会上传游戏文件。',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          _summaryCard(),
          const SizedBox(height: 18),
          _recommendCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------- 智能总结 ----------

  Widget _summaryCard() {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: KisakiColors.pink),
              const SizedBox(width: 8),
              Text('游玩智能总结',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _summarizing ? null : _generateSummary,
                icon: _summarizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_summarizing ? '生成中…' : '生成总结'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_summary.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              child: SelectableText(_summary,
                  style: const TextStyle(height: 1.7, fontSize: 13.5)),
            )
          else if (_summaryError != null)
            _errorBox(_summaryError!)
          else
            Text('点击「生成总结」，AI 将结合总时长、活跃天数、最常玩作品与标签词云给出一段点评。',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _generateSummary() async {
    final config = await _loadConfig();
    if (config == null) return;
    setState(() {
      _summarizing = true;
      _summaryError = null;
    });
    final data = await _gatherPlayData();
    final r = await AppServices.I.ai.chat(
      config: config,
      system: '你是 galgame 游戏库管理器「KisakiGals」的助手，语气轻松友好，用简体中文回答。',
      user: '请根据以下玩家游玩数据，写一段 120-200 字的游玩总结：概括游玩习惯（时段/频率）、'
          '偏好题材（结合标签词云）、点评 1-2 部最常玩或高分作品，最后给一句轻松的鼓励。\n\n$data',
    );
    if (!mounted) return;
    setState(() {
      _summarizing = false;
      if (r.ok) {
        _summary = r.content;
      } else {
        _summaryError = r.message;
      }
    });
  }

  // ---------- 作品推荐 ----------

  Widget _recommendCard() {
    final recs = _recs;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.recommend_rounded, color: KisakiColors.lavender),
              const SizedBox(width: 8),
              Text('作品推荐',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _recommending ? null : _generateRecommendations,
                icon: _recommending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.explore_rounded, size: 18),
                label: Text(_recommending ? '推荐中…' : '获取推荐'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_recommending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (recs != null && recs.isNotEmpty)
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
              itemBuilder: (context, i) =>
                  _RecCard(rec: recs[i], page: this),
            )
          else if (_recsError != null)
            _errorBox(_recsError!)
          else
            Text('点击「获取推荐」，AI 将根据你的库内作品与高频标签推荐 6 部新作品；点击卡片按钮即可搜刮入库。',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _generateRecommendations() async {
    final config = await _loadConfig();
    if (config == null) return;
    setState(() {
      _recommending = true;
      _recsError = null;
      _addState.clear();
    });
    final data = await _gatherPlayData();
    final r = await AppServices.I.ai.chat(
      config: config,
      system: '你是 galgame（美少女游戏）领域的资深推荐者，只输出 JSON，不输出任何解释文字。',
      user: '根据以下玩家资料推荐 6 部该玩家大概率会喜欢、且库中尚未拥有的 galgame 作品'
          '（经典或近年作品均可）。只输出 JSON 数组，格式：\n'
          '[{"title":"作品官方译名或日文原名","reason":"40字内推荐理由","tags":["标签1","标签2"]}]\n\n'
          '玩家资料：\n$data',
      temperature: 0.9,
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _recommending = false;
        _recsError = r.message;
      });
      return;
    }
    final recs = AppServices.I.ai.parseRecommendations(r.content);
    setState(() {
      _recommending = false;
      if (recs.isEmpty) {
        _recsError = 'AI 返回内容无法解析为推荐列表，请重试或换用支持 JSON 输出的模型';
      } else {
        _recs = recs;
      }
    });
  }

  // ---------- 推荐入库 ----------

  Future<void> _addRecommendation(AiRecommendation rec) async {
    if (_addState[rec.title] == _RecAddState.working) return;
    setState(() => _addState[rec.title] = _RecAddState.working);
    try {
      final repo = AppServices.I.repo;
      final existing = await repo.findGameByTitle(rec.title);
      if (existing != null) {
        setState(() => _addState[rec.title] = _RecAddState.exists);
        return;
      }
      final best = await AppServices.I.fetcher.fetchBest(rec.title);
      if (best == null || best.source.isEmpty) {
        setState(() {
          _addState[rec.title] = _RecAddState.failed;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('「${rec.title}」未搜到元数据，可手动到添加页搜索')));
        return;
      }
      final all = await AppServices.I.fetcher.mergeAcrossSources(
          best,
          kw: rec.title);
      final g = Game(
        name: best.name,
        nameCn: best.nameCn,
        aliases: best.aliases,
        developer: best.developer,
        releaseDate: best.releaseDate,
        summary: best.summary,
        nsfw: best.nsfw,
        screenshots: best.screenshots,
      );
      await repo.insertGame(g);
      await ScrapeApplier(repo, AppServices.I.fetcher).apply(g, all);
      ref.read(libraryVersionProvider.notifier).state++;
      if (!mounted) return;
      setState(() => _addState[rec.title] = _RecAddState.added);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '已添加「${g.displayName}」到游戏库（${all.length} 个数据源）')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _addState[rec.title] = _RecAddState.failed);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('添加失败：$e')));
    }
  }

  // ---------- 数据收集 ----------

  Future<String> _gatherPlayData() async {
    final repo = AppServices.I.repo;
    final stats = await repo.stats(period: StatsPeriod.all);
    final cloud = await repo.tagCloud(period: StatsPeriod.all);
    final games = await repo.listGames();

    final buf = StringBuffer();
    buf.writeln('- 库内作品数：${games.length}');
    buf.writeln('- 总时长：${fmtDuration(stats.totalSeconds)}，活跃天数：${stats.activeDays}，会话数：${stats.sessionCount}');
    if (stats.topGames.isNotEmpty) {
      buf.writeln('- 最常玩：${stats.topGames.take(5).map((t) => '${t.name}（${fmtDuration(t.seconds)}）').join('、')}');
    }
    final rated = games.where((g) => g.userRating > 0).take(8).toList();
    if (rated.isNotEmpty) {
      buf.writeln('- 我的评分：${rated.map((g) => '${g.displayName} ${g.userRating.toStringAsFixed(0)}/10').join('、')}');
    }
    final favs = games.where((g) => g.isFavorite).take(6).toList();
    if (favs.isNotEmpty) {
      buf.writeln('- 收藏：${favs.map((g) => g.displayName).join('、')}');
    }
    if (cloud.isNotEmpty) {
      buf.writeln('- 高频标签词云：${cloud.take(12).map((t) => '${t.name}(${t.weight.toStringAsFixed(0)})').join(' ')}');
    }
    buf.writeln('- 库内作品：${games.take(30).map((g) => g.displayName).join('、')}');
    return buf.toString();
  }

  Widget _errorBox(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: KisakiColors.pinkContainer,
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: KisakiColors.pink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(
                      fontSize: 12.5, color: KisakiColors.onPinkContainer)),
            ),
            TextButton(
              onPressed: _jumpSettings,
              child: const Text('去配置'),
            ),
          ],
        ),
      );
}

enum _RecAddState { idle, working, added, exists, failed }

/// 推荐卡片：封面（懒搜刮）+ 标题 + 理由 + 标签 + 添加按钮。
class _RecCard extends ConsumerWidget {
  final AiRecommendation rec;
  final _AiPageState page;
  const _RecCard({required this.rec, required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final state = page._addState[rec.title] ?? _RecAddState.idle;
    return Material(
      color: dark ? KisakiColors.nightBg.withValues(alpha: 0.5) : const Color(0xFFFDF6F1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: state == _RecAddState.working ? null : () => page._addRecommendation(rec),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 封面：懒搜刮（结果有 24h 缓存，添加时复用）
              SizedBox(
                width: 46,
                height: 64,
                child: FutureBuilder<ScrapedGame?>(
                  future: AppServices.I.fetcher.fetchBest(rec.title),
                  builder: (context, snap) {
                    final url = snap.data?.coverUrl ?? '';
                    if (url.isEmpty) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: KisakiColors.pinkContainer,
                        ),
                        child: const Icon(Icons.local_florist_rounded,
                            size: 18, color: KisakiColors.pink),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                          imageUrl: url, fit: BoxFit.cover),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(rec.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    if (rec.reason.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(rec.reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                    if (rec.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 3,
                        children: [
                          for (final t in rec.tags.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: dark
                                    ? KisakiColors.lavender.withValues(alpha: 0.18)
                                    : KisakiColors.lavenderContainer,
                              ),
                              child: Text(t,
                                  style: const TextStyle(fontSize: 10)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _addButton(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addButton(BuildContext context, _RecAddState state) {
    final l = state;
    if (l == _RecAddState.idle) {
      return IconButton(
        tooltip: '搜刮并加入游戏库',
        icon: const Icon(Icons.add_circle_rounded, size: 24, color: KisakiColors.pink),
        onPressed: () => page._addRecommendation(rec),
      );
    }
    if (l == _RecAddState.working) {
      return const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (l == _RecAddState.added) {
      return const Icon(Icons.check_circle_rounded,
          color: KisakiColors.pink, size: 24);
    }
    if (l == _RecAddState.exists) {
      return const Icon(Icons.library_books_rounded,
          size: 22, color: Colors.grey);
    }
    return IconButton(
      tooltip: '搜刮并加入游戏库',
      icon: Icon(
        l == _RecAddState.failed ? Icons.refresh_rounded : Icons.add_circle_rounded,
        size: 24,
        color: l == _RecAddState.failed ? Colors.grey : KisakiColors.pink,
      ),
      onPressed: () => page._addRecommendation(rec),
    );
  }
}
