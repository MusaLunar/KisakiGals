/// 右上角通知卡片：可滚动、可手动关闭、自动消失。
///
/// 设计要点：通知中心**不依赖 Riverpod / WidgetRef**。
/// 早先的实现把 `WidgetRef` 捕获进 `Timer`，4.5 秒后回调时页面可能已销毁
/// （「提示后立刻 pop」的调用点很多），会抛 StateError 且通知卡永久残留。
///
/// 视觉走基础层：卡片本体是 `KCard(overlayShadow: true)`（浮层重投影 +
/// 1px 描边），间距 / 圆角 / 字号取 Gap / Radii / Type。
/// 注意：本组件挂在 `MaterialApp.builder` 上，与 Navigator **平级**，
/// 因此**没有 Overlay 祖先**——带 Tooltip 的 KIconAction 在这里会崩
/// （Tooltip 依赖 OverlayPortal），关闭按钮必须保持无 tooltip 的 IconButton。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../design.dart';
import '../kit.dart';
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
    // 最多同时显示 3 条（参考 Reimanager 的 maxSnack=3）
    while (_items.length > 3) {
      final oldest = _items.first;
      _timers.remove(oldest.id)?.cancel();
      _items.removeAt(0);
    }
    _timers[id]?.cancel();
    _timers[id] = Timer(duration ?? const Duration(milliseconds: 3500), () {
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

/// 挂在 MaterialApp builder 顶层：为通知浮层提供 **Overlay 祖先**。
///
/// 背景：NoticeOverlay 与 Navigator 平级挂在 builder 的 Stack 里，
/// 祖先链中没有 Overlay，于是任何带 Tooltip 的控件（Tooltip 走
/// OverlayPortal）在悬停时会因找不到 Overlay 而崩溃。这里用一个
/// 常驻 Overlay 包住通知层，使通知内部可以正常使用 kit 的图标按钮。
class NoticeHost extends StatefulWidget {
  const NoticeHost({super.key});

  @override
  State<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends State<NoticeHost> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => const NoticeOverlay(child: SizedBox.shrink()),
  );

  @override
  Widget build(BuildContext context) =>
      Overlay(initialEntries: [_entry]);

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }
}

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
                          padding: const EdgeInsets.only(bottom: Gap.sm),
                          child: _NoticeCard(
                            // 以通知 id 为 key：某条消失时不会让后面的卡错位复用状态
                            key: ValueKey<int>(n.id),
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
  const _NoticeCard({super.key, required this.notice, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final base = dark ? KisakiColors.nightCard : Colors.white;
    // 错误通知用语义色轻染底色（KCard 的描边色由 kit 统一，不逐条定制）
    final fill = notice.error
        ? Color.alphaBlend(
            scheme.error.withValues(alpha: dark ? 0.16 : 0.05), base)
        : base;
    final accent = notice.error ? scheme.error : KisakiColors.success;
    return KCard(
      overlayShadow: true,
      color: fill,
      borderRadius: BorderRadius.circular(Radii.md),
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.sm, Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.error
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: Gap.sm + 2),
          Expanded(
            child: Padding(
              // 与左侧图标的视觉基线对齐（图标 18，正文首行更高）
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                notice.message,
                style: Type.body.copyWith(
                    color: dark ? KisakiColors.nightInk : KisakiColors.ink),
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
              // 刻意不设 tooltip：本浮层没有 Overlay 祖先（见文件头注释）
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
