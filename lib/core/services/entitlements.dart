import '../data/settings_repository.dart';

/// Whether the user has Varna Plus.
///
/// v1 has no store billing: [DebugToggleEntitlements] is a local switch kept
/// in settings. Real purchases (Play Billing / StoreKit) need store accounts
/// and are a TODO; they would be another implementation of this interface.
abstract class Entitlements {
  /// Current state.
  Future<bool> isPlus();

  /// Emits the current state, then every change.
  Stream<bool> watchIsPlus();

  /// True when [setDebugPlus] works (the debug toggle implementation).
  bool get supportsDebugToggle;

  /// Turns Plus on/off. Throws [UnsupportedError] when
  /// [supportsDebugToggle] is false.
  Future<void> setDebugPlus(bool value);
}

/// Plus is whatever the settings toggle says.
class DebugToggleEntitlements implements Entitlements {
  DebugToggleEntitlements(this._settings);

  final SettingsRepository _settings;

  @override
  Future<bool> isPlus() => _settings.getPlusDebug();

  @override
  Stream<bool> watchIsPlus() =>
      _settings.watch().map((settings) => settings.plusDebug).distinct();

  @override
  bool get supportsDebugToggle => true;

  @override
  Future<void> setDebugPlus(bool value) => _settings.setPlusDebug(value);
}

/// Fixed answer, for tests.
class FixedEntitlements implements Entitlements {
  FixedEntitlements({required this.plus});

  final bool plus;

  @override
  Future<bool> isPlus() async => plus;

  @override
  Stream<bool> watchIsPlus() => Stream<bool>.value(plus);

  @override
  bool get supportsDebugToggle => false;

  @override
  Future<void> setDebugPlus(bool value) {
    throw UnsupportedError('FixedEntitlements cannot be changed.');
  }
}
