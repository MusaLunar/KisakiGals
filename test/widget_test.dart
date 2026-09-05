// 基础冒烟：应用常量与工具函数（UI 测试需完整初始化，见 test/ 下的单元测试）
import 'package:flutter_test/flutter_test.dart';

import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/core/utils.dart';

void main() {
  test('PlayStatus 往返', () {
    for (final s in PlayStatus.values) {
      expect(PlayStatus.fromValue(s.value), s);
    }
  });

  test('normalizeRating', () {
    expect(normalizeRating(76.5), closeTo(7.65, 0.001));
    expect(normalizeRating(8.2), 8.2);
    expect(normalizeRating(0), 0);
  });

  test('cleanExeName', () {
    expect(cleanExeName('ATRI -My Dear Moments-.exe'), contains('ATRI'));
  });
}
