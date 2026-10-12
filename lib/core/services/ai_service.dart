import 'dart:typed_data';

/// Thrown by an unconfigured [AiService]. The UI should check
/// [AiService.isConfigured] first and show a "not available in this build"
/// state instead of calling.
class AiNotConfiguredException implements Exception {
  const AiNotConfiguredException();

  @override
  String toString() => 'AI features are not available in this build.';
}

/// Server-side AI features (speech-to-text, "Ask your notes"). These need an
/// API key that must live on a server, so v1 ships only the
/// [UnconfiguredAiService]. Results are never faked.
abstract class AiService {
  /// False when no real backend is wired in.
  bool get isConfigured;

  /// Speech to text for [audio] (e.g. m4a bytes). [languageCode] is a BCP-47
  /// code such as `en` or `te`.
  Future<String> transcribe(Uint8List audio, {String languageCode = 'en'});

  /// Answers [question] using [context] (text snippets taken from the user's
  /// notes).
  Future<String> ask(String question, {required List<String> context});
}

/// The only implementation in v1: always reports `isConfigured == false` and
/// throws [AiNotConfiguredException] if called.
class UnconfiguredAiService implements AiService {
  const UnconfiguredAiService();

  @override
  bool get isConfigured => false;

  @override
  Future<String> transcribe(Uint8List audio, {String languageCode = 'en'}) {
    throw const AiNotConfiguredException();
  }

  @override
  Future<String> ask(String question, {required List<String> context}) {
    throw const AiNotConfiguredException();
  }
}
