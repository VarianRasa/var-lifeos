import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/canvas_board_package_service.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';

void main() {
  test('portable project board round trip remaps image attachments', () async {
    final sourceRepository = _MemoryAttachmentRepository();
    final sourceAttachment = await sourceRepository.importBytes(
      bytes: <int>[1, 2, 3, 4],
      fileName: 'idea.png',
      mimeType: 'image/png',
    );
    final now = DateTime(2026, 7, 28, 10);
    final board = CanvasBoard(
      id: 'project:source',
      kind: CanvasBoardKind.project,
      title: 'Idea board',
      workspaceName: 'project:Source',
      votingSession: CanvasVotingSession()
          .start(maxVotes: 2)
          .changeVote(participantId: 'ari', objectId: 'image-1', add: true),
      objects: <CanvasObject>[
        CanvasObject(
          id: 'image-1',
          type: CanvasObjectType.image,
          geometry: const CanvasGeometry(x: 10, y: 20, width: 200, height: 120),
          payload: <String, Object?>{
            'attachmentId': sourceAttachment.id,
            'fileName': sourceAttachment.fileName,
            'mimeType': sourceAttachment.mimeType,
            'byteLength': sourceAttachment.byteLength,
          },
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final bytes = await CanvasBoardPackageService(
      attachmentRepository: sourceRepository,
    ).exportPackage(board);
    final targetRepository = _MemoryAttachmentRepository();
    await targetRepository.importBytes(
      bytes: <int>[9],
      fileName: 'existing.png',
      mimeType: 'image/png',
    );
    final imported =
        await CanvasBoardPackageService(
          attachmentRepository: targetRepository,
        ).importPackage(
          bytes,
          workspaceName: 'project:Target',
          now: now.add(const Duration(hours: 1)),
        );

    expect(imported.id, startsWith(projectCanvasBoardId('project:Target')));
    expect(imported.title, 'Idea board imported');
    expect(imported.workspaceName, 'project:Target');
    expect(imported.votingSession.status, CanvasVotingStatus.inactive);
    final importedImage = imported.objects.single;
    final importedAttachmentId =
        importedImage.payload['attachmentId']! as String;
    expect(importedAttachmentId, isNot(sourceAttachment.id));
    expect(await targetRepository.readBytes(importedAttachmentId), <int>[
      1,
      2,
      3,
      4,
    ]);
  });

  test('portable import rejects unsupported payload', () async {
    final service = CanvasBoardPackageService(
      attachmentRepository: _MemoryAttachmentRepository(),
    );

    expect(
      () => service.importPackage(
        <int>[1, 2, 3],
        workspaceName: 'project:Target',
        now: DateTime(2026, 7, 28),
      ),
      throwsA(anything),
    );
  });
}

final class _MemoryAttachmentRepository implements NodeAttachmentRepository {
  final Map<String, NodeAttachment> _attachments = <String, NodeAttachment>{};
  final Map<String, List<int>> _bytes = <String, List<int>>{};
  int _nextId = 0;

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final id = 'attachment-${_nextId++}';
    final attachment = NodeAttachment(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      byteLength: bytes.length,
      checksum: 'checksum-$id',
      createdAt: DateTime(2026, 7, 28),
    );
    _attachments[id] = attachment;
    _bytes[id] = List<int>.from(bytes);
    return attachment;
  }

  @override
  Future<NodeAttachment?> resolve(String attachmentId) async =>
      _attachments[attachmentId];

  @override
  Future<List<int>?> readBytes(String attachmentId) async =>
      _bytes[attachmentId];

  @override
  Future<List<int>?> exportBytes(String attachmentId) =>
      readBytes(attachmentId);

  @override
  Future<void> delete(String attachmentId) async {
    _attachments.remove(attachmentId);
    _bytes.remove(attachmentId);
  }

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async =>
      <NodeAttachmentManifestEntry>[
        for (final attachment in _attachments.values)
          NodeAttachmentManifestEntry(
            version: nodeAttachmentManifestVersion,
            attachment: attachment,
          ),
      ];
}
