library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../domain/node_attachment.dart';
import '../domain/node_type_payloads.dart';
import 'media_file_picker_mode.dart';

enum MediaFileKind { attachment, image, video, audio }

final class PickedMediaFile {
  const PickedMediaFile({
    required this.fileName,
    required this.byteLength,
    this.mimeType,
    this.bytes,
    this.readStream,
  });

  final String fileName;
  final int byteLength;
  final String? mimeType;
  final List<int>? bytes;
  final Stream<List<int>>? readStream;
}

abstract interface class MediaFilePicker {
  Future<PickedMediaFile?> pick(MediaFileKind kind);
}

final class FilePickerMediaFilePicker implements MediaFilePicker {
  const FilePickerMediaFilePicker();

  @override
  Future<PickedMediaFile?> pick(MediaFileKind kind) async {
    final result = await FilePicker.pickFiles(
      type: kind == MediaFileKind.attachment ? FileType.any : FileType.custom,
      allowedExtensions: kind == MediaFileKind.attachment
          ? null
          : _extensionsForKind(kind),
      allowMultiple: false,
      withData: mediaFilePickerUsesBytes,
      withReadStream: !mediaFilePickerUsesBytes,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    return PickedMediaFile(
      fileName: file.name,
      byteLength: file.size,
      mimeType: _mimeForExtension(p.extension(file.name)),
      bytes: file.bytes,
      readStream: file.readStream,
    );
  }
}

final class MediaFileImportService {
  const MediaFileImportService({
    required NodeAttachmentRepository repository,
    required MediaFilePicker picker,
    int maxBytes = maxNodeAttachmentBytes,
  }) : _repository = repository,
       _picker = picker,
       _maxBytes = maxBytes,
       assert(maxBytes > 0);

  final NodeAttachmentRepository _repository;
  final MediaFilePicker _picker;
  final int _maxBytes;

  Future<NodeAttachment?> pickAttachment() =>
      _pickAndImport(MediaFileKind.attachment);

  Future<ImagePayload?> pickImage({
    ImagePayload existing = const ImagePayload(),
  }) async {
    final attachment = await _pickAndImport(MediaFileKind.image);
    if (attachment == null) return null;
    return existing.copyWith(
      attachmentId: attachment.id,
      mimeType: attachment.mimeType,
      fileName: attachment.fileName,
      byteLength: attachment.byteLength,
      clearUrl: true,
    );
  }

  Future<VideoPayload?> pickVideo({
    VideoPayload existing = const VideoPayload(),
  }) async {
    final attachment = await _pickAndImport(MediaFileKind.video);
    if (attachment == null) return null;
    return existing.copyWith(
      attachmentId: attachment.id,
      mimeType: attachment.mimeType,
      fileName: attachment.fileName,
      clearUrl: true,
    );
  }

  Future<AudioPayload?> pickAudio({
    AudioPayload existing = const AudioPayload(),
  }) async {
    final attachment = await _pickAndImport(MediaFileKind.audio);
    if (attachment == null) return null;
    return existing.copyWith(
      sourceType: AudioSourceType.attachment,
      attachmentId: attachment.id,
      fileName: attachment.fileName,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.byteLength,
      remoteUrl: '',
      transcriptionStatus: 'idle',
      transcriptionError: '',
    );
  }

  Future<NodeAttachment?> _pickAndImport(MediaFileKind kind) async {
    final file = await _picker.pick(kind);
    if (file == null) return null;
    final fileName = p.basename(file.fileName.trim());
    if (fileName.isEmpty || fileName == '.' || fileName == '..') {
      throw const FormatException('Selected media filename is invalid.');
    }
    if (file.byteLength <= 0) {
      throw const FormatException('Selected media file is empty.');
    }
    if (file.byteLength > _maxBytes) {
      throw FormatException(_oversizedMessage);
    }
    final extensionMime = _mimeForExtension(p.extension(fileName));
    final declaredMime = file.mimeType?.trim().toLowerCase();
    final mimeType = kind == MediaFileKind.attachment
        ? extensionMime ?? 'application/octet-stream'
        : declaredMime;
    if (kind != MediaFileKind.attachment) {
      if (extensionMime == null || !_mimeMatchesKind(extensionMime, kind)) {
        throw FormatException('Unsupported ${kind.name} file extension.');
      }
      if (declaredMime == null ||
          !supportedNodeAttachmentMimeTypes.contains(declaredMime) ||
          !_mimeMatchesKind(declaredMime, kind)) {
        throw FormatException('Unsupported ${kind.name} MIME type.');
      }
      if (declaredMime != extensionMime) {
        throw const FormatException(
          'Selected media extension does not match its MIME type.',
        );
      }
    }
    final bytes = await _readBytes(file);
    if (bytes.isEmpty) {
      throw const FormatException('Selected media file is empty.');
    }
    if (bytes.length != file.byteLength) {
      throw const FormatException('Selected media file size is invalid.');
    }
    if (mimeType != 'application/octet-stream' &&
        !_matchesMagicBytes(bytes, mimeType!)) {
      throw const FormatException(
        'Selected media content does not match its MIME type.',
      );
    }
    return _repository.importBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType!,
    );
  }

