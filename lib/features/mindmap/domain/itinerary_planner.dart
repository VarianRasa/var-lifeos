/// Travel & Event Itinerary Canvas Planner domain models.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

final class ItineraryActivity {
  const ItineraryActivity({
    required this.title,
    required this.location,
    required this.startTime,
    required this.estimatedCost,
    this.isCompleted = false,
  });

  factory ItineraryActivity.fromJson(Map<String, Object?> json) {
    return ItineraryActivity(
      title: json['title'] as String? ?? 'Activity',
      location: json['location'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '09:00',
      estimatedCost: (json['estimatedCost'] as num?)?.toDouble() ?? 0.0,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  final String title;
  final String location;
  final String startTime;
  final double estimatedCost;
  final bool isCompleted;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'location': location,
      'startTime': startTime,
      'estimatedCost': estimatedCost,
      'isCompleted': isCompleted,
    };
  }
}

final class ItineraryData {
  const ItineraryData({
    required this.destination,
    required this.activities,
    required this.packingChecklist,
  });

  factory ItineraryData.fromNode(MindmapNode node) {
    if (node.type != NodeType.itinerary) {
      return const ItineraryData(
        destination: '',
        activities: [],
        packingChecklist: [],
      );
    }
    final raw = node.data['itinerary'];
    if (raw is! Map) {
      return const ItineraryData(
        destination: '',
        activities: [],
        packingChecklist: [],
      );
    }

    final map = raw.cast<String, Object?>();
    final dest = map['destination'] as String? ?? '';
    final activitiesList = <ItineraryActivity>[];
    if (map['activities'] is List) {
      for (final item in map['activities'] as List) {
        if (item is Map) {
          activitiesList.add(
            ItineraryActivity.fromJson(item.cast<String, Object?>()),
          );
        }
      }
    }

    final checklist = <String>[];
    if (map['packingChecklist'] is List) {
      for (final item in map['packingChecklist'] as List) {
        if (item is String) checklist.add(item);
      }
    }

    return ItineraryData(
      destination: dest,
      activities: activitiesList,
      packingChecklist: checklist,
    );
  }

  final String destination;
  final List<ItineraryActivity> activities;
  final List<String> packingChecklist;

  double get totalEstimatedCost {
    var sum = 0.0;
    for (final act in activities) {
      sum += act.estimatedCost;
    }
    return sum;
  }
}
