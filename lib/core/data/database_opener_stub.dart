import 'package:sembast/sembast.dart';

/// Fallback for platforms with neither dart:io nor the web; never used by the
/// supported targets.
Future<Database> openAppDatabase() {
  throw UnsupportedError('No database implementation for this platform.');
}
