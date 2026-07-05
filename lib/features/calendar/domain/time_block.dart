/// Safe parsing and formatting for calendar schedule blocks.
library;

enum TimeBlockStatus { unscheduled, valid, invalid }

enum TimeBlockConflictType { overlap, highPriorityOverload }

final class DayTimeBlock {
  const DayTimeBlock({
    required this.id,
    required this.block,
    this.isHighPriority = false,
    this.isDone = false,
  });

  final String id;
  final TimeBlock block;
  final bool isHighPriority;
  final bool isDone;
}

final class TimeBlockConflict {
  const TimeBlockConflict({
    required this.type,
    required this.nodeIds,
    required this.startMinute,
    required this.endMinute,
  });

  final TimeBlockConflictType type;
  final List<String> nodeIds;
  final int startMinute;
  final int endMinute;

  String get rangeLabel =>
      '${formatTimeOfDay(startMinute)} - ${formatTimeOfDay(endMinute)}';
}

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
    return {
      'startTime': startLabel,
      'endTime': endLabel,
      'startMinute': startMinute,
      'endMinute': endMinute,
      'timeBlockStart': startMinute,
      'timeBlockEnd': endMinute,
    };
  }
}

ParsedTimeBlock parseTimeBlock(Object? raw) {
  if (raw == null) return const ParsedTimeBlock.unscheduled();
  if (raw is! Map) return const ParsedTimeBlock.invalid();

  final map = raw.cast<Object?, Object?>();
  final startMinute =
      _minuteFromValue(map['startMinute']) ??
      _minuteFromValue(map['start']) ??
      _minuteFromValue(map['startTime']) ??
      _minuteFromValue(map['timeBlockStart']);
  final endMinute =
      _minuteFromValue(map['endMinute']) ??
      _minuteFromValue(map['end']) ??
      _minuteFromValue(map['endTime']) ??
      _minuteFromValue(map['timeBlockEnd']);

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

List<TimeBlockConflict> detectTimeBlockConflicts(
  List<DayTimeBlock> blocks, {
  int highPriorityLimitPerWindow = 2,
  int highPriorityWindowMinutes = 120,
}) {
  final activeBlocks = blocks.where((block) => !block.isDone).toList()
    ..sort((a, b) => a.block.startMinute.compareTo(b.block.startMinute));
  final conflicts = <TimeBlockConflict>[];

  for (var i = 0; i < activeBlocks.length; i += 1) {
    final current = activeBlocks[i];
    for (var j = i + 1; j < activeBlocks.length; j += 1) {
      final other = activeBlocks[j];
      if (other.block.startMinute >= current.block.endMinute) break;
      conflicts.add(
        TimeBlockConflict(
          type: TimeBlockConflictType.overlap,
          nodeIds: [current.id, other.id],
          startMinute: _max(current.block.startMinute, other.block.startMinute),
          endMinute: _min(current.block.endMinute, other.block.endMinute),
        ),
      );
    }
  }

  final highPriorityBlocks = activeBlocks
      .where((block) => block.isHighPriority)
      .toList();
  for (final anchor in highPriorityBlocks) {
    final windowEnd = (anchor.block.startMinute + highPriorityWindowMinutes)
        .clamp(1, 1440);
    final inWindow = highPriorityBlocks
        .where(
          (block) =>
              block.block.startMinute >= anchor.block.startMinute &&
              block.block.startMinute < windowEnd,
        )
        .toList();
    if (inWindow.length <= highPriorityLimitPerWindow) continue;

    final ids = inWindow.map((block) => block.id).toList();
    final alreadyReported = conflicts.any(
      (conflict) =>
          conflict.type == TimeBlockConflictType.highPriorityOverload &&
          _sameIds(conflict.nodeIds, ids),
    );
    if (alreadyReported) continue;

    conflicts.add(
      TimeBlockConflict(
        type: TimeBlockConflictType.highPriorityOverload,
        nodeIds: ids,
        startMinute: anchor.block.startMinute,
        endMinute: windowEnd,
      ),
    );
  }

  return List.unmodifiable(conflicts);
}

String formatTimeOfDay(int minuteOfDay) {
  var clamped = minuteOfDay;
  if (clamped < 0) clamped = 0;
  if (clamped >= 1440) clamped %= 1440;
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

bool _sameIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  final leftSet = left.toSet();
  return right.every(leftSet.contains);
}

int _min(int left, int right) => left < right ? left : right;

int _max(int left, int right) => left > right ? left : right;

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
