/// 刮削结果落库：把合并后的元数据写入 Game，并为每个提供数据的源
/// 登记 game_sources 评分记录（多源整合，ReinaManager 式）。
library;

import '../data/game_repository.dart';
import 'scraped_game.dart';
import '../data/models.dart';
import 'metadata_fetcher.dart';

class ScrapeApplier {
  final GameRepository repo;
  final MetadataFetcher fetcher;
  const ScrapeApplier(this.repo, this.fetcher);

  /// [all]: mergeAcrossSources 的返回（[0] 为合并结果）。
  /// [backgroundPick]: 用户选择的背景图 URL；空串表示纯色（清除）；
  /// null 表示保持不变。
  Future<void> apply(
    Game game,
    List<ScrapedGame> all, {
    String? backgroundPick,
  }) async {
    final merged = all.first;
    game.name = merged.name.isNotEmpty ? merged.name : game.name;
    if (merged.nameCn.isNotEmpty) game.nameCn = merged.nameCn;
    if (merged.aliases.isNotEmpty) game.aliases = merged.aliases;
    if (merged.developer.isNotEmpty) game.developer = merged.developer;
    if (merged.releaseDate.isNotEmpty) game.releaseDate = merged.releaseDate;
    if (merged.summary.isNotEmpty) game.summary = merged.summary;
    if (merged.nsfw) game.nsfw = true;
    if (merged.screenshots.isNotEmpty) game.screenshots = merged.screenshots;

    final cover = await fetcher.downloadCover(merged, game.id!);
    if (cover.isNotEmpty) game.coverPath = cover;

    if (backgroundPick != null) {
      if (backgroundPick.isEmpty) {
        game.backgroundUrl = '';
      } else {
        final local =
            await fetcher.downloadImage(backgroundPick, 'bg_${game.id}');
        if (local.isNotEmpty) game.backgroundUrl = local;
      }
    }

    await repo.updateGame(game);
    if (merged.tags.isNotEmpty) {
      await repo.setTags(
          game.id!,
          merged.tags
              .map((t) => TagItem(
                  name: t.name, weight: t.weight, source: merged.source))
              .toList());
    }
    // 每个有数据/有评分的源都登记一条记录（详情页显示各平台评分）
    for (final s in all) {
      if (s.source.isEmpty || (s.sourceId.isEmpty && s.rating <= 0)) continue;
      await repo.upsertSource(
        game.id!,
        SourceRecord(
          gameId: game.id!,
          source: s.source,
          sourceId: s.sourceId,
          rating: s.rating,
          voteCount: s.voteCount,
          raw: s.toJson(),
        ),
      );
    }
  }
}
