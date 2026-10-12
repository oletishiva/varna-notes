import 'ocr_service.dart';

/// Web / fallback: OCR is not available.
OcrService createOcrService() => const NoopOcrService();
