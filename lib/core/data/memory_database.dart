import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';

/// Opens a brand-new, empty in-memory database. Intended for tests (and
/// previews). Each call returns an independent database.
Future<Database> openInMemoryDatabase() {
  return newDatabaseFactoryMemory().openDatabase(sembastInMemoryDatabasePath);
}
