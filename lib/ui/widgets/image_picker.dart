/// 图片选择器：横向预览行 +「查看全部」网格弹窗。
///
/// 用于添加游戏与编辑信息中的封面/背景选择——候选很多时，
/// 横向一行很难挑到后面的图片，这里提供带滚动条的预览 + 全屏网格挑选。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

class ImageOption {
  final String label; // 平台名 / 分类名
  final String url; // 网络地址（与 localPath 二选一）
  final String localPath;
  final bool isSolid; // 纯色选项（无图）
  const ImageOption({
    required this.label,
    this.url = '',
    this.localPath = '',
    this.isSolid = false,
  });
}

/// 横跨整宽的图片选择行（自带滚动条与「查看全部」入口）。
class ImagePickerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ImageOption> options;
  final String? selectedUrl; // 选中的 url（'' 表示纯色/本地）
  final String selectedLocal;
  final double tileWidth;
  final ValueChanged<ImageOption> onPick;

  const ImagePickerRow({
    super.key,
    required this.title,
    required this.options,
    required this.selectedUrl,
    required this.onPick,
    this.subtitle = '',
    this.selectedLocal = '',
    this.tileWidth = 62,
  });

  bool _isSelected(ImageOption o) {
    if (o.isSolid) return (selectedUrl ?? '') == '' && selectedLocal.isEmpty;
    if (o.localPath.isNotEmpty) return selectedLocal == o.localPath;
    return selectedUrl == o.url;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final controller = ScrollController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(width: 8),
            if (subtitle.isNotEmpty)
              Expanded(
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            if (options.length > 4)
              TextButton.icon(
                onPressed: () => ImagePickerDialog.show(
                  context,
                  title: title,
                  options: options,
                  isSelected: _isSelected,
                  onPick: onPick,
                ),
                icon: const Icon(Icons.grid_view_rounded, size: 16),
                label: Text('查看全部 ${options.length}'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: tileWidth / (2 / 3) + 14,
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                for (final o in options)
                  _Tile(
                    option: o,
                    width: tileWidth,
                    selected: _isSelected(o),
                    dark: dark,
                    onTap: () => onPick(o),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final ImageOption option;
  final double width;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  const _Tile({
    required this.option,
    required this.width,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: option.label,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: width,
                height: width / (2 / 3),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? scheme.primary : Theme.of(context).dividerColor,
                    width: selected ? 2 : 1,
                  ),
                  color: scheme.surfaceContainerHigh,
                ),
                child: option.isSolid
                    ? const Icon(Icons.format_color_fill_rounded, size: 20)
                    : (option.localPath.isNotEmpty
                        ? Image.file(File(option.localPath), fit: BoxFit.cover)
                        : (option.url.isNotEmpty
                            ? Image.network(option.url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image_rounded,
                                    size: 16))
                            : const Icon(Icons.image_rounded, size: 18))),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: width,
                child: Text(option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        color: selected
                            ? scheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 网格挑选弹窗：候选多时用大图网格选择。
class ImagePickerDialog extends StatelessWidget {
  final String title;
  final List<ImageOption> options;
  final bool Function(ImageOption) isSelected;
  final ValueChanged<ImageOption> onPick;

  const ImagePickerDialog({
    super.key,
    required this.title,
    required this.options,
    required this.isSelected,
    required this.onPick,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<ImageOption> options,
    required bool Function(ImageOption) isSelected,
    required ValueChanged<ImageOption> onPick,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ImagePickerDialog(
        title: title,
        options: options,
        isSelected: isSelected,
        onPick: onPick,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: dark ? KisakiColors.nightCard : Colors.white,
      title: Text('$title（${options.length}）'),
      content: SizedBox(
        width: 720,
        height: 460,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 132,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2 / 3,
          ),
          itemCount: options.length,
          itemBuilder: (context, i) {
            final o = options[i];
            final selected = isSelected(o);
            return GestureDetector(
              onTap: () {
                onPick(o);
                Navigator.pop(context);
              },
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: o.isSolid
                          ? const Icon(Icons.format_color_fill_rounded, size: 22)
                          : (o.localPath.isNotEmpty
                              ? Image.file(File(o.localPath), fit: BoxFit.cover)
                              : Image.network(o.url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image_rounded, size: 18))),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(o.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭')),
      ],
    );
  }
}
