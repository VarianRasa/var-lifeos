import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> saveCanvasPng(Uint8List bytes, String fileName) async {
  final file = await _exportFile(fileName);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<String> saveCanvasSvg(String svg, String fileName) async {
  final file = await _exportFile(fileName);
  await file.writeAsString(svg, flush: true);
  return file.path;
}

Future<File> _exportFile(String fileName) async {
  final directory = await getApplicationDocumentsDirectory();
  final exportDirectory = Directory(p.join(directory.path, 'Var', 'exports'));
  await exportDirectory.create(recursive: true);
  return File(p.join(exportDirectory.path, fileName));
}
