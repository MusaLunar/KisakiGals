/// Fluent 2 标准 ContentDialog 辅助工具。
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;

import '../../core/media_paths.dart';
import 'fluent_icons.dart';

Future<bool> showFluentConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => ContentDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        Button(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        destructive
            ? Button(
                style: const ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Color(0xFFD13438)),
                  foregroundColor: WidgetStatePropertyAll(Colors.white),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              )
            : FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
      ],
    ),
  );
  return result == true;
}

Future<void> showFluentInfoDialog(
  BuildContext context, {
  required String title,
  required String content,
  String closeLabel = '知道了',
  IconData? icon,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ContentDialog(
      title: icon == null
          ? Text(title)
          : Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
              ],
            ),
      content: Text(content),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(closeLabel),
        ),
      ],
    ),
  );
}

Future<void> showFluentLightboxDialog(
  BuildContext context, {
  required String pathOrUrl,
  String title = '图片预览',
  String? caption,
}) async {
  final trimmed = pathOrUrl.trim();
  final isNet =
      trimmed.startsWith('http://') || trimmed.startsWith('https://');
  var resolved = trimmed;
  if (!isNet && trimmed.isNotEmpty) {
    try {
      resolved = MediaPaths.instance.resolveStored(trimmed);
    } catch (_) {
      resolved = trimmed;
    }
  }

  Widget buildFallback() => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Icon(FluentIcons.image_24_regular, size: 40),
        ),
      );

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ContentDialog(
      constraints: const BoxConstraints(maxWidth: 960, maxHeight: 740),
      title: Row(
        children: [
          const Icon(FluentIcons.image_20_regular, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(FluentIcons.dismiss_20_regular, size: 16),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: resolved.isEmpty
                    ? buildFallback()
                    : isNet
                        ? CachedNetworkImage(
                            imageUrl: resolved,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => buildFallback(),
                          )
                        : Image.file(
                            File(resolved),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => buildFallback(),
                          ),
              ),
            ),
          ),
          if (caption != null && caption.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(caption),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
