import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';

class OsShareReceiverService {
  final int maxFileBytes;
  final _shareStreamController = StreamController<CapturePayload>.broadcast();

  OsShareReceiverService({this.maxFileBytes = 100 * 1024 * 1024});

  Stream<CapturePayload> get onShareReceived => _shareStreamController.stream;

  bool validateFileSize({required int fileSizeBytes}) {
    return fileSizeBytes <= maxFileBytes;
  }

  Future<CapturePayload> parseShareData({
    String? text,
    List<String> filePaths = const [],
  }) async {
    final urls = <String>[];
    String? cleanText = text;

    if (text != null) {
      final urlRegExp = RegExp(r'https?://[^\s]+', caseSensitive: false);
      final matches = urlRegExp.allMatches(text);
      for (final match in matches) {
        final rawUrl = match.group(0);
        if (rawUrl != null) {
          final uri = Uri.tryParse(rawUrl);
          if (uri != null && !CaptureValidator.isPrivateOrLocalHost(uri.host)) {
            urls.add(rawUrl);
          }
        }
      }
      cleanText = text.replaceAll(urlRegExp, '').trim();
      if (cleanText.isEmpty) cleanText = null;
    }

    final attachments = <CaptureFileAttachment>[];
    for (final path in filePaths) {
      final file = File(path);
      if (await file.exists()) {
        final length = await file.length();
        if (validateFileSize(fileSizeBytes: length)) {
          final fileName = Uri.file(path).pathSegments.last;
          attachments.add(
            CaptureFileAttachment(
              fileName: fileName,
              mimeType: 'application/octet-stream',
              bytes: Uint8List(0),
              localPath: path,
            ),
          );
        }
      }
    }

    return CapturePayload(
      text: cleanText,
      urls: urls,
      attachments: attachments,
    );
  }

  Future<CapturePayload> emitShareData({
    String? text,
    List<String> filePaths = const [],
  }) async {
    final payload = await parseShareData(text: text, filePaths: filePaths);
    _shareStreamController.add(payload);
    return payload;
  }

  void dispose() {
    _shareStreamController.close();
  }
}

final osShareReceiverServiceProvider = Provider<OsShareReceiverService>((ref) {
  final service = OsShareReceiverService();
  ref.onDispose(service.dispose);
  return service;
});
