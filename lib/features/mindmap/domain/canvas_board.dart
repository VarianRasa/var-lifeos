import 'package:collection/collection.dart';

import '../../../core/utils/date_utils.dart';
import 'canvas_workshop.dart';
import 'mindmap_node.dart';
import 'node_ui_state_codec.dart';

enum CanvasBoardKind { daily, project }

enum CanvasProjectTemplate {
  projectPlan,
  kanban,
  brainstorm,
  contentCalendar,
  weeklyPlanner,
  researchBoard,
  moodboard,
  goalTracker,
}

enum CanvasVotingStatus { inactive, active, ended }

final class CanvasVotingSession {
  CanvasVotingSession({
    this.sessionId = '',
    this.ballotStorageVersion = 1,
    this.status = CanvasVotingStatus.inactive,
    this.isAnonymous = false,
    this.resultsRevealed = true,
    int maxVotesPerParticipant = 3,
    Map<String, Set<String>> allocations = const <String, Set<String>>{},
  }) : maxVotesPerParticipant = maxVotesPerParticipant.clamp(1, 10),
       allocations = Map<String, Set<String>>.unmodifiable(
         allocations.map(
           (participantId, objectIds) => MapEntry(
             participantId,
             Set<String>.unmodifiable(objectIds.where((id) => id.isNotEmpty)),
           ),
         ),
       );

  factory CanvasVotingSession.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    final statusName = json['status'] as String?;
    final rawAllocations = json['allocations'];
    return CanvasVotingSession(
      sessionId: json['sessionId'] as String? ?? '',
      ballotStorageVersion: json['ballotStorageVersion'] as int? ?? 1,
      status: CanvasVotingStatus.values.firstWhere(
        (candidate) => candidate.name == statusName,
        orElse: () => CanvasVotingStatus.inactive,
      ),
      isAnonymous: json['isAnonymous'] as bool? ?? false,
      resultsRevealed: json['resultsRevealed'] as bool? ?? true,
      maxVotesPerParticipant: json['maxVotesPerParticipant'] as int? ?? 3,
      allocations: rawAllocations is Map
          ? <String, Set<String>>{
              for (final entry in rawAllocations.entries)
                if (entry.key is String && entry.value is List)
                  entry.key as String: <String>{
                    for (final value in entry.value! as List)
                      if (value is String && value.isNotEmpty) value,
                  },
            }
          : const <String, Set<String>>{},
    );
  }

  final String sessionId;
  final int ballotStorageVersion;
  final CanvasVotingStatus status;
  final bool isAnonymous;
  final bool resultsRevealed;
  final int maxVotesPerParticipant;
  final Map<String, Set<String>> allocations;

  bool get isActive => status == CanvasVotingStatus.active;
  bool get resultsConcealed => !resultsRevealed;

  int votesUsedBy(String participantId) =>
      allocations[participantId]?.length ?? 0;

  int remainingVotesFor(String participantId) =>
      (maxVotesPerParticipant - votesUsedBy(participantId)).clamp(
        0,
        maxVotesPerParticipant,
      );

  bool hasVote(String participantId, String objectId) =>
      allocations[participantId]?.contains(objectId) ?? false;

  int votesForObject(String objectId) => allocations.values
      .where((objectIds) => objectIds.contains(objectId))
      .length;

  CanvasVotingSession start({required int maxVotes, bool anonymous = false}) =>
      CanvasVotingSession(
        sessionId: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        ballotStorageVersion: ballotStorageVersion,
        status: CanvasVotingStatus.active,
        isAnonymous: anonymous,
        resultsRevealed: false,
        maxVotesPerParticipant: maxVotes,
      );

  CanvasVotingSession end() => CanvasVotingSession(
    sessionId: sessionId,
    ballotStorageVersion: ballotStorageVersion,
    status: CanvasVotingStatus.ended,
    isAnonymous: isAnonymous,
    resultsRevealed: resultsRevealed,
    maxVotesPerParticipant: maxVotesPerParticipant,
    allocations: allocations,
  );

  CanvasVotingSession revealResults() => CanvasVotingSession(
    sessionId: sessionId,
    ballotStorageVersion: ballotStorageVersion,
    status: status,
    isAnonymous: isAnonymous,
    resultsRevealed: true,
    maxVotesPerParticipant: maxVotesPerParticipant,
    allocations: allocations,
  );

  CanvasVotingSession reset() =>
      CanvasVotingSession(maxVotesPerParticipant: maxVotesPerParticipant);

  CanvasVotingSession changeVote({
    required String participantId,
    required String objectId,
    required bool add,
  }) {
    if (!isActive || participantId.isEmpty || objectId.isEmpty) return this;
    final current = allocations[participantId] ?? const <String>{};
    if (add &&
        (current.contains(objectId) ||
            current.length >= maxVotesPerParticipant)) {
      return this;
    }
    if (!add && !current.contains(objectId)) return this;
    final nextVotes = <String>{...current};
    if (add) {
      nextVotes.add(objectId);
    } else {
      nextVotes.remove(objectId);
    }
    final nextAllocations = <String, Set<String>>{...allocations};
    if (nextVotes.isEmpty) {
      nextAllocations.remove(participantId);
    } else {
      nextAllocations[participantId] = nextVotes;
    }
    return CanvasVotingSession(
      sessionId: sessionId,
      ballotStorageVersion: ballotStorageVersion,
      status: status,
      isAnonymous: isAnonymous,
      resultsRevealed: resultsRevealed,
      maxVotesPerParticipant: maxVotesPerParticipant,
      allocations: nextAllocations,
    );
  }

  Map<String, Object?> toJson({bool includeAllocations = true}) =>
      <String, Object?>{
        'sessionId': sessionId,
        'ballotStorageVersion': ballotStorageVersion,
        'status': status.name,
        'isAnonymous': isAnonymous,
        'resultsRevealed': resultsRevealed,
        'maxVotesPerParticipant': maxVotesPerParticipant,
        if (includeAllocations)
          'allocations': <String, List<String>>{
            for (final entry in allocations.entries)
              entry.key: entry.value.toList()..sort(),
          },
      };

  @override
  bool operator ==(Object other) =>
      other is CanvasVotingSession &&
      other.sessionId == sessionId &&
      other.ballotStorageVersion == ballotStorageVersion &&
      other.status == status &&
      other.isAnonymous == isAnonymous &&
      other.resultsRevealed == resultsRevealed &&
      other.maxVotesPerParticipant == maxVotesPerParticipant &&
      const DeepCollectionEquality().equals(other.allocations, allocations);

  @override
  int get hashCode => Object.hash(
    sessionId,
    ballotStorageVersion,
    status,
    isAnonymous,
    resultsRevealed,
    maxVotesPerParticipant,
    const DeepCollectionEquality().hash(allocations),
  );
}

