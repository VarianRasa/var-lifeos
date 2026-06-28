/// Date helpers for working with calendar days.
///
/// The app treats dates as normalized local days (no time-of-day, no timezone
/// drift): every [DateTime] used as a "day" is normalized to midnight via
/// [dateOnly]. Comparisons and map keys rely on this invariant.
library;

/// Extensions on [DateTime] for calendar math.
extension CalendarDate on DateTime {
  /// Same date at local midnight — the canonical "day" representation.
  DateTime get dateOnly => DateTime(year, month, day);

  /// Whether this date is the same calendar day as [other].
  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  /// Whether this date is today.
  bool get isToday => isSameDay(DateTime.now());

  /// First day-of-week (Monday) of the week containing this date.
  DateTime get startOfWeek {
    final weekdayMondayBased = weekday - 1; // Mon=0 .. Sun=6
    return dateOnly.subtract(Duration(days: weekdayMondayBased));
  }

  /// Number of days in this date's month.
  int get daysInMonth {
    // Day 0 of next month = last day of this month.
    final firstOfNext = month == 12
        ? DateTime(year + 1, 1)
        : DateTime(year, month + 1);
    return firstOfNext.subtract(const Duration(days: 1)).day;
  }

  /// First day of this date's month.
  DateTime get firstOfMonth => DateTime(year, month);

  /// Add [n] calendar days, preserving the midnight normalization.
  DateTime addDays(int n) => DateTime(year, month, day + n);

  /// Add [n] calendar months (clamped to valid day), normalized.
  DateTime addMonths(int n) {
    final targetMonth = month + n;
    final newYear = year + (targetMonth - 1) ~/ 12;
    final newMonth = (targetMonth - 1) % 12 + 1;
    final maxDay = DateTime(newYear, newMonth + 1, 0).day;
    final newDay = day > maxDay ? maxDay : day;
    return DateTime(newYear, newMonth, newDay);
  }
}

/// The weekday header labels, Monday-first to match [CalendarDate.startOfWeek].
const List<String> kWeekdayLabelsShort = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// The 42 visible days for a month calendar: Monday-first, six rows.
List<DateTime> visibleDaysForMonth(DateTime month) {
  final start = month.dateOnly.firstOfMonth.startOfWeek;
  return List.generate(42, (index) => start.addDays(index));
}

/// Stable string key (ISO date) for a day, useful for DB indexing and maps.
String dayKey(DateTime day) {
  final d = day.dateOnly;
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$dd';
}
