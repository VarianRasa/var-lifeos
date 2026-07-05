/// Metadata-aware node index query parsing for the global command palette.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class CommandNodeQuery {
  const CommandNodeQuery({
    required this.searchText,
    this.type,
    this.status,
    this.priority,
    this.project = '',
    this.area = '',
    this.tags = const [],
    this.relatedNodeIds = const [],
    this.day,
    this.dueDate,
  });

  final String searchText;
  final NodeType? type;
  final NodeStatus? status;
  final NodePriority? priority;
  final String project;
  final String area;
  final List<String> tags;
  final List<String> relatedNodeIds;
  final DateTime? day;
  final DateTime? dueDate;

  bool get hasFilters {
    return type != null ||
        status != null ||
        priority != null ||
        project.isNotEmpty ||
        area.isNotEmpty ||
        tags.isNotEmpty ||
        relatedNodeIds.isNotEmpty ||
        day != null ||
        dueDate != null;
  }

  bool get isEmpty => searchText.isEmpty && !hasFilters;

  bool matches(MindmapNode node) {
    if (type != null && node.type != type) return false;
    if (status != null && node.status != status) return false;
    if (priority != null && node.priority != priority) return false;
    if (project.isNotEmpty && !_sameLabel(node.project, project)) return false;
    if (area.isNotEmpty && !_sameLabel(node.area, area)) return false;
    if (day != null && !node.day.isSameDay(day!)) return false;
    if (dueDate != null && !(node.dueDate?.isSameDay(dueDate!) ?? false)) {
      return false;
    }
    for (final tag in tags) {
      if (!node.tags.contains(tag)) return false;
    }
    for (final nodeId in relatedNodeIds) {
      if (!node.relatedNodeIds.contains(nodeId)) return false;
    }
    if (searchText.isEmpty) return true;
    return _matchesSearchText(node, searchText);
  }
}

CommandNodeQuery commandNodeQueryFromText(
  String value, {
  required DateTime today,
}) {
  final searchTokens = <String>[];
  final tags = <String>[];
  final relatedNodeIds = <String>[];
  NodeType? type;
  NodeStatus? status;
  NodePriority? priority;
  var project = '';
  var area = '';
  DateTime? day;
  DateTime? dueDate;

  for (final token in value.trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;

    if (token.startsWith('#')) {
      final tag = _normalizeTag(token.substring(1));
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
      continue;
    }

    if (token.startsWith('!')) {
      final parsedPriority = _priorityFromText(token.substring(1));
      if (parsedPriority != null) {
        priority = parsedPriority;
        continue;
      }
    }

    final modifier = _modifierFromToken(token);
    if (modifier == null) {
      searchTokens.add(token);
      continue;
    }

    switch (modifier.key) {
      case 'type':
      case 't':
        final parsedType = _typeFromText(modifier.value);
        if (parsedType == null) {
          searchTokens.add(token);
        } else {
          type = parsedType;
        }
      case 'status':
      case 's':
        final parsedStatus = _statusFromText(modifier.value);
        if (parsedStatus == null) {
          searchTokens.add(token);
        } else {
          status = parsedStatus;
        }
      case 'priority':
      case 'p':
        final parsedPriority = _priorityFromText(modifier.value);
        if (parsedPriority == null) {
          searchTokens.add(token);
        } else {
          priority = parsedPriority;
        }
      case 'project':
      case 'proj':
        project = _contextFromText(modifier.value);
      case 'area':
        area = _contextFromText(modifier.value);
      case 'day':
      case 'date':
      case 'on':
        final parsedDay = _dateFromText(modifier.value, today: today);
        if (parsedDay == null) {
          searchTokens.add(token);
        } else {
          day = parsedDay;
        }
      case 'due':
        final parsedDueDate = _dateFromText(modifier.value, today: today);
        if (parsedDueDate == null) {
          searchTokens.add(token);
        } else {
          dueDate = parsedDueDate;
        }
      case 'rel':
      case 'rels':
      case 'related':
      case 'link':
      case 'links':
        final nodeIds = _nodeIdsFromText(modifier.value);
        if (nodeIds.isEmpty) {
          searchTokens.add(token);
        } else {
          for (final nodeId in nodeIds) {
            if (!relatedNodeIds.contains(nodeId)) relatedNodeIds.add(nodeId);
          }
        }
      default:
        searchTokens.add(token);
    }
  }

  return CommandNodeQuery(
    searchText: searchTokens.join(' ').trim(),
    type: type,
    status: status,
    priority: priority,
    project: project,
    area: area,
    tags: List.unmodifiable(tags),
    relatedNodeIds: List.unmodifiable(relatedNodeIds),
    day: day,
    dueDate: dueDate,
  );
}