enum CanvasObjectType {
  nodeReference,
  stickyNote,
  text,
  shape,
  connector,
  freehand,
  frame,
  image,
  linkPreview,
  column,
  boardReference,
  unknown,
}

enum CanvasActivityType {
  objectsAdded,
  objectsUpdated,
  objectsDeleted,
  votingStarted,
  votingEnded,
  votingReset,
  votesChanged,
  boardRenamed,
  boardDuplicated,
  boardArchived,
  boardRestored,
  boardImported,
  workshopStarted,
  workshopPaused,
  workshopResumed,
  workshopStageChanged,
  workshopStageRevealed,
  workshopEnded,
  presenterChanged,
  assistantApplied,
}

final class CanvasActivity {
  CanvasActivity({
    required this.id,
    required this.type,
    required String summary,
    required this.occurredAt,
    List<String> objectIds = const <String>[],
  }) : summary = summary.trim(),
       objectIds = List<String>.unmodifiable(
         objectIds.where((objectId) => objectId.isNotEmpty),
       ) {
    if (id.isEmpty || this.summary.isEmpty || this.summary.length > 500) {
      throw const FormatException('Invalid canvas activity.');
    }
  }

  factory CanvasActivity.fromJson(Map<String, Object?> json) => CanvasActivity(
    id: json['id'] as String? ?? '',
    type: CanvasActivityType.values.firstWhere(
      (candidate) => candidate.name == json['type'],
      orElse: () => CanvasActivityType.objectsUpdated,
    ),
    summary: json['summary'] as String? ?? '',
    occurredAt: _dateTime(json['occurredAt']),
    objectIds: json['objectIds'] is List
        ? (json['objectIds']! as List).whereType<String>().toList()
        : const <String>[],
  );

  final String id;
  final CanvasActivityType type;
  final String summary;
  final DateTime occurredAt;
  final List<String> objectIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type.name,
    'summary': summary,
    'occurredAt': occurredAt.toIso8601String(),
    'objectIds': objectIds,
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasActivity &&
      other.id == id &&
      other.type == type &&
      other.summary == summary &&
      other.occurredAt == occurredAt &&
      const ListEquality<String>().equals(other.objectIds, objectIds);

  @override
  int get hashCode => Object.hash(
    id,
    type,
    summary,
    occurredAt,
    const ListEquality<String>().hash(objectIds),
  );
}

final class CanvasObjectComment {
  CanvasObjectComment({
    required this.id,
    required String body,
    required String authorName,
    required this.createdAt,
    this.parentId,
    this.isResolved = false,
  }) : body = body.trim(),
       authorName = authorName.trim() {
    if (id.isEmpty ||
        this.body.isEmpty ||
        this.body.length > 4000 ||
        this.authorName.isEmpty ||
        this.authorName.length > 100 ||
        parentId == id) {
      throw const FormatException('Invalid canvas object comment.');
    }
  }

