/// Search-bar command parsing for fast node capture.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../../calendar/domain/time_block.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_node_data.dart';

final class QuickCreateCommand {
  const QuickCreateCommand({
    required this.type,
    required this.title,
    required this.day,
    required this.status,
    required this.priority,
    required this.tags,
    required this.project,
    required this.area,
    this.body = '',
    this.data = const {},
    this.calendarPayload,
    this.timeBlock,
    this.dueDate,
    this.progress = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.checklistTitles = const [],
    this.relatedNodeIds = const [],
  });

  final NodeType type;
  final String title;
  final String body;
  final DateTime day;
  final NodeStatus status;
  final NodePriority priority;
  final List<String> tags;
  final String project;
  final String area;
  final Map<String, Object?> data;
  final CalendarNodePayload? calendarPayload;
  final TimeBlock? timeBlock;
  final DateTime? dueDate;
  final double progress;
  final bool isPinned;
  final bool isArchived;
  final List<String> checklistTitles;
  final List<String> relatedNodeIds;

  String get label => 'Create ${calendarPayload?.label ?? type.label}: $title';
}

QuickCreateCommand? quickCreateCommandFromQuery(
  String query, {
  required DateTime today,
  required DateTime defaultDay,
}) {
  final tokens = query.trim().split(RegExp(r'\s+'));
  if (tokens.isEmpty || tokens.first.isEmpty) return null;

  final type = _typeFromToken(tokens.first);
  if (type == null) return null;

  final calendarKind = _calendarKindFromToken(tokens.first);
  final titleTokens = <String>[];
  final tags = <String>[];
  var day = defaultDay.dateOnly;
  DateTime? dueDate;
  var status = NodeStatus.open;
  var priority = NodePriority.none;
  var project = '';
  var area = '';
  var progress = 0.0;
  var isPinned = false;
  var isArchived = false;
  final checklistTitles = <String>[];
  final relatedNodeIds = <String>[];
  String? agenda;
  String? attendees;
  String? location;
  String? metricValue;
  String? metricUnit;
  String? reason;
  String? selectedOption;
  final decisionOptions = <String>[];
  int? startMinute;
  int? endMinute;

  for (var index = 1; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.isEmpty) continue;

    switch (token.trim().toLowerCase()) {
      case 'pin':
      case 'pinned':
        isPinned = true;
        continue;
      case 'archive':
      case 'archived':
        isArchived = true;
        continue;
    }

    if (token.startsWith('#')) {
      final tag = _normalizeTag(token.substring(1));
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
      continue;
    }

    if (token.startsWith('!')) {
      final parsedPriority = _priorityFromToken(token.substring(1));
      if (parsedPriority == null) return null;
      priority = parsedPriority;
      continue;
    }

    final modifier = _modifierFromToken(token);
    if (modifier != null) {
      final key = modifier.key;
      final value = modifier.value;
      switch (key) {
        case 'due':
          final parsedDueDate = _parseDateAlias(value, today: today);
          if (parsedDueDate == null) return null;
          dueDate = parsedDueDate;
        case 'on':
        case 'date':
        case 'day':
          final parsedDay = _parseDateAlias(value, today: today);
          if (parsedDay == null) return null;
          day = parsedDay;
        case 'status':
        case 's':
          final parsedStatus = _statusFromToken(value);
          if (parsedStatus == null) return null;
          status = parsedStatus;
        case 'priority':
        case 'p':
          final parsedPriority = _priorityFromToken(value);
          if (parsedPriority == null) return null;
          priority = parsedPriority;
        case 'project':
        case 'proj':
          project = _contextFromToken(value);
        case 'area':
          area = _contextFromToken(value);
        case 'progress':
        case 'prog':
          final parsedProgress = _progressFromToken(value);
          if (parsedProgress == null) return null;
          progress = parsedProgress;
        case 'check':
        case 'checklist':
        case 'todo':
          final items = _checklistTitlesFromToken(value);
          if (items.isEmpty) return null;
          for (final item in items) {
            if (!checklistTitles.contains(item)) checklistTitles.add(item);
          }
        case 'rel':
        case 'rels':
        case 'related':
        case 'link':
        case 'links':
          final nodeIds = _nodeIdsFromToken(value);
          if (nodeIds.isEmpty) return null;
          for (final nodeId in nodeIds) {
            if (!relatedNodeIds.contains(nodeId)) relatedNodeIds.add(nodeId);
          }
        case 'time':
        case 'at':
        case 'start':
        case 'from':
        case 'jam':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          final parsedTime = _minuteFromClockText(value, allowHourOnly: true);
          if (parsedTime == null) return null;
          startMinute = parsedTime;
        case 'end':
        case 'to':
        case 'until':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          final parsedTime = _minuteFromClockText(value, allowHourOnly: true);
          if (parsedTime == null) return null;
          endMinute = parsedTime;
        case 'loc':
        case 'location':
        case 'where':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          location = _contextFromToken(value);
        case 'with':
        case 'attendee':
        case 'attendees':
        case 'participant':
        case 'participants':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          attendees = _attendeesFromText(value);
        case 'agenda':
        case 'about':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          agenda = _contextFromToken(value);
        case 'value':
        case 'val':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          metricValue = _metricValueFromToken(value);
          if (metricValue == null) return null;
        case 'unit':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          metricUnit = _cleanToken(value);
        case 'option':
        case 'options':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          decisionOptions.addAll(_linesFromDelimitedText(value));
        case 'selected':
        case 'choice':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          selectedOption = _contextFromToken(value);
        case 'reason':
        case 'because':
          if (calendarKind == null) {
            titleTokens.add(token);
            continue;
          }
          reason = _contextFromToken(value);
        default:
          titleTokens.add(token);
      }
      continue;
    }

    if (calendarKind != null) {
      final parsedDate = _naturalDateFromTokens(tokens, index, today: today);
      if (parsedDate != null) {
        if (parsedDate.isInvalid) return null;
        day = parsedDate.date!;
        index += parsedDate.consumed - 1;
        continue;
      }

      final parsedTime = _naturalTimeFromTokens(tokens, index);
      if (parsedTime != null) {
        if (parsedTime.isInvalid) return null;
        startMinute = parsedTime.minute;
        index += parsedTime.consumed - 1;
        continue;
      }

      if (token.startsWith('@')) {
        final parsedLocation = _contextFromToken(token.substring(1));
        if (parsedLocation.isNotEmpty) location = parsedLocation;
        continue;
      }

      if (calendarKind == CalendarNodeKind.meeting &&
          token.trim().toLowerCase() == 'with') {
        final phrase = _collectPhrase(tokens, index + 1, today: today);
        if (phrase.text.isEmpty) return null;
        attendees = _attendeesFromText(phrase.text);
        index = phrase.nextIndex - 1;
        continue;
      }

      if (calendarKind == CalendarNodeKind.metric && metricValue == null) {
        final parsedValue = _metricValueFromToken(token);
        if (parsedValue != null) {
          metricValue = parsedValue;
          final nextIndex = index + 1;
          if (nextIndex < tokens.length &&
              !_isCalendarBoundaryToken(tokens, nextIndex, today: today)) {
            metricUnit = _cleanToken(tokens[nextIndex]);
            index = nextIndex;
          }
          continue;
        }
      }
    }

    titleTokens.add(token);
  }

  var title = _titleFromTokens(titleTokens);
  var body = '';
  CalendarNodePayload? calendarPayload;
  TimeBlock? timeBlock;
  var data = const <String, Object?>{};

  if (calendarKind != null) {
    if (calendarKind == CalendarNodeKind.decision) {
      final decisionParts = _decisionPartsFromTitleTokens(titleTokens);
      title = decisionParts.title;
      for (final option in decisionParts.options) {
        if (!decisionOptions.contains(option)) decisionOptions.add(option);
      }
    }

    if (title.isEmpty) return null;

    timeBlock = _timeBlockFromMinutes(
      startMinute: startMinute,
      endMinute: endMinute,
      kind: calendarKind,
    );
    if (startMinute != null && endMinute != null && timeBlock == null) {
      return null;
    }

    final startTimeLabel = startMinute == null
        ? null
        : formatTimeOfDay(startMinute);
    final optionsText = decisionOptions.isEmpty
        ? null
        : decisionOptions.join('\n');

    calendarPayload = switch (calendarKind) {
      CalendarNodeKind.meeting => CalendarNodePayload(
        kind: calendarKind,
        attendees: attendees,
        agenda: agenda ?? title,
      ),
      CalendarNodeKind.reminder => CalendarNodePayload(
        kind: calendarKind,
        remindAt: startTimeLabel,
      ),
      CalendarNodeKind.event => CalendarNodePayload(
        kind: calendarKind,
        location: location,
      ),
      CalendarNodeKind.metric => CalendarNodePayload(
        kind: calendarKind,
        value: metricValue,
        unit: metricUnit,
      ),
      CalendarNodeKind.decision => CalendarNodePayload(
        kind: calendarKind,
        options: optionsText,
        selectedOption: selectedOption,
        reason: reason,
      ),
    };

    body = switch (calendarKind) {
      CalendarNodeKind.meeting => agenda ?? title,
      CalendarNodeKind.decision => optionsText ?? '',
      _ => '',
    };

    data = dataWithCalendarSchedule(
      data: const {},
      payload: calendarPayload,
      timeBlock: timeBlock,
    );
  }

  if (title.isEmpty) return null;

  return QuickCreateCommand(
    type: type,
    title: title,
    body: body,
    day: day,
    status: status,
    priority: priority,
    tags: List.unmodifiable(tags),
    project: project,
    area: area,
    data: Map.unmodifiable(data),
    calendarPayload: calendarPayload,
    timeBlock: timeBlock,
    dueDate: dueDate,
    progress: progress,
    isPinned: isPinned,
    isArchived: isArchived,
    checklistTitles: List.unmodifiable(checklistTitles),
    relatedNodeIds: List.unmodifiable(relatedNodeIds),
  );
}

