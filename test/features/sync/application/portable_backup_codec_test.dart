import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';

void main() {
  test(
    'encrypts a backup package and restores it with the same passphrase',
    () async {
      final codec = PortableMindmapBackupCodec(
        iterations: 2,
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

  test('rejects a backup package opened with the wrong passphrase', () async {
    final codec = PortableMindmapBackupCodec(
      iterations: 2,
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
    final codec = PortableMindmapBackupCodec(iterations: 2);

    expect(
      () => codec.decode('not-json', passphrase: 'shared-secret'),
      throwsA(isA<PortableBackupException>()),
    );
  });
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
