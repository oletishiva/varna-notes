import 'model_utils.dart';

/// What an [Attachment] contains.
enum AttachmentKind {
  audio,
  image;

  static AttachmentKind fromName(String? name) {
    for (final AttachmentKind k in AttachmentKind.values) {
      if (k.name == name) {
        return k;
      }
    }
    return AttachmentKind.image;
  }
}

/// Metadata about a binary blob. The bytes live in the `AttachmentStore`,
/// keyed by [id]. Attachments are immutable: to change one, save a new id.
class Attachment {
  const Attachment({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.byteLength,
    this.durationMs,
  });

  final String id;
  final AttachmentKind kind;

  /// Original or suggested file name, e.g. `scan.jpg`, `memo.m4a`.
  final String fileName;

  /// Size of the stored bytes.
  final int byteLength;

  /// Playback length for audio, null otherwise.
  final int? durationMs;

  Attachment copyWith({
    String? id,
    AttachmentKind? kind,
    String? fileName,
    int? byteLength,
    Object? durationMs = kUnset,
  }) {
    return Attachment(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      fileName: fileName ?? this.fileName,
      byteLength: byteLength ?? this.byteLength,
      durationMs: identical(durationMs, kUnset)
          ? this.durationMs
          : durationMs as int?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'fileName': fileName,
        'byteLength': byteLength,
        'durationMs': durationMs,
      };

  factory Attachment.fromJson(Map<String, Object?> json) {
    return Attachment(
      id: json['id'] as String,
      kind: AttachmentKind.fromName(json['kind'] as String?),
      fileName: (json['fileName'] as String?) ?? '',
      byteLength: (json['byteLength'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      other.id == id &&
      other.kind == kind &&
      other.fileName == fileName &&
      other.byteLength == byteLength &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(id, kind, fileName, byteLength, durationMs);

  @override
  String toString() => 'Attachment($id, ${kind.name}, $fileName)';
}
