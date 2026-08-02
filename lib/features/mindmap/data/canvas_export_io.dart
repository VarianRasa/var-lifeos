import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> saveCanvasPng(Uint8List bytes, String fileName) async {
  final directory = await getApplicationDocumentsDirectory();
  final exportDirectory = Directory(p.join(directory.path, 'Var', 'exports'));
  await exportDirectory.create(recursive: true);
  final file = File(p.join(exportDirectory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
