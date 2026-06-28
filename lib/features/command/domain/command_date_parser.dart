/// Date command parsing for the global command palette.
library;

import '../../../core/utils/date_utils.dart';

final class CommandDateResult {
  const CommandDateResult({required this.date, required this.label});

  final DateTime date;
  final String label;
}

CommandDateResult? dateCommandFromQuery(
  String query, {
  required DateTime today,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return null;

  final normalizedToday = today.dateOnly;
  final date = switch (normalizedQuery) {
    'today' || 'hari ini' => normalizedToday,
    'tomorrow' || 'besok' => normalizedToday.addDays(1),
    'yesterday' || 'kemarin' => normalizedToday.addDays(-1),
    _ => _parseStrictDayKey(normalizedQuery),
  };
  if (date == null) return null;

  return CommandDateResult(date: date, label: 'Jump to ${dayKey(date)}');
}

DateTime? _parseStrictDayKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;

  final parsed = DateTime.tryParse(value)?.dateOnly;
  if (parsed == null || dayKey(parsed) != value) return null;
  return parsed;
}
