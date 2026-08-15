import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/command/domain/command_palette_entry.dart';
import 'package:var_app/features/mindmap/application/collaboration_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Collaboration Room ID Cleaning', () {
    test('accepts UUID room IDs and valid collaboration URIs', () {
      const roomId = '123e4567-e89b-42d3-a456-426614174000';
      expect(CollaborationNotifier.cleanRoomId(roomId), roomId);
      expect(
        CollaborationNotifier.cleanRoomId('var-collab://var.app/room/$roomId'),
        roomId,
      );
    });

    test('rejects short IDs and invalid collaboration URIs', () {
      expect(CollaborationNotifier.cleanRoomId('room-xyz'), isEmpty);
      expect(
        CollaborationNotifier.cleanRoomId(
          'var-collab://var.app/room/123e4567-e89b-42d3-a456-426614174000?key=abc',
        ),
        isEmpty,
      );
      expect(
        CollaborationNotifier.cleanRoomId(
          'var-collab://other.app/room/123e4567-e89b-42d3-a456-426614174000',
        ),
        isEmpty,
      );
    });
  });

  group('CommandPaletteEntry collab parser', () {
    test('parses collab links from query', () {
      final entries = commandPaletteEntriesFromQuery(
        query: 'var-collab://var.app/room/123',
        today: DateTime(2026, 6, 18),
        defaultDay: DateTime(2026, 6, 18),
        filteredNodes: [],
      );

      expect(entries, hasLength(1));
      expect(entries.first.kind, CommandPaletteEntryKind.collab);
      expect(entries.first.collabLink, 'var-collab://var.app/room/123');
    });

    test('parses collab links with /join command prefix', () {
      final entries = commandPaletteEntriesFromQuery(
        query: '/join var-collab://var.app/room/456',
        today: DateTime(2026, 6, 18),
        defaultDay: DateTime(2026, 6, 18),
        filteredNodes: [],
      );

      expect(entries, hasLength(1));
      expect(entries.first.kind, CommandPaletteEntryKind.collab);
      expect(entries.first.collabLink, 'var-collab://var.app/room/456');
    });
  });
}
