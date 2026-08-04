/// Typed helpers around the flexible `MindmapNode.data` map.
library;

import 'dart:ui';

import '../../calendar/domain/calendar_node_payload.dart';
import '../../calendar/domain/time_block.dart';
import 'mindmap_node.dart';

const mindmapTimeBlockDataKey = 'time_block';

class ConnectionMetadata {
  const ConnectionMetadata({
    this.startNodeId,
    this.startPoint,
    this.endNodeId,
    this.endPoint,
    this.lineStyle = 'solid',
    this.arrowStyle = 'end',
    this.color = 'slate',
    this.label,
  });

  final String? startNodeId;
  final Offset? startPoint;
  final String? endNodeId;
  final Offset? endPoint;
  final String lineStyle;
  final String arrowStyle;
  final String color;
  final String? label;
}

Offset? _parseOffset(Map<String, Object?> data, String prefix) {
  final rawDx = data['${prefix}Dx'] ?? data['${prefix}X'];
  final rawDy = data['${prefix}Dy'] ?? data['${prefix}Y'];
  final dx = rawDx is num ? rawDx.toDouble() : (rawDx is String ? double.tryParse(rawDx) : null);
  final dy = rawDy is num ? rawDy.toDouble() : (rawDy is String ? double.tryParse(rawDy) : null);
  if (dx != null && dy != null) {
    return Offset(dx, dy);
  }
  final mapVal = data[prefix];
  if (mapVal is Map) {
    final mapDx = mapVal['dx'] ?? mapVal['x'];
    final mapDy = mapVal['dy'] ?? mapVal['y'];
    final parsedDx = mapDx is num ? mapDx.toDouble() : (mapDx is String ? double.tryParse(mapDx) : null);
    final parsedDy = mapDy is num ? mapDy.toDouble() : (mapDy is String ? double.tryParse(mapDy) : null);
    if (parsedDx != null && parsedDy != null) {
      return Offset(parsedDx, parsedDy);
    }
  }
  return null;
}

ConnectionMetadata connectionMetadataFromData(Map<String, Object?> data) {
  final startNodeId = data['connectionStartNodeId'] as String? ?? data['startNodeId'] as String?;
  final endNodeId = data['connectionEndNodeId'] as String? ?? data['endNodeId'] as String?;
  final startPoint = _parseOffset(data, 'connectionStart') ?? _parseOffset(data, 'startPoint');
  final endPoint = _parseOffset(data, 'connectionEnd') ?? _parseOffset(data, 'endPoint');
  final lineStyle = data['connectionLineStyle'] as String? ?? data['lineStyle'] as String? ?? 'solid';
  final arrowStyle = data['connectionArrowStyle'] as String? ?? data['arrowStyle'] as String? ?? 'end';
  final color = data['connectionColor'] as String? ?? data['color'] as String? ?? 'slate';
  final label = data['connectionLabel'] as String? ?? data['label'] as String?;

  return ConnectionMetadata(
    startNodeId: startNodeId,
    startPoint: startPoint,
    endNodeId: endNodeId,
    endPoint: endPoint,
    lineStyle: lineStyle,
    arrowStyle: arrowStyle,
    color: color,
    label: label,
  );
}

Map<String, Object?> dataWithConnectionMetadata(
  Map<String, Object?> data,
  ConnectionMetadata metadata,
) {
  return Map.unmodifiable({
    ...data,
    'connectionStartNodeId': metadata.startNodeId,
    'connectionStartDx': metadata.startPoint?.dx,
    'connectionStartDy': metadata.startPoint?.dy,
    'connectionEndNodeId': metadata.endNodeId,
    'connectionEndDx': metadata.endPoint?.dx,
    'connectionEndDy': metadata.endPoint?.dy,
    'connectionLineStyle': metadata.lineStyle,
    'connectionArrowStyle': metadata.arrowStyle,
    'connectionColor': metadata.color,
    'connectionLabel': metadata.label,
  });
}

class GroupMetadata {
  const GroupMetadata({
    this.title = 'Group',
    this.color = 'slate',
    this.isCollapsed = false,
    this.layout = 'free',
  });

  final String title;
  final String color;
  final bool isCollapsed;
  final String layout;
}

GroupMetadata groupMetadataFromData(Map<String, Object?> data) {
  return GroupMetadata(
    title: data['groupTitle'] as String? ?? 'Group',
    color: data['groupColor'] as String? ?? 'slate',
    isCollapsed: data['groupCollapsed'] as bool? ?? false,
    layout: data['groupLayout'] as String? ?? 'free',
  );
}

Map<String, Object?> dataWithGroupMetadata(
  Map<String, Object?> data,
  GroupMetadata metadata,
) {
  return Map.unmodifiable({
    ...data,
    'groupTitle': metadata.title,
    'groupColor': metadata.color,
    'groupCollapsed': metadata.isCollapsed,
    'groupLayout': metadata.layout,
  });
}

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
