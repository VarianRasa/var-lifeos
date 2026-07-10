/// Desktop/mobile database opener for Sembast.
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openMindmapDatabase({SembastCodec? codec}) async {
  final directory = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase(
    p.join(directory.path, 'var_mindmap_v2.db'),
    codec: codec,
  );
}
