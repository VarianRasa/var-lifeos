/// Weather-node external service providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/open_meteo_weather_service.dart';

final weatherHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final weatherServiceProvider = Provider<OpenMeteoWeatherService>((ref) {
  return OpenMeteoWeatherService(client: ref.watch(weatherHttpClientProvider));
});
