import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_validation.dart';

void main() {
  group('NodeValidation', () {
    test('requires a non-empty title', () {
      expect(NodeValidation.requiredTitle('  '), isNotEmpty);
      expect(NodeValidation.requiredTitle('Ship release'), isEmpty);
    });

    test('accepts only supported external URL schemes', () {
      for (final value in [
        'https://example.com',
        'http://example.com',
        'mailto:hello@example.com',
        'tel:+621234',
      ]) {
        expect(NodeValidation.url(value), isEmpty, reason: value);
      }
      expect(NodeValidation.url('javascript:alert(1)'), isNotEmpty);
      expect(NodeValidation.url('example.com'), isNotEmpty);
      expect(NodeValidation.url('https:missing-host'), isNotEmpty);
    });

    test('rejects non-finite and out-of-range numbers', () {
      expect(NodeValidation.number(double.nan), isNotEmpty);
      expect(NodeValidation.number(double.infinity), isNotEmpty);
      expect(NodeValidation.number(11, min: 0, max: 10), isNotEmpty);
      expect(NodeValidation.number(10, min: 0, max: 10), isEmpty);
    });

    test('validates dates and ordered date/time ranges', () {
      expect(NodeValidation.date('2026-07-13'), isEmpty);
      expect(NodeValidation.date('13/07/2026'), isNotEmpty);
      expect(NodeValidation.date('2026-02-30'), isNotEmpty);
      expect(NodeValidation.dateRange('2026-07-14', '2026-07-13'), isNotEmpty);
      expect(NodeValidation.timeRange('09:00', '10:30'), isEmpty);
      expect(NodeValidation.timeRange('25:00', '10:30'), isNotEmpty);
      expect(NodeValidation.timeRange('10:30', '09:00'), isNotEmpty);
    });
  });
}
