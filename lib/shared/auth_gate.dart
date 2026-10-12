// Asks for biometrics / the device passcode before a locked notebook opens.
// Exposes: `Future<bool> authenticateUser({String reason})`.
//
// The real implementation (local_auth) is only compiled where dart:io exists;
// on the web the stub always answers true so notebooks never get stuck.
export 'auth_gate_stub.dart' if (dart.library.io) 'auth_gate_io.dart';
