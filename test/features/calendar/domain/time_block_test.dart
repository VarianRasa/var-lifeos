import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/calendar/domain/time_block.dart';

void main() {
  group('parseTimeBlock', () {
    test('null is unscheduled', () {
      final result = parseTimeBlock(null);
      expect(result.status, TimeBlockStatus.unscheduled);
      expect(result.isUnscheduled, isTrue);
    });

    test('absent key returns invalid', () {
      final result = parseTimeBlock('not a map');
      expect(result.isInvalid, isTrue);
    });

    test('valid start/end string map returns valid', () {
      final result = parseTimeBlock({'startTime': '09:00', 'endTime': '10:00'});
      expect(result.isValid, isTrue);
      expect(result.block!.startMinute, 9 * 60);
      expect(result.block!.endMinute, 10 * 60);
      expect(result.block!.rangeLabel, '09:00 - 10:00');
    });

    test('valid startMinute/endMinute int map', () {
      final result = parseTimeBlock({'startMinute': 540, 'endMinute': 600});
      expect(result.isValid, isTrue);
      expect(result.block!.startLabel, '09:00');
      expect(result.block!.durationMinutes, 60);
    });

    test('reversed start/end returns invalid', () {
      final result = parseTimeBlock({'startTime': '10:00', 'endTime': '09:00'});
      expect(result.isInvalid, isTrue);
    });

    test('out-of-range hour returns invalid', () {
      final result = parseTimeBlock({'startTime': '25:00', 'endTime': '26:00'});
      expect(result.isInvalid, isTrue);
    });

    test('bad format string returns invalid', () {
      final result = parseTimeBlock({'startTime': 'abc', 'endTime': 'def'});
      expect(result.isInvalid, isTrue);
    });

    test('toJson round-trip produces re-parseable map', () {
      const block = TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60);
      final json = block.toJson();
      final parsed = parseTimeBlock(json);
      expect(parsed.isValid, isTrue);
      expect(parsed.block!.startMinute, 9 * 60);
      expect(parsed.block!.endMinute, 10 * 60);
    });
  });

  group('detectTimeBlockConflicts', () {
    test('detects overlapping blocks', () {
      final conflicts = detectTimeBlockConflicts([
        const DayTimeBlock(
          id: 'a',
          block: TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60),
        ),
        const DayTimeBlock(
          id: 'b',
          block: TimeBlock(startMinute: 9 * 60 + 30, endMinute: 11 * 60),
        ),
      ]);

      expect(conflicts, hasLength(1));
      expect(conflicts.single.type, TimeBlockConflictType.overlap);
      expect(conflicts.single.nodeIds, ['a', 'b']);
      expect(conflicts.single.rangeLabel, '09:30 - 10:00');
    });

    test('ignores done blocks for conflicts', () {
      final conflicts = detectTimeBlockConflicts([
        const DayTimeBlock(
          id: 'a',
          block: TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60),
          isDone: true,
        ),
        const DayTimeBlock(
          id: 'b',
          block: TimeBlock(startMinute: 9 * 60 + 30, endMinute: 11 * 60),
        ),
      ]);

      expect(conflicts, isEmpty);
    });

    test('detects too many high-priority blocks in a window', () {
      final conflicts = detectTimeBlockConflicts([
        const DayTimeBlock(
          id: 'a',
          block: TimeBlock(startMinute: 9 * 60, endMinute: 9 * 60 + 30),
          isHighPriority: true,
        ),
        const DayTimeBlock(
          id: 'b',
          block: TimeBlock(startMinute: 10 * 60, endMinute: 10 * 60 + 30),
          isHighPriority: true,
        ),
        const DayTimeBlock(
          id: 'c',
          block: TimeBlock(startMinute: 10 * 60 + 30, endMinute: 11 * 60),
          isHighPriority: true,
        ),
      ]);

      expect(
        conflicts.any(
          (conflict) =>
              conflict.type == TimeBlockConflictType.highPriorityOverload,
        ),
        isTrue,
      );
    });
  });

  group('autoResolveConflicts', () {
    test('shifts overlapping blocks to next available free slot', () {
      final blocks = [
        const DayTimeBlock(
          id: 'a',
          block: TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60),
        ),
        const DayTimeBlock(
          id: 'b',
          block: TimeBlock(startMinute: 9 * 60 + 30, endMinute: 10 * 60 + 30),
        ),
      ];

      final resolved = autoResolveConflicts(blocks);

      expect(resolved.containsKey('b'), isTrue);
      expect(resolved['b']!.startMinute, 10 * 60);
      expect(resolved['b']!.endMinute, 11 * 60);
    });

    test('does not shift non-overlapping blocks', () {
      final blocks = [
        const DayTimeBlock(
          id: 'a',
          block: TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60),
        ),
        const DayTimeBlock(
          id: 'b',
          block: TimeBlock(startMinute: 10 * 60, endMinute: 11 * 60),
        ),
      ];

      final resolved = autoResolveConflicts(blocks);
      expect(resolved, isEmpty);
    });
  });

  group('formatTimeOfDay', () {
    test('midnight is 00:00', () {
      expect(formatTimeOfDay(0), '00:00');
    });

    test('noon is 12:00', () {
      expect(formatTimeOfDay(720), '12:00');
    });

    test('last minute is 23:59', () {
      expect(formatTimeOfDay(1439), '23:59');
    });

    test('clamps out of range', () {
      expect(formatTimeOfDay(-1), '00:00');
      expect(formatTimeOfDay(1441), '00:01');
    });
  });
}
