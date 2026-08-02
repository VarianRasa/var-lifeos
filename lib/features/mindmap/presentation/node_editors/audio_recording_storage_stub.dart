import 'dart:typed_data';

bool get audioRecordingUsesStream => true;

Future<String> createAudioRecordingPath() async => '';

Future<Uint8List> readAudioRecording(String path) async => Uint8List(0);

Future<String> createAudioPlaybackSource(
  Uint8List bytes,
  String mimeType,
) async => '';

Future<void> deleteAudioPlaybackSource(String path) async {}

Future<void> deleteAudioRecording(String path) async {}
