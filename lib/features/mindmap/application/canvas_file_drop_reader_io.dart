import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readCanvasFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) return Uint8List(0);
  return file.readAsBytes();
}