NodeType? _typeFromToken(String token) {
  return switch (token.trim().toLowerCase()) {
    'task' || 'todo' => NodeType.task,
    'kanban' || 'board' => NodeType.kanban,
    'plan' => NodeType.plan,
    'note' => NodeType.note,
    'journal' => NodeType.journal,
    'habit' => NodeType.habit,
    'goal' => NodeType.goal,
    'link' => NodeType.link,
    'event' => NodeType.task,
    'reminder' || 'remind' => NodeType.task,
    'meeting' => NodeType.note,
    'metric' => NodeType.task,
    'decision' => NodeType.note,
    _ => null,
  };
}

CalendarNodeKind? _calendarKindFromToken(String token) {
  return switch (token.trim().toLowerCase()) {
    'event' => CalendarNodeKind.event,
    'reminder' || 'remind' => CalendarNodeKind.reminder,
    'meeting' => CalendarNodeKind.meeting,
    'metric' => CalendarNodeKind.metric,
    'decision' => CalendarNodeKind.decision,
    _ => null,
  };
}

NodeStatus? _statusFromToken(String token) {
  final value = token.trim().toLowerCase();
  for (final status in NodeStatus.values) {
    if (status.name == value) return status;
  }
  return null;
}

NodePriority? _priorityFromToken(String token) {
  final value = token.trim().toLowerCase();
  for (final priority in NodePriority.values) {
    if (priority.name == value) return priority;
  }
  return null;
}

