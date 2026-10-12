import 'note_card.dart';

/// The part of a card in which a search term was found.
enum SearchField {
  title,
  body,
  items,
  ocrText,
  transcript,
}

/// One search result.
class SearchHit {
  const SearchHit({
    required this.card,
    required this.matchedIn,
    required this.matchedFields,
    required this.snippet,
  });

  final NoteCard card;

  /// The highest-priority field that matched (title > body > items > ocrText
  /// > transcript). [snippet] is taken from this field.
  final SearchField matchedIn;

  /// Every field that matched, in priority order.
  final List<SearchField> matchedFields;

  /// Short excerpt of [matchedIn] around the first match (original casing,
  /// single line, with "..." where text was cut).
  final String snippet;

  @override
  String toString() => 'SearchHit(${card.id}, ${matchedIn.name}, $snippet)';
}
