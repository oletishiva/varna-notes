import 'package:flutter/services.dart' show MissingPluginException;
import 'package:local_auth/local_auth.dart';

/// Asks for biometrics / the device passcode. Returns true when the user
/// passed, and also true where there is nothing to ask (platforms or devices
/// without authentication support) so notebooks never get stuck.
Future<bool> authenticateUser({String reason = 'Unlock your notebook'}) async {
  try {
    final LocalAuthentication auth = LocalAuthentication();
    final bool supported = await auth.isDeviceSupported();
    if (!supported) {
      return true;
    }
    return await auth.authenticate(localizedReason: reason);
  } on MissingPluginException {
    return true;
  } catch (_) {
    return false;
  }
}
