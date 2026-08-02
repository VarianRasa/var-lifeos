library;

import 'package:collection/collection.dart';

enum ProjectPlanStatus { planning, active, blocked, completed, archived }

enum ProjectTaskStatus { planned, inProgress, blocked, done }

enum ProjectTaskPriority { none, low, medium, high, urgent }

ProjectPlanStatus _planStatus(Object? value) =>
    ProjectPlanStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ProjectPlanStatus.planning,
    );
ProjectTaskStatus _taskStatus(Object? value) =>
    ProjectTaskStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ProjectTaskStatus.planned,
    );
ProjectTaskPriority _taskPriority(Object? value) =>
    ProjectTaskPriority.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ProjectTaskPriority.none,
    );
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
String _text(Object? value) => value is String ? value.trim() : '';
int? _minutes(Object? value) => value is int && value >= 0 ? value : null;

final class ProjectPlanAttachmentReference {
  const ProjectPlanAttachmentReference({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
  });

  factory ProjectPlanAttachmentReference.fromJson(Map<String, Object?> json) =>
      ProjectPlanAttachmentReference(
        id: _text(json['id']),
        fileName: _text(json['fileName']),
        mimeType: _text(json['mimeType']),
        byteLength: json['byteLength'] is int ? json['byteLength']! as int : 0,
      );

  final String id;
  final String fileName;
  final String mimeType;
  final int byteLength;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fileName': fileName,
    'mimeType': mimeType,
    'byteLength': byteLength,
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectPlanAttachmentReference &&
      other.id == id &&
      other.fileName == fileName &&
      other.mimeType == mimeType &&
      other.byteLength == byteLength;

  @override
  int get hashCode => Object.hash(id, fileName, mimeType, byteLength);
}

