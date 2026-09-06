/// 右上角通知卡片：可滚动、可手动关闭、自动消失。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';

class AppNotice {
  final int id;
  final String message;
  final bool error;
  AppNotice({required this.id, required this.message, this.error = false});
}

final appNoticesProvider = StateProvider<List<AppNotice>>((ref) => []);

int _nextId = 1;

/// 弹出右上角通知卡片（自动 4.5s 消失，可手动关闭）。
void showNotice(WidgetRef ref, String message, {bool error = false}) {
  final id = _nextId++;
  ref.read(appNoticesProvider.notifier).state = [
    ...ref.read(appNoticesProvider),
    AppNotice(id: id, message: message, error: error),
  ];
  Timer(const Duration(milliseconds: 4500), () => _remove(ref, id));
}

void _remove(WidgetRef ref, int id) {
  ref.read(appNoticesProvider.notifier).state =
      ref.read(appNoticesProvider).where((n) => n.id != id).toList();
}

/// 挂在 MaterialApp builder 顶层：右上角堆叠通知卡。
class NoticeOverlay extends ConsumerWidget {
  final Widget child;
  const NoticeOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(appNoticesProvider);
    return Stack(
      children: [
        child,
        if (notices.isNotEmpty)
          Positioned(
            top: 56,
            right: 16,
            width: 340,
            child: Material(
              color: Colors.transparent,
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
                              onClose: () => _remove(ref, n.id)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
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
                  color: dark
                      ? KisakiColors.nightInkSoft
                      : KisakiColors.inkSoft),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}
