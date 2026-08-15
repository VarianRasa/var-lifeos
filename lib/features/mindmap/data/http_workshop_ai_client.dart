import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/workshop_ai.dart';

final class HttpWorkshopAiClient implements WorkshopAiClient {
  HttpWorkshopAiClient({
    required Uri endpoint,
    required http.Client client,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 1024 * 1024,
  }) : endpoint = _validatedEndpoint(endpoint),
       _client = client;

  final Uri endpoint;
  final http.Client _client;
  final Duration requestTimeout;
  final int maxResponseBytes;

  @override
  Future<WorkshopAiAnalysis> analyze(List<WorkshopAiSticky> sticky) async {
    if (sticky.isEmpty || sticky.length > 300) {
      throw const WorkshopAiException(
        'Workshop analysis requires 1 to 300 visible sticky notes.',
        code: 'invalid-input',
      );
    }
    final ids = sticky.map((item) => item.id).toSet();
    if (ids.length != sticky.length) {
      throw const WorkshopAiException(
        'Sticky IDs must be unique.',
        code: 'invalid-input',
      );
    }
    final uri = endpoint.path.endsWith('/analyze')
        ? endpoint
        : endpoint.replace(
            path: '${endpoint.path.replaceFirst(RegExp(r'/$'), '')}/analyze',
          );
    try {
      final response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object>{
              'sticky': sticky.map((item) => item.toJson()).toList(),
            }),
          )
          .timeout(requestTimeout);
      if (response.bodyBytes.length > maxResponseBytes) {
        throw const WorkshopAiException(
          'Workshop AI response is too large.',
          code: 'response-too-large',
        );
      }
      if (response.statusCode != 200) {
        throw WorkshopAiException(
          'Workshop AI returned HTTP ${response.statusCode}.',
          code: 'http-${response.statusCode}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      return _parse(Map<Object?, Object?>.from(decoded), ids);
    } on TimeoutException {
      throw const WorkshopAiException(
        'Workshop AI request timed out.',
        code: 'timeout',
      );
    } on WorkshopAiException {
      rethrow;
    } on Object {
      throw const WorkshopAiException(
        'Workshop AI returned an invalid response.',
        code: 'invalid-response',
      );
    }
  }

  static Uri _validatedEndpoint(Uri endpoint) {
    final localhost =
        endpoint.host == 'localhost' ||
        endpoint.host == '127.0.0.1' ||
        endpoint.host == '::1';
    if (!endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        (endpoint.scheme != 'https' &&
            !(localhost && endpoint.scheme == 'http')) ||
        endpoint.hasFragment ||
        endpoint.hasQuery) {
      throw const WorkshopAiException(
        'Workshop AI endpoint must use HTTPS or HTTP localhost.',
        code: 'invalid-endpoint',
      );
    }
    return endpoint;
  }

  static WorkshopAiAnalysis _parse(
    Map<Object?, Object?> map,
    Set<String> sourceIds,
  ) => WorkshopAiAnalysis(
    summary: _text(map['summary']),
    themes: _groups(map['themes'], sourceIds),
    clusters: _groups(map['clusters'], sourceIds),
    decisions: _statements(map['decisions'], sourceIds),
    actionItems: _statements(map['actionItems'], sourceIds),
    risks: _statements(map['risks'], sourceIds),
    model: _text(map['model']),
    version: _text(map['version']),
  );

  static List<WorkshopAiSourceGroup> _groups(
    Object? value,
    Set<String> validIds,
  ) => _items(value)
      .map(
        (item) => WorkshopAiSourceGroup(
          name: _text(item['name']),
          sourceIds: _sourceIds(item['sourceIds'], validIds),
        ),
      )
      .toList(growable: false);

  static List<WorkshopAiSourceStatement> _statements(
    Object? value,
    Set<String> validIds,
  ) => _items(value)
      .map(
        (item) => WorkshopAiSourceStatement(
          text: _text(item['text']),
          sourceIds: _sourceIds(item['sourceIds'], validIds),
        ),
      )
      .toList(growable: false);

  static List<Map<Object?, Object?>> _items(Object? value) {
    if (value is! List || value.length > 300) throw const FormatException();
    return value
        .map((item) {
          if (item is! Map) throw const FormatException();
          return Map<Object?, Object?>.from(item);
        })
        .toList(growable: false);
  }

  static List<String> _sourceIds(Object? value, Set<String> validIds) {
    if (value is! List || value.isEmpty || value.length > 300) {
      throw const FormatException();
    }
    final result = value.map(_text).toList(growable: false);
    if (result.any((id) => !validIds.contains(id))) {
      throw const FormatException();
    }
    return result;
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value.trim();
  }
}
