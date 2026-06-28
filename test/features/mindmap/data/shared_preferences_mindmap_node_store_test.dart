import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/mindmap/data/shared_preferences_mindmap_node_store.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('writes and reads mindmap JSON using the configured key', () async {
    final preferences = SharedPreferencesAsync();
    final store = SharedPreferencesMindmapNodeStore(
      preferences: preferences,
      key: 'test.var.nodes',
    );

    expect(await store.readNodesJson(), isNull);

    await store.writeNodesJson('{"version":1,"nodes":[]}');

    final restoredStore = SharedPreferencesMindmapNodeStore(
      preferences: preferences,
      key: 'test.var.nodes',
    );

    expect(await restoredStore.readNodesJson(), '{"version":1,"nodes":[]}');
  });
}
