import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/settings/settings_page.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/application/sync_providers.dart';
import 'package:var_app/features/sync/data/in_memory_sync_activity_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_device_identity_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_restore_point_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_state_store.dart';
import 'package:var_app/features/sync/data/local_sync_auth_gateway.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';
import 'package:var_app/features/sync/domain/sync_activity.dart';
import 'package:var_app/features/sync/domain/sync_restore_point.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.physicalSize = const Size(1024, 1024);
    view.devicePixelRatio = 1.0;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('persists saved view defaults from Settings controls', (
    tester,
  ) async {
    final preferences = SharedPreferencesAsync();
    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();

    await _tapKey(tester, 'settings-day-view-table');
    await _tapKey(tester, 'settings-table-quick-view-priority');
    await _tapKey(tester, 'settings-table-sort-mode');
    await tester.tap(find.text('Due').last);
    await tester.pumpAndSettle();

    expect(await preferences.getString('day_view_mode'), 'table');
    expect(await preferences.getString('day_table_quick_view'), 'priority');
    expect(await preferences.getString('day_table_sort_mode'), 'dueAsc');
    expect(
      find.text('Current default: Table / Priority / Sort: Due'),
      findsOneWidget,
    );
  });

  testWidgets('edits custom saved view fields in Settings', (tester) async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'custom_saved_views',
      jsonEncode([
        {
          'id': 'focus-view',
          'label': 'Focus view',
          'dayView': 'table',
          'tableView': 'priority',
          'tableSort': 'priorityDesc',
        },
      ]),
    );

    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();

    await _tapKey(tester, 'settings-custom-view-menu-focus-view');
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('saved-view-label-field')),
      'Due focus',
    );
    await tester.tap(
      find.byKey(const ValueKey('saved-view-dialog-day-view-board')),
    );
    await tester.tap(
      find.byKey(const ValueKey('saved-view-dialog-table-view-due')),
    );
    await tester.tap(
      find.byKey(const ValueKey('saved-view-dialog-table-sort')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Due').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final raw = await preferences.getString('custom_saved_views');
    final decoded = jsonDecode(raw!) as List<Object?>;
    final view = decoded.single! as Map<Object?, Object?>;
    expect(view['id'], 'focus-view');
    expect(view['label'], 'Due focus');
    expect(view['dayView'], 'board');
    expect(view['tableView'], 'due');
    expect(view['tableSort'], 'dueAsc');
    expect(find.text('Due focus'), findsOneWidget);
  });

  testWidgets('loads stored recent sync activity when Settings opens', (
    tester,
  ) async {
    final activityStore = InMemorySyncActivityStore();
    await activityStore.add(
      SyncActivityEntry(
        id: 'stored-activity',
        action: SyncActivityAction.syncNow,
        status: SyncActivityStatus.success,
        message: 'Stored sync complete',
        occurredAt: DateTime(2026, 6, 19, 12),
        savedCount: 3,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(activityStore),
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
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Result: Stored sync complete'), findsOneWidget);
    expect(find.text('Saved 3 / Deleted 0 / Conflicts 0'), findsOneWidget);
  });

  testWidgets('syncs local data from the Settings sync card', (tester) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'settings-sync-note',
          type: NodeType.note,
          title: 'Settings sync note',
          day: DateTime(2026, 6, 19),
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(authGateway),
          syncRemoteBackupStoreProvider.overrideWithValue(remoteStore),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
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
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _expandSyncSections(tester);
    await _tapKey(tester, 'sync-sign-in-button');
    await tester.enterText(
      find.byKey(const ValueKey('sync-auth-email-field')),
      'local@var.app',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sync-auth-password-field')),
      'password',
    );
    await _tapKey(tester, 'sync-auth-sign-in-submit-button');
    await tester.pumpAndSettle();

    final account = await authGateway.currentState();
    final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
    expect(find.text('Sync complete'), findsOneWidget);
    expect(remoteDocument?.nodes.single.id, 'settings-sync-note');
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Sync now'), findsAtLeastNWidgets(1));
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('1 saved'), findsOneWidget);
  });

  testWidgets('keeps auth dialog open and shows auth failures', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
          syncAuthGatewayProvider.overrideWithValue(_FailingAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
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
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _expandSyncSections(tester);
    await _tapKey(tester, 'sync-sign-in-button');
    await tester.enterText(
      find.byKey(const ValueKey('sync-auth-email-field')),
      'local@var.app',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sync-auth-password-field')),
      'password',
    );
    await _tapKey(tester, 'sync-auth-sign-in-submit-button');

    expect(find.byKey(const ValueKey('sync-auth-email-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-auth-message')), findsOneWidget);
    expect(
      find.text('Email or password is incorrect.'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('shows sync health and renames this device', (tester) async {
    final deviceStore = InMemorySyncDeviceIdentityStore(
      const SyncDeviceIdentity(id: 'device-laptop', label: 'Work laptop'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
          syncRestorePointStoreProvider.overrideWithValue(
            InMemorySyncRestorePointStore(),
          ),
          syncDeviceIdentityStoreProvider.overrideWithValue(deviceStore),
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync health'), findsOneWidget);
    expect(find.text('Signed out'), findsAtLeastNWidgets(1));
    expect(find.text('Sign in to enable cloud sync.'), findsOneWidget);
    expect(find.text('Work laptop'), findsAtLeastNWidgets(1));
    expect(find.text('device-laptop'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('sync-device-name-field')),
      'Studio desktop',
    );
    await _tapKey(tester, 'sync-device-save-button');

    final updated = await deviceStore.readOrCreateIdentity();
    expect(updated.label, 'Studio desktop');
    expect(find.text('Device renamed'), findsOneWidget);
    expect(find.text('Studio desktop'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows sync conflict details in the Settings sync card', (
    tester,
  ) async {
    final baseline = MindmapNode.create(
      id: 'settings-conflict-note',
      type: NodeType.note,
      title: 'Shared note',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 19, 8),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(authGateway),
          syncRemoteBackupStoreProvider.overrideWithValue(remoteStore),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
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
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _expandSyncSections(tester);
    await _tapKey(tester, 'sync-sign-in-button');
    await tester.enterText(
      find.byKey(const ValueKey('sync-auth-email-field')),
      'local@var.app',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sync-auth-password-field')),
      'password',
    );
    await _tapKey(tester, 'sync-auth-sign-in-submit-button');
    await tester.pumpAndSettle();

    await repository.saveNode(
      baseline.copyWith(
        title: 'Local edit',
        updatedAt: DateTime(2026, 6, 19, 9),
      ),
    );
    final account = await authGateway.currentState();
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 19, 13),
        nodes: [
          baseline.copyWith(
            title: 'Remote edit',
            updatedAt: DateTime(2026, 6, 19, 10),
          ),
        ],
      ),
    );

    await _tapKey(tester, 'sync-now-button');

    expect(find.text('Sync blocked by conflicts'), findsOneWidget);
    expect(find.text('Conflict queue'), findsOneWidget);
    expect(find.text('Both edited'), findsOneWidget);
    expect(find.text('Shared note'), findsOneWidget);
    expect(find.text('Local edit'), findsOneWidget);
    expect(find.text('Remote edit'), findsOneWidget);
    expect(
      find.text('Note / 2026-06-19 / Open / Updated 2026-06-19 08:00'),
      findsOneWidget,
    );
    expect(
      find.text('Note / 2026-06-19 / Open / Updated 2026-06-19 09:00'),
      findsOneWidget,
    );
    expect(
      find.text('Note / 2026-06-19 / Open / Updated 2026-06-19 10:00'),
      findsOneWidget,
    );

    await _tapKey(tester, 'sync-conflict-use-remote-settings-conflict-note');

    final resolvedRemote = await remoteStore.fetchLatestBackup(account.user!);
    expect(find.text('Remote version applied'), findsOneWidget);
    expect(find.text('Conflict queue'), findsNothing);
    expect(resolvedRemote?.nodes.single.title, 'Remote edit');
  });

  testWidgets('exports and imports encrypted portable backups', (tester) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'settings-portable-note',
          type: NodeType.note,
          title: 'Settings private note',
          day: DateTime(2026, 6, 19),
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
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
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await _expandSyncSections(tester);

    await tester.enterText(
      find.byKey(const ValueKey('portable-passphrase-field')),
      'shared-secret',
    );
    await _tapKey(tester, 'portable-export-button');

    final packageField = tester.widget<TextField>(
      find.byKey(const ValueKey('portable-package-field')),
    );
    final package = packageField.controller!.text;
    expect(package, contains('var.mindmap.backup.encrypted'));
    expect(package, isNot(contains('Settings private note')));

    await repository.deleteNode('settings-portable-note');
    await _tapKey(tester, 'portable-import-button');

    expect(find.text('Portable backup imported'), findsOneWidget);
    expect(
      (await repository.getNode('settings-portable-note'))?.title,
      'Settings private note',
    );
  });

  testWidgets('restores a saved restore point from Settings', (tester) async {
    final original = MindmapNode.create(
      id: 'settings-restore-note',
      type: NodeType.note,
      title: 'Settings restore note',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 19, 8),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [original]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
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
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _expandSyncSections(tester);
    await tester.enterText(
      find.byKey(const ValueKey('portable-passphrase-field')),
      'shared-secret',
    );
    await _tapKey(tester, 'portable-export-button');

    expect(find.text('Restore points'), findsOneWidget);
    expect(find.text('1 node'), findsAtLeastNWidgets(1));

    await repository.saveNode(
      original.copyWith(
        title: 'Changed after export',
        updatedAt: DateTime(2026, 6, 19, 13),
      ),
    );
    await repository.saveNode(
      MindmapNode.create(
        id: 'settings-extra-note',
        type: NodeType.note,
        title: 'Temporary extra note',
        day: DateTime(2026, 6, 19),
        now: DateTime(2026, 6, 19, 13),
      ),
    );

    await _tapKey(tester, 'restore-point-0-button');

    expect(find.text('Restore preview'), findsOneWidget);
    expect(find.text('1 update'), findsOneWidget);
    expect(find.text('1 delete'), findsOneWidget);
    expect(find.text('Temporary extra note'), findsOneWidget);
    expect(
      (await repository.getNode('settings-restore-note'))?.title,
      'Changed after export',
    );

    final disabledRestoreButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('restore-point-confirm-button')),
    );
    expect(disabledRestoreButton.onPressed, isNull);
    expect(
      find.text('I understand local nodes may be deleted'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('restore-destructive-confirmation-checkbox')),
    );
    await tester.pumpAndSettle();

    final enabledRestoreButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('restore-point-confirm-button')),
    );
    expect(enabledRestoreButton.onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey('restore-point-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restore point applied'), findsOneWidget);
    expect(find.text('Before restore'), findsOneWidget);
    expect(
      (await repository.getNode('settings-restore-note'))?.title,
      'Settings restore note',
    );
    expect(await repository.getNode('settings-extra-note'), isNull);
  });

  testWidgets('shows sectioned restore preview changes in Settings', (
    tester,
  ) async {
    final original = MindmapNode.create(
      id: 'settings-preview-shared',
      type: NodeType.note,
      title: 'Original preview note',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 19, 8),
    );
    final backupOnly = MindmapNode.create(
      id: 'settings-preview-added',
      type: NodeType.note,
      title: 'Backup-only preview note',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 19, 8),
    );
    final localOnly = MindmapNode.create(
      id: 'settings-preview-deleted',
      type: NodeType.note,
      title: 'Local-only preview note',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 19, 9),
    );
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        original.copyWith(
          title: 'Local preview draft',
          updatedAt: DateTime(2026, 6, 19, 13),
        ),
        localOnly,
      ],
    );
    final restorePointStore = InMemorySyncRestorePointStore();
    await restorePointStore.add(
      SyncRestorePoint(
        id: 'sectioned-preview',
        label: 'Sectioned preview',
        createdAt: DateTime(2026, 6, 19, 11),
        document: MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
          exportedAt: DateTime(2026, 6, 19, 10),
          nodes: [original, backupOnly],
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
          syncRestorePointStoreProvider.overrideWithValue(restorePointStore),
          syncDeviceIdentityStoreProvider.overrideWithValue(
            InMemorySyncDeviceIdentityStore(
              const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
            ),
          ),
          syncDeviceIdentityProvider.overrideWithValue(
            const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
          ),
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, 'restore-point-0-button');

    expect(find.text('Restore preview'), findsOneWidget);
    expect(find.text('Will add'), findsOneWidget);
    expect(find.text('Will update'), findsOneWidget);
    expect(find.text('Will delete'), findsOneWidget);
    expect(find.text('Backup-only preview note'), findsOneWidget);
    expect(find.text('Original preview note'), findsOneWidget);
    expect(find.text('Local-only preview note'), findsOneWidget);
  });

  testWidgets('labels high impact restore points in Settings', (tester) async {
    final original = MindmapNode.create(
      id: 'settings-risk-shared',
      type: NodeType.note,
      title: 'Risk backup note',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 19, 8),
    );
    final localOnly = MindmapNode.create(
      id: 'settings-risk-local-only',
      type: NodeType.note,
      title: 'Risk local scratch',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 19, 9),
    );
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        original.copyWith(
          title: 'Risk local draft',
          updatedAt: DateTime(2026, 6, 19, 13),
        ),
        localOnly,
      ],
    );
    final restorePointStore = InMemorySyncRestorePointStore();
    await restorePointStore.add(
      SyncRestorePoint(
        id: 'high-risk-restore',
        label: 'High risk restore',
        createdAt: DateTime(2026, 6, 19, 11),
        document: MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
          exportedAt: DateTime(2026, 6, 19, 10),
          nodes: [original],
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
          syncRestorePointStoreProvider.overrideWithValue(restorePointStore),
          syncDeviceIdentityStoreProvider.overrideWithValue(
            InMemorySyncDeviceIdentityStore(
              const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
            ),
          ),
          syncDeviceIdentityProvider.overrideWithValue(
            const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
          ),
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('High risk restore'), findsOneWidget);
    expect(find.text('High impact'), findsOneWidget);
    expect(find.text('Impact: 1 update / 1 delete'), findsOneWidget);
  });

  testWidgets('deletes a restore point from Settings', (tester) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'settings-delete-restore-note',
          type: NodeType.note,
          title: 'Settings delete restore',
          day: DateTime(2026, 6, 19),
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );
    final restorePointStore = InMemorySyncRestorePointStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
          syncRestorePointStoreProvider.overrideWithValue(restorePointStore),
          syncDeviceIdentityStoreProvider.overrideWithValue(
            InMemorySyncDeviceIdentityStore(
              const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
            ),
          ),
          syncDeviceIdentityProvider.overrideWithValue(
            const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
          ),
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _expandSyncSections(tester);
    await tester.enterText(
      find.byKey(const ValueKey('portable-passphrase-field')),
      'shared-secret',
    );
    await _tapKey(tester, 'portable-export-button');

    expect(find.text('Restore points'), findsOneWidget);

    await _tapKey(tester, 'restore-point-0-delete-button');

    expect(await restorePointStore.recent(), isEmpty);
    expect(find.text('Restore points'), findsNothing);
  });

  testWidgets('filters restore points by source device in Settings', (
    tester,
  ) async {
    final restorePointStore = InMemorySyncRestorePointStore();
    await restorePointStore.add(
      _restorePoint(
        id: 'phone-snapshot',
        label: 'Phone snapshot',
        sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
      ),
    );
    await restorePointStore.add(
      _restorePoint(
        id: 'laptop-snapshot',
        label: 'Laptop snapshot',
        sourceDevice: const SyncDeviceIdentity(id: 'laptop', label: 'Laptop'),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
          syncAuthGatewayProvider.overrideWithValue(LocalSyncAuthGateway()),
          syncRemoteBackupStoreProvider.overrideWithValue(
            InMemorySyncRemoteBackupStore(),
          ),
          syncStateStoreProvider.overrideWithValue(InMemorySyncStateStore()),
          syncActivityStoreProvider.overrideWithValue(
            InMemorySyncActivityStore(),
          ),
          syncRestorePointStoreProvider.overrideWithValue(restorePointStore),
          syncDeviceIdentityStoreProvider.overrideWithValue(
            InMemorySyncDeviceIdentityStore(
              const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
            ),
          ),
          syncDeviceIdentityProvider.overrideWithValue(
            const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
          ),
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
          portableBackupCodecProvider.overrideWithValue(
            PortableMindmapBackupCodec(
              iterations: 2,
              randomBytes: _deterministicRandomBytes(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restore points'), findsOneWidget);
    expect(find.text('Phone snapshot'), findsOneWidget);
    expect(find.text('Laptop snapshot'), findsOneWidget);

    await _tapKey(tester, 'restore-source-filter-Phone');

    expect(find.text('Phone snapshot'), findsOneWidget);
    expect(find.text('Laptop snapshot'), findsNothing);

    await _tapKey(tester, 'restore-source-filter-All');

    expect(find.text('Phone snapshot'), findsOneWidget);
    expect(find.text('Laptop snapshot'), findsOneWidget);
  });

  testWidgets('SettingsPage collapses template and saved view managers', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();
    await _scrollToKey(tester, 'settings-template-manager-toggle');

    expect(find.text('Template manager'), findsOneWidget);
    expect(
      find.text(
        'Custom templates are stored locally and appear in Command quick create.',
      ),
      findsNothing,
    );
    expect(find.text('Saved views'), findsOneWidget);
    expect(find.text('Default day view'), findsNothing);
    expect(find.text('Graph filters'), findsOneWidget);
    expect(find.text('No saved graph filters yet.'), findsNothing);

    await _tapKey(tester, 'settings-template-manager-toggle');
    expect(
      find.text(
        'Custom templates are stored locally and appear in Command quick create.',
      ),
      findsOneWidget,
    );

    await _tapKey(tester, 'settings-saved-views-toggle');
    expect(find.text('Default day view'), findsOneWidget);

    await _tapKey(tester, 'settings-graph-filters-toggle');
    expect(find.text('No saved graph filters yet.'), findsOneWidget);
  });

  testWidgets('SettingsPage collapses data management options', (tester) async {
    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();
    await _scrollToKey(tester, 'data-management-toggle');

    expect(find.text('Data management'), findsOneWidget);
    expect(find.text('Export Data'), findsNothing);

    await _tapKey(tester, 'data-management-toggle');
    expect(find.text('Export Data'), findsOneWidget);
    expect(find.text('Clear All Data'), findsOneWidget);
  });

  testWidgets('SettingsPage collapses quick start guide until toggled', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Quick start guide'), findsOneWidget);
    expect(find.text('Calendar first'), findsNothing);
    expect(find.text('Show guide'), findsOneWidget);

    await tester.tap(find.text('Show guide'));
    await tester.pumpAndSettle();

    expect(find.text('Calendar first'), findsOneWidget);
    expect(find.text('Hide guide'), findsOneWidget);

    await tester.tap(find.text('Hide guide'));
    await tester.pumpAndSettle();

    expect(find.text('Calendar first'), findsNothing);
    expect(find.text('Show guide'), findsOneWidget);
  });
}

Widget _settingsTestApp() {
  return ProviderScope(
    overrides: [
      mindmapRepositoryProvider.overrideWithValue(InMemoryMindmapRepository()),
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
      syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
      portableBackupCodecProvider.overrideWithValue(
        PortableMindmapBackupCodec(
          iterations: 2,
          randomBytes: _deterministicRandomBytes(),
        ),
      ),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

final class _FailingAuthGateway implements SyncAuthGateway {
  @override
  Future<SyncAuthState> currentState() async => const SyncAuthState.signedOut();

  @override
  Future<SyncAuthState> signIn({
    required String email,
    String password = '',
    String displayName = '',
  }) async {
    throw const SyncAuthException('Email or password is incorrect.');
  }

  @override
  Future<SyncAuthState> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    throw const SyncAuthException('An account already exists for this email.');
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    throw const SyncAuthException('Enter a valid email address.');
  }

  @override
  Future<void> signOut() async {}
}

Finder _keyFinder(String key) => find.byKey(ValueKey<String>(key));

Future<void> _scrollToKey(WidgetTester tester, String key) async {
  final finder = _keyFinder(key);
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }
}

Future<void> _expandSyncSections(WidgetTester tester) async {
  // Expand Cloud sync if collapsed
  final cloudTile = find.text('Cloud sync');
  if (cloudTile.evaluate().isNotEmpty) {
    await tester.ensureVisible(cloudTile.first);
    await tester.pumpAndSettle();
    final signIn = find.byKey(const ValueKey('sync-sign-in-button'));
    if (signIn.evaluate().isEmpty) {
      await tester.tap(cloudTile.first);
      await tester.pumpAndSettle();
    }
  }
  // Expand Portable encrypted backup if collapsed
  final backupTile = find.text('Portable encrypted backup');
  if (backupTile.evaluate().isNotEmpty) {
    await tester.ensureVisible(backupTile.first);
    await tester.pumpAndSettle();
    final passphrase = find.byKey(const ValueKey('portable-passphrase-field'));
    if (passphrase.evaluate().isEmpty) {
      await tester.tap(backupTile.first);
      await tester.pumpAndSettle();
    }
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await _expandSettingsSectionForKey(tester, key);
  await _scrollToKey(tester, key);
  await tester.tap(_keyFinder(key).first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _expandSettingsSectionForKey(
  WidgetTester tester,
  String key,
) async {
  String? toggleKey;
  if (key.startsWith('settings-day-view') ||
      key.startsWith('settings-table-quick-view') ||
      key.startsWith('settings-custom-view') ||
      key.startsWith('settings-saved-view-preset') ||
      key == 'settings-saved-view-current-default' ||
      key == 'settings-table-sort-mode') {
    toggleKey = 'settings-saved-views-toggle';
  }
  if (toggleKey == null) return;
  // If key already in tree, section is expanded — skip
  if (_keyFinder(key).evaluate().isNotEmpty) return;
  // Section collapsed — scroll to toggle and tap it
  await _scrollToKey(tester, toggleKey);
  final toggle = _keyFinder(toggleKey);
  if (toggle.evaluate().isEmpty) return;
  await tester.tap(toggle.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

List<int> Function(int) _deterministicRandomBytes() {
  var call = 0;
  return (length) {
    call += 1;
    return List<int>.generate(length, (index) => (call * 43 + index) % 256);
  };
}

SyncRestorePoint _restorePoint({
  required String id,
  required String label,
  required SyncDeviceIdentity sourceDevice,
}) {
  return SyncRestorePoint(
    id: id,
    label: label,
    createdAt: DateTime(2026, 6, 19, 11),
    document: MindmapBackupDocument.create(
      sourceDevice: sourceDevice,
      exportedAt: DateTime(2026, 6, 19, 10),
      nodes: [
        MindmapNode.create(
          id: '$id-node',
          type: NodeType.note,
          title: label,
          day: DateTime(2026, 6, 19),
          now: DateTime(2026, 6, 19, 9),
        ),
      ],
    ),
  );
}
