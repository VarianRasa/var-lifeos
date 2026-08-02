import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

bool get audioRecordingUsesStream => false;

Future<String> createAudioRecordingPath() async {
  final directory = await getTemporaryDirectory();
  return p.join(
    directory.path,
    'var-audio-${DateTime.now().microsecondsSinceEpoch}.wav',
  );
}

Future<Uint8List> readAudioRecording(String path) => File(path).readAsBytes();

Future<String> createAudioPlaybackSource(
  Uint8List bytes,
  String mimeType,
) async {
  final extension = switch (mimeType) {
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/ogg' => 'ogg',
    'audio/mp4' || 'audio/aac' => 'm4a',
    _ => 'mp3',
  };
  final path = p.join(
    Directory.systemTemp.path,
    'var-playback-${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<void> deleteAudioPlaybackSource(String path) async {
  await deleteAudioRecording(path);
}

Future<void> deleteAudioRecording(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
