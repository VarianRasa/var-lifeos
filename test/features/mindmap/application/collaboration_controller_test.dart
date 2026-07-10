import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/command/domain/command_palette_entry.dart';
import 'package:var_app/features/mindmap/application/collaboration_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Collaboration Room ID Cleaning', () {
    test('cleans room ID correctly from various formats', () {
      final link1 = CollaborationNotifier.cleanRoomId('var-collab://var.app/room/room123?key=abc');
      expect(link1, 'room123');

      final link2 = CollaborationNotifier.cleanRoomId('room-xyz');
      expect(link2, 'room-xyz');

      final link3 = CollaborationNotifier.cleanRoomId('var-collab://var.app/room/12345');
      expect(link3, '12345');
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