  factory CanvasObjectComment.fromJson(Map<String, Object?> json) =>
      CanvasObjectComment(
        id: json['id'] as String? ?? '',
        body: json['body'] as String? ?? '',
        authorName: json['authorName'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        parentId: json['parentId'] as String?,
        isResolved: json['isResolved'] as bool? ?? false,
      );

  final String id;
  final String body;
  final String authorName;
  final DateTime createdAt;
  final String? parentId;
  final bool isResolved;

  CanvasObjectComment copyWith({bool? isResolved}) => CanvasObjectComment(
    id: id,
    body: body,
    authorName: authorName,
    createdAt: createdAt,
    parentId: parentId,
    isResolved: isResolved ?? this.isResolved,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'body': body,
    'authorName': authorName,
    'createdAt': createdAt.toIso8601String(),
    if (parentId != null) 'parentId': parentId,
    'isResolved': isResolved,
  };
}

final class CanvasGeometry {
  const CanvasGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  factory CanvasGeometry.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return CanvasGeometry(
      x: _finiteDouble(json['x']),
      y: _finiteDouble(json['y']),
      width: _positiveDouble(json['width'], 1),
      height: _positiveDouble(json['height'], 1),
      rotation: _finiteDouble(json['rotation']),
    );
  }

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  CanvasGeometry copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) => CanvasGeometry(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasGeometry &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(x, y, width, height, rotation);
}

final class CanvasViewport {
  const CanvasViewport({this.x = 0, this.y = 0, this.scale = 1});

  factory CanvasViewport.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return CanvasViewport(
      x: _finiteDouble(json['x']),
      y: _finiteDouble(json['y']),
      scale: _positiveDouble(json['scale'], 1),
    );
  }

  final double x;
  final double y;
  final double scale;

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'scale': scale,
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasViewport &&
      other.x == x &&
      other.y == y &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(x, y, scale);
}

final class CanvasBoardSettings {
  const CanvasBoardSettings({
    this.showGrid = true,
    this.snapToGrid = true,
    this.showMinimap = true,
    this.background = 'dots',
  });

  factory CanvasBoardSettings.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return CanvasBoardSettings(
      showGrid: json['showGrid'] as bool? ?? true,
      snapToGrid: json['snapToGrid'] as bool? ?? true,
      showMinimap: json['showMinimap'] as bool? ?? true,
      background: json['background'] as String? ?? 'dots',
    );
  }

  final bool showGrid;
  final bool snapToGrid;
  final bool showMinimap;
  final String background;

  Map<String, Object?> toJson() => <String, Object?>{
    'showGrid': showGrid,
    'snapToGrid': snapToGrid,
    'showMinimap': showMinimap,
    'background': background,
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasBoardSettings &&
      other.showGrid == showGrid &&
      other.snapToGrid == snapToGrid &&
      other.showMinimap == showMinimap &&
      other.background == background;

  @override
  int get hashCode =>
      Object.hash(showGrid, snapToGrid, showMinimap, background);
}

