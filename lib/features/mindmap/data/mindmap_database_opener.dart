/// Platform-aware opener for the mindmap local database.
library;

export 'mindmap_database_opener_stub.dart'
    if (dart.library.html) 'mindmap_database_opener_web.dart'
    if (dart.library.io) 'mindmap_database_opener_io.dart';
