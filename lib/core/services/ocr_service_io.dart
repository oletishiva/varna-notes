import 'dart:io' show Platform;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_service.dart';

/// OCR on Android/iOS via ML Kit; unsupported elsewhere (desktop).
OcrService createOcrService() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MlKitOcrService();
  }
  return const NoopOcrService();
}

/// Google ML Kit text recognition (Latin script).
class MlKitOcrService implements OcrService {
  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<OcrResult> recognizeFile(String imagePath) async {
    if (!isSupported) {
      throw const OcrUnsupportedException();
    }
    final TextRecognizer recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final InputImage input = InputImage.fromFilePath(imagePath);
      final RecognizedText result = await recognizer.processImage(input);
      return OcrResult(result.text);
    } finally {
      await recognizer.close();
    }
  }
}
