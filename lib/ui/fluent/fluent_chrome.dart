/// 共享无边框窗口标题按钮与子页面 Fluent 2 顶部导航标题栏。
library;

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:window_manager/window_manager.dart';

import 'fluent_icons.dart';
import 'fluent_motion.dart';
import 'fluent_theme.dart';

/// Windows 11 原生感窗口标题栏按钮（最小化 / 最大化-还原 / 关闭）。
class WindowCaptionButtons extends StatelessWidget {
  final bool enabled;
  final bool isMaximized;
  final VoidCallback onToggleMaximize;
  final double height;

  const WindowCaptionButtons({
    super.key,
    required this.enabled,
    required this.isMaximized,
    required this.onToggleMaximize,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: FluentIcons.subtract_16_regular,
          tooltip: '最小化',
          height: height,
          onPressed: enabled ? windowManager.minimize : null,
        ),
        _CaptionButton(
          icon: isMaximized
              ? FluentIcons.square_multiple_16_regular
              : FluentIcons.maximize_16_regular,
          tooltip: isMaximized ? '还原' : '最大化',
          height: height,
          onPressed: enabled ? onToggleMaximize : null,
        ),
        _CaptionButton(
          icon: FluentIcons.dismiss_16_regular,
          tooltip: '关闭',
          height: height,
          isClose: true,
          onPressed: enabled ? windowManager.close : null,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double height;
  final bool isClose;
  final VoidCallback? onPressed;

  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.height,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final disableAnim = fluentAnimationsDisabled(context);
    final idleFg = theme.textSecondary;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: HoverButton(
          onPressed: onPressed,
          builder: (context, states) {
            final pressed = states.isPressed;
            final hovered = states.isHovered;
            final focused = states.isFocused;
            final Color hoverBg;
            final Color fg;
            if (isClose) {
              hoverBg = pressed
                  ? const Color(0xFFB32719)
                  : (hovered || focused)
                      ? const Color(0xFFC42B1C)
                      : Colors.transparent;
              fg = (hovered || pressed || focused) ? Colors.white : idleFg;
            } else {
              hoverBg = pressed
                  ? theme.subtlePressed
                  : (hovered || focused)
                      ? theme.subtleHover
                      : Colors.transparent;
              fg = (hovered || pressed || focused)
                  ? theme.textPrimary
                  : idleFg;
            }
            return AnimatedContainer(
              duration: disableAnim ? Duration.zero : FluentMotion.fast,
              curve: FluentMotion.enterCurve,
              width: 46,
              height: height,
              alignment: Alignment.center,
              color: hoverBg,
              child: Icon(icon, size: 14, color: fg),
            );
          },
        ),
      ),
    );
  }
}

/// 推入子页面（详情页、全网百科页）专用无边框 48px 标题栏：
/// 保留返回按钮、面包屑导航、窗口拖拽区与 Win11 右上角控制按钮。
class FluentSubpageTitleBar extends StatefulWidget {
  final VoidCallback onBack;
  final String backTooltip;
  final Widget? breadcrumb;
  final String? title;
  final List<Widget> trailing;
  final bool enableWindowHooks;

  const FluentSubpageTitleBar({
    super.key,
    required this.onBack,
    this.backTooltip = '返回 (Alt+← / Esc)',
    this.breadcrumb,
    this.title,
    this.trailing = const [],
    this.enableWindowHooks = true,
  });

  @override
  State<FluentSubpageTitleBar> createState() => _FluentSubpageTitleBarState();
}

class _FluentSubpageTitleBarState extends State<FluentSubpageTitleBar>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableWindowHooks) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((v) {
        if (mounted && v != _isMaximized) {
          setState(() => _isMaximized = v);
        }
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    if (widget.enableWindowHooks) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (!widget.enableWindowHooks) return;
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final barBg = theme.isDark
        ? const Color(0xB8202020)
        : const Color(0xC8F3F3F3);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          bottom: BorderSide(color: theme.dividerHairline),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Tooltip(
            message: widget.backTooltip,
            child: Semantics(
              label: '返回',
              button: true,
              child: IconButton(
                icon: const Icon(FluentIcons.arrow_left_16_regular, size: 16),
                onPressed: widget.onBack,
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (widget.breadcrumb != null)
            Flexible(flex: 3, child: widget.breadcrumb!)
          else if (widget.title != null)
            Flexible(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  widget.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.bodyStrong,
                ),
              ),
            ),
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap:
                    widget.enableWindowHooks ? _toggleMaximize : null,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (widget.trailing.isNotEmpty) ...[
            ...widget.trailing,
            const SizedBox(width: 8),
          ],
          WindowCaptionButtons(
            enabled: widget.enableWindowHooks,
            isMaximized: _isMaximized,
            onToggleMaximize: _toggleMaximize,
            height: 48,
          ),
        ],
      ),
    );
  }
}
