/// One line of a checklist card.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.done = false,
  });

  final String id;
  final String text;
  final bool done;

  ChecklistItem copyWith({String? id, String? text, bool? done}) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        'done': done,
      };

  factory ChecklistItem.fromJson(Map<String, Object?> json) {
    return ChecklistItem(
      id: json['id'] as String,
      text: (json['text'] as String?) ?? '',
      done: (json['done'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem &&
      other.id == id &&
      other.text == text &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, text, done);

  @override
  String toString() => 'ChecklistItem($id, $text, $done)';
}
