/// Read-only fitness data imported from a device health store.
library;

final class FitnessSnapshot {
  const FitnessSnapshot({
    required this.source,
    required this.syncedAt,
    this.steps,
    this.distanceKilometers,
    this.durationMinutes,
    this.calories,
    this.waterLiters,
    this.sleepHours,
    this.restingHeartRate,
    this.workout = '',
  });

  final String source;
  final DateTime syncedAt;
  final double? steps;
  final double? distanceKilometers;
  final double? durationMinutes;
  final double? calories;
  final double? waterLiters;
  final double? sleepHours;
  final double? restingHeartRate;
  final String workout;
}

abstract interface class FitnessHealthService {
  bool get isSupported;

  String get sourceLabel;

  Future<FitnessSnapshot> syncDay(
    DateTime day, {
    required bool requestAuthorization,
  });
}

final class FitnessHealthException implements Exception {
  const FitnessHealthException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => message;
}