DateTime? _parseDateAlias(String value, {required DateTime today}) {
  final normalized = _cleanToken(value).toLowerCase();
  if (normalized.isEmpty) return null;

  final normalizedToday = today.dateOnly;
  return switch (normalized) {
    'today' || 'hari-ini' || 'hari_ini' || 'hariini' => normalizedToday,
    'tomorrow' || 'besok' => normalizedToday.addDays(1),
    'yesterday' || 'kemarin' => normalizedToday.addDays(-1),
    _ => _parseStrictDayKey(normalized),
  };
}

_NaturalDateResult? _naturalDateFromTokens(
  List<String> tokens,
  int index, {
  required DateTime today,
}) {
  final token = _cleanToken(tokens[index]).toLowerCase();
  if (token.isEmpty) return null;

  if (token == 'hari') {
    final nextIndex = index + 1;
    if (nextIndex >= tokens.length) return null;
    final next = _cleanToken(tokens[nextIndex]).toLowerCase();
    if (next == 'ini') {
      return _NaturalDateResult.valid(today.dateOnly, consumed: 2);
    }
    return null;
  }

  if (token == 'tanggal') {
    final nextIndex = index + 1;
    if (nextIndex >= tokens.length) return const _NaturalDateResult.invalid();
    final dayOfMonth = _dayOfMonthFromToken(tokens[nextIndex]);
    if (dayOfMonth == null) return const _NaturalDateResult.invalid();
    final date = _upcomingDayOfMonth(dayOfMonth, today: today);
    if (date == null) return const _NaturalDateResult.invalid();
    return _NaturalDateResult.valid(date, consumed: 2);
  }

  final parsed = _parseDateAlias(token, today: today);
  if (parsed != null) return _NaturalDateResult.valid(parsed);
  if (_looksLikeStrictDate(token)) return const _NaturalDateResult.invalid();
  return null;
}

