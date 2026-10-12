import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/varna_colors.dart';
import '../../core/theme/varna_theme.dart';
import '../format.dart';
import 'attachment_image.dart';
import 'tokens.dart';

/// The coloured preview of a [NoteCard] used in the notebook masonry.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    this.onTap,
    this.onLongPress,
  });

  final NoteCard card;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  bool get _imageCard =>
      card.type == CardType.photo || card.type == CardType.scan;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final Widget content;
    switch (card.type) {
      case CardType.text:
        content = _text(context);
      case CardType.checklist:
        content = _checklist(context);
      case CardType.voice:
        content = _voice(context);
      case CardType.photo:
        content = _photo(context);
      case CardType.scan:
        content = _scan(context);
      case CardType.link:
        content = _link(context);
    }
    return Material(
      color: _imageCard ? c.surface : c.cardColor(card.colorIndex),
      borderRadius: BorderRadius.circular(VarnaMetrics.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.all(card.type == CardType.photo ? 8 : 16),
          child: content,
        ),
      ),
    );
  }

  String get _when => relativeDay(card.updatedAt);

  Widget _title(BuildContext context, {double size = 18, String fallback = ''}) {
    final String text = card.title.trim().isEmpty ? fallback : card.title.trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: displayStyle(context, size, letterSpacing: -0.2, height: 1.15),
    );
  }

  Widget _footer(BuildContext context, String text, {Color? color}) {
    final VarnaColors c = VarnaColors.of(context);
    final Color fg = color ?? c.ink;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(context, 12, weight: FontWeight.w600, color: fg),
          ),
        ),
        if (card.reminderAt != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              label: 'Has a reminder',
              child: Icon(Icons.notifications_none_rounded, size: 16, color: fg),
            ),
          ),
        if (card.favourite)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              label: 'Favourite',
              child: Icon(Icons.star_rounded, size: 16, color: fg),
            ),
          ),
      ],
    );
  }

  Widget _text(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final bool empty = card.title.trim().isEmpty && card.body.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _title(context),
        if (card.body.trim().isNotEmpty || empty) ...<Widget>[
          SizedBox(height: card.title.trim().isEmpty ? 0 : 8),
          Text(
            empty ? 'Empty note' : card.body.trim(),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(context, 14, color: empty ? c.muted : c.ink),
          ),
        ],
        const SizedBox(height: 12),
        _footer(context, 'Text, $_when'),
      ],
    );
  }

  Widget _checklist(BuildContext context) {
    final List<ChecklistItem> shown = card.items.take(4).toList();
    final int more = card.items.length - shown.length;
    final VarnaColors c = VarnaColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _title(context, fallback: 'Checklist'),
        const SizedBox(height: 10),
        for (final ChecklistItem item in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: item.done ? c.ink : null,
                    borderRadius: BorderRadius.circular(5),
                    border: item.done ? null : Border.all(color: c.ink, width: 2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(context, 14).copyWith(
                      decoration: item.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '+$more more',
              style: bodyStyle(context, 12, weight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 4),
        _footer(context, 'Checklist, ${card.doneCount} of ${card.items.length}'),
      ],
    );
  }

  /// Deterministic bar heights so a card always shows the same waveform.
  List<double> _bars() {
    int seed = card.id.codeUnits.fold<int>(7, (int a, int b) => (a * 31 + b) & 0x7fffffff);
    final List<double> out = <double>[];
    for (int i = 0; i < 10; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      out.add(8 + ((seed >> 8) % 31).toDouble());
    }
    return out;
  }

  Widget _voice(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    int? durationMs;
    for (final Attachment a in card.attachments) {
      if (a.kind == AttachmentKind.audio) {
        durationMs = a.durationMs;
        break;
      }
    }
    final String transcript = (card.transcript ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                for (final double h in _bars())
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      width: 4,
                      height: h,
                      decoration: BoxDecoration(
                        color: c.ink,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          card.title.trim().isEmpty ? 'Voice note' : card.title.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(context, 15, weight: FontWeight.w700, height: 1.25),
        ),
        if (transcript.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            transcript,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(context, 13),
          ),
        ],
        const SizedBox(height: 6),
        _footer(context, 'Voice, ${formatDuration(durationMs)}'),
      ],
    );
  }

  String? get _imageId {
    for (final Attachment a in card.attachments) {
      if (a.kind == AttachmentKind.image) {
        return a.id;
      }
    }
    return null;
  }

  Widget _imagePlaceholder(BuildContext context, String label, Color color) {
    final VarnaColors c = VarnaColors.of(context);
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        label,
        style: bodyStyle(context, 12, weight: FontWeight.w600, color: c.muted),
      ),
    );
  }

  Widget _photo(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final String? id = _imageId;
    final Widget placeholder =
        _imagePlaceholder(context, 'Photo', c.cardColor(card.colorIndex));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 128,
            width: double.infinity,
            child: id == null
                ? placeholder
                : AttachmentImage(attachmentId: id, placeholder: placeholder),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: _footer(
            context,
            card.title.trim().isEmpty
                ? 'Photo, $_when'
                : '${card.title.trim()}, $_when',
            color: c.muted,
          ),
        ),
      ],
    );
  }

  Widget _scan(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final String? id = _imageId;
    final int pages = card.attachments
        .where((Attachment a) => a.kind == AttachmentKind.image)
        .length;
    final Widget placeholder = _imagePlaceholder(context, 'Scanned page', c.hairline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 84,
            width: double.infinity,
            child: id == null
                ? placeholder
                : AttachmentImage(attachmentId: id, placeholder: placeholder),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          card.title.trim().isEmpty ? 'Scan' : card.title.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(context, 15, weight: FontWeight.w700, height: 1.25),
        ),
        const SizedBox(height: 4),
        _footer(
          context,
          'Scan, ${pluralize(pages < 1 ? 1 : pages, 'page')}',
          color: c.muted,
        ),
      ],
    );
  }

  Widget _link(BuildContext context) {
    final String url = card.body.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          card.title.trim().isEmpty ? (url.isEmpty ? 'Link' : url) : card.title.trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(context, 15, weight: FontWeight.w700, height: 1.25),
        ),
        if (url.isNotEmpty && card.title.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(context, 12),
          ),
        ],
        const SizedBox(height: 8),
        _footer(context, 'Link, $_when'),
      ],
    );
  }
}
