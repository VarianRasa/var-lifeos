// Smoke test — verifies the widget tree mounts without error.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/app.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/sembast_mindmap_node_database.dart';

Future<ProviderScope> _testApp() async {
  final database = await databaseFactoryMemory.openDatabase('widget-test.db');
  return ProviderScope(
    overrides: [
      mindmapNodeDatabaseProvider.overrideWithValue(
        SembastMindmapNodeDatabase(database: database),
      ),
    ],
    child: const VarApp(),
  );
}

void main() {
  disableSembastCooperator();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('App boots and renders without error', (tester) async {
    final app = await _testApp();
    await tester.pumpWidget(app);
    await tester.pump();

    expect(find.byType(VarApp), findsOneWidget);
  });
}
