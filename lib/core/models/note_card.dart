import 'attachment.dart';
import 'card_type.dart';
import 'checklist_item.dart';
import 'model_utils.dart';

/// A single card inside a notebook.
///
/// Conventions:
/// * `link` cards keep the URL in [body] and the page title in [title].
/// * [expiryDate] is a calendar date stored as `DateTime.utc(y, m, d)` and
///   serialised as `yyyy-MM-dd`; [reminderAt] is an instant (UTC).
/// * [ocrText] holds text recognised from a photo/scan, [transcript] holds
///   speech-to-text output for voice cards.
class NoteCard {
  const NoteCard({
    required this.id,
    required this.notebookId,
    this.type = CardType.text,
    this.title = '',
    this.body = '',
    this.colorIndex = 0,
    this.items = const <ChecklistItem>[],
    this.attachments = const <Attachment>[],
    this.ocrText,
    this.transcript,
    this.favourite = false,
    this.reminderAt,
    this.expiryDate,
    this.paperFolder,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String notebookId;
  final CardType type;
  final String title;
  final String body;

  /// Index 0..4 into the card colour palette.
  final int colorIndex;
  final List<ChecklistItem> items;
  final List<Attachment> attachments;
  final String? ocrText;
  final String? transcript;
  final bool favourite;
  final DateTime? reminderAt;
  final DateTime? expiryDate;

  /// One of `AppConfig.paperFolders`, or null when not a paper.
  final String? paperFolder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  /// Number of completed checklist items.
  int get doneCount => items.where((ChecklistItem i) => i.done).length;

  /// Copy with changes. For nullable fields (`ocrText`, `transcript`,
  /// `reminderAt`, `expiryDate`, `paperFolder`) omit the argument to keep the
  /// current value, or pass `null` explicitly to clear it.
  NoteCard copyWith({
    String? id,
    String? notebookId,
    CardType? type,
    String? title,
    String? body,
    int? colorIndex,
    List<ChecklistItem>? items,
    List<Attachment>? attachments,
    Object? ocrText = kUnset,
    Object? transcript = kUnset,
    bool? favourite,
    Object? reminderAt = kUnset,
    Object? expiryDate = kUnset,
    Object? paperFolder = kUnset,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return NoteCard(
      id: id ?? this.id,
      notebookId: notebookId ?? this.notebookId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      colorIndex: colorIndex ?? this.colorIndex,
      items: items ?? this.items,
      attachments: attachments ?? this.attachments,
      ocrText: identical(ocrText, kUnset) ? this.ocrText : ocrText as String?,
      transcript:
          identical(transcript, kUnset) ? this.transcript : transcript as String?,
      favourite: favourite ?? this.favourite,
      reminderAt: identical(reminderAt, kUnset)
          ? this.reminderAt
          : reminderAt as DateTime?,
      expiryDate: identical(expiryDate, kUnset)
          ? this.expiryDate
          : expiryDate as DateTime?,
      paperFolder: identical(paperFolder, kUnset)
          ? this.paperFolder
          : paperFolder as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'notebookId': notebookId,
        'type': type.name,
        'title': title,
        'body': body,
        'colorIndex': colorIndex,
        'items': items.map((ChecklistItem i) => i.toJson()).toList(),
        'attachments': attachments.map((Attachment a) => a.toJson()).toList(),
        'ocrText': ocrText,
        'transcript': transcript,
        'favourite': favourite,
        'reminderAt': reminderAt == null ? null : formatUtc(reminderAt!),
        'expiryDate': expiryDate == null ? null : formatDateOnly(expiryDate!),
        'paperFolder': paperFolder,
        'createdAt': formatUtc(createdAt),
        'updatedAt': formatUtc(updatedAt),
        'deleted': deleted,
      };

  factory NoteCard.fromJson(Map<String, Object?> json) {
    return NoteCard(
      id: json['id'] as String,
      notebookId: json['notebookId'] as String,
      type: CardType.fromName(json['type'] as String?),
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      items: asList(json['items'])
          .map((Object? e) => ChecklistItem.fromJson(asStringMap(e)))
          .toList(),
      attachments: asList(json['attachments'])
          .map((Object? e) => Attachment.fromJson(asStringMap(e)))
          .toList(),
      ocrText: json['ocrText'] as String?,
      transcript: json['transcript'] as String?,
      favourite: (json['favourite'] as bool?) ?? false,
      reminderAt: parseUtcOrNull(json['reminderAt']),
      expiryDate: parseDateOnly(json['expiryDate']),
      paperFolder: json['paperFolder'] as String?,
      createdAt: parseUtc(json['createdAt']),
      updatedAt: parseUtc(json['updatedAt']),
      deleted: (json['deleted'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteCard &&
      other.id == id &&
      other.notebookId == notebookId &&
      other.type == type &&
      other.title == title &&
      other.body == body &&
      other.colorIndex == colorIndex &&
      listEquals(other.items, items) &&
      listEquals(other.attachments, attachments) &&
      other.ocrText == ocrText &&
      other.transcript == transcript &&
      other.favourite == favourite &&
      other.reminderAt == reminderAt &&
      other.expiryDate == expiryDate &&
      other.paperFolder == paperFolder &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(
        id,
        notebookId,
        type,
        title,
        body,
        colorIndex,
        Object.hashAll(items),
        Object.hashAll(attachments),
        ocrText,
        transcript,
        favourite,
        reminderAt,
        expiryDate,
        paperFolder,
        createdAt,
        updatedAt,
        deleted,
      );

  @override
  String toString() => 'NoteCard($id, ${type.name}, $title)';
}
