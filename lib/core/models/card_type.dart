/// The kind of a [NoteCard]. Link cards keep their URL in `body`.
enum CardType {
  text,
  checklist,
  voice,
  photo,
  scan,
  link;

  /// Parses the stored name; unknown or null values fall back to [text].
  static CardType fromName(String? name) {
    for (final CardType t in CardType.values) {
      if (t.name == name) {
        return t;
      }
    }
    return CardType.text;
  }
}
