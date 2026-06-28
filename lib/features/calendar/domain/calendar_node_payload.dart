/// Additive calendar payloads stored inside `MindmapNode.data`.
library;

enum CalendarNodeKind {
  event('Event'),
  reminder('Reminder'),
  meeting('Meeting'),
  decision('Decision'),
  metric('Metric');

  const CalendarNodeKind(this.label);

  final String label;
}

final class CalendarNodePayload {
  const CalendarNodePayload({
    required this.kind,
    this.value,
    this.unit,
    this.location,
    this.participants,
    this.attendees,
    this.agenda,
    this.decisions,
    this.actions,
    this.options,
    this.selectedOption,
    this.reason,
    this.remindAt,
  });

  final CalendarNodeKind kind;
  final String? value;
  final String? unit;
  final String? location;
  final String? participants;
  final String? attendees;
  final String? agenda;
  final String? decisions;
  final String? actions;
  final String? options;
  final String? selectedOption;
  final String? reason;
  final String? remindAt;

  String get label => kind.label;

  String get subtitle {
    switch (kind) {
      case CalendarNodeKind.metric:
        final v = value?.trim() ?? '';
        final u = unit?.trim() ?? '';
        if (v.isEmpty) return 'Metric';
        return u.isEmpty ? v : '$v $u';
      case CalendarNodeKind.meeting:
        return attendeeCount > 0
            ? 'Meeting · $attendeeCount attendees'
            : 'Meeting';
      case CalendarNodeKind.decision:
        final opt = selectedOption?.trim() ?? '';
        return opt.isNotEmpty ? 'Decision: $opt' : 'Decision';
      case CalendarNodeKind.event:
        final loc = location?.trim() ?? '';
        return loc.isNotEmpty ? 'Event @ $loc' : 'Event';
      case CalendarNodeKind.reminder:
        final at = remindAt?.trim() ?? '';
        return at.isNotEmpty ? 'Reminder @ $at' : 'Reminder';
    }
  }

  int get attendeeCount {
    final a = attendees?.trim() ?? '';
    if (a.isEmpty) return 0;
    return a.split('\n').where((l) => l.trim().isNotEmpty).length;
  }

  Map<String, Object?> toJson() {
    final map = <String, Object?>{'calendar_kind': kind.name};
    if (value != null && value!.trim().isNotEmpty) map['value'] = value!.trim();
    if (unit != null && unit!.trim().isNotEmpty) map['unit'] = unit!.trim();
    if (location != null && location!.trim().isNotEmpty) {
      map['location'] = location!.trim();
    }
    if (participants != null && participants!.trim().isNotEmpty) {
      map['participants'] = participants!.trim();
    }
    if (attendees != null && attendees!.trim().isNotEmpty) {
      map['attendees'] = attendees!.trim();
    }
    if (agenda != null && agenda!.trim().isNotEmpty) {
      map['agenda'] = agenda!.trim();
    }
    if (decisions != null && decisions!.trim().isNotEmpty) {
      map['decisions'] = decisions!.trim();
    }
    if (actions != null && actions!.trim().isNotEmpty) {
      map['actions'] = actions!.trim();
    }
    if (options != null && options!.trim().isNotEmpty) {
      map['options'] = options!.trim();
    }
    if (selectedOption != null && selectedOption!.trim().isNotEmpty) {
      map['selectedOption'] = selectedOption!.trim();
    }
    if (reason != null && reason!.trim().isNotEmpty) {
      map['reason'] = reason!.trim();
    }
    if (remindAt != null && remindAt!.trim().isNotEmpty) {
      map['remindAt'] = remindAt!.trim();
    }
    return map;
  }
}

CalendarNodePayload? calendarNodePayloadFromData(Map<String, Object?> data) {
  final raw = data['calendar_kind'] ?? data['calendarKind'];
  if (raw is! String) return null;

  final kind = _kindFromString(raw);
  if (kind == null) return null;

  // Metric values may come from a nested map or flat keys.
  String? value;
  String? unit;
  final metricRaw = data['metric'];
  if (metricRaw is Map) {
    final metricMap = metricRaw.cast<String, Object?>();
    value = metricMap['value']?.toString();
    unit = metricMap['unit']?.toString();
  }
  value ??= data['value']?.toString();
  unit ??= data['unit']?.toString();

  return CalendarNodePayload(
    kind: kind,
    value: value,
    unit: unit,
    location: data['location']?.toString(),
    participants: data['participants']?.toString(),
    attendees: data['attendees']?.toString(),
    agenda: data['agenda']?.toString(),
    decisions: data['decisions']?.toString(),
    actions: data['actions']?.toString(),
    options: data['options']?.toString(),
    selectedOption: data['selectedOption']?.toString(),
    reason: data['reason']?.toString(),
    remindAt: data['remindAt']?.toString(),
  );
}

CalendarNodeKind? _kindFromString(String raw) {
  final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
  for (final kind in CalendarNodeKind.values) {
    if (kind.name == normalized) return kind;
  }
  return null;
}
