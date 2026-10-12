import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

/// Opens (creating if needed) `varna.db` inside the app documents directory.
Future<Database> openAppDatabase() async {
  final Directory dir = await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  return databaseFactoryIo.openDatabase('${dir.path}/varna.db');
}
