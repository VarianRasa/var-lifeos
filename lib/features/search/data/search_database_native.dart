import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

Future<CommonDatabase> openPlatformSearchDatabase() async {
  final directory = await getApplicationSupportDirectory();
  return sqlite3.open(path.join(directory.path, 'search-index.sqlite'));
}