_NaturalTimeResult? _naturalTimeFromTokens(List<String> tokens, int index) {
  final token = _cleanToken(tokens[index]).toLowerCase();
  if (token.isEmpty) return null;

  if (token == 'jam' || token == 'at') {
    final nextIndex = index + 1;
    if (nextIndex >= tokens.length) return const _NaturalTimeResult.invalid();
    final minute = _minuteFromClockText(tokens[nextIndex], allowHourOnly: true);
    if (minute == null) return const _NaturalTimeResult.invalid();
    return _NaturalTimeResult.valid(minute, consumed: 2);
  }

  if (_looksLikeClockText(token)) {
    final minute = _minuteFromClockText(token);
    if (minute == null) return const _NaturalTimeResult.invalid();
    return _NaturalTimeResult.valid(minute);
  }

  return null;
}

DateTime? _parseStrictDayKey(String value) {
  if (!_looksLikeStrictDate(value)) return null;

  final parsed = DateTime.tryParse(value)?.dateOnly;
  if (parsed == null || dayKey(parsed) != value) return null;
  return parsed;
}

bool _looksLikeStrictDate(String value) {
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
}

DateTime? _upcomingDayOfMonth(int dayOfMonth, {required DateTime today}) {
  final normalizedToday = today.dateOnly;
  final thisMonth = _dateInMonth(today.year, today.month, dayOfMonth);
  if (thisMonth != null && !thisMonth.isBefore(normalizedToday)) {
    return thisMonth;
  }
  return _dateInMonth(today.year, today.month + 1, dayOfMonth);
}

DateTime? _dateInMonth(int year, int month, int dayOfMonth) {
  if (dayOfMonth < 1 || dayOfMonth > 31) return null;
  final firstOfTargetMonth = DateTime(year, month);
  final date = DateTime(
    firstOfTargetMonth.year,
    firstOfTargetMonth.month,
    dayOfMonth,
  ).dateOnly;
  if (date.month != firstOfTargetMonth.month || date.day != dayOfMonth) {
    return null;
  }
  return date;
}

int? _dayOfMonthFromToken(String token) {
  final match = RegExp(
    r'^(\d{1,2})(?:st|nd|rd|th)?$',
  ).firstMatch(_cleanToken(token).toLowerCase());
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

_CommandModifier? _modifierFromToken(String token) {
  final separator = token.indexOf(':');
  if (separator <= 0 || separator == token.length - 1) return null;

  final key = token.substring(0, separator).trim().toLowerCase();
  if (!RegExp(r'^[a-z_]+$').hasMatch(key)) return null;

  return _CommandModifier(
    key: key,
    value: token.substring(separator + 1).trim(),
  );
}

String _normalizeTag(String value) {
  return value.trim().toLowerCase().replaceFirst(RegExp('^#+'), '');
}

String _contextFromToken(String value) {
  return value.trim().replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
}

String _titleFromTokens(List<String> tokens) {
  return _contextFromToken(tokens.join(' '));
}

String _cleanToken(String value) {
  return value.trim().replaceAll(RegExp(r'^[,;]+|[,;.]+$'), '');
}

double? _progressFromToken(String value) {
  final normalized = value.trim().replaceFirst(RegExp(r'%$'), '');
  if (normalized.isEmpty) return null;

  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed.isNaN || parsed < 0) return null;
  if (parsed <= 1) return parsed;
  if (parsed <= 100) return parsed / 100;
  return null;
}

