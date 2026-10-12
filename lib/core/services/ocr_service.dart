/// Text recognised in an image.
class OcrResult {
  const OcrResult(this.text);

  /// Recognised text, possibly empty. Line breaks are preserved.
  final String text;

  bool get isEmpty => text.trim().isEmpty;
}

/// Thrown by [OcrService.recognizeFile] when OCR is not available on this
/// platform (check [OcrService.isSupported] first).
class OcrUnsupportedException implements Exception {
  const OcrUnsupportedException();

  @override
  String toString() => 'Text recognition is not available on this platform.';
}

/// On-device text recognition for photos and scans.
///
/// Android/iOS use Google ML Kit (Latin script only: there is no Telugu
/// model, so Telugu text is not recognised). On web and desktop
/// [isSupported] is false.
abstract class OcrService {
  bool get isSupported;

  /// Recognises text in the image file at [imagePath] (a real file path, for
  /// example `XFile.path` from image_picker on mobile).
  ///
  /// Throws [OcrUnsupportedException] when [isSupported] is false.
  Future<OcrResult> recognizeFile(String imagePath);
}

/// Does nothing; used on web/desktop and as a safe default.
class NoopOcrService implements OcrService {
  const NoopOcrService();

  @override
  bool get isSupported => false;

  @override
  Future<OcrResult> recognizeFile(String imagePath) {
    throw const OcrUnsupportedException();
  }
}
