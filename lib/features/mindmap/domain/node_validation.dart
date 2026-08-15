/// Validation helpers for typed mindmap payload trust boundaries.
library;

abstract final class NodeValidation {
  static List<String> requiredTitle(String title) =>
      title.trim().isEmpty ? const ['Title is required.'] : const [];

  static List<String> url(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? const ['URL is required.'] : const [];
    final uri = Uri.tryParse(text);
    const schemes = {'http', 'https', 'mailto', 'tel'};
    final validTarget =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https'
            ? uri.host.isNotEmpty
            : uri.path.isNotEmpty);
    return uri != null &&
            uri.hasScheme &&
            schemes.contains(uri.scheme) &&
            validTarget
        ? const []
        : const ['URL scheme is not supported.'];
  }

  static List<String> number(num? value, {num? min, num? max}) {
    if (value == null || !value.isFinite) {
      return const ['Value must be finite.'];
    }
    if (min != null && value < min) {
      return ['Value must be at least $min.'];
    }
    if (max != null && value > max) return ['Value must be at most $max.'];
    return const [];
  }

  static List<String> date(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? const ['Date is required.'] : const [];
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    final parsed = DateTime.tryParse(text);
    final exact =
        match != null &&
        parsed != null &&
        parsed.year == int.parse(match.group(1)!) &&
        parsed.month == int.parse(match.group(2)!) &&
        parsed.day == int.parse(match.group(3)!);
    return exact ? const [] : const ['Date is invalid.'];
  }

  static List<String> dateRange(String? start, String? end) {
    final errors = [...date(start), ...date(end)];
    if (errors.isNotEmpty) return errors;
    return DateTime.parse(end!).isBefore(DateTime.parse(start!))
        ? const ['End date must not precede start date.']
        : const [];
  }

  static List<String> timeRange(String? start, String? end) {
    final startMinutes = _timeMinutes(start);
    final endMinutes = _timeMinutes(end);
    if (startMinutes == null || endMinutes == null) {
      return const ['Time is invalid.'];
    }
    return endMinutes < startMinutes
        ? const ['End time must not precede start time.']
        : const [];
  }

  static int? _timeMinutes(String? value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value?.trim() ?? '');
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }
}
