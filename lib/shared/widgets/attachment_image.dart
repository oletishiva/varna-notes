import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Bytes of a stored attachment (null when missing).
final attachmentBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, id) => ref.watch(attachmentStoreProvider).read(id),
);

/// Shows an image attachment, or [placeholder] while loading / when missing.
class AttachmentImage extends ConsumerWidget {
  const AttachmentImage({
    super.key,
    required this.attachmentId,
    this.fit = BoxFit.cover,
    this.placeholder = const SizedBox.shrink(),
  });

  final String attachmentId;
  final BoxFit fit;
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List?> bytes =
        ref.watch(attachmentBytesProvider(attachmentId));
    return bytes.when(
      data: (Uint8List? data) {
        if (data == null || data.isEmpty) {
          return placeholder;
        }
        return Image.memory(
          data,
          fit: fit,
          cacheWidth: 700,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
              placeholder,
        );
      },
      loading: () => placeholder,
      error: (Object _, StackTrace __) => placeholder,
    );
  }
}
