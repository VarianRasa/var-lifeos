/// Fallback database opener for unsupported platforms.
library;

import 'package:sembast/sembast.dart';

Future<Database> openMindmapDatabase({SembastCodec? codec}) {
  throw UnsupportedError('Mindmap database is not supported on this platform.');
}
