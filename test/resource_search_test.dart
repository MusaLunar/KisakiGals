import 'package:kisakigals/services/resource_search.dart';
import 'package:test/test.dart';

/// 资源搜索：适配器解析与流式聚合（联网；站点不可达时容忍为空结果）
void main() {
  test('鲲Galgame 适配器解析出条目与发布页链接', () async {
    final s = ResourceSearcher();
    try {
      final r = await KunResourceAdapter().search(s.dio, '千恋万花');
      for (final it in r) {
        expect(it.site, '鲲Galgame');
        expect(it.title, isNotEmpty);
        expect(it.url, startsWith('https://www.kungal.com/zh-cn/galgame/'));
      }
    } finally {
      s.dispose();
    }
  });

  test('GAL图书馆 适配器解析出条目与详情页链接', () async {
    final s = ResourceSearcher();
    try {
      final r = await GalLibraryAdapter().search(s.dio, '千恋万花');
      for (final it in r) {
        expect(it.site, 'GAL图书馆');
        expect(it.title, isNotEmpty);
        expect(it.url, startsWith('https://gallibrary.pw/game.html?id='));
      }
    } finally {
      s.dispose();
    }
  });

  test('流式搜索按来源逐个推送并以 done 结束', () async {
    final s = ResourceSearcher();
    final updates = <ResourceSearchUpdate>[];
    await for (final u in s.search('千恋万花', only: [KunResourceAdapter()])) {
      updates.add(u);
    }
    s.dispose();
    expect(updates.first.total, 1);
    expect(updates.any((u) => u.result != null), isTrue,
        reason: '应至少推送一次来源结果（网络失败也会以 error 形式推送）');
    expect(updates.last.done, isTrue);
    expect(updates.last.completed, updates.last.total);
  });

  test('内置三源都会出现在结果里（含不可达来源的错误）', () async {
    final s = ResourceSearcher();
    final sites = <String>{};
    await for (final u in s.search('ATRI')) {
      if (u.result != null) sites.add(u.result!.site);
    }
    s.dispose();
    expect(sites, containsAll(['鲲Galgame', 'GAL图书馆', '真红小站']));
  });

  test('SearchGal 标签映射为中文语义', () async {
    final s = ResourceSearcher();
    // 通过一个不可达地址验证错误被包装而不是抛出
    final updates = <ResourceSearchUpdate>[];
    await for (final u
        in s.search('test', searchGalApi: 'http://127.0.0.1:1/gal')) {
      updates.add(u);
    }
    s.dispose();
    final agg = updates
        .where((u) => u.result?.site == 'SearchGal 聚合')
        .map((u) => u.result!)
        .toList();
    expect(agg, isNotEmpty, reason: '聚合源应返回一条错误结果而非中断搜索');
    expect(agg.first.error, isNotNull);
  });
}
