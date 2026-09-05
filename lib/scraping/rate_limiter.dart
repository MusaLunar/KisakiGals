/// 每源限流器：最小间隔 + 60s 滑动窗口；429 时指数退避重试一次。
library;

class RateLimiter {
  final Duration minInterval;
  final int maxPerWindow;
  final Duration _window = const Duration(seconds: 60);
  final List<DateTime> _hits = [];
  DateTime? _last;

  RateLimiter({this.minInterval = const Duration(milliseconds: 500), this.maxPerWindow = 60});

  /// 等待直到允许发起请求。
  Future<void> acquire() async {
    while (true) {
      final now = DateTime.now();
      // 滑动窗口清理
      _hits.removeWhere((t) => now.difference(t) > _window);
      if (_hits.length >= maxPerWindow) {
        final wait = _window - now.difference(_hits.first);
        if (wait > Duration.zero) {
          await Future.delayed(wait);
          continue;
        }
      }
      if (_last != null) {
        final since = now.difference(_last!);
        if (since < minInterval) {
          await Future.delayed(minInterval - since);
        }
      }
      _last = DateTime.now();
      _hits.add(_last!);
      return;
    }
  }

  /// 429 退避时长：指数增长 1s→30s。
  static Duration backoff(int retry) {
    final secs = (1 << retry).clamp(1, 30);
    return Duration(seconds: secs);
  }
}

/// 每源一个限流器的注册表。
class RateLimiters {
  final Map<String, RateLimiter> _map = {};
  final Map<String, RateLimiter> config;

  RateLimiters({Map<String, RateLimiter>? defaults})
      : config = defaults ?? const {} {
    config.forEach((k, v) => _map[k] = v);
  }

  RateLimiter forSource(String source) =>
      _map.putIfAbsent(source, () => config[source] ?? RateLimiter());
}
