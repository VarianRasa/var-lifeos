import 'package:sqlite3/common.dart';

import 'search_database_stub.dart'
    if (dart.library.io) 'search_database_native.dart'
    if (dart.library.js_interop) 'search_database_web.dart';

Future<CommonDatabase> openSearchDatabase() => openPlatformSearchDatabase();
