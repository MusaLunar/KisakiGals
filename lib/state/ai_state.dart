/// AI 助手的**生成状态**（app 级 Provider，不 autoDispose）。
///
/// 为什么要提升到状态层：
/// 外壳用 `FadeThroughSwitcher + KeyedSubtree` 切页，切走时 `AiPage` 整棵子树
/// 会被销毁。原先状态放在页面 State 里 —— 请求其实还在跑，但页面销毁后
/// `setState` 已失效、结果无处落脚，回到 AI 页就是空白。
/// 这里把「生成内容 / 进行中标志 / 每条的入库状态」整体搬到 app 级
/// （非 autoDispose）Provider：
/// 1. 切页不中断、不丢结果（notifier 生命周期 = ProviderScope）；
/// 2. 生成完成 / 失败 / 入库完成统一调用全局 `showNotice(...)` —— 通知层挂在
///    `MaterialApp.builder` 上（`NoticeHost`），用户在任何页面都能看到，
///    这正是「切页后仍要收到完成提示」的需求。
///
/// 请求参数（baseUrl / apiKey / model / maxTokens）与游玩数据聚合也一并
/// 收在这里，页面只负责「展示 + 触发」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_services.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../providers.dart';
import '../scraping/apply.dart';
import '../services/ai_service.dart';
import '../ui/widgets/notifications.dart';

/// 未配置 AI 时的统一提示（页面内错误框与通知共用同一份文案）。
const String kAiNotConfiguredMsg =
    '尚未配置 AI：请前往「设置 → AI」填写 Base URL、API Key 与模型名称';

/// 推荐条目的入库状态。
enum RecAddState {
  /// 可添加（显示「+」）
  idle,

  /// 搜刮/入库进行中（显示转圈）
  working,

  /// 本次已成功入库（显示对勾）
  added,

  /// 库中已存在同名作品（显示「已在库」）
  exists,

  /// 搜刮失败 / 入库异常（显示重试）
  failed,
}

/// AI 页的完整状态快照（不可变；每次变更整体替换）。
class AiState {
  /// 游玩智能总结正文（空串 = 尚未生成）。
  final String summary;

  /// 最近一次总结失败原因；成功或尚未开始时为 null。
  final String? summaryError;

  /// 总结生成中。
  final bool summarizing;

  /// 作品推荐列表。
  final List<AiRecommendation> recommendations;

  /// 最近一次推荐失败原因；成功或尚未开始时为 null。
  final String? recommendationsError;

  /// 推荐生成中。
  final bool loadingRecommendations;

  /// 每个推荐条目的入库状态（key = 作品标题）。
  final Map<String, RecAddState> addStates;

  const AiState({
    this.summary = '',
    this.summaryError,
    this.summarizing = false,
    this.recommendations = const [],
    this.recommendationsError,
    this.loadingRecommendations = false,
    this.addStates = const {},
  });

  /// 是否已有总结正文可展示。
  bool get hasSummary => summary.isNotEmpty;

  /// 取某条推荐的入库状态（未记录 = 可添加）。
  RecAddState addStateOf(String title) => addStates[title] ?? RecAddState.idle;

  /// copyWith 的「不修改」哨兵：用于把 `xxxError` 显式置回 null。
  static const Object _keep = Object();

  AiState copyWith({
    String? summary,
    Object? summaryError = _keep,
    bool? summarizing,
    List<AiRecommendation>? recommendations,
    Object? recommendationsError = _keep,
    bool? loadingRecommendations,
    Map<String, RecAddState>? addStates,
  }) {
    return AiState(
      summary: summary ?? this.summary,
      summaryError: identical(summaryError, _keep)
          ? this.summaryError
          : summaryError as String?,
      summarizing: summarizing ?? this.summarizing,
      recommendations: recommendations ?? this.recommendations,
      recommendationsError: identical(recommendationsError, _keep)
          ? this.recommendationsError
          : recommendationsError as String?,
      loadingRecommendations:
          loadingRecommendations ?? this.loadingRecommendations,
      addStates: addStates ?? this.addStates,
    );
  }
}

