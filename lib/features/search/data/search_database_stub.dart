import 'package:sqlite3/common.dart';

Future<CommonDatabase> openPlatformSearchDatabase() {
  throw UnsupportedError('Search database is unavailable on this platform.');
}
