import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/data/canvas_board_template_repositories.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template_repository.dart';
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

  testWidgets('cloud extraction is disabled by default and persists opt-in', (
    tester,
  ) async {
    final preferences = SharedPreferencesAsync();
    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('settings-cloud-extraction'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(await preferences.getBool('search.cloudExtractionEnabled'), isTrue);
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

  testWidgets('SettingsPage shows compact Recovery Center entry', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();
    await _scrollToKey(tester, 'settings-recovery-center-entry');

    expect(
      find.byKey(const ValueKey('settings-recovery-center-entry')),
      findsOneWidget,
    );
    expect(find.text('Recovery Center'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-now-button')), findsNothing);
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

  testWidgets('saves trimmed linked board template', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, 'settings-board-templates-toggle');
    await _tapKey(tester, 'settings-board-template-add');
    await tester.tap(find.text('Roadmap').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('board-template-name-field')),
      '  Launch board  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = (await templates.listTemplates()).single;
    expect(saved.name, 'Launch board');
    expect(saved.sourceBoardId, 'source');
    expect(find.text('Launch board'), findsOneWidget);
  });

  testWidgets('board template panel ListTiles paint ink and open actions', (
    tester,
  ) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    await templates.saveTemplate(_boardTemplate('linked', 'Launch', 'source'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, 'settings-board-templates-toggle');
    final linkedTile = find.widgetWithText(ListTile, 'Launch');
    final panelMaterial = tester.widget<Material>(
      find.ancestor(of: linkedTile, matching: find.byType(Material)).first,
    );
    expect(panelMaterial.color, isNot(Colors.transparent));
    expect(panelMaterial.clipBehavior, Clip.antiAlias);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(linkedTile));
    await tester.pump();
    await tester.tap(linkedTile);
    await tester.pump();
    await _tapKey(tester, 'settings-board-template-menu-linked');

    expect(find.text('Rename'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renames and deletes linked board template', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    await templates.saveTemplate(_boardTemplate('linked', 'Launch', 'source'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, 'settings-board-templates-toggle');
    await _tapKey(tester, 'settings-board-template-menu-linked');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('board-template-name-field')),
      '  Renamed  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect((await templates.listTemplates()).single.name, 'Renamed');

    await _tapKey(tester, 'settings-board-template-menu-linked');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await templates.listTemplates(), isNotEmpty);
    await tester.tap(
      find.byKey(const ValueKey('board-template-delete-confirm')),
    );
    await tester.pumpAndSettle();
    expect(await templates.listTemplates(), isEmpty);
  });

  testWidgets('stale rename dialog preserves concurrent template rename', (
    tester,
  ) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    final displayed = _boardTemplate('linked', 'Launch', 'source');
    await templates.saveTemplate(displayed);
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, 'settings-board-templates-toggle');
    await _tapKey(tester, 'settings-board-template-menu-linked');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    final concurrentAt = displayed.updatedAt.add(const Duration(minutes: 1));
    final concurrent = await templates.renameTemplate(
      templateId: displayed.id,
      expectedUpdatedAt: displayed.updatedAt,
      name: 'Concurrent',
      updatedAt: concurrentAt,
    );
    await tester.enterText(
      find.byKey(const ValueKey('board-template-name-field')),
      'Stale UI rename',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Failed to rename board template'),
      findsOneWidget,
    );
    expect(await templates.listTemplates(), <CanvasBoardTemplate>[concurrent]);
  });

  testWidgets('search filters live board templates', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoardsAtomically([
      _projectBoard('alpha-source', title: 'Alpha source'),
      _projectBoard('beta-source', title: 'Beta source'),
    ]);
    await templates.saveTemplate(
      _boardTemplate('alpha', 'Alpha launch', 'alpha-source'),
    );
    await templates.saveTemplate(
      _boardTemplate('beta', 'Beta review', 'beta-source'),
    );
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, 'settings-board-templates-toggle');
    await tester.enterText(
      find.byKey(const ValueKey('settings-board-template-search')),
      'beta',
    );
    await tester.pumpAndSettle();

    expect(find.text('Beta review'), findsOneWidget);
    expect(find.text('Alpha launch'), findsNothing);
  });

  testWidgets('trashed source disappears from board templates', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    final source = _projectBoard('source', title: 'Roadmap');
    await boards.saveBoard(source);
    await templates.saveTemplate(_boardTemplate('linked', 'Launch', 'source'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'settings-board-templates-toggle');
    expect(find.text('Launch'), findsOneWidget);

    await boards.saveBoard(
      source.copyWith(trashedAt: DateTime.utc(2026, 8, 2)),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    container.invalidate(workspaceBoardGraphProvider('Work'));
    await tester.pumpAndSettle();

    expect(find.text('Launch'), findsNothing);
  });

  testWidgets('deleted source disappears from board templates', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    await templates.saveTemplate(_boardTemplate('linked', 'Launch', 'source'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'settings-board-templates-toggle');
    expect(find.text('Launch'), findsOneWidget);

    await boards.deleteBoard('source');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    container.invalidate(workspaceBoardGraphProvider('Work'));
    await tester.pumpAndSettle();

    expect(find.text('Launch'), findsNothing);
  });

  testWidgets('shows save failure for board template', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = _FailingTemplateRepository(saveFailure: true);
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'settings-board-templates-toggle');
    await _tapKey(tester, 'settings-board-template-add');
    await tester.tap(find.text('Roadmap').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to save board template: save failed'),
      findsOneWidget,
    );
  });

  testWidgets('shows rename failure for board template', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = _FailingTemplateRepository(renameFailure: true);
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'settings-board-templates-toggle');
    await _tapKey(tester, 'settings-board-template-menu-linked');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to rename board template: rename failed'),
      findsOneWidget,
    );
  });

  testWidgets('shows delete failure for board template', (tester) async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = _FailingTemplateRepository(deleteFailure: true);
    await boards.saveBoard(_projectBoard('source', title: 'Roadmap'));
    await tester.pumpWidget(
      _settingsTestApp(canvasRepository: boards, templateRepository: templates),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'settings-board-templates-toggle');
    await _tapKey(tester, 'settings-board-template-menu-linked');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('board-template-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to delete board template: delete failed'),
      findsOneWidget,
    );
    expect(find.text('Launch'), findsOneWidget);
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