/// AI 生成控制器：唯一持有生成状态与请求参数的地方。
///
/// 因为 provider 不是 autoDispose，即使 AI 页被销毁，这里的方法体仍在运行，
/// 完成后把结果写回 state，并弹全局通知。
class AiController extends StateNotifier<AiState> {
  AiController(this._ref) : super(const AiState());

  final Ref _ref;

  /// 写入状态。notifier 随容器销毁后（应用退出瞬间请求才返回）静默丢弃：
  /// `state` 的读写带 mounted 断言，靠这里兜住，避免 debug 下抛 StateError。
  void _emit(AiState next) {
    if (!mounted) return;
    state = next;
  }

  // ---------- 生成入口 ----------

  /// 生成「游玩智能总结」。完成后通知「AI 总结已生成」，失败通知原因。
  Future<void> generateSummary() async {
    if (state.summarizing) return; // 防重复点击（按钮同时会禁用）
    final config = await _config();
    if (!config.ready) {
      _emit(state.copyWith(summarizing: false, summaryError: kAiNotConfiguredMsg));
      showNotice('生成失败：$kAiNotConfiguredMsg', error: true);
      return;
    }
    _emit(state.copyWith(summarizing: true, summaryError: null));
    try {
      final data = await gatherPlayData();
      final r = await AppServices.I.ai.chat(
        config: config,
        system: '你是 galgame 游戏库管理器「KisakiGals」的助手，语气轻松友好，用简体中文回答。',
        user: '请根据以下玩家游玩数据，写一段 120-200 字的游玩总结：概括游玩习惯（时段/频率）、'
            '偏好题材（结合标签词云）、点评 1-2 部最常玩或高分作品，最后给一句轻松的鼓励。\n\n$data',
        maxTokens: await _maxTokens(),
      );
      if (r.ok) {
        _emit(state.copyWith(
            summarizing: false, summary: r.content, summaryError: null));
        showNotice('AI 总结已生成');
      } else {
        _emit(state.copyWith(summarizing: false, summaryError: r.message));
        showNotice('生成失败：${r.message}', error: true);
      }
    } catch (e) {
      _emit(state.copyWith(summarizing: false, summaryError: '生成失败：$e'));
      showNotice('生成失败：$e', error: true);
    }
  }

  /// 生成「作品推荐」。完成后通知「AI 推荐已更新」，失败通知原因。
  Future<void> generateRecommendations() async {
    if (state.loadingRecommendations) return;
    final config = await _config();
    if (!config.ready) {
      _emit(state.copyWith(
          loadingRecommendations: false, recommendationsError: kAiNotConfiguredMsg));
      showNotice('生成失败：$kAiNotConfiguredMsg', error: true);
      return;
    }
    _emit(state.copyWith(
        loadingRecommendations: true,
        recommendationsError: null,
        addStates: const {}));
    try {
      final data = await gatherPlayData();
      final r = await AppServices.I.ai.chat(
        config: config,
        system: '你是 galgame（美少女游戏）领域的资深推荐者，只输出 JSON，不输出任何解释文字。',
        user: '根据以下玩家资料推荐 6 部该玩家大概率会喜欢、且库中尚未拥有的 galgame 作品'
            '（经典或近年作品均可）。只输出 JSON 数组，格式：\n'
            '[{"title":"作品官方译名或日文原名","reason":"40字内推荐理由","tags":["标签1","标签2"]}]\n\n'
            '玩家资料：\n$data',
        temperature: 0.9,
        maxTokens: await _maxTokens(),
      );
      if (!r.ok) {
        _emit(state.copyWith(
            loadingRecommendations: false, recommendationsError: r.message));
        showNotice('生成失败：${r.message}', error: true);
        return;
      }
      final recs = AppServices.I.ai.parseRecommendations(r.content);
      if (recs.isEmpty) {
        const msg = 'AI 返回内容无法解析为推荐列表，请重试或换用支持 JSON 输出的模型';
        _emit(state.copyWith(
            loadingRecommendations: false, recommendationsError: msg));
        showNotice('生成失败：$msg', error: true);
        return;
      }
      _emit(state.copyWith(
          loadingRecommendations: false,
          recommendations: recs,
          recommendationsError: null));
      showNotice('AI 推荐已更新（${recs.length} 部）');
    } catch (e) {
      _emit(state.copyWith(
          loadingRecommendations: false, recommendationsError: '生成失败：$e'));
      showNotice('生成失败：$e', error: true);
    }
  }

