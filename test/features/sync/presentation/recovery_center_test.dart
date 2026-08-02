import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/application/sync_providers.dart';
import 'package:var_app/features/sync/data/in_memory_sync_activity_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_device_identity_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_restore_point_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_state_store.dart';
import 'package:var_app/features/sync/data/local_sync_auth_gateway.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/presentation/recovery_center.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('portable destructive import stays read-only until confirmed', (
    tester,
  ) async {
    final local = _node('local', 'Local node');
    final remote = _node('remote', 'Remote node');
    final repository = InMemoryMindmapRepository(seedNodes: [local]);
    final package = (await tester.runAsync(
      () =>
          PortableMindmapBackupCodec(
            iterations: PortableMindmapBackupCodec.minKdfIterations,
            randomBytes: _randomBytes(),
          ).encode(
            MindmapBackupDocument.create(
              sourceDevice: const SyncDeviceIdentity(
                id: 'phone',
                label: 'Phone',
              ),
              exportedAt: DateTime(2026, 7, 22),
              nodes: [remote],
            ),
            passphrase: 'secret',
          ),
    ))!;

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('portable-passphrase-field')),
      'secret',
    );
    await tester.enterText(
      find.byKey(const ValueKey('portable-package-field')),
      package,
    );
    final previewButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('portable-import-button')),
    );
    await tester.runAsync(() async {
      previewButton.onPressed!();
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Portable import preview'), findsOneWidget);
    expect(find.text('Local node'), findsOneWidget);
    expect((await repository.listNodes()).single.id, 'local');
    var importButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('operation-preview-confirm-button')),
    );
    expect(importButton.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('restore-destructive-confirmation-checkbox')),
    );
    await tester.pumpAndSettle();
    importButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('operation-preview-confirm-button')),
    );
    expect(importButton.onPressed, isNotNull);
    expect((await repository.listNodes()).single.id, 'local');
  });
}

Widget _app(InMemoryMindmapRepository repository) {
  return ProviderScope(
    overrides: [
      mindmapRepositoryProvider.overrideWithValue(repository),
      syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
      syncRemoteBackupStoreProvider.overrideWithValue(
        InMemorySyncRemoteBackupStore(),
      ),
      syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
      syncActivityStoreProvider.overrideWithValue(InMemorySyncActivityStore()),
      syncRestorePointStoreProvider.overrideWithValue(
        InMemorySyncRestorePointStore(),
      ),
      syncDeviceIdentityStoreProvider.overrideWithValue(
        InMemorySyncDeviceIdentityStore(
          const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
        ),
      ),
      syncDeviceIdentityProvider.overrideWithValue(
        const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
      ),
      syncNowProvider.overrideWithValue(() => DateTime(2026, 7, 22, 12)),
      portableBackupCodecProvider.overrideWithValue(
        PortableMindmapBackupCodec(
          iterations: PortableMindmapBackupCodec.minKdfIterations,
        ),
      ),
    ],
    child: const MaterialApp(home: RecoveryCenterPage()),
  );
}

MindmapNode _node(String id, String title) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 7, 22),
    now: DateTime(2026, 7, 22, 9),
  );
}

List<int> Function(int) _randomBytes() {
  var call = 0;
  return (length) {
    call += 1;
    return List<int>.generate(length, (index) => (call * 47 + index) % 256);
  };
}
