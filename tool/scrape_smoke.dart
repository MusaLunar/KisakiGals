// ignore_for_file: avoid_print
// 刮削层冒烟测试：dart run tool/scrape_smoke.dart [关键词]
import 'package:kisakigals/data/metadata_cache.dart';
import 'package:kisakigals/scraping/metadata_fetcher.dart';

Future<void> main(List<String> args) async {
  final kw = args.isNotEmpty ? args.join(' ') : '千恋万花';
  final fetcher = MetadataFetcher(
      cache: MetadataCache('.dart_tool/mc_test'), coversDir: '.dart_tool/covers_test');
  await fetcher.init();
  print('proxy: ${fetcher.proxy ?? '直连'}');

  final sw = Stopwatch()..start();
  final bySource = await fetcher.searchAll(kw);
  for (final entry in bySource.entries) {
    final list = entry.value;
    if (list.isEmpty) {
      print('${entry.key.padRight(12)}: 0 条');
      continue;
    }
    final g = list.first;
    print('${entry.key.padRight(12)}: ${list.length} 条 | ${g.displayName}'
        ' | 评分 ${g.rating}${g.coverUrl.isEmpty ? ' | 无封面' : ''}');
  }
  print('--- 并发搜索耗时 ${sw.elapsedMilliseconds}ms ---');

  final best = await fetcher.fetchBest(kw);
  print('BEST: ${best?.source} ${best?.displayName} '
      '(${best?.rating}) 标签=${best?.tags.take(5).map((t) => t.name).join(',')}');

  // 各源 fetchById 验证
  if (best != null) {
    final full = await fetcher.adapter(best.source)?.fetchById(best.sourceId);
    print('BYID: ${full?.displayName} summary=${(full?.summary.isEmpty ?? true) ? '无' : '${full!.summary.length} 字'}');
  }
  fetcher.dispose();
}
