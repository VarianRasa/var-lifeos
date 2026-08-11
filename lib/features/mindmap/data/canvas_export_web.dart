import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> saveCanvasPng(Uint8List bytes, String fileName) =>
    _download(bytes.toJS, fileName, 'image/png');

Future<String> saveCanvasSvg(String svg, String fileName) =>
    _download(svg.toJS, fileName, 'image/svg+xml;charset=utf-8');

Future<String> _download(JSAny content, String fileName, String type) async {
  final blob = web.Blob(<JSAny>[content].toJS, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return fileName;
}
