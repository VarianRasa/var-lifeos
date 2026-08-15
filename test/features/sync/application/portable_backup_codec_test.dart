import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/inline_node_workspace_controller.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_ui_state_codec.dart';
import 'package:var_app/features/sync/application/mindmap_backup_service.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';

void main() {
  test(
    'encrypts a backup package and restores it with the same passphrase',
    () async {
      final codec = PortableMindmapBackupCodec(
        iterations: PortableMindmapBackupCodec.minKdfIterations,
        randomBytes: _deterministicRandomBytes(),
      );
      final document = MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        exportedAt: DateTime(2026, 6, 19, 8),
        nodes: [_node(id: 'private-note', title: 'Private launch note')],
      );

      final package = await codec.encode(
        document,
        passphrase: 'correct horse battery staple',
      );
      final restored = await codec.decode(
        package,
        passphrase: 'correct horse battery staple',
      );

      expect(package, contains('var.mindmap.backup.encrypted'));
      expect(package, isNot(contains('Private launch note')));
      expect(restored.exportedAt, DateTime(2026, 6, 19, 8));
      expect(restored.nodes.single.title, 'Private launch note');
    },
  );

  test('production portable export ignores dirty inline draft', () async {
    final committed =
        _node(
          id: 'private-note',
          title: 'Committed repository title',
        ).copyWithUiState(
          NodeUiState(
            sizePreset: NodeSizePreset.custom,
            width: 420,
            height: 280,
            collapsedSections: <String>{'metadata'},
          ),
        );
    final repository = InMemoryMindmapRepository(seedNodes: [committed]);
    final container = ProviderContainer(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        inlineNodeAutosaveSchedulerProvider.overrideWithValue(
          (delay, callback) => () {},
        ),
      ],
    );
    addTearDown(container.dispose);
    final workspace = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    expect(await workspace.requestExpansion(committed.id), isTrue);
    workspace.updateDraft(
      committed.id,
      InlineNodeDraftPatch(title: 'Dirty unflushed draft'),
    );

    final codec = PortableMindmapBackupCodec(
      iterations: PortableMindmapBackupCodec.minKdfIterations,
      randomBytes: _deterministicRandomBytes(),
    );
    final service = MindmapBackupService(
      repository: repository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 19, 8),
      portableCodec: codec,
    );
    final export = await service.createPortableBackup(
      passphrase: 'shared-secret',
    );
    final restored = await codec.decode(
      export.package,
      passphrase: 'shared-secret',
    );

    expect(export.document.nodes.single.title, 'Committed repository title');
    expect(restored.nodes.single.title, 'Committed repository title');
    final payloadKeys = _allMapKeys(export.document.toJson());
    final forbiddenKeys = <String>{
      'expandedNodeId',
      'dirty',
      'saveGeneration',
      'scroll',
      'debounce',
      inlineWorkspaceExpandedNodeIdKey,
      inlineWorkspaceDraftKey,
      inlineWorkspaceDirtyKey,
      inlineWorkspaceSaveStatusKey,
      inlineWorkspaceScrollKey,
      inlineWorkspaceDebounceKey,
    };
    expect(payloadKeys.intersection(forbiddenKeys), isEmpty);
  });

  test('rejects a backup package opened with the wrong passphrase', () async {
    final codec = PortableMindmapBackupCodec(
      iterations: PortableMindmapBackupCodec.minKdfIterations,
      randomBytes: _deterministicRandomBytes(),
    );
    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      exportedAt: DateTime(2026, 6, 19, 8),
      nodes: [_node(id: 'private-note', title: 'Private launch note')],
    );
    final package = await codec.encode(document, passphrase: 'right-secret');

    expect(
      () => codec.decode(package, passphrase: 'wrong-secret'),
      throwsA(isA<PortableBackupException>()),
    );
  });

  test('rejects malformed backup packages with a portable exception', () async {
    final codec = PortableMindmapBackupCodec(
      iterations: PortableMindmapBackupCodec.minKdfIterations,
    );

    expect(
      () => codec.decode('not-json', passphrase: 'shared-secret'),
      throwsA(isA<PortableBackupException>()),
    );
  });

  test('rejects unsafe KDF and exact cryptographic field lengths', () async {
    final codec = PortableMindmapBackupCodec(
      iterations: PortableMindmapBackupCodec.minKdfIterations,
      randomBytes: _deterministicRandomBytes(),
    );
    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      exportedAt: DateTime(2026, 6, 19, 8),
      nodes: [_node(id: 'note', title: 'Note')],
    );
    final package = await codec.encode(document, passphrase: 'shared-secret');
    final json = jsonDecode(package) as Map<String, Object?>;

    for (final changed in <Map<String, Object?>>[
      <String, Object?>{
        ...json,
        'kdf': <String, Object?>{
          ...(json['kdf']! as Map<String, Object?>),
          'iterations': PortableMindmapBackupCodec.minKdfIterations - 1,
        },
      },
      <String, Object?>{
        ...json,
        'nonce': base64Encode(List<int>.filled(11, 0)),
      },
      <String, Object?>{...json, 'mac': base64Encode(List<int>.filled(15, 0))},
    ]) {
      expect(
        () => codec.decode(jsonEncode(changed), passphrase: 'shared-secret'),
        throwsA(isA<PortableBackupException>()),
      );
    }
  });
}

Set<String> _allMapKeys(Object? value) {
  final keys = <String>{};
  void visit(Object? item) {
    if (item is Map<Object?, Object?>) {
      for (final entry in item.entries) {
        if (entry.key is String) keys.add(entry.key! as String);
        visit(entry.value);
      }
    } else if (item is Iterable<Object?>) {
      for (final child in item) {
        visit(child);
      }
    }
  }

  visit(value);
  return keys;
}

MindmapNode _node({required String id, required String title}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 6, 19),
    now: DateTime(2026, 6, 19, 8),
  );
}

List<int> Function(int) _deterministicRandomBytes() {
  var call = 0;
  return (length) {
    call += 1;
    return List<int>.generate(length, (index) => (call * 31 + index) % 256);
  };
}
