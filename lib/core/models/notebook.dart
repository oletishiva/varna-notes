import 'model_utils.dart';

/// A notebook groups cards. Deleting sets [deleted] (a tombstone) so the
/// deletion syncs; use `NotesRepository.deleteNotebook`.
class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    this.colorIndex = 0,
    this.locked = false,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String title;

  /// Index 0..4 into the card colour palette (see `VarnaColors.cardColor`).
  final int colorIndex;

  /// When true the UI asks for biometrics/PIN before opening the notebook.
  final bool locked;

  /// UTC.
  final DateTime createdAt;

  /// UTC. Bumped by every repository write.
  final DateTime updatedAt;

  final bool deleted;

  Notebook copyWith({
    String? id,
    String? title,
    int? colorIndex,
    bool? locked,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return Notebook(
      id: id ?? this.id,
      title: title ?? this.title,
      colorIndex: colorIndex ?? this.colorIndex,
      locked: locked ?? this.locked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'colorIndex': colorIndex,
        'locked': locked,
        'createdAt': formatUtc(createdAt),
        'updatedAt': formatUtc(updatedAt),
        'deleted': deleted,
      };

  factory Notebook.fromJson(Map<String, Object?> json) {
    return Notebook(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      locked: (json['locked'] as bool?) ?? false,
      createdAt: parseUtc(json['createdAt']),
      updatedAt: parseUtc(json['updatedAt']),
      deleted: (json['deleted'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Notebook &&
      other.id == id &&
      other.title == title &&
      other.colorIndex == colorIndex &&
      other.locked == locked &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode =>
      Object.hash(id, title, colorIndex, locked, createdAt, updatedAt, deleted);

  @override
  String toString() => 'Notebook($id, $title)';
}
