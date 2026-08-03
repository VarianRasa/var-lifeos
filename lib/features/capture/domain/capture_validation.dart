import 'package:var_app/features/capture/domain/capture_payload.dart';

class CaptureValidationResult {
  final bool isValid;
  final List<String> errors;

  const CaptureValidationResult({required this.isValid, required this.errors});
}

class CaptureValidator {
  static bool isPrivateOrLocalHost(String host) {
    final cleanHost = host.toLowerCase().trim();
    if (cleanHost.isEmpty) return true;

    final h = cleanHost.startsWith('[') && cleanHost.endsWith(']')
        ? cleanHost.substring(1, cleanHost.length - 1)
        : cleanHost;

    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) {
      return true;
    }

    if (h == '::1' || h == '0:0:0:0:0:0:0:1') return true;
    if (h.startsWith('fe80:') ||
        h.startsWith('fe8') ||
        h.startsWith('fe9') ||
        h.startsWith('fea') ||
        h.startsWith('feb')) {
      return true;
    }
    if (h.startsWith('fc') || h.startsWith('fd')) {
      return true;
    }

    final parts = h.split('.');
    if (parts.isNotEmpty && parts.length <= 4) {
      final nums = <int>[];
      bool allInts = true;
      for (final p in parts) {
        final val = int.tryParse(p);
        if (val == null || val < 0 || val > 255) {
          allInts = false;
          break;
        }
        nums.add(val);
      }

      if (allInts && nums.isNotEmpty) {
        final first = nums[0];
        final second = nums.length > 1 ? nums[1] : 0;

        if (first == 0 || first == 127 || first == 10) return true;
        if (first == 192 && second == 168) return true;
        if (first == 172 && second >= 16 && second <= 31) return true;
      }
    }

    return false;
  }

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

      if (uri.host.isEmpty) {
        errors.add('URL host cannot be empty: $urlString');
        continue;
      }

      if (isPrivateOrLocalHost(uri.host)) {
        errors.add('Private or local network URL rejected: ${uri.host}');
      }
    }

    return CaptureValidationResult(isValid: errors.isEmpty, errors: errors);
  }
}
