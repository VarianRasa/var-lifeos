import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/config/runtime_config.dart';

void main() {
  test('RuntimeConfig environment uses production transcription endpoint', () {
    final config = RuntimeConfig.fromEnvironment();

    expect(
      config.audioTranscriptionEndpoint,
      Uri.parse('https://var-audio-transcription.mp2n2-var-app.workers.dev'),
    );
  });

  test('RuntimeConfig defaults optional features to disabled', () {
    const config = RuntimeConfig();

    expect(config.demoSeedEnabled, isFalse);
    expect(config.quoteDiscoveryEnabled, isFalse);
    expect(config.audioTranscriptionEnabled, isFalse);
  });

  test('RuntimeConfig exposes audio transcription endpoint', () {
    final config = RuntimeConfig(
      audioTranscriptionEndpoint: Uri.parse('https://audio.example.test'),
    );
    expect(config.audioTranscriptionEnabled, isTrue);
  });

  test('RuntimeConfig exposes Quote discovery endpoint', () {
    final config = RuntimeConfig(
      quoteEndpoint: Uri.parse('https://quotes.example.test'),
    );

    expect(config.quoteDiscoveryEnabled, isTrue);
    expect(config.quoteEndpoint, Uri.parse('https://quotes.example.test'));
  });

  test('RuntimeConfig exposes enabled demo seed', () {
    const config = RuntimeConfig(demoSeedEnabled: true);

    expect(config.demoSeedEnabled, isTrue);
  });
}