Widget _settingsTestApp({
  InMemoryCanvasBoardRepository? canvasRepository,
  CanvasBoardTemplateRepository? templateRepository,
}) {
  return ProviderScope(
    overrides: [
      mindmapRepositoryProvider.overrideWithValue(InMemoryMindmapRepository()),
      if (canvasRepository != null)
        canvasBoardRepositoryProvider.overrideWithValue(canvasRepository),
      if (templateRepository != null)
        canvasBoardTemplateRepositoryProvider.overrideWithValue(
          templateRepository,
        ),
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
          iterations: PortableMindmapBackupCodec.minKdfIterations,
          randomBytes: _deterministicRandomBytes(),
        ),
      ),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

CanvasBoard _projectBoard(String id, {required String title}) => CanvasBoard(
  id: id,
  kind: CanvasBoardKind.project,
  title: title,
  workspaceName: 'Work',
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

CanvasBoardTemplate _boardTemplate(String id, String name, String sourceId) =>
    CanvasBoardTemplate(
      id: id,
      name: name,
      sourceBoardId: sourceId,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );

final class _FailingTemplateRepository
    implements CanvasBoardTemplateRepository {
  _FailingTemplateRepository({
    this.saveFailure = false,
    this.renameFailure = false,
    this.deleteFailure = false,
  });

  final bool saveFailure;
  final bool renameFailure;
  final bool deleteFailure;
  final CanvasBoardTemplate template = _boardTemplate(
    'linked',
    'Launch',
    'source',
  );

  @override
  Future<void> deleteTemplate(String templateId) async {
    if (deleteFailure) throw StateError('delete failed');
  }

  @override
  Future<List<CanvasBoardTemplate>> listTemplates() async => [template];

  @override
  Future<CanvasBoardTemplate> renameTemplate({
    required String templateId,
    required DateTime expectedUpdatedAt,
    required String name,
    required DateTime updatedAt,
  }) async {
    if (renameFailure) throw StateError('rename failed');
    return CanvasBoardTemplate(
      id: template.id,
      name: name,
      sourceBoardId: template.sourceBoardId,
      createdAt: template.createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<CanvasBoardTemplate> saveTemplate(CanvasBoardTemplate value) async {
    if (saveFailure && value.id != template.id) throw StateError('save failed');
    if (renameFailure && value.id == template.id) {
      throw StateError('rename failed');
    }
    return value;
  }
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