  // ---------- 推荐入库 ----------

  /// 把一条推荐搜刮元数据后写入游戏库。
  ///
  /// 与页面无关（不碰 BuildContext）：切页/关页后仍在跑，完成后照常通知，
  /// 并递增 `libraryVersionProvider` 让游戏库等页面刷新。
  Future<void> addRecommendation(AiRecommendation rec) async {
    if (rec.title.isEmpty) return;
    if (state.addStateOf(rec.title) == RecAddState.working) return;
    _setAddState(rec.title, RecAddState.working);
    try {
      final repo = AppServices.I.repo;
      final existing = await repo.findGameByTitle(rec.title);
      if (existing != null) {
        _setAddState(rec.title, RecAddState.exists);
        showNotice('「${existing.displayName}」已在游戏库中');
        return;
      }
      final best = await AppServices.I.fetcher.fetchBest(rec.title);
      if (best == null || best.source.isEmpty) {
        _setAddState(rec.title, RecAddState.failed);
        showNotice('「${rec.title}」未搜到元数据，可手动到添加页搜索', error: true);
        return;
      }
      final all =
          await AppServices.I.fetcher.mergeAcrossSources(best, kw: rec.title);
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
      // 库变更：通知各页重新读取（游戏库网格/统计等）；
      // 容器已销毁时跳过（`ref` 在销毁后不可用）
      if (mounted) _ref.read(libraryVersionProvider.notifier).state++;
      _setAddState(rec.title, RecAddState.added);
      showNotice('已入库：${g.displayName}（${all.length} 个数据源）');
    } catch (e) {
      _setAddState(rec.title, RecAddState.failed);
      showNotice('入库失败：$e', error: true);
    }
  }

  // ---------- 内部工具 ----------

  void _setAddState(String title, RecAddState s) {
    if (!mounted) return;
    _emit(state.copyWith(
        addStates: Map<String, RecAddState>.from(state.addStates)..[title] = s));
  }

  /// 读取设置里的接入参数（设置 → AI）。
  Future<AiConfig> _config() async {
    final s = AppServices.I.settings;
    return AiConfig(
      baseUrl: await s.getString(SettingsStore.kAiBaseUrl, ''),
      apiKey: await s.getString(SettingsStore.kAiApiKey, ''),
      model: await s.getString(SettingsStore.kAiModel, ''),
    );
  }

  /// 最大回复长度（推理模型需要余量，默认 4000）。
  Future<int> _maxTokens() =>
      AppServices.I.settings.getInt(SettingsStore.kAiMaxTokens, 4000);

  /// 汇总游玩数据（总时长/活跃天数/最常玩/评分/收藏/标签词云/库内作品），
  /// 作为提示词的「玩家资料」段。原先在页面里，现整体搬到状态层。
  Future<String> gatherPlayData() async {
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
}

/// app 级 AI 状态（**不 autoDispose**）：
/// 首次进入 AI 页创建，此后一直存活 —— 这是「切页后生成继续、结果不丢」的关键。
final aiStateProvider =
    StateNotifierProvider<AiController, AiState>((ref) => AiController(ref));
