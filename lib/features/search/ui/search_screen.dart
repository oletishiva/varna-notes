import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/app_state.dart';
import '../../cards/ui/widgets/attachment_image.dart';
import '../../cards/ui/widgets/format_utils.dart';
import '../../cards/ui/widgets/tinted_card_scaffold.dart';
import '../../cards/ui/widgets/ui_kit.dart';

enum _Filter {
  all('All', null),
  text('Text', CardType.text),
  scans('Scans', CardType.scan),
  voice('Voice', CardType.voice),
  checklists('Checklists', CardType.checklist);

  const _Filter(this.label, this.type);

  final String label;
  final CardType? type;
}

/// Full-text search over all cards, running on this phone.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() => _query = value.trim());
      }
    });
    setState(() {});
  }

  void _commit(String value) {
    _debounce?.cancel();
    setState(() => _query = value.trim());
  }

  /// Opens a card and, when the user comes back, runs the search again: the
  /// card may have been edited or deleted meanwhile.
  Future<void> _openCard(String cardId) async {
    await context.push<void>('/card/$cardId');
    if (!mounted) {
      return;
    }
    ref.invalidate(searchProvider);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final bool hasQuery = _query.isNotEmpty;
    final AsyncValue<List<SearchHit>>? results = hasQuery
        ? ref.watch(searchProvider(SearchQuery(_query, type: _filter.type)))
        : null;
    final AsyncValue<List<Notebook>> notebooksAsync =
        ref.watch(notebooksProvider);
    final Map<String, String> notebookNames = <String, String>{
      for (final Notebook n in notebooksAsync.value ?? const <Notebook>[])
        n.id: n.title,
    };
    // Cards of locked notebooks stay hidden until the notebook is unlocked.
    final Set<String> unlocked = ref.watch(unlockedNotebooksProvider);
    final Set<String> hiddenNotebooks = <String>{
      for (final Notebook n in notebooksAsync.value ?? const <Notebook>[])
        if (n.locked && !unlocked.contains(n.id)) n.id,
    };
    final bool keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final List<String> terms = _query
        .split(RegExp(r'\s+'))
        .where((String t) => t.isNotEmpty)
        .toList();

    Widget listFor(List<SearchHit> hits) {
      if (hits.isEmpty) {
        return _Hint(
          icon: Icons.search_off,
          title: 'No cards match "$_query"',
          message: _filter == _Filter.all
              ? 'Try a different word, or a shorter one.'
              : 'Try another filter, or a different word.',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.only(top: 10, bottom: 12),
        itemCount: hits.length + 1,
        separatorBuilder: (BuildContext c, int i) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                hits.length == 1 ? '1 card' : '${hits.length} cards',
                style: bodyStyle(
                  context,
                  13,
                  weight: FontWeight.w600,
                  color: colors.muted,
                ),
              ),
            );
          }
          final SearchHit hit = hits[index - 1];
          return _ResultTile(
            hit: hit,
            terms: terms,
            notebookName: notebookNames[hit.card.notebookId] ?? '',
            locked: hiddenNotebooks.contains(hit.card.notebookId),
            onTap: () => unawaited(_openCard(hit.card.id)),
          );
        },
      );
    }

    final Widget body = results == null
        ? const _Hint(
            icon: Icons.search,
            title: 'Search your cards',
            message: 'Type a word to look through titles, notes, checklists, '
                'scanned text and voice transcripts.',
          )
        : results.when(
            // Wait for the notebooks too: they say which cards are locked.
            data: (List<SearchHit> hits) => notebooksAsync.hasValue
                ? listFor(hits)
                : const Center(child: CircularProgressIndicator()),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, StackTrace s) => const _Hint(
              icon: Icons.error_outline,
              title: 'Search did not work',
              message: 'Something went wrong. Please try again.',
            ),
          );

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 50),
                          padding: const EdgeInsets.only(left: 16),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.ink, width: 2),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.search, color: colors.ink),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  autofocus: true,
                                  textInputAction: TextInputAction.search,
                                  cursorColor: colors.ink,
                                  style: bodyStyle(context, 17),
                                  decoration: InputDecoration(
                                    hintText: 'Search cards',
                                    hintStyle: bodyStyle(
                                      context,
                                      17,
                                      color: colors.muted,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  onChanged: _onChanged,
                                  onSubmitted: _commit,
                                ),
                              ),
                              if (_controller.text.isNotEmpty)
                                IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: _clear,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => leaveScreen(context),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final _Filter f in _Filter.values)
                        FilterPill(
                          label: f.label,
                          selected: _filter == f,
                          onTap: () => setState(() => _filter = f),
                        ),
                    ],
                  ),
                  Expanded(child: body),
                  // Hidden while the keyboard is open: there is no room.
                  if (!keyboardOpen) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Search runs on this phone, so it works offline.',
                      textAlign: TextAlign.center,
                      style: bodyStyle(
                        context,
                        13,
                        color: colors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: colors.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: displayStyle(context, 22),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: bodyStyle(context, 15, color: colors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

String _fieldLabel(SearchField field) {
  switch (field) {
    case SearchField.title:
      return 'the title';
    case SearchField.body:
      return 'the note text';
    case SearchField.items:
      return 'a checklist item';
    case SearchField.ocrText:
      return 'the scanned text';
    case SearchField.transcript:
      return 'the voice transcript';
  }
}

IconData _typeIcon(CardType type) {
  switch (type) {
    case CardType.text:
      return Icons.notes;
    case CardType.checklist:
      return Icons.checklist;
    case CardType.voice:
      return Icons.mic_none;
    case CardType.photo:
      return Icons.image_outlined;
    case CardType.scan:
      return Icons.document_scanner_outlined;
    case CardType.link:
      return Icons.link;
  }
}

/// [text] as spans with every occurrence of one of [terms] highlighted
/// (case-insensitive).
List<InlineSpan> highlightSpans(
  String text,
  List<String> terms,
  Color highlight,
) {
  final List<String> clean =
      terms.where((String t) => t.isNotEmpty).map(RegExp.escape).toList();
  if (clean.isEmpty || text.isEmpty) {
    return <InlineSpan>[TextSpan(text: text)];
  }
  final RegExp pattern = RegExp(clean.join('|'), caseSensitive: false);
  final List<InlineSpan> spans = <InlineSpan>[];
  int cursor = 0;
  for (final RegExpMatch m in pattern.allMatches(text)) {
    if (m.end == m.start) {
      continue;
    }
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    spans.add(TextSpan(
      text: text.substring(m.start, m.end),
      style: TextStyle(backgroundColor: highlight),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.hit,
    required this.terms,
    required this.notebookName,
    required this.locked,
    required this.onTap,
  });

  final SearchHit hit;
  final List<String> terms;
  final String notebookName;

  /// The card is in a locked notebook that has not been unlocked: show no
  /// title, snippet, picture or matched field.
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final NoteCard card = hit.card;
    final Color highlight = colors.cardColor(0);
    Attachment? image;
    for (final Attachment a in locked ? const <Attachment>[] : card.attachments) {
      if (a.kind == AttachmentKind.image) {
        image = a;
        break;
      }
    }
    final String where = notebookName.isEmpty
        ? cardTypeLabel(card.type)
        : '${cardTypeLabel(card.type)} in $notebookName';
    final bool showSnippet = !locked &&
        hit.matchedIn != SearchField.title &&
        hit.snippet.isNotEmpty;

    return Semantics(
      button: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 56,
                    height: 68,
                    color: colors.cardColor(card.colorIndex),
                    child: image != null
                        ? AttachmentImage(attachmentId: image.id)
                        : Icon(_typeIcon(card.type), color: colors.ink),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text.rich(
                        TextSpan(
                          children: locked
                              ? <InlineSpan>[const TextSpan(text: 'Locked note')]
                              : highlightSpans(
                                  displayTitle(card),
                                  terms,
                                  highlight,
                                ),
                        ),
                        style: bodyStyle(context, 16, weight: FontWeight.w700),
                      ),
                      if (showSnippet) ...<Widget>[
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            children: highlightSpans(
                              hit.snippet,
                              terms,
                              highlight,
                            ),
                          ),
                          style: bodyStyle(
                            context,
                            14,
                            color: colors.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        locked
                            ? (notebookName.isEmpty
                                ? 'In a locked notebook'
                                : 'In the locked notebook $notebookName')
                            : 'Matched in ${_fieldLabel(hit.matchedIn)}, $where',
                        style: bodyStyle(
                          context,
                          12,
                          weight: FontWeight.w600,
                          color: colors.muted,
                        ),
                      ),
                    ],
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
