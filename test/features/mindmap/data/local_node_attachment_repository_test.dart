import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:var_app/features/mindmap/data/local_node_attachment_repository_io.dart';
import 'package:var_app/features/mindmap/data/local_node_attachment_repository_web.dart'
    as web;
import 'package:var_app/features/mindmap/domain/node_attachment.dart';

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('var-attachment-test-');
    root = Directory(p.join(sandbox.path, 'root'));
  });
  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('byte round-trip, resolve, export, and repository restart', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final attachment = await repository.importBytes(
      bytes: const [137, 80, 78, 71],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    expect(await repository.resolve(attachment.id), isNotNull);
    expect(await repository.readBytes(attachment.id), [137, 80, 78, 71]);
    expect(await repository.exportBytes(attachment.id), [137, 80, 78, 71]);
    final restarted = LocalNodeAttachmentRepository(root: root);
    expect(
      (await restarted.buildManifest()).single.attachment.id,
      attachment.id,
    );
    expect(await restarted.readBytes(attachment.id), [137, 80, 78, 71]);
  });

  test(
    'generic task document round-trips through attachment repository',
    () async {
      final repository = LocalNodeAttachmentRepository(root: root);
      final attachment = await repository.importBytes(
        bytes: const <int>[1, 2, 3, 4],
        fileName: 'brief.pdf',
        mimeType: 'application/octet-stream',
      );

      expect(await repository.readBytes(attachment.id), <int>[1, 2, 3, 4]);
      expect((await repository.resolve(attachment.id))?.fileName, 'brief.pdf');
    },
  );
  test(
    'rejects empty, oversized, unsupported, and mismatched imports',
    () async {
      final repository = LocalNodeAttachmentRepository(root: root);
      await expectLater(
        repository.importBytes(
          bytes: const [],
          fileName: 'x.png',
          mimeType: 'image/png',
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.importBytes(
          bytes: List.filled(maxNodeAttachmentBytes + 1, 0),
          fileName: 'x.png',
          mimeType: 'image/png',
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.importBytes(
          bytes: const [1],
          fileName: 'x.exe',
          mimeType: 'application/octet-stream',
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.importBytes(
          bytes: const [1],
          fileName: 'x.jpg',
          mimeType: 'image/png',
        ),
        throwsFormatException,
      );
    },
  );

  test('normalizes traversal and never writes outside root', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final attachment = await repository.importBytes(
      bytes: const [1, 2],
      fileName: '../../safe.png',
      mimeType: 'image/png',
    );
    expect(attachment.fileName, 'safe.png');
    final files = await sandbox
        .list(recursive: true)
        .where((value) => value is File)
        .cast<File>()
        .toList();
    expect(
      files.every((file) => p.isWithin(root.absolute.path, file.absolute.path)),
      isTrue,
    );
    await expectLater(repository.readBytes('../escape'), throwsFormatException);
  });

  test('delete removes bytes and manifest safely', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final attachment = await repository.importBytes(
      bytes: const [1],
      fileName: 'voice.mp3',
      mimeType: 'audio/mpeg',
    );
    await repository.delete(attachment.id);
    expect(await repository.readBytes(attachment.id), isNull);
    expect(await repository.buildManifest(), isEmpty);
    await repository.delete(attachment.id);
  });

  test(
    'manifest replacement failure preserves previous durable manifest',
    () async {
      var failCommit = false;
      final repository = LocalNodeAttachmentRepository(
        root: root,
        beforeManifestReplace: () async {
          if (failCommit) throw StateError('injected manifest failure');
        },
      );
      final first = await repository.importBytes(
        bytes: const [1],
        fileName: 'first.png',
        mimeType: 'image/png',
      );
      failCommit = true;
      await expectLater(
        repository.importBytes(
          bytes: const [2],
          fileName: 'second.png',
          mimeType: 'image/png',
        ),
        throwsStateError,
      );
      final restarted = LocalNodeAttachmentRepository(root: root);
      expect(
        (await restarted.buildManifest()).map((value) => value.attachment.id),
        [first.id],
      );
      expect(await restarted.readBytes(first.id), [1]);
    },
  );

  test(
    'delete manifest failure restores metadata and readable bytes',
    () async {
      var failCommit = false;
      final repository = LocalNodeAttachmentRepository(
        root: root,
        beforeManifestReplace: () async {
          if (failCommit) throw StateError('injected manifest failure');
        },
      );
      final attachment = await repository.importBytes(
        bytes: const [7, 8],
        fileName: 'keep.mp4',
        mimeType: 'video/mp4',
      );
      failCommit = true;
      await expectLater(repository.delete(attachment.id), throwsStateError);
      final restarted = LocalNodeAttachmentRepository(root: root);
      expect(await restarted.resolve(attachment.id), isNotNull);
      expect(await restarted.readBytes(attachment.id), [7, 8]);
    },
  );

  test('post-commit cleanup failure never resurrects deleted blob', () async {
    var failCleanup = false;
    final repository = LocalNodeAttachmentRepository(
      root: root,
      beforeTombstoneCleanup: () async {
        if (failCleanup) throw StateError('injected cleanup failure');
      },
    );
    final attachment = await repository.importBytes(
      bytes: const [9, 10],
      fileName: 'delete.mp4',
      mimeType: 'video/mp4',
    );
    failCleanup = true;
    await repository.delete(attachment.id);

    expect(
      File(p.join(root.path, '${attachment.id}.bin')).existsSync(),
      isFalse,
    );
    expect(
      root.listSync().whereType<File>().any(
        (file) =>
            p.basename(file.path).startsWith('${attachment.id}.bin.delete-'),
      ),
      isTrue,
    );
    final restarted = LocalNodeAttachmentRepository(root: root);
    expect(await restarted.resolve(attachment.id), isNull);
    expect(await restarted.readBytes(attachment.id), isNull);
    expect(await restarted.buildManifest(), isEmpty);
    expect(
      root.listSync().whereType<File>().any(
        (file) =>
            p.basename(file.path).startsWith('${attachment.id}.bin.delete-'),
      ),
      isFalse,
    );
  });

  test('invalid IDs throw and missing valid IDs are safe', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    await expectLater(repository.resolve('../bad'), throwsFormatException);
    await expectLater(repository.delete('../bad'), throwsFormatException);
    const missing = '00000000-0000-4000-8000-000000000000';
    expect(await repository.resolve(missing), isNull);
    expect(await repository.readBytes(missing), isNull);
    await repository.delete(missing);
  });

  test('web memory fallback enforces cap and validation parity', () async {
    final repository = web.MemoryNodeAttachmentRepository(maxTotalBytes: 3);
    final attachment = await repository.importBytes(
      bytes: const [1, 2],
      fileName: r'C:\safe.png',
      mimeType: 'image/png',
    );
    expect(attachment.fileName, 'safe.png');
    await expectLater(
      repository.importBytes(
        bytes: const [3, 4],
        fileName: 'full.png',
        mimeType: 'image/png',
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.importBytes(
        bytes: const [256],
        fileName: 'bad.png',
        mimeType: 'image/png',
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.importBytes(
        bytes: const [1],
        fileName: 'bad.jpg',
        mimeType: 'image/png',
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.importBytes(
        bytes: const [1],
        fileName: 'CON.png',
        mimeType: 'image/png',
      ),
      throwsFormatException,
    );
    await expectLater(repository.readBytes('../bad'), throwsFormatException);
    await repository.delete(attachment.id);
    expect(await repository.readBytes(attachment.id), isNull);
  });

  test('malformed manifest entry does not discard valid entries', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final attachment = await repository.importBytes(
      bytes: const [1, 2, 3],
      fileName: 'clip.mp4',
      mimeType: 'video/mp4',
    );
    final file = File(p.join(root.path, 'manifest.json'));
    final manifest =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    (manifest['entries']! as List<Object?>).add({'id': '../bad'});
    await file.writeAsString(jsonEncode(manifest));
    final entries = await LocalNodeAttachmentRepository(
      root: root,
    ).buildManifest();
    expect(entries.map((value) => value.attachment.id), [attachment.id]);
  });

  test(
    'concurrent imports serialize without losing manifest entries',
    () async {
      final repository = LocalNodeAttachmentRepository(root: root);
      final imports = await Future.wait([
        for (var index = 0; index < 12; index++)
          repository.importBytes(
            bytes: [index + 1],
            fileName: 'image-$index.png',
            mimeType: 'image/png',
          ),
      ]);
      final manifest = await repository.buildManifest();
      expect(
        manifest.map((value) => value.attachment.id).toSet(),
        imports.map((value) => value.id).toSet(),
      );
    },
  );

  test('concurrent import and delete preserve committed entries', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final old = await repository.importBytes(
      bytes: const [1],
      fileName: 'old.png',
      mimeType: 'image/png',
    );
    final results = await Future.wait<Object?>([
      repository.importBytes(
        bytes: const [2],
        fileName: 'new.png',
        mimeType: 'image/png',
      ),
      repository.delete(old.id),
    ]);
    final added = results.first as NodeAttachment;
    expect(await repository.resolve(old.id), isNull);
    expect(await repository.readBytes(added.id), [2]);
    expect(
      (await repository.buildManifest()).map((value) => value.attachment.id),
      [added.id],
    );
  });

  test('backup-only crash state restores manifest on restart', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final attachment = await repository.importBytes(
      bytes: const [4, 5],
      fileName: 'backup.png',
      mimeType: 'image/png',
    );
    final active = File(p.join(root.path, 'manifest.json'));
    await active.rename(p.join(root.path, 'manifest.json.backup-crash'));
    final restarted = LocalNodeAttachmentRepository(root: root);
    expect(await restarted.readBytes(attachment.id), [4, 5]);
    expect(active.existsSync(), isTrue);
  });

  test('corrupt blob is rejected consistently', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final attachment = await repository.importBytes(
      bytes: const [6, 7, 8],
      fileName: 'corrupt.mp4',
      mimeType: 'video/mp4',
    );
    await File(
      p.join(root.path, '${attachment.id}.bin'),
    ).writeAsBytes(const [6]);
    expect(await repository.resolve(attachment.id), isNull);
    expect(await repository.readBytes(attachment.id), isNull);
    expect(await repository.exportBytes(attachment.id), isNull);
    expect(await repository.buildManifest(), isEmpty);
  });

  test('startup removes only known safe orphan patterns', () async {
    final repository = LocalNodeAttachmentRepository(root: root);
    final kept = await repository.importBytes(
      bytes: const [1],
      fileName: 'kept.png',
      mimeType: 'image/png',
    );
    final active = File(p.join(root.path, 'manifest.json'));
    await active.copy(p.join(root.path, 'manifest.json.backup-stale'));
    await File(
      p.join(root.path, 'manifest.json.tmp-stale'),
    ).writeAsString('temp');
    await File(
      p.join(root.path, '${kept.id}.bin.delete-stale'),
    ).writeAsBytes(const [1]);
    await File(
      p.join(root.path, '00000000-0000-4000-8000-000000000001.bin'),
    ).writeAsBytes(const [2]);
    final unknown = File(p.join(root.path, 'user-notes.txt'));
    await unknown.writeAsString('keep');

    final restarted = LocalNodeAttachmentRepository(root: root);
    expect(await restarted.readBytes(kept.id), [1]);
    expect(
      File(p.join(root.path, 'manifest.json.backup-stale')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(root.path, 'manifest.json.tmp-stale')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(root.path, '${kept.id}.bin.delete-stale')).existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(root.path, '00000000-0000-4000-8000-000000000001.bin'),
      ).existsSync(),
      isFalse,
    );
    expect(unknown.existsSync(), isTrue);
  });

  test('restoreBytes preserves stable id and rejects corrupt bytes', () async {
    final source = LocalNodeAttachmentRepository(
      root: Directory(p.join(sandbox.path, 'source')),
    );
    final metadata = await source.importBytes(
      bytes: const [1, 2, 3],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    final target = LocalNodeAttachmentRepository(root: root);

    await expectLater(
      target.restoreBytes(attachment: metadata, bytes: const [9, 9, 9]),
      throwsFormatException,
    );
    final restored = await target.restoreBytes(
      attachment: metadata,
      bytes: const [1, 2, 3],
    );

    expect(restored.id, metadata.id);
    expect(await target.readBytes(metadata.id), [1, 2, 3]);
  });

  test('concurrent stable-id restores serialize manifest commits', () async {
    final source = LocalNodeAttachmentRepository(
      root: Directory(p.join(sandbox.path, 'source')),
    );
    final first = await source.importBytes(
      bytes: const [1],
      fileName: 'first.png',
      mimeType: 'image/png',
    );
    final second = await source.importBytes(
      bytes: const [2],
      fileName: 'second.png',
      mimeType: 'image/png',
    );
    final target = LocalNodeAttachmentRepository(root: root);

    await Future.wait([
      target.restoreBytes(attachment: first, bytes: const [1]),
      target.restoreBytes(attachment: second, bytes: const [2]),
    ]);

    expect(
      (await target.buildManifest()).map((entry) => entry.attachment.id),
      containsAll([first.id, second.id]),
    );
  });
}
