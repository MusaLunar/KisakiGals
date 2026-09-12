/// 右上角通知卡片：可滚动、可手动关闭、自动消失。
///
/// 设计要点：通知中心**不依赖 Riverpod / WidgetRef**。
/// 早先的实现把 `WidgetRef` 捕获进 `Timer`，4.5 秒后回调时页面可能已销毁
/// （「提示后立刻 pop」的调用点很多），会抛 StateError 且通知卡永久残留。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

class AppNotice {
  final int id;
  final String message;
  final bool error;
  const AppNotice({required this.id, required this.message, this.error = false});
}

/// 全局通知中心（ChangeNotifier，无 Widget 依赖）。
class NoticeCenter extends ChangeNotifier {
  NoticeCenter._();
  static final NoticeCenter instance = NoticeCenter._();

  final List<AppNotice> _items = [];
  final Map<int, Timer> _timers = {};
  int _nextId = 1;

  List<AppNotice> get items => List.unmodifiable(_items);

  void show(String message, {bool error = false, Duration? duration}) {
    final id = _nextId++;
    _items.add(AppNotice(id: id, message: message, error: error));
    _timers[id]?.cancel();
    _timers[id] = Timer(duration ?? const Duration(milliseconds: 4500), () {
      dismiss(id);
    });
    notifyListeners();
  }

  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    final before = _items.length;
    _items.removeWhere((n) => n.id == id);
    if (_items.length != before) notifyListeners();
  }

  void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _items.clear();
    notifyListeners();
  }
}

/// 弹出右上角通知（可在任意位置调用：await 之后、页面 pop 之前都安全）。
void showNotice(String message, {bool error = false}) =>
    NoticeCenter.instance.show(message, error: error);

/// 挂在 MaterialApp builder 顶层：右上角堆叠通知卡。
class NoticeOverlay extends StatelessWidget {
  final Widget child;
  const NoticeOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        AnimatedBuilder(
          animation: NoticeCenter.instance,
          builder: (context, _) {
            final notices = NoticeCenter.instance.items;
            if (notices.isEmpty) return const SizedBox.shrink();
            return Positioned(
              top: 56,
              right: 16,
              width: 340,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final n in notices.reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _NoticeCard(
                            notice: n,
                            onClose: () => NoticeCenter.instance.dismiss(n.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final AppNotice notice;
  final VoidCallback onClose;
  const _NoticeCard({required this.notice, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: dark ? KisakiColors.nightCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: notice.error
              ? KisakiColors.pink.withValues(alpha: 0.5)
              : (dark ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.4 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.error
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 18,
            color: notice.error ? KisakiColors.pink : const Color(0xFF7EC8C3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: dark ? KisakiColors.nightInk : KisakiColors.ink,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: Icon(Icons.close_rounded,
                  color:
                      dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}
