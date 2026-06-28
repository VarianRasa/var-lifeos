/// Safe parsing and formatting for calendar schedule blocks.
library;

enum TimeBlockStatus { unscheduled, valid, invalid }

final class ParsedTimeBlock {
  const ParsedTimeBlock._({required this.status, this.block});

  const ParsedTimeBlock.unscheduled()
    : this._(status: TimeBlockStatus.unscheduled);

  const ParsedTimeBlock.invalid() : this._(status: TimeBlockStatus.invalid);

  const ParsedTimeBlock.valid(TimeBlock block)
    : this._(status: TimeBlockStatus.valid, block: block);

  final TimeBlockStatus status;
  final TimeBlock? block;

  bool get isValid => status == TimeBlockStatus.valid && block != null;
  bool get isInvalid => status == TimeBlockStatus.invalid;
  bool get isUnscheduled => status == TimeBlockStatus.unscheduled;
}

final class TimeBlock {
  const TimeBlock({required this.startMinute, required this.endMinute})
    : assert(startMinute >= 0),
      assert(startMinute < 1440),
      assert(endMinute > startMinute),
      assert(endMinute <= 1440);

  final int startMinute;
  final int endMinute;

  int get durationMinutes => endMinute - startMinute;
  String get startLabel => formatTimeOfDay(startMinute);
  String get endLabel => formatTimeOfDay(endMinute);
  String get rangeLabel => '$startLabel - $endLabel';

  Map<String, Object?> toJson() {
    return {'startTime': startLabel, 'endTime': endLabel};
  }
}

ParsedTimeBlock parseTimeBlock(Object? raw) {
  if (raw == null) return const ParsedTimeBlock.unscheduled();
  if (raw is! Map) return const ParsedTimeBlock.invalid();

  final map = raw.cast<Object?, Object?>();
  final startMinute =
      _minuteFromValue(map['startMinute']) ??
      _minuteFromValue(map['start']) ??
      _minuteFromValue(map['startTime']);
  final endMinute =
      _minuteFromValue(map['endMinute']) ??
      _minuteFromValue(map['end']) ??
      _minuteFromValue(map['endTime']);

  if (startMinute == null || endMinute == null) {
    return const ParsedTimeBlock.invalid();
  }
  if (startMinute < 0 || startMinute >= 1440) {
    return const ParsedTimeBlock.invalid();
  }
  if (endMinute <= startMinute || endMinute > 1440) {
    return const ParsedTimeBlock.invalid();
  }

  return ParsedTimeBlock.valid(
    TimeBlock(startMinute: startMinute, endMinute: endMinute),
  );
}

String formatTimeOfDay(int minuteOfDay) {
  var clamped = minuteOfDay;
  if (clamped < 0) clamped = 0;
  if (clamped >= 1440) clamped %= 1440;
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

int? _minuteFromValue(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  if (value is! String) return null;

  final trimmed = value.trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
  if (match == null) return null;

  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 24 || minute < 0 || minute > 59) return null;
  if (hour == 24 && minute != 0) return null;
  return hour * 60 + minute;
}
