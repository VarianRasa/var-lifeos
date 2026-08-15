import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> saveInsightsExport(String data, String fileName) async {
  Directory? directory;
  try {
    directory = await getDownloadsDirectory();
  } on UnsupportedError {
    directory = null;
  }
  directory ??= await getApplicationDocumentsDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(data, flush: true);
  return file.path;
}
