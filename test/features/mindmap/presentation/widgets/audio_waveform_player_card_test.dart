import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/widgets/audio_waveform_player_card.dart';

void main() {
  testWidgets('AudioWaveformPlayerCard renders audio title and duration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AudioWaveformPlayerCard(
            title: 'Meeting Voice Memo',
            durationSeconds: 125,
          ),
        ),
      ),
    );

    expect(find.text('Meeting Voice Memo'), findsOneWidget);
    expect(find.text('02:05'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
