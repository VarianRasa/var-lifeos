import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/capture/application/capture_providers.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';

class LocalClipperServer {
  static const int _maxBodyBytes = 1024 * 1024;

  final CaptureService _captureService;
  final String _authToken;
  final int _port;
  HttpServer? _server;

  LocalClipperServer({
    required CaptureService captureService,
    required String authToken,
    int port = 18420,
  })  : _captureService = captureService,
        _authToken = authToken,
        _port = port;

  int get port => _server?.port ?? _port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
    if (authHeader != 'Bearer $_authToken') {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Unauthorized'}));
      await request.response.close();
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/v1/boards') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
            'boards': [
              {
                'boardId': 'default',
                'boardTitle': 'Inbox Board',
                'workspaceId': 'default',
              },
            ],
          }));
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/v1/capture') {
      final contentLength = request.contentLength;
      if (contentLength > _maxBodyBytes) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Request body too large'}));
        await request.response.close();
        return;
      }

      try {
        final chunks = <List<int>>[];
        var totalBytes = 0;
        await for (final chunk in request) {
          totalBytes += chunk.length;
          if (totalBytes > _maxBodyBytes) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Request body too large'}));
            await request.response.close();
            return;
          }
          chunks.add(chunk);
        }
        final content = utf8.decode(chunks.expand((c) => c).toList());
        final body = jsonDecode(content) as Map<String, dynamic>;

        final payload = CapturePayload(
          text: body['text'] as String?,
          urls: ((body['urls'] as List?) ?? []).cast<String>(),
        );

        final destination = CaptureDestination(
          boardId: body['boardId'] as String? ?? 'default',
          boardTitle: body['boardTitle'] as String? ?? 'Inbox Board',
          workspaceId: body['workspaceId'] as String? ?? 'default',
        );

        final node = await _captureService.saveCapture(
          payload: payload,
          destination: destination,
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'success', 'nodeId': node.id}));
        await request.response.close();
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': e.toString()}));
        await request.response.close();
      }
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }
}

final localClipperServerProvider = Provider<LocalClipperServer>((ref) {
  final service = ref.watch(captureServiceProvider);
  return LocalClipperServer(
    captureService: service.valueOrNull ??
        (throw StateError('CaptureService not yet available')),
    // ponytail: generate per-install UUID token, store in shared_preferences
    authToken: 'var-local-token',
  );
});
