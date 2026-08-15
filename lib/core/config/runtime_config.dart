/// Runtime flags sourced from `--dart-define`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final runtimeConfigProvider = Provider<RuntimeConfig>((ref) {
  return RuntimeConfig.fromEnvironment();
});

final class RuntimeConfig {
  const RuntimeConfig({
    this.quoteEndpoint,
    this.audioTranscriptionEndpoint,
    this.weatherEndpoint,
    this.workshopAiEndpoint,
    this.votingApiEndpoint,
    this.demoSeedEnabled = false,
  });

  factory RuntimeConfig.fromEnvironment() {
    const quoteEndpoint = String.fromEnvironment('VAR_QUOTE_ENDPOINT');
    const audioTranscriptionEndpoint = String.fromEnvironment(
      'VAR_AUDIO_TRANSCRIPTION_ENDPOINT',
      defaultValue: 'https://var-audio-transcription.mp2n2-var-app.workers.dev',
    );
    const weatherEndpoint = String.fromEnvironment('VAR_WEATHER_ENDPOINT');
    const workshopAiEndpoint = String.fromEnvironment(
      'VAR_WORKSHOP_AI_ENDPOINT',
    );
    const votingApiEndpoint = String.fromEnvironment('VAR_VOTING_API_ENDPOINT');
    const demoSeed = String.fromEnvironment('VAR_DEMO_SEED');
    return RuntimeConfig(
      quoteEndpoint: _parseUri(quoteEndpoint),
      audioTranscriptionEndpoint: _parseUri(audioTranscriptionEndpoint),
      weatherEndpoint: _parseUri(weatherEndpoint),
      workshopAiEndpoint: _parseUri(workshopAiEndpoint),
      votingApiEndpoint: _parseSecureEndpoint(votingApiEndpoint),
      demoSeedEnabled: _parseBool(demoSeed),
    );
  }

  final Uri? quoteEndpoint;
  final Uri? audioTranscriptionEndpoint;
  final Uri? weatherEndpoint;
  final Uri? workshopAiEndpoint;
  final Uri? votingApiEndpoint;
  final bool demoSeedEnabled;

  bool get quoteDiscoveryEnabled => quoteEndpoint != null;
  bool get audioTranscriptionEnabled => audioTranscriptionEndpoint != null;
  bool get weatherEnabled => weatherEndpoint != null;
  bool get workshopAiEnabled => workshopAiEndpoint != null;

  static Uri? _parseUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return Uri.parse(trimmed);
  }

  static Uri? _parseSecureEndpoint(String value) {
    final endpoint = _parseUri(value);
    if (endpoint == null) return null;
    final localhost =
        endpoint.host == 'localhost' ||
        endpoint.host == '127.0.0.1' ||
        endpoint.host == '::1';
    if (!endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        (endpoint.scheme != 'https' &&
            !(localhost && endpoint.scheme == 'http'))) {
      throw FormatException(
        'VAR_VOTING_API_ENDPOINT must use HTTPS or HTTP localhost.',
        value,
      );
    }
    return endpoint;
  }

  static bool _parseBool(String value) {
    return switch (value.trim().toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      _ => false,
    };
  }
}
