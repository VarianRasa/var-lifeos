/// Browser database opener for Sembast over IndexedDB.
library;

import 'package:sembast_web/sembast_web.dart';

Future<Database> openMindmapDatabase() {
  return databaseFactoryWeb.openDatabase('var_mindmap_v2');
}
