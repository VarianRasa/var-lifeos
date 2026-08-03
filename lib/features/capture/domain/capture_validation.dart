import 'package:var_app/features/capture/domain/capture_payload.dart';

class CaptureValidationResult {
  final bool isValid;
  final List<String> errors;

  const CaptureValidationResult({required this.isValid, required this.errors});
}

class CaptureValidator {
  static final _privateHostRegex = RegExp(
    r'^(localhost|127\.\d+\.\d+\.\d+|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)$',
    caseSensitive: false,
  );

  static CaptureValidationResult validate(CapturePayload payload) {
    final errors = <String>[];

    if (payload.isEmpty) {
      errors.add('Capture payload cannot be empty');
    }

    for (final urlString in payload.urls) {
      final uri = Uri.tryParse(urlString);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        errors.add('Invalid URL scheme: $urlString');
        continue;
      }

      if (_privateHostRegex.hasMatch(uri.host)) {
        errors.add('Private or local network URL rejected: ${uri.host}');
      }
    }

    return CaptureValidationResult(isValid: errors.isEmpty, errors: errors);
  }
}