bool _matchesSearchText(MindmapNode node, String searchText) {
  final query = searchText.trim().toLowerCase();
  if (query.isEmpty) return true;
  final values = [
    node.title,
    node.body,
    node.type.label,
    node.status.label,
    node.priority.label,
    node.project,
    node.area,
    dayKey(node.day),
    if (node.dueDate != null) dayKey(node.dueDate!),
    for (final tag in node.tags) tag,
    for (final nodeId in node.relatedNodeIds) nodeId,
    ..._dataSearchValues(node.data),
  ];
  final tokens = query.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
  return tokens.every(
    (token) =>
        values.any((value) => _fuzzyContains(value.toLowerCase(), token)),
  );
}

bool _fuzzyContains(String value, String query) {
  if (value.contains(query)) return true;
  if (query.length < 4) return false;
  final words = value
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty);
  for (final word in words) {
    if (_isSubsequence(query, word)) return true;
    final maxDistance = query.length <= 6 ? 1 : 2;
    if ((word.length - query.length).abs() <= maxDistance &&
        _editDistanceAtMost(word, query, maxDistance)) {
      return true;
    }
  }
  return false;
}

bool _isSubsequence(String query, String value) {
  if (query.length > value.length || query.length < 4) return false;
  var index = 0;
  for (final unit in value.codeUnits) {
    if (unit == query.codeUnitAt(index)) index++;
    if (index == query.length) return true;
  }
  return false;
}

bool _editDistanceAtMost(String a, String b, int maxDistance) {
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, i);
    var rowMin = current.first;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = [
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + cost,
      ].reduce((min, value) => value < min ? value : min);
      if (current[j] < rowMin) rowMin = current[j];
    }
    if (rowMin > maxDistance) return false;
    previous = current;
  }
  return previous.last <= maxDistance;
}

List<String> _dataSearchValues(Map<String, Object?> data) {
  final values = <String>[];
  void collect(Object? value) {
    switch (value) {
      case String():
        values.add(value);
      case num() || bool():
        values.add('$value');
      case Map<Object?, Object?>():
        for (final entry in value.entries) {
          collect(entry.key);
          collect(entry.value);
        }
      case Iterable<Object?>():
        for (final item in value) {
          collect(item);
        }
      case null:
        break;
      default:
        values.add(value.toString());
    }
  }

  collect(data);
  return values;
}

NodeType? _typeFromText(String value) {
  final normalized = value.trim().toLowerCase();
  for (final type in NodeType.values) {
    if (type.name == normalized || type.label.toLowerCase() == normalized) {
      return type;
    }
  }
  return null;
}

NodeStatus? _statusFromText(String value) {
  final normalized = value.trim().toLowerCase();
  for (final status in NodeStatus.values) {
    if (status.name == normalized || status.label.toLowerCase() == normalized) {
      return status;
    }
  }
  return null;
}

NodePriority? _priorityFromText(String value) {
  final normalized = value.trim().toLowerCase();
  for (final priority in NodePriority.values) {
    if (priority.name == normalized ||
        priority.label.toLowerCase() == normalized) {
      return priority;
    }
  }
  return null;
}

DateTime? _dateFromText(String value, {required DateTime today}) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return null;

  final normalizedToday = today.dateOnly;
  return switch (normalized) {
    'today' || 'hari-ini' || 'hari_ini' || 'hariini' => normalizedToday,
    'tomorrow' || 'besok' => normalizedToday.addDays(1),
    'yesterday' || 'kemarin' => normalizedToday.addDays(-1),
    _ => _parseStrictDayKey(normalized),
  };
}

DateTime? _parseStrictDayKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;

  final parsed = DateTime.tryParse(value)?.dateOnly;
  if (parsed == null || dayKey(parsed) != value) return null;
  return parsed;
}

_CommandQueryModifier? _modifierFromToken(String token) {
  final separator = token.indexOf(':');
  if (separator <= 0 || separator == token.length - 1) return null;

  return _CommandQueryModifier(
    key: token.substring(0, separator).trim().toLowerCase(),
    value: token.substring(separator + 1).trim(),
  );
}

String _normalizeTag(String value) {
  return value.trim().toLowerCase().replaceFirst(RegExp('^#+'), '');
}

String _contextFromText(String value) {
  return value.trim().replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
}

List<String> _nodeIdsFromText(String value) {
  final nodeIds = <String>[];
  final seen = <String>{};
  for (final rawNodeId in value.split(RegExp(r'[|,]'))) {
    final nodeId = rawNodeId.trim();
    if (nodeId.isEmpty || !seen.add(nodeId)) continue;
    nodeIds.add(nodeId);
  }
  return nodeIds;
}

bool _sameLabel(String left, String right) {
  return left.trim().toLowerCase() == right.trim().toLowerCase();
}

final class _CommandQueryModifier {
  const _CommandQueryModifier({required this.key, required this.value});

  final String key;
  final String value;
}