final class CanvasObject {
  CanvasObject({
    required this.id,
    required this.type,
    required this.geometry,
    required this.createdAt,
    required this.updatedAt,
    this.rawType,
    this.zIndex = 0,
    this.isLocked = false,
    this.isVisible = true,
    this.parentFrameId,
    this.parentColumnId,
    this.mindmapNodeId,
    String? referencedBoardId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) : referencedBoardId = referencedBoardId?.trim(),
       payload = Map<String, Object?>.unmodifiable(payload) {
    if (type == CanvasObjectType.column) {
      _validateColumnPayload(payload);
    }
    if (type == CanvasObjectType.boardReference &&
        (this.referencedBoardId == null || this.referencedBoardId!.isEmpty)) {
      throw const FormatException('Invalid board reference.');
    }
  }

  factory CanvasObject.fromJson(Map<String, Object?> json) {
    final typeName = json['type'] as String? ?? 'unknown';
    final type = CanvasObjectType.values.firstWhere(
      (candidate) => candidate.name == typeName,
      orElse: () => CanvasObjectType.unknown,
    );
    return CanvasObject(
      id: json['id'] as String? ?? '',
      type: type,
      rawType: type == CanvasObjectType.unknown ? typeName : null,
      geometry: CanvasGeometry.fromJson(json['geometry']),
      zIndex: json['zIndex'] as int? ?? 0,
      isLocked: json['isLocked'] as bool? ?? false,
      isVisible: json['isVisible'] as bool? ?? true,
      parentFrameId: json['parentFrameId'] as String?,
      parentColumnId: json['parentColumnId'] as String?,
      mindmapNodeId: json['mindmapNodeId'] as String?,
      referencedBoardId: json['referencedBoardId'] as String?,
      payload: json['payload'] is Map
          ? Map<String, Object?>.from(json['payload']! as Map)
          : const <String, Object?>{},
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
    );
  }

  final String id;
  final CanvasObjectType type;
  final String? rawType;
  final CanvasGeometry geometry;
  final int zIndex;
  final bool isLocked;
  final bool isVisible;
  final String? parentFrameId;
  final String? parentColumnId;
  final String? mindmapNodeId;
  final String? referencedBoardId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get columnTitle => (payload['title'] as String).trim();

  bool get isColumnCollapsed => payload['isCollapsed'] as bool;

  List<String> get orderedColumnChildIds =>
      List<String>.unmodifiable((payload['orderedChildIds']! as List).cast());

  bool get isEligibleColumnChild =>
      !isLocked &&
      type != CanvasObjectType.connector &&
      type != CanvasObjectType.frame &&
      type != CanvasObjectType.column;

  int get voteCount {
    final value = payload['voteCount'];
    return value is num && value.isFinite ? value.toInt().clamp(0, 999999) : 0;
  }

  List<CanvasObjectComment> get comments {
    final values = payload['comments'];
    if (values is! List) return const <CanvasObjectComment>[];
    return <CanvasObjectComment?>[
      for (final value in values)
        if (value is Map) tryComment(Map<String, Object?>.from(value)),
    ].whereType<CanvasObjectComment>().toList(growable: false);
  }

  int get openCommentCount {
    final values = comments;
    final resolvedRootIds = values
        .where((comment) => comment.parentId == null && comment.isResolved)
        .map((comment) => comment.id)
        .toSet();
    return values
        .where(
          (comment) =>
              comment.parentId == null && !resolvedRootIds.contains(comment.id),
        )
        .length;
  }

  CanvasObject withComments(
    Iterable<CanvasObjectComment> comments, {
    required DateTime updatedAt,
  }) => copyWith(
    payload: <String, Object?>{
      ...payload,
      'comments': <Map<String, Object?>>[
        for (final comment in comments) comment.toJson(),
      ],
    },
    updatedAt: updatedAt,
  );

  CanvasObject withVoteCount(int value, {required DateTime updatedAt}) =>
      copyWith(
        payload: <String, Object?>{
          ...payload,
          'voteCount': value.clamp(0, 999999),
        },
        updatedAt: updatedAt,
      );

  CanvasObject copyWith({
    CanvasGeometry? geometry,
    int? zIndex,
    bool? isLocked,
    bool? isVisible,
    String? parentFrameId,
    bool clearParentFrameId = false,
    String? parentColumnId,
    bool clearParentColumnId = false,
    Map<String, Object?>? payload,
    DateTime? updatedAt,
  }) => CanvasObject(
    id: id,
    type: type,
    rawType: rawType,
    geometry: geometry ?? this.geometry,
    zIndex: zIndex ?? this.zIndex,
    isLocked: isLocked ?? this.isLocked,
    isVisible: isVisible ?? this.isVisible,
    parentFrameId: clearParentFrameId
        ? null
        : parentFrameId ?? this.parentFrameId,
    parentColumnId: clearParentColumnId
        ? null
        : parentColumnId ?? this.parentColumnId,
    mindmapNodeId: mindmapNodeId,
    referencedBoardId: referencedBoardId,
    payload: payload ?? this.payload,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type == CanvasObjectType.unknown ? rawType ?? 'unknown' : type.name,
    'geometry': geometry.toJson(),
    'zIndex': zIndex,
    'isLocked': isLocked,
    'isVisible': isVisible,
    if (parentFrameId != null) 'parentFrameId': parentFrameId,
    if (parentColumnId != null) 'parentColumnId': parentColumnId,
    if (mindmapNodeId != null) 'mindmapNodeId': mindmapNodeId,
    if (referencedBoardId != null) 'referencedBoardId': referencedBoardId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasObject &&
      other.id == id &&
      other.type == type &&
      other.rawType == rawType &&
      other.geometry == geometry &&
      other.zIndex == zIndex &&
      other.isLocked == isLocked &&
      other.isVisible == isVisible &&
      other.parentFrameId == parentFrameId &&
      other.parentColumnId == parentColumnId &&
      other.mindmapNodeId == mindmapNodeId &&
      other.referencedBoardId == referencedBoardId &&
      const DeepCollectionEquality().equals(other.payload, payload) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    type,
    rawType,
    geometry,
    zIndex,
    isLocked,
    isVisible,
    parentFrameId,
    parentColumnId,
    mindmapNodeId,
    referencedBoardId,
    const DeepCollectionEquality().hash(payload),
    createdAt,
    updatedAt,
  ]);
}

void _validateColumnPayload(Map<String, Object?> payload) {
  final title = payload['title'];
  final isCollapsed = payload['isCollapsed'];
  final childIds = payload['orderedChildIds'];
  if (title is! String ||
      title.trim().isEmpty ||
      isCollapsed is! bool ||
      childIds is! List ||
      childIds.any((id) => id is! String || id.isEmpty) ||
      childIds.toSet().length != childIds.length) {
    throw const FormatException('Invalid canvas column payload.');
  }
}

