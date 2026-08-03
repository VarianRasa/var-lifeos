import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:var_app/core/services/local_clipper_server.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';

void main() {
  group('LocalClipperServer', () {
    late LocalClipperServer server;
    late String testToken;
    late String baseUrl;

    setUp(() async {
      testToken = 'test-token-123';
      final repository = InMemoryMindmapRepository();
      final captureService = CaptureService(mindmapRepository: repository);
      server = LocalClipperServer(
        captureService: captureService,
        authToken: testToken,
        port: 0,
      );
      await server.start();
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.stop();
    });

    test('rejects requests without valid authorization token', () async {
      final response = await http.get(Uri.parse('$baseUrl/v1/boards'));
      expect(response.statusCode, equals(401));
    });

    test('returns boards list when authorized', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/v1/boards'),
        headers: {'Authorization': 'Bearer $testToken'},
      );
      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['boards'], isList);
    });

    test('captures payload when authorized', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/v1/capture'),
        headers: {
          'Authorization': 'Bearer $testToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': 'Test clipping',
          'urls': ['https://example.com'],
          'boardId': 'default',
        }),
      );
      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['status'], equals('success'));
      expect(data['nodeId'], isNotNull);
    });

    test('returns 404 for unknown endpoints', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/v1/unknown'),
        headers: {'Authorization': 'Bearer $testToken'},
      );
      expect(response.statusCode, equals(404));
    });

    test('returns 400 for malformed JSON body', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/v1/capture'),
        headers: {
          'Authorization': 'Bearer $testToken',
          'Content-Type': 'application/json',
        },
        body: 'not valid json {{{',
      );
      expect(response.statusCode, equals(400));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['error'], isNotNull);
    });
  });
}
