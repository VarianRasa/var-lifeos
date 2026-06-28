/// Runtime flags sourced from `--dart-define`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final runtimeConfigProvider = Provider<RuntimeConfig>((ref) {
  return RuntimeConfig.fromEnvironment();
});

final class RuntimeConfig {
  const RuntimeConfig({this.syncEndpoint, this.demoSeedEnabled = false});

  factory RuntimeConfig.fromEnvironment() {
    const syncEndpoint = String.fromEnvironment('VAR_SYNC_ENDPOINT');
    const demoSeed = String.fromEnvironment('VAR_DEMO_SEED');
    return RuntimeConfig(
      syncEndpoint: _parseUri(syncEndpoint),
      demoSeedEnabled: _parseBool(demoSeed),
    );
  }

  final Uri? syncEndpoint;
  final bool demoSeedEnabled;

  bool get syncEnabled => syncEndpoint != null;

  static Uri? _parseUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return Uri.parse(trimmed);
  }

  static bool _parseBool(String value) {
    return switch (value.trim().toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      _ => false,
    };
  }
}
