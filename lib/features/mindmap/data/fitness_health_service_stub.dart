import '../domain/fitness_health.dart';

FitnessHealthService createFitnessHealthService() =>
    const UnsupportedFitnessHealthService();

final class UnsupportedFitnessHealthService implements FitnessHealthService {
  const UnsupportedFitnessHealthService();

  @override
  bool get isSupported => false;

  @override
  String get sourceLabel => 'Manual';

  @override
  Future<FitnessSnapshot> syncDay(
    DateTime day, {
    required bool requestAuthorization,
  }) => throw const FitnessHealthException(
    'Automatic fitness sync is available only on Android and iOS.',
    code: 'unsupported-platform',
  );
}