List<String> _checklistTitlesFromToken(String value) {
  final titles = <String>[];
  final seen = <String>{};
  for (final rawItem in value.split('|')) {
    final title = _contextFromToken(rawItem);
    if (title.isEmpty) continue;
    final key = title.toLowerCase();
    if (!seen.add(key)) continue;
    titles.add(title);
  }
  return titles;
}

List<String> _nodeIdsFromToken(String value) {
  final nodeIds = <String>[];
  final seen = <String>{};
  for (final rawNodeId in value.split(RegExp(r'[|,]'))) {
    final nodeId = rawNodeId.trim();
    if (nodeId.isEmpty || !seen.add(nodeId)) continue;
    nodeIds.add(nodeId);
  }
  return nodeIds;
}

int? _minuteFromClockText(String value, {bool allowHourOnly = false}) {
  final normalized = _cleanToken(value);
  final clockMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalized);
  if (clockMatch != null) {
    final hour = int.tryParse(clockMatch.group(1)!);
    final minute = int.tryParse(clockMatch.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  if (!allowHourOnly) return null;
  final hour = int.tryParse(normalized);
  if (hour == null || hour < 0 || hour > 23) return null;
  return hour * 60;
}

bool _looksLikeClockText(String value) {
  return RegExp(r'^\d{1,2}:\d{2}$').hasMatch(_cleanToken(value));
}

TimeBlock? _timeBlockFromMinutes({
  required int? startMinute,
  required int? endMinute,
  required CalendarNodeKind kind,
}) {
  if (startMinute == null) return null;
  final fallbackDuration = kind == CalendarNodeKind.reminder ? 15 : 60;
  final resolvedEndMinute = endMinute ?? startMinute + fallbackDuration;
  if (resolvedEndMinute <= startMinute || resolvedEndMinute > 1440) return null;
  return TimeBlock(startMinute: startMinute, endMinute: resolvedEndMinute);
}

_PhraseResult _collectPhrase(
  List<String> tokens,
  int startIndex, {
  required DateTime today,
}) {
  final phraseTokens = <String>[];
  var index = startIndex;
  while (index < tokens.length &&
      !_isCalendarBoundaryToken(tokens, index, today: today)) {
    phraseTokens.add(tokens[index]);
    index++;
  }
  return _PhraseResult(text: _titleFromTokens(phraseTokens), nextIndex: index);
}

bool _isCalendarBoundaryToken(
  List<String> tokens,
  int index, {
  required DateTime today,
}) {
  final token = tokens[index];
  final normalized = _cleanToken(token).toLowerCase();
  if (normalized.isEmpty) return true;
  if (token.startsWith('#') || token.startsWith('!') || token.startsWith('@')) {
    return true;
  }
  if (_knownModifierKey(_modifierFromToken(token)?.key)) return true;
  if (normalized == 'with' || normalized == 'vs' || normalized == 'versus') {
    return true;
  }
  if (_naturalDateFromTokens(tokens, index, today: today) != null) return true;
  if (_naturalTimeFromTokens(tokens, index) != null) return true;
  return false;
}

bool _knownModifierKey(String? key) {
  return switch (key) {
    'due' ||
    'on' ||
    'date' ||
    'day' ||
    'status' ||
    's' ||
    'priority' ||
    'p' ||
    'project' ||
    'proj' ||
    'area' ||
    'progress' ||
    'prog' ||
    'check' ||
    'checklist' ||
    'todo' ||
    'rel' ||
    'rels' ||
    'related' ||
    'link' ||
    'links' ||
    'time' ||
    'at' ||
    'start' ||
    'from' ||
    'jam' ||
    'end' ||
    'to' ||
    'until' ||
    'loc' ||
    'location' ||
    'where' ||
    'with' ||
    'attendee' ||
    'attendees' ||
    'participant' ||
    'participants' ||
    'agenda' ||
    'about' ||
    'value' ||
    'val' ||
    'unit' ||
    'option' ||
    'options' ||
    'selected' ||
    'choice' ||
    'reason' ||
    'because' => true,
    _ => false,
  };
}

String? _attendeesFromText(String value) {
  final attendees = _linesFromDelimitedText(value);
  if (attendees.isEmpty) return null;
  return attendees.join('\n');
}

List<String> _linesFromDelimitedText(String value) {
  final items = <String>[];
  final seen = <String>{};
  for (final rawItem in value.split(RegExp(r'[,|]'))) {
    final item = _contextFromToken(_cleanToken(rawItem));
    if (item.isEmpty) continue;
    final key = item.toLowerCase();
    if (!seen.add(key)) continue;
    items.add(item);
  }
  return items;
}

String? _metricValueFromToken(String token) {
  final normalized = _cleanToken(token).replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) return null;
  return normalized;
}

