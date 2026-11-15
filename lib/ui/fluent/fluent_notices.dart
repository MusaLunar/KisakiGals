/// Fluent 2 全局通知中心（InfoBar 浮层队列）。
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_animate/flutter_animate.dart';

class AppNotice {
  final int id;
  final String message;
  final bool error;
  const AppNotice({required this.id, required this.message, this.error = false});
}

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
    while (_items.length > 3) {
      final oldest = _items.first;
      _timers.remove(oldest.id)?.cancel();
      _items.removeAt(0);
    }
    _timers[id]?.cancel();
    _timers[id] = Timer(duration ?? const Duration(milliseconds: 3600), () {
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

void showNotice(String message, {bool error = false, Duration? duration}) =>
    NoticeCenter.instance.show(message, error: error, duration: duration);

class FluentNoticeHost extends StatelessWidget {
  const FluentNoticeHost({super.key});

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) != null) {
      return const _NoticeOverlayLayer();
    }
    // FluentApp.builder 与 Navigator 平级，外层没有 Overlay 祖先；
    // 通过 Overlay.wrap 兜底，确保 InfoBar 关闭按钮上的 Tooltip 悬停时不崩溃。
    return Overlay.wrap(child: const _NoticeOverlayLayer());
  }
}

class _NoticeOverlayLayer extends StatefulWidget {
  const _NoticeOverlayLayer();

  @override
  State<_NoticeOverlayLayer> createState() => _NoticeOverlayLayerState();
}

class _NoticeOverlayLayerState extends State<_NoticeOverlayLayer> {
  @override
  void initState() {
    super.initState();
    NoticeCenter.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    NoticeCenter.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = NoticeCenter.instance.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 54, right: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final n in items)
                  Padding(
                    key: ValueKey(n.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _NoticeInfoCard(
                      notice: n,
                      disableAnim: disableAnim,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeInfoCard extends StatelessWidget {
  final AppNotice notice;
  final bool disableAnim;

  const _NoticeInfoCard({required this.notice, required this.disableAnim});

  @override
  Widget build(BuildContext context) {
    final bar = InfoBar(
      title: Text(notice.error ? '操作提示' : '通知'),
      content: Text(notice.message),
      severity: notice.error ? InfoBarSeverity.error : InfoBarSeverity.info,
      isLong: notice.message.length > 34,
      onClose: () => NoticeCenter.instance.dismiss(notice.id),
    );
    if (disableAnim) return bar;
    return bar
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 160))
        .slideX(
          begin: 0.08,
          end: 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
  }
}
