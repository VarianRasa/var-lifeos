import 'package:var_app/features/capture/application/dns_lookup.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';

class CaptureValidationResult {
  final bool isValid;
  final List<String> errors;

  const CaptureValidationResult({required this.isValid, required this.errors});
}

class CaptureValidator {
  static bool isPrivateIp(String ip) {
    final clean = ip.trim().toLowerCase();
    if (clean.isEmpty) return true;
    if (clean.startsWith('::ffff:') || clean.startsWith('0:0:0:0:0:0:ffff:')) {
      return isPrivateIp(clean.substring(clean.lastIndexOf(':') + 1));
    }
    if (clean == '::1' ||
        clean == '0:0:0:0:0:0:0:1' ||
        clean == '::' ||
        clean == '0:0:0:0:0:0:0:0') {
      return true;
    }
    if (RegExp(r'^fe[89ab]').hasMatch(clean) ||
        clean.startsWith('fc') ||
        clean.startsWith('fd') ||
        clean.startsWith('ff')) {
      return true;
    }
    final parts = clean.split('.');
    if (parts.length == 2 && parts[0] == '127') {
      final val = int.tryParse(parts[1]);
      if (val != null && val >= 0 && val <= 255) return true;
    }
    if (parts.length != 4) return false;
    final values = parts.map(int.tryParse).toList();
    if (values.any((value) => value == null || value < 0 || value > 255)) {
      return false;
    }
    final first = values[0]!;
    final second = values[1]!;
    return first == 0 ||
        first == 10 ||
        first == 127 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        first >= 224;
  }

  static bool isPrivateOrLocalHost(String host) {
    final clean = host.toLowerCase().trim();
    if (clean.isEmpty) return true;
    final value = clean.startsWith('[') && clean.endsWith(']')
        ? clean.substring(1, clean.length - 1)
        : clean;
    return isPrivateIp(value) ||
        value == 'localhost' ||
        value.endsWith('.local') ||
        value.endsWith('.internal');
  }

  static Future<bool> isPrivateOrLocalHostAsync(
    String host, {
    DnsResolver? dnsResolver,
  }) async {
    if (isPrivateOrLocalHost(host)) return true;
    try {
      final addresses = await (dnsResolver ?? defaultDnsResolver)(host);
      return addresses.isEmpty || addresses.any(isPrivateIp);
    } on Object {
      return true;
    }
  }

  static CaptureValidationResult validate(
    CapturePayload payload, {
    CaptureDestination? destination,
  }) {
    final errors = <String>[];
    if (payload.isEmpty) errors.add('Capture payload cannot be empty');
    if (destination != null) {
      if (destination.boardId.trim().isEmpty) {
        errors.add('Destination boardId cannot be empty');
      }
      if (destination.workspaceId.trim().isEmpty) {
        errors.add('Destination workspaceId cannot be empty');
      }
    }
    for (final urlString in payload.urls) {
      final uri = Uri.tryParse(urlString);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        errors.add('Invalid URL scheme: $urlString');
      } else if (uri.host.isEmpty) {
        errors.add('URL host cannot be empty: $urlString');
      } else if (isPrivateOrLocalHost(uri.host)) {
        errors.add('Private or local network URL rejected: ${uri.host}');
      }
    }
    return CaptureValidationResult(isValid: errors.isEmpty, errors: errors);
  }
}
