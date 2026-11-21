/// Fluent 2 共享图片选择对话框（支持比例适配、候选缩略图、手动 URL/路径输入、本地图片文件选择）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

import '../../core/media_paths.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';

/// 打开 Fluent 图片选择对话框，返回选中的图片 URL 或本地路径；取消返回 null。
Future<String?> showImagePickerDialog(
  BuildContext context, {
  required String title,
  List<String> candidates = const [],
  String? initialValue,
  double aspectRatio = 2 / 3,
  Future<String?> Function()? pickLocalFile,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ensureFluentScope(
      ctx,
      _ImagePickerDialog(
        title: title,
        candidates: candidates,
        initialValue: initialValue,
        aspectRatio: aspectRatio,
        pickLocalFile: pickLocalFile,
      ),
    ),
  );
}

class _ImagePickerDialog extends StatefulWidget {
  final String title;
  final List<String> candidates;
  final String? initialValue;
  final double aspectRatio;
  final Future<String?> Function()? pickLocalFile;

  const _ImagePickerDialog({
    required this.title,
    required this.candidates,
    required this.aspectRatio,
    this.initialValue,
    this.pickLocalFile,
  });

  @override
  State<_ImagePickerDialog> createState() => _ImagePickerDialogState();
}

class _ImagePickerDialogState extends State<_ImagePickerDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue?.trim() ?? '');
  late String _selected = widget.initialValue?.trim() ?? '';
  DateTime? _lastTapAt;
  String? _lastTapItem;

  late final List<String> _baseCandidates = _dedupe(widget.candidates);

  static List<String> _dedupe(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in raw) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        out.add(trimmed);
      }
    }
    return out;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static bool _isPreviewableInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    }
    if ('http://'.startsWith(lower) || 'https://'.startsWith(lower)) {
      return false;
    }
    try {
      final resolved = MediaPaths.instance.resolveStored(trimmed);
      return resolved.isNotEmpty && File(resolved).existsSync();
    } catch (_) {
      return false;
    }
  }

  List<String> get _displayItems {
    if (_selected.isEmpty ||
        _baseCandidates.contains(_selected) ||
        !_isPreviewableInput(_selected)) {
      return _baseCandidates;
    }
    return [_selected, ..._baseCandidates];
  }

  void _select(String value) {
    setState(() {
      _selected = value;
      if (_ctrl.text.trim() != value) {
        _ctrl.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    });
  }

  Future<void> _pickLocal() async {
    String? path;
    if (widget.pickLocalFile != null) {
      path = await widget.pickLocalFile!();
    } else {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: widget.title,
      );
      path = res?.files.single.path;
    }
    if (!mounted || path == null || path.trim().isEmpty) return;
    _select(path.trim());
  }

  void _confirm([String? explicit]) {
    final value = (explicit ?? _selected).trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentInk;
    final items = _displayItems;
    final manualInput = _selected.isNotEmpty &&
        !_baseCandidates.contains(_selected) &&
        !_isPreviewableInput(_selected);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 740, maxHeight: 640),
      title: Row(
        children: [
          Icon(FluentIcons.image_20_regular, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
          if (items.isNotEmpty)
            Text(
              '${items.length} 个候选',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoLabel(
            label: '图片地址或本地路径',
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _ctrl,
                    placeholder: '输入图片链接 (http/https) 或本地文件路径',
                    prefix: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Icon(
                        FluentIcons.image_16_regular,
                        size: 14,
                        color: theme.textSecondary,
                      ),
                    ),
                    suffix: _ctrl.text.isNotEmpty
                        ? Tooltip(
                            message: '清空输入',
                            child: IconButton(
                              icon: const Icon(
                                FluentIcons.dismiss_12_regular,
                                size: 12,
                              ),
                              onPressed: () {
                                _ctrl.clear();
                                setState(() => _selected = '');
                              },
                            ),
                          )
                        : null,
                    onChanged: (v) => setState(() => _selected = v.trim()),
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: _pickLocal,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.folder_open_20_regular, size: 16),
                      SizedBox(width: 6),
                      Text('浏览本地图片…'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (manualInput) ...[
            const SizedBox(height: 6),
            Text(
              '未检测到本地图片或完整 http(s) 地址，仍可直接按当前文本确定',
              style: theme.typography.caption?.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: FluentEmptyState(
                icon: FluentIcons.image_24_regular,
                title: '暂无候选图片',
                message: '可输入图片 URL 或点击「浏览本地图片…」选择本地文件',
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: widget.aspectRatio > 1.2 ? 220 : 140,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: widget.aspectRatio,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = item == _selected;
                    return _CandidateTile(
                      pathOrUrl: item,
                      selected: selected,
                      accentColor: accent,
                      onTap: () {
                        final now = DateTime.now();
                        final isDouble = _lastTapItem == item &&
                            _lastTapAt != null &&
                            now.difference(_lastTapAt!) <
                                const Duration(milliseconds: 350);
                        _lastTapItem = item;
                        _lastTapAt = now;
                        if (isDouble) {
                          _confirm(item);
                        } else {
                          _select(item);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty ? null : () => _confirm(),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final String pathOrUrl;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _CandidateTile({
    required this.pathOrUrl,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  static String _shortTooltip(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.host.isNotEmpty) {
      return '${uri.host}\n$raw';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final disableAnim = fluentAnimationsDisabled(context);

    return Tooltip(
      message: _shortTooltip(pathOrUrl),
      child: Semantics(
        button: true,
        selected: selected,
        label: '候选图片：$pathOrUrl',
        child: HoverButton(
          cursor: SystemMouseCursors.click,
          onPressed: onTap,
            builder: (context, states) {
              final borderColor = selected
                  ? accentColor
                  : (states.isHovered
                      ? accentColor.withValues(alpha: 0.65)
                      : theme.surfaceStroke);

              return FocusBorder(
                focused: states.isFocused,
                renderOutside: false,
                child: AnimatedContainer(
                  duration: disableAnim ? Duration.zero : FluentMotion.fast,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                      width: selected ? 2.0 : 1.0,
                    ),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FluentCoverImage(
                        pathOrUrl: pathOrUrl,
                        fit: BoxFit.cover,
                        radius: 6,
                        allowRevealOnHover: false,
                      ),
                      if (selected)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.onAccentInk.withValues(alpha: 0.25),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              FluentIcons.checkmark_12_regular,
                              size: 13,
                              color: theme.onAccentInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
  }
}
