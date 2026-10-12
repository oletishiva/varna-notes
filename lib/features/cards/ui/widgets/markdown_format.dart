import 'package:flutter/material.dart';

// Text cards are plain text with a tiny Markdown subset:
//   **bold**    *italic*    "- " at the start of a line = bullet.
// The toolbar only inserts these markers around the selection (or at the
// cursor); the editor shows the formatting live while keeping the markers
// visible but dimmed, and shares/exports the text exactly as typed. There is
// deliberately no rich-text editor package.

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

final RegExp _inlinePattern = RegExp(r'\*\*([^*\n]+)\*\*|\*([^*\n]+)\*');

/// Wraps the selection in [marker] (for example `**`). With nothing selected
/// the markers are inserted around the cursor. When the selection is already
/// wrapped, the markers are removed again.
TextEditingValue toggleWrap(TextEditingValue value, String marker) {
  final String text = value.text;
  TextSelection sel = value.selection;
  if (!sel.isValid) {
    sel = TextSelection.collapsed(offset: text.length);
  }
  final int start = _clampInt(sel.start, 0, text.length);
  final int end = _clampInt(sel.end, 0, text.length);
  final int m = marker.length;
  final String selected = text.substring(start, end);

  bool wrapped = start >= m &&
      end + m <= text.length &&
      text.substring(start - m, start) == marker &&
      text.substring(end, end + m) == marker;
  // A single `*` next to another `*` belongs to a bold marker: leave it.
  if (wrapped && m == 1) {
    final bool partOfBold = (start >= 2 && text[start - 2] == '*') ||
        (end + 1 < text.length && text[end + 1] == '*');
    if (partOfBold) {
      wrapped = false;
    }
  }

  if (wrapped) {
    final String next =
        text.substring(0, start - m) + selected + text.substring(end + m);
    return TextEditingValue(
      text: next,
      selection: TextSelection(baseOffset: start - m, extentOffset: end - m),
    );
  }
  final String next = '${text.substring(0, start)}$marker$selected'
      '$marker${text.substring(end)}';
  return TextEditingValue(
    text: next,
    selection: TextSelection(baseOffset: start + m, extentOffset: end + m),
  );
}

/// Adds [prefix] (for example `- `) to every line touched by the selection,
/// or removes it when all those lines already start with it.
TextEditingValue togglePrefix(TextEditingValue value, String prefix) {
  final String text = value.text;
  TextSelection sel = value.selection;
  if (!sel.isValid) {
    sel = TextSelection.collapsed(offset: text.length);
  }
  final int start = _clampInt(sel.start, 0, text.length);
  int end = _clampInt(sel.end, 0, text.length);
  if (end > start && end > 0 && text[end - 1] == '\n') {
    end -= 1;
  }
  final int blockStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
  int blockEnd = text.indexOf('\n', end);
  if (blockEnd < 0) {
    blockEnd = text.length;
  }
  final String block = text.substring(blockStart, blockEnd);
  final List<String> lines = block.split('\n');
  final bool allPrefixed =
      lines.every((String line) => line.startsWith(prefix));
  final List<String> changed = lines
      .map((String line) => allPrefixed
          ? line.substring(prefix.length)
          : (line.startsWith(prefix) ? line : '$prefix$line'))
      .toList();
  final String newBlock = changed.join('\n');
  final String next =
      text.substring(0, blockStart) + newBlock + text.substring(blockEnd);

  if (sel.isCollapsed) {
    final int delta = allPrefixed
        ? -prefix.length
        : (lines.first.startsWith(prefix) ? 0 : prefix.length);
    final int caret = _clampInt(start + delta, blockStart, next.length);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret),
    );
  }
  return TextEditingValue(
    text: next,
    selection: TextSelection(
      baseOffset: blockStart,
      extentOffset: blockStart + newBlock.length,
    ),
  );
}

/// Spans for [text] with `**bold**` and `*italic*` rendered. With
/// [keepMarkers] the markers stay in the output (dimmed), so the total text is
/// unchanged, as an editor needs; without it they are dropped (for reading).
List<InlineSpan> markdownSpans(
  String text,
  TextStyle base, {
  bool keepMarkers = false,
}) {
  final List<InlineSpan> spans = <InlineSpan>[];
  final TextStyle dim =
      base.copyWith(color: (base.color ?? Colors.black).withValues(alpha: 0.4));
  int cursor = 0;
  for (final RegExpMatch match in _inlinePattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final String? boldText = match.group(1);
    final String marker = boldText != null ? '**' : '*';
    final String inner = boldText ?? match.group(2) ?? '';
    final TextStyle inner0 = boldText != null
        ? base.copyWith(fontWeight: FontWeight.w700)
        : base.copyWith(fontStyle: FontStyle.italic);
    if (keepMarkers) {
      spans.add(TextSpan(text: marker, style: dim));
    }
    spans.add(TextSpan(text: inner, style: inner0));
    if (keepMarkers) {
      spans.add(TextSpan(text: marker, style: dim));
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

/// A text controller that renders the Markdown subset above while editing.
/// The text itself is never changed.
class MarkdownTextEditingController extends TextEditingController {
  MarkdownTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final bool composing =
        withComposing && value.isComposingRangeValid && !value.composing.isCollapsed;
    if (composing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final TextStyle base = style ?? const TextStyle();
    return TextSpan(
      style: style,
      children: markdownSpans(text, base, keepMarkers: true),
    );
  }
}
