import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/config/runtime_config.dart';

void main() {
  test('RuntimeConfig defaults to safe local-only behavior', () {
    const config = RuntimeConfig();

    expect(config.syncEndpoint, isNull);
    expect(config.syncEnabled, isFalse);
    expect(config.demoSeedEnabled, isFalse);
  });

  test('RuntimeConfig exposes enabled sync endpoint', () {
    final config = RuntimeConfig(
      syncEndpoint: Uri.parse('https://sync.example.test'),
      demoSeedEnabled: true,
    );

    expect(config.syncEnabled, isTrue);
    expect(config.syncEndpoint, Uri.parse('https://sync.example.test'));
    expect(config.demoSeedEnabled, isTrue);
  });
}
