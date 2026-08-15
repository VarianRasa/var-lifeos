import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/audio_recording_storage_io.dart';

void main() {
  test('desktop recording storage reads and deletes captured bytes', () async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}var-audio-test.wav',
    );
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    await file.writeAsBytes(const <int>[82, 73, 70, 70]);

    expect(audioRecordingUsesStream, isFalse);
    expect(
      await readAudioRecording(file.path),
      Uint8List.fromList(<int>[82, 73, 70, 70]),
    );

    await deleteAudioRecording(file.path);
    expect(await file.exists(), isFalse);
  });

  test(
    'desktop playback source creates a real file with matching bytes',
    () async {
      final bytes = Uint8List.fromList(<int>[82, 73, 70, 70]);
      final path = await createAudioPlaybackSource(bytes, 'audio/wav');
      final file = File(path);
      addTearDown(() => deleteAudioPlaybackSource(path));

      expect(path, endsWith('.wav'));
      expect(await file.readAsBytes(), bytes);

      await deleteAudioPlaybackSource(path);
      expect(await file.exists(), isFalse);
    },
  );
}
