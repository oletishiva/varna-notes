// Chooses the OCR implementation at compile time (ML Kit only exists on
// dart:io builds; the io implementation additionally checks the platform at
// runtime). Exposes: `OcrService createOcrService()`.
export 'ocr_service_stub.dart' if (dart.library.io) 'ocr_service_io.dart';
