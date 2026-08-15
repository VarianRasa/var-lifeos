import 'dart:typed_data';

class CaptureFileAttachment {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String? localPath;

  const CaptureFileAttachment({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.localPath,
  });
}

class CapturePayload {
  final String? text;
  final List<String> urls;
  final List<CaptureFileAttachment> attachments;
  final Map<String, Object?> metadata;

  const CapturePayload({
    this.text,
    this.urls = const [],
    this.attachments = const [],
    this.metadata = const {},
  });

  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) &&
      urls.isEmpty &&
      attachments.isEmpty;
}
