import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/domain/itinerary_planner.dart';
import 'package:var_app/features/mindmap/domain/journal_prompts.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/quote_collector.dart';

void main() {
  final now = DateTime.now();
  final day = now.dateOnly;

  group('JournalPromptGenerator', () {
    test('generates contextual prompts based on completed tasks', () {
      final tasks = [
        MindmapNode(
          id: 't1',
          day: day,
          type: NodeType.task,
          title: 'Finish feature',
          isDone: true,
          status: NodeStatus.done,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final prompts = JournalPromptGenerator.generateContextualPrompts(
        dayNodes: tasks,
      );
      expect(prompts.first, contains('completed 1 tasks today'));
    });
  });

  group('ItineraryData Domain', () {
    test('parses itinerary activities and total costs', () {
      final node = MindmapNode(
        id: 'it1',
        day: day,
        type: NodeType.itinerary,
        title: 'Trip to Bali',
        createdAt: now,
        updatedAt: now,
        data: {
          'itinerary': {
            'destination': 'Bali',
            'activities': [
              {'title': 'Flight', 'estimatedCost': 1500000.0},
              {'title': 'Hotel', 'estimatedCost': 800000.0},
            ],
            'packingChecklist': ['Passport', 'Sunscreen'],
          },
        },
      );

      final itinerary = ItineraryData.fromNode(node);
      expect(itinerary.destination, equals('Bali'));
      expect(itinerary.activities.length, equals(2));
      expect(itinerary.totalEstimatedCost, equals(2300000.0));
      expect(itinerary.packingChecklist, contains('Passport'));
    });
  });

  group('Quote Collector', () {
    test('converts quote node to flashcard', () {
      final quoteNode = MindmapNode(
        id: 'q1',
        day: day,
        type: NodeType.quote,
        title: 'Stay hungry, stay foolish.',
        createdAt: now,
        updatedAt: now,
        data: {
          'quote': {'author': 'Steve Jobs'},
        },
      );

      final flashcardNode = convertQuoteToFlashcard(quoteNode, now: now);
      expect(flashcardNode.tags, contains('flashcard'));
      expect(flashcardNode.data.containsKey('flashcard'), isTrue);
    });
  });
}
