import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/features/mindmap/data/byok_ai_service.dart';

void main() {
  group('BYOK AI Service', () {
    test('ByokAiConfig detects configuration state', () {
      const emptyConfig = ByokAiConfig(apiKey: '');
      expect(emptyConfig.isConfigured, isFalse);

      const validConfig = ByokAiConfig(apiKey: 'sk-test12345');
      expect(validConfig.isConfigured, isTrue);
    });

    test(
      'decomposeTaskWithAi parses completion JSON response into sub-tasks',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.headers['Authorization'],
            equals('Bearer sk-test12345'),
          );
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'subtasks': [
                        {'title': 'AI Step 1', 'minutes': 20},
                        {'title': 'AI Step 2', 'minutes': 40},
                      ],
                    }),
                  },
                },
              ],
            }),
            200,
          );
        });

        final service = ByokAiService(client: mockClient);
        const config = ByokAiConfig(apiKey: 'sk-test12345');

        final subtasks = await service.decomposeTaskWithAi(
          taskTitle: 'Build App',
          config: config,
        );

        expect(subtasks.length, equals(2));
        expect(subtasks.first.title, equals('AI Step 1'));
        expect(subtasks.first.estimatedMinutes, equals(20));
      },
    );
  });
}
