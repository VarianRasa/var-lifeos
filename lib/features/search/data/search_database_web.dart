import 'package:sqlite3/wasm.dart';

Future<CommonDatabase> openPlatformSearchDatabase() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fileSystem = await IndexedDbFileSystem.open(dbName: 'var-search');
  sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);
  return sqlite.open('/search-index.sqlite');
}
