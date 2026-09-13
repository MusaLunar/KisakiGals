import 'package:kisakigals/services/resource_search.dart';
import 'package:test/test.dart';

/// 相关度排序 + 新增来源（TouchGal / 量子ACG）
void main() {
  group('相关度评分', () {
    test('完全匹配最高', () {
      expect(ResourceSearcher.relevance('千恋万花', '千恋万花'), 1000);
    });

    test('前缀匹配高于中间命中', () {
      final prefix = ResourceSearcher.relevance('千恋万花 汉化版', '千恋万花');
      final middle = ResourceSearcher.relevance('汉化版 千恋万花', '千恋万花');
      expect(prefix, greaterThan(middle));
      expect(middle, greaterThan(0));
    });

    test('更短的标题优先于带大量后缀的标题', () {
      final short = ResourceSearcher.relevance('千恋万花', '千恋万花');
      final long = ResourceSearcher.relevance(
          '千恋万花+FD+OST+攻略 整合包 免安装 汉化版', '千恋万花');
      expect(short, greaterThan(long));
    });

    test('归一化忽略空格与装饰符号（Senren＊Banka）', () {
      expect(ResourceSearcher.relevance('Senren＊Banka', 'senren banka'),
          greaterThan(850));
      expect(ResourceSearcher.relevance('ATRI -My Dear Moments-', 'atri'),
          greaterThan(850));
    });

    test('分段命中（多词关键词）给部分分', () {
      final s = ResourceSearcher.relevance('ATRI My Dear Moments 汉化', 'ATRI Moments');
      expect(s, greaterThan(0));
      expect(s, lessThan(850));
    });

    test('毫不相关的标题为 0 分', () {
      expect(ResourceSearcher.relevance('CLANNAD', '千恋万花'), 0);
    });

    test('按相关度排序能把最匹配的放在第一位', () {
      final titles = [
        '汉化版 千恋万花',
        '千恋万花+FD 整合',
        '千恋万花',
        'CLANNAD',
      ];
      titles.sort((a, b) => ResourceSearcher.relevance(b, '千恋万花')
          .compareTo(ResourceSearcher.relevance(a, '千恋万花')));
      expect(titles.first, '千恋万花');
      expect(titles.last, 'CLANNAD');
    });
  });

  group('新增来源', () {
    test('TouchGal 关键词过短时按官方约束直接返回空（不发起请求）', () async {
      final s = ResourceSearcher();
      try {
        expect(await TouchGalResourceAdapter().search(s.dio, 'AT'), isEmpty);
        expect(await TouchGalResourceAdapter().search(s.dio, ''), isEmpty);
      } finally {
        s.dispose();
      }
    });

    test('不可达来源经 search 包装后以错误形式返回（不抛异常、不中断）', () async {
      final s = ResourceSearcher();
      final bySite = <String, ResourceSourceResult>{};
      await for (final u in s.search('千恋万花',
          only: [TouchGalResourceAdapter(), LiangZiAcgAdapter()])) {
        if (u.result != null) bySite[u.result!.site] = u.result!;
      }
      s.dispose();
      expect(bySite.keys, containsAll(['TouchGal', '量子ACG']));
      for (final e in bySite.entries) {
        // 能连通则校验结构；连不通则必须是「错误结果」而不是崩溃
        if (e.value.error == null) {
          for (final it in e.value.items) {
            expect(it.site, e.key);
            expect(it.url, startsWith('http'));
            expect(it.title, isNotEmpty);
          }
        } else {
          expect(e.value.items, isEmpty);
        }
      }
    });

    test('内置源共 5 个（鲲/GAL图书馆/TouchGal/量子ACG/真红小站）', () async {
      final s = ResourceSearcher();
      final sites = <String>{};
      await for (final u in s.search('ATRI')) {
        if (u.result != null) sites.add(u.result!.site);
      }
      s.dispose();
      expect(
          sites,
          containsAll([
            '鲲Galgame',
            'GAL图书馆',
            'TouchGal',
            '量子ACG',
            '真红小站',
          ]));
    });
  });
}
