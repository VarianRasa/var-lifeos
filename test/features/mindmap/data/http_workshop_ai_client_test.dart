import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/features/mindmap/data/http_workshop_ai_client.dart';
import 'package:var_app/features/mindmap/domain/workshop_ai.dart';

void main() {
  const sticky = <WorkshopAiSticky>[
    WorkshopAiSticky(id: 's1', text: 'Ship weekly', votes: 3, locale: 'en'),
  ];

  test('sends only typed sticky fields and parses typed result', () async {
    final client = HttpWorkshopAiClient(
      endpoint: Uri.parse('https://worker.test'),
      client: MockClient((request) async {
        expect(request.url.path, '/analyze');
        expect(jsonDecode(request.body), <String, Object>{
          'sticky': <Object>[
            <String, Object>{
              'id': 's1',
              'text': 'Ship weekly',
              'votes': 3,
              'locale': 'en',
            },
          ],
        });
        return http.Response(
          jsonEncode(<String, Object>{
            'summary': 'Weekly delivery',
            'themes': <Object>[
              <String, Object>{
                'name': 'Delivery',
                'sourceIds': <String>['s1'],
              },
            ],
            'clusters': <Object>[],
            'decisions': <Object>[],
            'actionItems': <Object>[],
            'risks': <Object>[],
            'model': 'model',
            'version': '1',
          }),
          200,
        );
      }),
    );

    final result = await client.analyze(sticky);

    expect(result.summary, 'Weekly delivery');
    expect(result.themes.single.sourceIds, <String>['s1']);
  });

  test('rejects insecure non-local endpoint', () {
    expect(
      () => HttpWorkshopAiClient(
        endpoint: Uri.parse('http://worker.test'),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      throwsA(
        isA<WorkshopAiException>().having(
          (error) => error.code,
          'code',
          'invalid-endpoint',
        ),
      ),
    );
  });

  test('rejects unknown response source ID', () async {
    final client = HttpWorkshopAiClient(
      endpoint: Uri.parse('http://localhost:8787'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'summary': 'Summary',
            'themes': <Object>[
              <String, Object>{
                'name': 'Theme',
                'sourceIds': <String>['other'],
              },
            ],
            'clusters': <Object>[],
            'decisions': <Object>[],
            'actionItems': <Object>[],
            'risks': <Object>[],
            'model': 'model',
            'version': '1',
          }),
          200,
        ),
      ),
    );

    await expectLater(
      client.analyze(sticky),
      throwsA(
        isA<WorkshopAiException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });
}
