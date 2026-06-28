/// Typed helpers around the flexible `MindmapNode.data` map.
library;

import '../../calendar/domain/calendar_node_payload.dart';
import '../../calendar/domain/time_block.dart';
import 'mindmap_node.dart';

const mindmapTimeBlockDataKey = 'time_block';

CalendarNodePayload? calendarPayloadForNode(MindmapNode node) {
  return calendarNodePayloadFromData(node.data);
}

ParsedTimeBlock timeBlockForNode(MindmapNode node) {
  return parseTimeBlock(node.data[mindmapTimeBlockDataKey]);
}

Map<String, Object?> dataWithCalendarPayload(
  Map<String, Object?> data,
  CalendarNodePayload payload,
) {
  return Map.unmodifiable({...data, ...payload.toJson()});
}

Map<String, Object?> dataWithTimeBlock(
  Map<String, Object?> data,
  TimeBlock block,
) {
  return Map.unmodifiable({...data, mindmapTimeBlockDataKey: block.toJson()});
}

Map<String, Object?> dataWithoutTimeBlock(Map<String, Object?> data) {
  final next = Map<String, Object?>.of(data)..remove(mindmapTimeBlockDataKey);
  return Map.unmodifiable(next);
}

Map<String, Object?> dataWithCalendarSchedule({
  required Map<String, Object?> data,
  required CalendarNodePayload payload,
  TimeBlock? timeBlock,
}) {
  return Map.unmodifiable({
    ...data,
    ...payload.toJson(),
    if (timeBlock != null) mindmapTimeBlockDataKey: timeBlock.toJson(),
  });
}
