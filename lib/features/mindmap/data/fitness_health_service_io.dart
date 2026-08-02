import 'dart:io';

import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/fitness_health.dart';

FitnessHealthService createFitnessHealthService() =>
    MobileFitnessHealthService();

final class MobileFitnessHealthService implements FitnessHealthService {
  MobileFitnessHealthService({Health? health}) : _health = health ?? Health();

  final Health _health;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  String get sourceLabel => Platform.isAndroid
      ? 'Health Connect'
      : Platform.isIOS
      ? 'Apple Health'
      : 'Manual';

  List<HealthDataType> get _types => Platform.isAndroid
      ? const <HealthDataType>[
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.WATER,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.WORKOUT,
          HealthDataType.RESTING_HEART_RATE,
        ]
      : const <HealthDataType>[
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_WALKING_RUNNING,
          HealthDataType.DISTANCE_CYCLING,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.WATER,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.EXERCISE_TIME,
          HealthDataType.WORKOUT,
          HealthDataType.RESTING_HEART_RATE,
        ];

  @override
  Future<FitnessSnapshot> syncDay(
    DateTime day, {
    required bool requestAuthorization,
  }) async {
    if (!isSupported) {
      throw const FitnessHealthException(
        'Automatic fitness sync is available only on Android and iOS.',
        code: 'unsupported-platform',
      );
    }

    try {
      await _health.configure();
      if (Platform.isAndroid) {
        final sdkStatus = await _health.getHealthConnectSdkStatus();
        if (sdkStatus == HealthConnectSdkStatus.sdkUnavailable) {
          throw const FitnessHealthException(
            'Health Connect is not available on this device.',
            code: 'health-connect-unavailable',
          );
        }
        if (sdkStatus ==
            HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
          throw const FitnessHealthException(
            'Install or update Health Connect before syncing fitness data.',
            code: 'health-connect-update-required',
          );
        }
        final activityPermission = requestAuthorization
            ? await Permission.activityRecognition.request()
            : await Permission.activityRecognition.status;
        if (!activityPermission.isGranted) {
          throw const FitnessHealthException(
            'Activity recognition permission is required to sync fitness data.',
            code: 'activity-permission-denied',
          );
        }
      }

      final permissions = List<HealthDataAccess>.filled(
        _types.length,
        HealthDataAccess.READ,
      );
      if (requestAuthorization) {
        final authorized = await _health.requestAuthorization(
          _types,
          permissions: permissions,
        );
        if (!authorized) {
          throw FitnessHealthException(
            '$sourceLabel permission was not granted.',
            code: 'health-permission-denied',
          );
        }
      } else if (Platform.isAndroid) {
        final authorized = await _health.hasPermissions(
          _types,
          permissions: permissions,
        );
        if (authorized != true) {
          throw const FitnessHealthException(
            'Tap Connect health to grant fitness permissions.',
            code: 'health-permission-required',
          );
        }
      }

      final start = DateTime(day.year, day.month, day.day);
      final nextDay = start.add(const Duration(days: 1));
      final now = DateTime.now();
      final end = nextDay.isAfter(now) ? now : nextDay;
      if (!end.isAfter(start)) {
        return FitnessSnapshot(source: sourceLabel, syncedAt: now);
      }

      final points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: start,
        endTime: end,
        preferredUnits: const <HealthDataType, HealthDataUnit>{
          HealthDataType.DISTANCE_DELTA: HealthDataUnit.METER,
          HealthDataType.DISTANCE_WALKING_RUNNING: HealthDataUnit.METER,
          HealthDataType.DISTANCE_CYCLING: HealthDataUnit.METER,
          HealthDataType.ACTIVE_ENERGY_BURNED: HealthDataUnit.KILOCALORIE,
          HealthDataType.WATER: HealthDataUnit.LITER,
          HealthDataType.SLEEP_ASLEEP: HealthDataUnit.MINUTE,
          HealthDataType.EXERCISE_TIME: HealthDataUnit.MINUTE,
          HealthDataType.RESTING_HEART_RATE: HealthDataUnit.BEATS_PER_MINUTE,
        },
      );
      final steps = await _health.getTotalStepsInInterval(start, end);
      return _snapshotFromPoints(points, steps: steps, syncedAt: now);
    } on FitnessHealthException {
      rethrow;
    } catch (error) {
      throw FitnessHealthException(
        'Unable to sync $sourceLabel: $error',
        code: 'health-sync-failed',
      );
    }
  }

  FitnessSnapshot _snapshotFromPoints(
    List<HealthDataPoint> points, {
    required int? steps,
    required DateTime syncedAt,
  }) {
    var distanceMeters = 0.0;
    var exerciseMinutes = 0.0;
    var workoutMinutes = 0.0;
    var calories = 0.0;
    var waterLiters = 0.0;
    var sleepMinutes = 0.0;
    double? restingHeartRate;
    DateTime? restingHeartRateAt;
    final workouts = <String>[];

    for (final point in points) {
      switch (point.type) {
        case HealthDataType.DISTANCE_DELTA:
        case HealthDataType.DISTANCE_WALKING_RUNNING:
        case HealthDataType.DISTANCE_CYCLING:
          distanceMeters += _numericValue(point);
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          calories += _numericValue(point);
        case HealthDataType.WATER:
          waterLiters += _numericValue(point);
        case HealthDataType.SLEEP_ASLEEP:
          sleepMinutes += _numericValue(point);
        case HealthDataType.EXERCISE_TIME:
          exerciseMinutes += _numericValue(point);
        case HealthDataType.RESTING_HEART_RATE:
          if (restingHeartRateAt == null ||
              point.dateTo.isAfter(restingHeartRateAt)) {
            restingHeartRate = _numericValue(point);
            restingHeartRateAt = point.dateTo;
          }
        case HealthDataType.WORKOUT:
          workoutMinutes +=
              point.dateTo.difference(point.dateFrom).inSeconds / 60;
          final value = point.value;
          if (value is WorkoutHealthValue) {
            final label = _workoutLabel(value.workoutActivityType);
            if (!workouts.contains(label)) workouts.add(label);
          }
        default:
          break;
      }
    }

    return FitnessSnapshot(
      source: sourceLabel,
      syncedAt: syncedAt,
      steps: steps?.toDouble(),
      distanceKilometers: distanceMeters == 0 ? null : distanceMeters / 1000,
      durationMinutes: workoutMinutes > 0
          ? workoutMinutes
          : exerciseMinutes == 0
          ? null
          : exerciseMinutes,
      calories: calories == 0 ? null : calories,
      waterLiters: waterLiters == 0 ? null : waterLiters,
      sleepHours: sleepMinutes == 0 ? null : sleepMinutes / 60,
      restingHeartRate: restingHeartRate,
      workout: workouts.take(2).join(' + '),
    );
  }
}

double _numericValue(HealthDataPoint point) {
  final value = point.value;
  return value is NumericHealthValue ? value.numericValue.toDouble() : 0;
}

String _workoutLabel(HealthWorkoutActivityType type) => switch (type) {
  HealthWorkoutActivityType.WALKING => 'Walk',
  HealthWorkoutActivityType.RUNNING => 'Run',
  HealthWorkoutActivityType.BIKING => 'Cycling',
  HealthWorkoutActivityType.SWIMMING => 'Swimming',
  HealthWorkoutActivityType.YOGA => 'Yoga',
  HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING ||
  HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING => 'Strength',
  _ =>
    type.name
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0]}${word.substring(1).toLowerCase()}',
        )
        .join(' '),
};