CanvasObjectComment? tryComment(Map<String, Object?> json) {
  try {
    return CanvasObjectComment.fromJson(json);
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

CanvasActivity? tryActivity(Map<String, Object?> json) {
  try {
    return CanvasActivity.fromJson(json);
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

Map<String, Object?> _normalizedColumnObjectJson(Map<Object?, Object?> value) {
  final json = Map<String, Object?>.from(value);
  if (json['type'] != CanvasObjectType.column.name) return json;
  final payload = json['payload'] is Map
      ? Map<String, Object?>.from(json['payload']! as Map)
      : <String, Object?>{};
  final seen = <String>{};
  json['payload'] = <String, Object?>{
    ...payload,
    'title': (payload['title'] as String?)?.trim().isNotEmpty == true
        ? payload['title']
        : 'Column',
    'isCollapsed': payload['isCollapsed'] is bool
        ? payload['isCollapsed']
        : false,
    'orderedChildIds': <String>[
      for (final id
          in payload['orderedChildIds'] is List
              ? payload['orderedChildIds']! as List
              : const <Object?>[])
        if (id is String && id.isNotEmpty && seen.add(id)) id,
    ],
  };
  return json;
}

List<CanvasObject> _normalizeColumnMembership(List<CanvasObject> objects) {
  final byId = <String, CanvasObject>{
    for (final object in objects) object.id: object,
  };
  final claimed = <String>{};
  final orderedByColumn = <String, List<String>>{};
  for (final column in objects.where(
    (object) => object.type == CanvasObjectType.column,
  )) {
    orderedByColumn[column.id] = <String>[
      for (final id in column.orderedColumnChildIds)
        if (byId[id] case final child?)
          if (child.isEligibleColumnChild && claimed.add(id)) id,
    ];
  }
  return <CanvasObject>[
    for (final object in objects)
      if (object.type == CanvasObjectType.column)
        object.copyWith(
          payload: <String, Object?>{
            ...object.payload,
            'orderedChildIds': orderedByColumn[object.id]!,
          },
        )
      else if (claimed.contains(object.id))
        object.copyWith(
          parentColumnId: orderedByColumn.entries
              .firstWhere((entry) => entry.value.contains(object.id))
              .key,
        )
      else if (object.parentColumnId != null)
        object.copyWith(clearParentColumnId: true)
      else
        object,
  ];
}

final class CanvasBoard {
  CanvasBoard({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.day,
    this.workspaceName,
    String? parentBoardId,
    this.trashedAt,
    this.isArchived = false,
    this.viewport = const CanvasViewport(),
    this.settings = const CanvasBoardSettings(),
    CanvasVotingSession? votingSession,
    CanvasWorkshopSession? workshopSession,
    this.schemaVersion = currentSchemaVersion,
    List<CanvasObject> objects = const <CanvasObject>[],
    List<CanvasActivity> activity = const <CanvasActivity>[],
  }) : parentBoardId = parentBoardId?.trim(),
       votingSession = votingSession ?? CanvasVotingSession(),
       workshopSession = workshopSession ?? CanvasWorkshopSession(),
       objects = List<CanvasObject>.unmodifiable(objects),
       activity = List<CanvasActivity>.unmodifiable(activity) {
    if (kind != CanvasBoardKind.project && this.parentBoardId != null) {
      throw const FormatException('Only project boards can be nested.');
    }
  }

  factory CanvasBoard.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String?;
    final parsedObjects = <CanvasObject>[
      for (final value
          in json['objects'] is List
              ? json['objects']! as List
              : const <Object?>[])
        if (value is Map)
          CanvasObject.fromJson(_normalizedColumnObjectJson(value)),
    ];
    final objects = _normalizeColumnMembership(parsedObjects);
    return CanvasBoard(
      id: json['id'] as String? ?? '',
      kind: CanvasBoardKind.values.firstWhere(
        (candidate) => candidate.name == kindName,
        orElse: () => CanvasBoardKind.daily,
      ),
      title: json['title'] as String? ?? '',
      day: _optionalDate(json['day']),
      workspaceName: json['workspaceName'] as String?,
      parentBoardId: json['parentBoardId'] as String?,
      trashedAt: _optionalDateTime(json['trashedAt']),
      isArchived: json['isArchived'] as bool? ?? false,
      viewport: CanvasViewport.fromJson(json['viewport']),
      settings: CanvasBoardSettings.fromJson(json['settings']),
      votingSession: CanvasVotingSession.fromJson(json['votingSession']),
      workshopSession: CanvasWorkshopSession.fromJson(json['workshopSession']),
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      objects: objects,
      activity: json['activity'] is List
          ? <CanvasActivity?>[
              for (final value in json['activity']! as List)
                if (value is Map) tryActivity(Map<String, Object?>.from(value)),
            ].whereType<CanvasActivity>().toList()
          : const <CanvasActivity>[],
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
    );
  }

  factory CanvasBoard.daily({
    required DateTime day,
    required Iterable<MindmapNode> nodes,
    required DateTime now,
  }) {
    final normalizedDay = day.dateOnly;
    return CanvasBoard(
      id: dailyCanvasBoardId(normalizedDay),
      kind: CanvasBoardKind.daily,
      title: dayKey(normalizedDay),
      day: normalizedDay,
      createdAt: now,
      updatedAt: now,
      objects: <CanvasObject>[
        for (final (index, node) in nodes.indexed)
          CanvasObject(
            id: 'node:${node.id}',
            type: CanvasObjectType.nodeReference,
            geometry: CanvasGeometry(
              x: node.position.dx,
              y: node.position.dy,
              width: NodeUiStateCodec.read(node).width,
              height: NodeUiStateCodec.read(node).height,
            ),
            zIndex: index,
            isLocked: node.data['groupLocked'] == true,
            parentFrameId: node.data['groupId'] as String?,
            mindmapNodeId: node.id,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
          ),
      ],
    );
  }

  factory CanvasBoard.project({
    required String workspaceName,
    required Iterable<MindmapNode> nodes,
    required DateTime now,
  }) => CanvasBoard(
    id: projectCanvasBoardId(workspaceName),
    kind: CanvasBoardKind.project,
    title: workspaceName,
    workspaceName: workspaceName,
    createdAt: now,
    updatedAt: now,
    objects: <CanvasObject>[
      for (final (index, node) in nodes.indexed)
        CanvasObject(
          id: 'node:${node.id}',
          type: CanvasObjectType.nodeReference,
          geometry: CanvasGeometry(
            x: node.position.dx,
            y: node.position.dy,
            width: NodeUiStateCodec.read(node).width,
            height: NodeUiStateCodec.read(node).height,
          ),
          zIndex: index,
          mindmapNodeId: node.id,
          createdAt: node.createdAt,
          updatedAt: node.updatedAt,
        ),
    ],
  );

  static const int currentSchemaVersion = 2;

  final String id;
  final CanvasBoardKind kind;
  final String title;
  final DateTime? day;
  final String? workspaceName;
  final String? parentBoardId;
  final DateTime? trashedAt;
  final bool isArchived;
  final CanvasViewport viewport;
  final CanvasBoardSettings settings;
  final CanvasVotingSession votingSession;
  final CanvasWorkshopSession workshopSession;
  final int schemaVersion;
  final List<CanvasObject> objects;
  final List<CanvasActivity> activity;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTrashed => trashedAt != null;

  bool isTrashExpired(DateTime now) =>
      trashedAt != null &&
      !now.toUtc().isBefore(trashedAt!.toUtc().add(const Duration(days: 30)));

  CanvasBoard copyWith({
    String? title,
    String? parentBoardId,
    bool clearParentBoardId = false,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    bool? isArchived,
    CanvasViewport? viewport,
    CanvasBoardSettings? settings,
    CanvasVotingSession? votingSession,
    CanvasWorkshopSession? workshopSession,
    List<CanvasObject>? objects,
    List<CanvasActivity>? activity,
    DateTime? updatedAt,
  }) => CanvasBoard(
    id: id,
    kind: kind,
    title: title ?? this.title,
    day: day,
    workspaceName: workspaceName,
    parentBoardId: clearParentBoardId
        ? null
        : parentBoardId ?? this.parentBoardId,
    trashedAt: clearTrashedAt ? null : trashedAt ?? this.trashedAt,
    isArchived: isArchived ?? this.isArchived,
    viewport: viewport ?? this.viewport,
    settings: settings ?? this.settings,
    votingSession: votingSession ?? this.votingSession,
    workshopSession: workshopSession ?? this.workshopSession,
    schemaVersion: schemaVersion,
    objects: objects ?? this.objects,
    activity: activity ?? this.activity,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  CanvasObject? objectById(String id) =>
      objects.firstWhereOrNull((object) => object.id == id);

  CanvasBoard reconcileColumnMembership({
    required String columnId,
    required List<String> orderedChildIds,
    required DateTime now,
  }) {
    final column = objectById(columnId);
    if (column == null || column.type != CanvasObjectType.column) {
      throw const FormatException('Invalid canvas column.');
    }
    if (orderedChildIds.toSet().length != orderedChildIds.length) {
      throw const FormatException('Duplicate canvas column child.');
    }
    for (final childId in orderedChildIds) {
      final child = objectById(childId);
      if (child == null ||
          childId == columnId ||
          !child.isEligibleColumnChild ||
          (child.parentColumnId != null && child.parentColumnId != columnId)) {
        throw const FormatException('Invalid canvas column child.');
      }
    }
    final childIds = orderedChildIds.toSet();
    return copyWith(
      objects: <CanvasObject>[
        for (final object in objects)
          if (object.id == columnId)
            object.copyWith(
              payload: <String, Object?>{
                ...object.payload,
                'orderedChildIds': orderedChildIds,
              },
              updatedAt: now,
            )
          else if (childIds.contains(object.id))
            object.copyWith(parentColumnId: columnId, updatedAt: now)
          else if (object.parentColumnId == columnId)
            object.copyWith(clearParentColumnId: true, updatedAt: now)
          else
            object,
      ],
      updatedAt: now,
    );
  }

  CanvasBoard detachColumnChildren(String columnId, {required DateTime now}) {
    final column = objectById(columnId);
    if (column == null || column.type != CanvasObjectType.column) {
      throw const FormatException('Invalid canvas column.');
    }
    return reconcileColumnMembership(
      columnId: columnId,
      orderedChildIds: const <String>[],
      now: now,
    );
  }

  CanvasBoard visibleForWorkshop({
    required CanvasWorkshopSession session,
    required String viewerUid,
    required bool isHost,
  }) => copyWith(
    objects: objects
        .where(
          (object) => isWorkshopObjectVisible(
            object.payload,
            session,
            viewerUid: viewerUid,
            isHost: isHost,
          ),
        )
        .toList(growable: false),
  );

  CanvasBoard recordActivity({
    required CanvasActivityType type,
    required String summary,
    required DateTime now,
    Iterable<String> objectIds = const <String>[],
  }) => copyWith(
    activity: <CanvasActivity>[
      CanvasActivity(
        id: 'activity:${now.microsecondsSinceEpoch}:${activity.length}',
        type: type,
        summary: summary,
        occurredAt: now,
        objectIds: objectIds.toList(),
      ),
      ...activity.take(499),
    ],
    updatedAt: now,
  );

  CanvasBoard replaceObject(CanvasObject replacement) {
    if (objectById(replacement.id) == null) return this;
    return copyWith(
      objects: <CanvasObject>[
        for (final object in objects)
          if (object.id == replacement.id) replacement else object,
      ],
      updatedAt: replacement.updatedAt,
    );
  }

  CanvasBoard reconcileNodeReferences(
    Iterable<MindmapNode> nodes, {
    required DateTime now,
  }) {
    final nodeList = nodes.toList(growable: false);
    final nodeIds = nodeList.map((node) => node.id).toSet();
    final existingReferences = <String, CanvasObject>{
      for (final object in objects)
        if (object.type == CanvasObjectType.nodeReference &&
            object.mindmapNodeId != null)
          object.mindmapNodeId!: object,
    };
    final missingNodes = nodeList
        .where((node) => !existingReferences.containsKey(node.id))
        .toList();
    final hasStaleReferences = existingReferences.keys.any(
      (nodeId) => !nodeIds.contains(nodeId),
    );
    if (missingNodes.isEmpty && !hasStaleReferences) return this;
    var nextZIndex = objects.fold<int>(
      -1,
      (current, object) => object.zIndex > current ? object.zIndex : current,
    );
    return copyWith(
      objects: <CanvasObject>[
        for (final object in objects)
          if (object.type != CanvasObjectType.nodeReference ||
              (object.mindmapNodeId != null &&
                  nodeIds.contains(object.mindmapNodeId)))
            object,
        for (final node in missingNodes)
          CanvasObject(
            id: 'node:${node.id}',
            type: CanvasObjectType.nodeReference,
            geometry: CanvasGeometry(
              x: node.position.dx,
              y: node.position.dy,
              width: NodeUiStateCodec.read(node).width,
              height: NodeUiStateCodec.read(node).height,
            ),
            zIndex: ++nextZIndex,
            mindmapNodeId: node.id,
            createdAt: node.createdAt,
            updatedAt: now,
          ),
      ],
      updatedAt: now,
    );
  }

  CanvasBoard addProjectTemplate(
    CanvasProjectTemplate template, {
    required DateTime now,
  }) {
    final baseId = 'template-${template.name}-${now.microsecondsSinceEpoch}';
    var nextZIndex = objects.fold<int>(
      -1,
      (current, object) => object.zIndex > current ? object.zIndex : current,
    );
    CanvasObject frame(String id, String text, double x, String color) =>
        CanvasObject(
          id: '$baseId-frame-$id',
          type: CanvasObjectType.frame,
          geometry: CanvasGeometry(x: x, y: -260, width: 360, height: 520),
          zIndex: ++nextZIndex,
          payload: <String, Object?>{'text': text, 'color': color},
          createdAt: now,
          updatedAt: now,
        );
    CanvasObject sticky(
      String id,
      String text,
      double x,
      double y,
      String color, {
      String? parentFrameId,
    }) => CanvasObject(
      id: '$baseId-sticky-$id',
      type: CanvasObjectType.stickyNote,
      geometry: CanvasGeometry(x: x, y: y, width: 240, height: 160),
      zIndex: ++nextZIndex,
      parentFrameId: parentFrameId,
      payload: <String, Object?>{'text': text, 'color': color},
      createdAt: now,
      updatedAt: now,
    );

    final additions = switch (template) {
      CanvasProjectTemplate.projectPlan => () {
        final backlog = frame('backlog', 'Backlog', -580, 'blue');
        final progress = frame('progress', 'In progress', -180, 'amber');
        final done = frame('done', 'Done', 220, 'green');
        return <CanvasObject>[
          backlog,
          progress,
          done,
          sticky(
            'scope',
            'Define project scope',
            -520,
            -150,
            'blue',
            parentFrameId: backlog.id,
          ),
          sticky(
            'next',
            'Next action',
            -120,
            -150,
            'amber',
            parentFrameId: progress.id,
          ),
          sticky(
            'outcome',
            'Completed outcome',
            280,
            -150,
            'green',
            parentFrameId: done.id,
          ),
        ];
      }(),
      CanvasProjectTemplate.kanban => <CanvasObject>[
        frame('todo', 'To do', -580, 'blue'),
        frame('doing', 'Doing', -180, 'amber'),
        frame('done', 'Done', 220, 'green'),
      ],
      CanvasProjectTemplate.brainstorm => <CanvasObject>[
        sticky('question', 'Core question', -120, -90, 'amber'),
        sticky('idea-1', 'Idea 1', -460, -250, 'blue'),
        sticky('idea-2', 'Idea 2', 220, -250, 'green'),
        sticky('idea-3', 'Idea 3', -460, 110, 'rose'),
        sticky('idea-4', 'Idea 4', 220, 110, 'blue'),
      ],
      CanvasProjectTemplate.contentCalendar => <CanvasObject>[
        frame('ideas', 'Ideas', -580, 'blue'),
        frame('scheduled', 'Scheduled', -180, 'amber'),
        frame('published', 'Published', 220, 'green'),
      ],
      CanvasProjectTemplate.weeklyPlanner => <CanvasObject>[
        frame('priorities', 'Priorities', -580, 'rose'),
        frame('week', 'This week', -180, 'blue'),
        frame('later', 'Later', 220, 'amber'),
      ],
      CanvasProjectTemplate.researchBoard => <CanvasObject>[
        frame('questions', 'Questions', -580, 'amber'),
        frame('sources', 'Sources', -180, 'blue'),
        frame('findings', 'Findings', 220, 'green'),
      ],
      CanvasProjectTemplate.moodboard => <CanvasObject>[
        sticky('theme', 'Visual theme', -320, -140, 'rose'),
        sticky('colors', 'Color palette', 0, -140, 'blue'),
        sticky('references', 'References', -160, 100, 'amber'),
      ],
      CanvasProjectTemplate.goalTracker => <CanvasObject>[
        frame('goals', 'Goals', -580, 'blue'),
        frame('milestones', 'Milestones', -180, 'amber'),
        frame('wins', 'Wins', 220, 'green'),
      ],
    };
    return copyWith(
      objects: <CanvasObject>[...objects, ...additions],
      updatedAt: now,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'title': title,
    if (day != null) 'day': dayKey(day!),
    if (workspaceName != null) 'workspaceName': workspaceName,
    if (parentBoardId != null) 'parentBoardId': parentBoardId,
    if (trashedAt != null) 'trashedAt': trashedAt!.toIso8601String(),
    'isArchived': isArchived,
    'viewport': viewport.toJson(),
    'settings': settings.toJson(),
    'votingSession': votingSession.toJson(),
    'workshopSession': workshopSession.toJson(),
    'schemaVersion': schemaVersion,
    'objects': <Map<String, Object?>>[
      for (final object in objects) object.toJson(),
    ],
    'activity': <Map<String, Object?>>[
      for (final item in activity) item.toJson(),
    ],
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasBoard &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.day == day &&
      other.workspaceName == workspaceName &&
      other.parentBoardId == parentBoardId &&
      other.trashedAt == trashedAt &&
      other.isArchived == isArchived &&
      other.viewport == viewport &&
      other.settings == settings &&
      other.votingSession == votingSession &&
      other.workshopSession == workshopSession &&
      other.schemaVersion == schemaVersion &&
      const ListEquality<CanvasObject>().equals(other.objects, objects) &&
      const ListEquality<CanvasActivity>().equals(other.activity, activity) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    kind,
    title,
    day,
    workspaceName,
    parentBoardId,
    trashedAt,
    isArchived,
    viewport,
    settings,
    votingSession,
    workshopSession,
    schemaVersion,
    const ListEquality<CanvasObject>().hash(objects),
    const ListEquality<CanvasActivity>().hash(activity),
    createdAt,
    updatedAt,
  ]);
}

String dailyCanvasBoardId(DateTime day) => 'daily:${dayKey(day)}';

String projectCanvasBoardId(String workspaceName) =>
    'project:${Uri.encodeComponent(workspaceName.trim().toLowerCase())}';

double _finiteDouble(Object? value) {
  final result = value is num ? value.toDouble() : 0.0;
  return result.isFinite ? result : 0.0;
}

double _positiveDouble(Object? value, double fallback) {
  final result = _finiteDouble(value);
  return result > 0 ? result : fallback;
}

DateTime _dateTime(Object? value) =>
    DateTime.tryParse(value as String? ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _optionalDate(Object? value) {
  final parsed = DateTime.tryParse(value as String? ?? '');
  return parsed?.dateOnly;
}

DateTime? _optionalDateTime(Object? value) =>
    DateTime.tryParse(value as String? ?? '');
