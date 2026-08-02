import 'canvas_board.dart';

List<CanvasObject> cloneCanvasObjects(
  Iterable<CanvasObject> objects, {
  required String Function() idFactory,
  required DateTime now,
  bool excludeBoardReferences = false,
}) {
  final included = objects
      .where(
        (object) =>
            !excludeBoardReferences ||
            object.type != CanvasObjectType.boardReference,
      )
      .toList(growable: false);
  final ids = <String, String>{};
  final types = <String, CanvasObjectType>{};
  final generatedIds = <String>{};
  for (final object in included) {
    if (ids.containsKey(object.id)) {
      throw StateError('Duplicate canvas object source ID.');
    }
    final generatedId = idFactory();
    if (!generatedIds.add(generatedId)) {
      throw StateError('Duplicate canvas object generated ID.');
    }
    ids[object.id] = generatedId;
    types[object.id] = object.type;
  }

  return <CanvasObject>[
    for (final object in included)
      if (_hasValidConnectorEndpoints(object, ids))
        _cloneObject(object, ids: ids, types: types, now: now),
  ];
}

bool _hasValidConnectorEndpoints(CanvasObject object, Map<String, String> ids) {
  if (object.type != CanvasObjectType.connector) return true;
  final sourceId = object.payload['sourceObjectId'];
  final targetId = object.payload['targetObjectId'];
  return sourceId is String &&
      targetId is String &&
      ids.containsKey(sourceId) &&
      ids.containsKey(targetId);
}

CanvasObject _cloneObject(
  CanvasObject object, {
  required Map<String, String> ids,
  required Map<String, CanvasObjectType> types,
  required DateTime now,
}) {
  final payload = <String, Object?>{...object.payload};
  for (final key in <String>['sourceObjectId', 'targetObjectId']) {
    final value = payload[key];
    if (value is String && ids[value] != null) payload[key] = ids[value];
  }
  if (object.type == CanvasObjectType.column) {
    payload['orderedChildIds'] = <String>[
      for (final childId in object.orderedColumnChildIds)
        if (ids[childId] != null) ids[childId]!,
    ];
  }
  return CanvasObject(
    id: ids[object.id]!,
    type: object.type,
    rawType: object.rawType,
    geometry: object.geometry,
    zIndex: object.zIndex,
    isLocked: object.isLocked,
    isVisible: object.isVisible,
    parentFrameId: types[object.parentFrameId] == CanvasObjectType.frame
        ? ids[object.parentFrameId]
        : null,
    parentColumnId: types[object.parentColumnId] == CanvasObjectType.column
        ? ids[object.parentColumnId]
        : null,
    mindmapNodeId: object.mindmapNodeId,
    referencedBoardId: object.referencedBoardId,
    payload: payload,
    createdAt: now,
    updatedAt: now,
  );
}