  Future<Uint8List> _readBytes(PickedMediaFile file) async {
    final direct = file.bytes;
    if (direct is Uint8List) return direct;
    if (direct != null) return Uint8List.fromList(direct);
    final stream = file.readStream;
    if (stream == null) {
      throw const FormatException('Selected media data is unavailable.');
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      if (length > _maxBytes) {
        throw FormatException(_oversizedMessage);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String get _oversizedMessage => _maxBytes == maxNodeAttachmentBytes
      ? 'Selected media file exceeds 100 MB.'
      : 'Selected media file exceeds allowed size.';
}

List<String> _extensionsForKind(MediaFileKind kind) => switch (kind) {
  MediaFileKind.attachment => const [],
  MediaFileKind.image => const ['gif', 'jpg', 'jpeg', 'png', 'webp'],
  MediaFileKind.video => const ['mp4', 'mov', 'webm'],
  MediaFileKind.audio => const ['aac', 'm4a', 'mp3', 'ogg', 'wav', 'webm'],
};

bool _mimeMatchesKind(String mime, MediaFileKind kind) => switch (kind) {
  MediaFileKind.attachment => true,
  MediaFileKind.image => mime.startsWith('image/'),
  MediaFileKind.video => mime.startsWith('video/'),
  MediaFileKind.audio => mime.startsWith('audio/'),
};

String? _mimeForExtension(String extension) =>
    switch (extension.trim().toLowerCase()) {
      '.gif' => 'image/gif',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.pdf' => 'application/pdf',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.aac' => 'audio/aac',
      '.m4a' => 'audio/mp4',
      '.mp3' => 'audio/mpeg',
      '.ogg' => 'audio/ogg',
      '.wav' => 'audio/wav',
      _ => null,
    };

bool _matchesMagicBytes(List<int> bytes, String mime) => switch (mime) {
  'image/png' => _startsWith(bytes, const [
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ]),
  'image/jpeg' =>
    bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff,
  'image/gif' =>
    _startsWithAscii(bytes, 'GIF87a') || _startsWithAscii(bytes, 'GIF89a'),
  'image/webp' =>
    bytes.length >= 12 &&
        _asciiAt(bytes, 0, 'RIFF') &&
        _asciiAt(bytes, 8, 'WEBP'),
  'video/mp4' ||
  'video/quicktime' => bytes.length >= 12 && _asciiAt(bytes, 4, 'ftyp'),
  'video/webm' => _startsWith(bytes, const [0x1a, 0x45, 0xdf, 0xa3]),
  'audio/aac' =>
    bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xf6) == 0xf0,
  'audio/mp4' => bytes.length >= 12 && _asciiAt(bytes, 4, 'ftyp'),
  'audio/mpeg' =>
    _startsWithAscii(bytes, 'ID3') ||
        (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0),
  'audio/ogg' => _startsWithAscii(bytes, 'OggS'),
  'audio/wav' =>
    bytes.length >= 12 &&
        _asciiAt(bytes, 0, 'RIFF') &&
        _asciiAt(bytes, 8, 'WAVE'),
  'audio/webm' => _startsWith(bytes, const [0x1a, 0x45, 0xdf, 0xa3]),
  'application/pdf' => _startsWithAscii(bytes, '%PDF'),
  _ => false,
};

bool _startsWith(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

bool _startsWithAscii(List<int> bytes, String signature) =>
    _asciiAt(bytes, 0, signature);

bool _asciiAt(List<int> bytes, int offset, String signature) {
  if (bytes.length < offset + signature.length) return false;
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[offset + index] != signature.codeUnitAt(index)) return false;
  }
  return true;
}
