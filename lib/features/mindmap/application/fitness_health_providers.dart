import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fitness_health_service_stub.dart'
    if (dart.library.io) '../data/fitness_health_service_io.dart'
    as implementation;
import '../domain/fitness_health.dart';

final fitnessHealthServiceProvider = Provider<FitnessHealthService>((ref) {
  return implementation.createFitnessHealthService();
});