final class ProjectTaskChecklistItem {
  const ProjectTaskChecklistItem({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  factory ProjectTaskChecklistItem.fromJson(Map<String, Object?> json) =>
      ProjectTaskChecklistItem(
        id: _text(json['id']),
        title: _text(json['title']),
        isDone: json['isDone'] as bool? ?? false,
      );

  final String id;
  final String title;
  final bool isDone;

  ProjectTaskChecklistItem copyWith({String? title, bool? isDone}) =>
      ProjectTaskChecklistItem(
        id: id,
        title: title ?? this.title,
        isDone: isDone ?? this.isDone,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'isDone': isDone,
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectTaskChecklistItem &&
      other.id == id &&
      other.title == title &&
      other.isDone == isDone;

  @override
  int get hashCode => Object.hash(id, title, isDone);
}

final class ProjectTask {
  const ProjectTask({
    required this.id,
    required this.title,
    required this.order,
    this.description = '',
    this.status = ProjectTaskStatus.planned,
    this.priority = ProjectTaskPriority.none,
    this.deadline,
    this.labels = const <String>[],
    this.checklist = const <ProjectTaskChecklistItem>[],
    this.attachments = const <ProjectPlanAttachmentReference>[],
    this.dependencyTaskIds = const <String>[],
    this.estimatedMinutes,
    this.actualMinutes,
    this.blockingReason = '',
  });

  factory ProjectTask.fromJson(Map<String, Object?> json, int fallbackOrder) {
    final rawChecklist = json['checklist'];
    final rawAttachments = json['attachments'];
    final rawLabels = json['labels'];
    final rawDependencies = json['dependencyTaskIds'];
    return ProjectTask(
      id: _text(json['id']).isEmpty ? 'task-$fallbackOrder' : _text(json['id']),
      title: _text(json['title']),
      order: json['order'] is int ? json['order']! as int : fallbackOrder,
      description: _text(json['description']),
      status: _taskStatus(json['status']),
      priority: _taskPriority(json['priority']),
      deadline: _date(json['deadline']),
      labels: <String>[
        if (rawLabels is List)
          for (final value in rawLabels)
            if (_text(value).isNotEmpty) _text(value),
      ],
      checklist: <ProjectTaskChecklistItem>[
        if (rawChecklist is List)
          for (final value in rawChecklist)
            if (value is Map)
              ProjectTaskChecklistItem.fromJson(value.cast<String, Object?>()),
      ],
      attachments: <ProjectPlanAttachmentReference>[
        if (rawAttachments is List)
          for (final value in rawAttachments)
            if (value is Map)
              ProjectPlanAttachmentReference.fromJson(
                value.cast<String, Object?>(),
              ),
      ],
      dependencyTaskIds: <String>[
        if (rawDependencies is List)
          for (final value in rawDependencies)
            if (_text(value).isNotEmpty) _text(value),
      ],
      estimatedMinutes: _minutes(json['estimatedMinutes']),
      actualMinutes: _minutes(json['actualMinutes']),
      blockingReason: _text(json['blockingReason']),
    );
  }

  final String id;
  final String title;
  final int order;
  final String description;
  final ProjectTaskStatus status;
  final ProjectTaskPriority priority;
  final DateTime? deadline;
  final List<String> labels;
  final List<ProjectTaskChecklistItem> checklist;
  final List<ProjectPlanAttachmentReference> attachments;
  final List<String> dependencyTaskIds;
  final int? estimatedMinutes;
  final int? actualMinutes;
  final String blockingReason;

  List<String> get normalizedDependencyTaskIds => dependencyTaskIds
      .where((value) => value != id)
      .toSet()
      .toList(growable: false);
  int get completedChecklistCount =>
      checklist.where((item) => item.isDone).length;

  ProjectTask copyWith({
    String? id,
    String? title,
    int? order,
    String? description,
    ProjectTaskStatus? status,
    ProjectTaskPriority? priority,
    DateTime? deadline,
    bool clearDeadline = false,
    List<String>? labels,
    List<ProjectTaskChecklistItem>? checklist,
    List<ProjectPlanAttachmentReference>? attachments,
    List<String>? dependencyTaskIds,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    int? actualMinutes,
    bool clearActualMinutes = false,
    String? blockingReason,
  }) => ProjectTask(
    id: id ?? this.id,
    title: title ?? this.title,
    order: order ?? this.order,
    description: description ?? this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    deadline: clearDeadline ? null : deadline ?? this.deadline,
    labels: labels ?? this.labels,
    checklist: checklist ?? this.checklist,
    attachments: attachments ?? this.attachments,
    dependencyTaskIds: dependencyTaskIds ?? this.dependencyTaskIds,
    estimatedMinutes: clearEstimatedMinutes
        ? null
        : estimatedMinutes ?? this.estimatedMinutes,
    actualMinutes: clearActualMinutes
        ? null
        : actualMinutes ?? this.actualMinutes,
    blockingReason: blockingReason ?? this.blockingReason,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'order': order,
    'description': description,
    'status': status.name,
    'priority': priority.name,
    if (deadline != null) 'deadline': deadline!.toIso8601String(),
    'labels': labels,
    'checklist': <Map<String, Object?>>[
      for (final item in checklist) item.toJson(),
    ],
    'attachments': <Map<String, Object?>>[
      for (final item in attachments) item.toJson(),
    ],
    'dependencyTaskIds': normalizedDependencyTaskIds,
    if (estimatedMinutes != null) 'estimatedMinutes': estimatedMinutes,
    if (actualMinutes != null) 'actualMinutes': actualMinutes,
    'blockingReason': blockingReason,
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectTask &&
      other.id == id &&
      other.title == title &&
      other.order == order &&
      other.description == description &&
      other.status == status &&
      other.priority == priority &&
      other.deadline == deadline &&
      const ListEquality<String>().equals(other.labels, labels) &&
      const ListEquality<ProjectTaskChecklistItem>().equals(
        other.checklist,
        checklist,
      ) &&
      const ListEquality<ProjectPlanAttachmentReference>().equals(
        other.attachments,
        attachments,
      ) &&
      const ListEquality<String>().equals(
        other.normalizedDependencyTaskIds,
        normalizedDependencyTaskIds,
      ) &&
      other.estimatedMinutes == estimatedMinutes &&
      other.actualMinutes == actualMinutes &&
      other.blockingReason == blockingReason;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    order,
    description,
    status,
    priority,
    deadline,
    const ListEquality<String>().hash(labels),
    const ListEquality<ProjectTaskChecklistItem>().hash(checklist),
    const ListEquality<ProjectPlanAttachmentReference>().hash(attachments),
    const ListEquality<String>().hash(normalizedDependencyTaskIds),
    estimatedMinutes,
    actualMinutes,
    blockingReason,
  );
}

final class ProjectMilestone {
  const ProjectMilestone({
    required this.id,
    required this.title,
    required this.order,
    this.description = '',
    this.status = ProjectTaskStatus.planned,
    this.deadline,
    this.tasks = const <ProjectTask>[],
  });

  factory ProjectMilestone.fromJson(
    Map<String, Object?> json,
    int fallbackOrder,
  ) {
    final rawTasks = json['tasks'];
    return ProjectMilestone(
      id: _text(json['id']).isEmpty
          ? 'milestone-$fallbackOrder'
          : _text(json['id']),
      title: _text(json['title']),
      order: json['order'] is int ? json['order']! as int : fallbackOrder,
      description: _text(json['description']),
      status: _taskStatus(json['status']),
      deadline: _date(json['deadline']),
      tasks: <ProjectTask>[
        if (rawTasks is List)
          for (var index = 0; index < rawTasks.length; index++)
            if (rawTasks[index] is Map)
              ProjectTask.fromJson(
                (rawTasks[index] as Map).cast<String, Object?>(),
                index,
              ),
      ],
    );
  }

  final String id;
  final String title;
  final int order;
  final String description;
  final ProjectTaskStatus status;
  final DateTime? deadline;
  final List<ProjectTask> tasks;

  int get completedTaskCount =>
      tasks.where((task) => task.status == ProjectTaskStatus.done).length;
  double get progress => tasks.isEmpty ? 0 : completedTaskCount / tasks.length;

  ProjectMilestone copyWith({
    String? title,
    int? order,
    String? description,
    ProjectTaskStatus? status,
    DateTime? deadline,
    bool clearDeadline = false,
    List<ProjectTask>? tasks,
  }) => ProjectMilestone(
    id: id,
    title: title ?? this.title,
    order: order ?? this.order,
    description: description ?? this.description,
    status: status ?? this.status,
    deadline: clearDeadline ? null : deadline ?? this.deadline,
    tasks: tasks ?? this.tasks,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'order': order,
    'description': description,
    'status': status.name,
    if (deadline != null) 'deadline': deadline!.toIso8601String(),
    'tasks': <Map<String, Object?>>[for (final task in tasks) task.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectMilestone &&
      other.id == id &&
      other.title == title &&
      other.order == order &&
      other.description == description &&
      other.status == status &&
      other.deadline == deadline &&
      const ListEquality<ProjectTask>().equals(other.tasks, tasks);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    order,
    description,
    status,
    deadline,
    const ListEquality<ProjectTask>().hash(tasks),
  );
}

final class ProjectPhase {
  const ProjectPhase({
    required this.id,
    required this.title,
    required this.order,
    this.description = '',
    this.status = ProjectTaskStatus.planned,
    this.targetDate,
    this.milestones = const <ProjectMilestone>[],
  });

  factory ProjectPhase.fromJson(Map<String, Object?> json, int fallbackOrder) {
    final rawMilestones = json['milestones'];
    return ProjectPhase(
      id: _text(json['id']).isEmpty
          ? 'phase-$fallbackOrder'
          : _text(json['id']),
      title: _text(json['title']),
      order: json['order'] is int ? json['order']! as int : fallbackOrder,
      description: _text(json['description']),
      status: _taskStatus(json['status']),
      targetDate: _date(json['targetDate']),
      milestones: <ProjectMilestone>[
        if (rawMilestones is List)
          for (var index = 0; index < rawMilestones.length; index++)
            if (rawMilestones[index] is Map)
              ProjectMilestone.fromJson(
                (rawMilestones[index] as Map).cast<String, Object?>(),
                index,
              ),
      ],
    );
  }

  final String id;
  final String title;
  final int order;
  final String description;
  final ProjectTaskStatus status;
  final DateTime? targetDate;
  final List<ProjectMilestone> milestones;

  Iterable<ProjectTask> get tasks sync* {
    for (final milestone in milestones) {
      yield* milestone.tasks;
    }
  }

  int get taskCount => tasks.length;
  int get completedTaskCount =>
      tasks.where((task) => task.status == ProjectTaskStatus.done).length;
  double get progress => taskCount == 0 ? 0 : completedTaskCount / taskCount;

  ProjectPhase copyWith({
    String? title,
    int? order,
    String? description,
    ProjectTaskStatus? status,
    DateTime? targetDate,
    bool clearTargetDate = false,
    List<ProjectMilestone>? milestones,
  }) => ProjectPhase(
    id: id,
    title: title ?? this.title,
    order: order ?? this.order,
    description: description ?? this.description,
    status: status ?? this.status,
    targetDate: clearTargetDate ? null : targetDate ?? this.targetDate,
    milestones: milestones ?? this.milestones,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'order': order,
    'description': description,
    'status': status.name,
    if (targetDate != null) 'targetDate': targetDate!.toIso8601String(),
    'milestones': <Map<String, Object?>>[
      for (final milestone in milestones) milestone.toJson(),
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectPhase &&
      other.id == id &&
      other.title == title &&
      other.order == order &&
      other.description == description &&
      other.status == status &&
      other.targetDate == targetDate &&
      const ListEquality<ProjectMilestone>().equals(
        other.milestones,
        milestones,
      );

  @override
  int get hashCode => Object.hash(
    id,
    title,
    order,
    description,
    status,
    targetDate,
    const ListEquality<ProjectMilestone>().hash(milestones),
  );
}

final class ProjectPlan {
  const ProjectPlan({
    this.status = ProjectPlanStatus.planning,
    this.startDate,
    this.targetDate,
    this.phases = const <ProjectPhase>[],
  });

  factory ProjectPlan.fromJson(Map<String, Object?> json) {
    final rawPhases = json['phases'];
    return ProjectPlan(
      status: _planStatus(json['status']),
      startDate: _date(json['startDate']),
      targetDate: _date(json['targetDate']),
      phases: <ProjectPhase>[
        if (rawPhases is List)
          for (var index = 0; index < rawPhases.length; index++)
            if (rawPhases[index] is Map)
              ProjectPhase.fromJson(
                (rawPhases[index] as Map).cast<String, Object?>(),
                index,
              ),
      ],
    );
  }

  final ProjectPlanStatus status;
  final DateTime? startDate;
  final DateTime? targetDate;
  final List<ProjectPhase> phases;

  Iterable<ProjectMilestone> get milestones sync* {
    for (final phase in phases) {
      yield* phase.milestones;
    }
  }

  Iterable<ProjectTask> get tasks sync* {
    for (final milestone in milestones) {
      yield* milestone.tasks;
    }
  }

  int get milestoneCount => milestones.length;
  int get taskCount => tasks.length;
  int get completedTaskCount =>
      tasks.where((task) => task.status == ProjectTaskStatus.done).length;
  int get blockedTaskCount =>
      tasks.where((task) => task.status == ProjectTaskStatus.blocked).length;
  double get progress => taskCount == 0 ? 0 : completedTaskCount / taskCount;
  ProjectTask? taskById(String id) =>
      tasks.firstWhereOrNull((task) => task.id == id);

  ProjectPlan copyWith({
    ProjectPlanStatus? status,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? targetDate,
    bool clearTargetDate = false,
    List<ProjectPhase>? phases,
  }) => ProjectPlan(
    status: status ?? this.status,
    startDate: clearStartDate ? null : startDate ?? this.startDate,
    targetDate: clearTargetDate ? null : targetDate ?? this.targetDate,
    phases: phases ?? this.phases,
  );

  ProjectPlan movePhase(String phaseId, int targetIndex) {
    final values = [...phases]..sort((a, b) => a.order.compareTo(b.order));
    final source = values.indexWhere((item) => item.id == phaseId);
    if (source < 0) return this;
    final phase = values.removeAt(source);
    values.insert(targetIndex.clamp(0, values.length), phase);
    return copyWith(
      phases: <ProjectPhase>[
        for (var index = 0; index < values.length; index++)
          values[index].copyWith(order: index),
      ],
    );
  }

  ProjectPlan moveMilestone(
    String milestoneId,
    String phaseId,
    int targetIndex,
  ) {
    final moved = milestones.firstWhereOrNull(
      (milestone) => milestone.id == milestoneId,
    );
    if (moved == null || !phases.any((phase) => phase.id == phaseId)) {
      return this;
    }
    final without = <ProjectPhase>[
      for (final phase in phases)
        phase.copyWith(
          milestones: phase.milestones
              .where((milestone) => milestone.id != milestoneId)
              .toList(),
        ),
    ];
    return copyWith(
      phases: <ProjectPhase>[
        for (final phase in without)
          if (phase.id == phaseId)
            phase.copyWith(
              milestones: _insertMilestone(
                phase.milestones,
                moved,
                targetIndex,
              ),
            )
          else
            phase,
      ],
    );
  }

  ProjectPlan moveTask(String taskId, String milestoneId, int targetIndex) {
    final moved = tasks.firstWhereOrNull((task) => task.id == taskId);
    if (moved == null || !milestones.any((item) => item.id == milestoneId)) {
      return this;
    }
    final without = <ProjectPhase>[
      for (final phase in phases)
        phase.copyWith(
          milestones: <ProjectMilestone>[
            for (final milestone in phase.milestones)
              milestone.copyWith(
                tasks: milestone.tasks
                    .where((task) => task.id != taskId)
                    .toList(),
              ),
          ],
        ),
    ];
    return copyWith(
      phases: <ProjectPhase>[
        for (final phase in without)
          phase.copyWith(
            milestones: <ProjectMilestone>[
              for (final milestone in phase.milestones)
                if (milestone.id == milestoneId)
                  milestone.copyWith(
                    tasks: _insertTask(milestone.tasks, moved, targetIndex),
                  )
                else
                  milestone,
            ],
          ),
      ],
    );
  }

  ProjectPlan updateTask(ProjectTask updatedTask) => copyWith(
    phases: <ProjectPhase>[
      for (final phase in phases)
        phase.copyWith(
          milestones: <ProjectMilestone>[
            for (final milestone in phase.milestones)
              milestone.copyWith(
                tasks: <ProjectTask>[
                  for (final task in milestone.tasks)
                    if (task.id == updatedTask.id) updatedTask else task,
                ],
              ),
          ],
        ),
    ],
  );

  ProjectPlan removeTask(String taskId) => copyWith(
    phases: <ProjectPhase>[
      for (final phase in phases)
        phase.copyWith(
          milestones: <ProjectMilestone>[
            for (final milestone in phase.milestones)
              milestone.copyWith(
                tasks: milestone.tasks
                    .where((task) => task.id != taskId)
                    .toList(),
              ),
          ],
        ),
    ],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    if (startDate != null) 'startDate': startDate!.toIso8601String(),
    if (targetDate != null) 'targetDate': targetDate!.toIso8601String(),
    'phases': <Map<String, Object?>>[
      for (final phase in phases) phase.toJson(),
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectPlan &&
      other.status == status &&
      other.startDate == startDate &&
      other.targetDate == targetDate &&
      const ListEquality<ProjectPhase>().equals(other.phases, phases);

  @override
  int get hashCode => Object.hash(
    status,
    startDate,
    targetDate,
    const ListEquality<ProjectPhase>().hash(phases),
  );
}

List<ProjectMilestone> _insertMilestone(
  List<ProjectMilestone> source,
  ProjectMilestone moved,
  int targetIndex,
) {
  final values = source.where((item) => item.id != moved.id).toList();
  values.insert(targetIndex.clamp(0, values.length), moved);
  return <ProjectMilestone>[
    for (var index = 0; index < values.length; index++)
      values[index].copyWith(order: index),
  ];
}

List<ProjectTask> _insertTask(
  List<ProjectTask> source,
  ProjectTask moved,
  int targetIndex,
) {
  final values = source.where((item) => item.id != moved.id).toList();
  values.insert(targetIndex.clamp(0, values.length), moved);
  return <ProjectTask>[
    for (var index = 0; index < values.length; index++)
      values[index].copyWith(order: index),
  ];
}
