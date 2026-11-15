/// Fluent 2 共享图片选择对话框（支持候选缩略图、手动 URL/路径输入、本地图片文件选择）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

import '../fluent/fluent_icons.dart';
import '../fluent/fluent_surfaces.dart';

/// 打开 Fluent 图片选择对话框，返回选中的图片 URL 或本地路径；取消返回 null。
Future<String?> showImagePickerDialog(
  BuildContext context, {
  required String title,
  List<String> candidates = const [],
  String? initialValue,
  Future<String?> Function()? pickLocalFile,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ImagePickerDialog(
      title: title,
      candidates: candidates,
      initialValue: initialValue,
      pickLocalFile: pickLocalFile,
    ),
  );
}

class _ImagePickerDialog extends StatefulWidget {
  final String title;
  final List<String> candidates;
  final String? initialValue;
  final Future<String?> Function()? pickLocalFile;

  const _ImagePickerDialog({
    required this.title,
    required this.candidates,
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

  List<String> get _displayItems {
    if (_selected.isEmpty || _baseCandidates.contains(_selected)) {
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

  void _confirm() {
    final value = _selected.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final items = _displayItems;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
      title: Row(
        children: [
          const Icon(FluentIcons.image_20_regular, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _ctrl,
                  placeholder: '输入图片链接 (http/https) 或本地文件路径',
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
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2 / 3,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = item == _selected;
                    return _CandidateTile(
                      pathOrUrl: item,
                      selected: selected,
                      accentColor: accent,
                      onTap: () => _select(item),
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
          onPressed: _selected.isEmpty ? null : _confirm,
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

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Tooltip(
      message: pathOrUrl,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? accentColor
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.1)),
                width: selected ? 2.5 : 1,
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
                      decoration: const BoxDecoration(
                        color: Color(0xCCFFFFFF),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(1),
                      child: Icon(
                        FluentIcons.checkmark_circle_16_filled,
                        size: 16,
                        color: accentColor,
                      ),
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
