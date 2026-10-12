import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/varna_colors.dart';
import 'ui_kit.dart';

/// Shows the image stored under [attachmentId] (read from the attachment
/// store, so it also works on web where attachments live in memory).
class AttachmentImage extends ConsumerStatefulWidget {
  const AttachmentImage({
    super.key,
    required this.attachmentId,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  final String attachmentId;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  ConsumerState<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends ConsumerState<AttachmentImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List?> _load() async {
    try {
      return await ref.read(attachmentStoreProvider).read(widget.attachmentId);
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentId != widget.attachmentId) {
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    Widget placeholder() => ColoredBox(
          color: colors.hairline,
          child: Center(
            child: Icon(Icons.image_not_supported_outlined, color: colors.muted),
          ),
        );
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ColoredBox(color: colors.hairline);
        }
        final Uint8List? bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return placeholder();
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          semanticLabel: widget.semanticLabel,
          errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
              placeholder(),
        );
      },
    );
  }
}

/// Opens [attachmentId] full screen with pinch-to-zoom. When [onRemove] is
/// given a "Remove photo" button is shown; it is called after the viewer has
/// closed.
Future<void> showAttachmentViewer(
  BuildContext context, {
  required String attachmentId,
  VoidCallback? onRemove,
}) async {
  final bool? remove = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: AttachmentImage(
                    attachmentId: attachmentId,
                    fit: BoxFit.contain,
                    semanticLabel: 'Photo',
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: RoundIconButton(
                  icon: Icons.close,
                  tooltip: 'Close photo',
                  background: Colors.white24,
                  foreground: Colors.white,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
              ),
              if (onRemove != null)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: VarnaColors.of(dialogContext).ink,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove photo'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (remove == true && onRemove != null) {
    onRemove();
  }
}
