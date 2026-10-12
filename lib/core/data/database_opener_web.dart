import 'package:sembast_web/sembast_web.dart';

/// Opens the IndexedDB-backed database named `varna.db`.
Future<Database> openAppDatabase() {
  return databaseFactoryWeb.openDatabase('varna.db');
}
