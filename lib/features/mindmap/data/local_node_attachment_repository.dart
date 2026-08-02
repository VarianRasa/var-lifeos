/// Platform-aware attachment repository exports.
library;

export 'local_node_attachment_repository_stub.dart'
    if (dart.library.html) 'local_node_attachment_repository_web.dart'
    if (dart.library.io) 'local_node_attachment_repository_io.dart';