_DecisionParts _decisionPartsFromTitleTokens(List<String> tokens) {
  final vsIndex = tokens.indexWhere((token) {
    final normalized = _cleanToken(token).toLowerCase();
    return normalized == 'vs' || normalized == 'versus';
  });
  if (vsIndex <= 0 || vsIndex >= tokens.length - 1) {
    return _DecisionParts(title: _titleFromTokens(tokens));
  }

  final colonIndex = tokens
      .sublist(0, vsIndex)
      .lastIndexWhere((token) => _cleanToken(token).endsWith(':'));
  if (colonIndex < 0) {
    final leftOption = _titleFromTokens(tokens.sublist(0, vsIndex));
    final rightOption = _titleFromTokens(tokens.sublist(vsIndex + 1));
    return _DecisionParts(
      title: _titleFromTokens(tokens),
      options: [
        if (leftOption.isNotEmpty) leftOption,
        if (rightOption.isNotEmpty) rightOption,
      ],
    );
  }

  final titleTokens = [...tokens.sublist(0, colonIndex + 1)];
  titleTokens[titleTokens.length - 1] = _trimTrailingColon(titleTokens.last);
  final leftOption = _titleFromTokens(tokens.sublist(colonIndex + 1, vsIndex));
  final rightOption = _titleFromTokens(tokens.sublist(vsIndex + 1));
  return _DecisionParts(
    title: _titleFromTokens(titleTokens),
    options: [
      if (leftOption.isNotEmpty) leftOption,
      if (rightOption.isNotEmpty) rightOption,
    ],
  );
}

String _trimTrailingColon(String value) {
  return value.trim().replaceFirst(RegExp(r':$'), '');
}

final class _CommandModifier {
  const _CommandModifier({required this.key, required this.value});

  final String key;
  final String value;
}

final class _NaturalDateResult {
  const _NaturalDateResult.valid(this.date, {this.consumed = 1})
    : isInvalid = false;

  const _NaturalDateResult.invalid()
    : date = null,
      consumed = 1,
      isInvalid = true;

  final DateTime? date;
  final int consumed;
  final bool isInvalid;
}

final class _NaturalTimeResult {
  const _NaturalTimeResult.valid(this.minute, {this.consumed = 1})
    : isInvalid = false;

  const _NaturalTimeResult.invalid()
    : minute = null,
      consumed = 1,
      isInvalid = true;

  final int? minute;
  final int consumed;
  final bool isInvalid;
}

final class _PhraseResult {
  const _PhraseResult({required this.text, required this.nextIndex});

  final String text;
  final int nextIndex;
}

final class _DecisionParts {
  const _DecisionParts({required this.title, this.options = const []});

  final String title;
  final List<String> options;
}
