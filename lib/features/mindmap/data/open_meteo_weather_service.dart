/// Free Open-Meteo location search and current-weather adapter.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/weather_snapshot.dart';

final class OpenMeteoWeatherService {
  const OpenMeteoWeatherService({required http.Client client})
    : _client = client;

  final http.Client _client;

  Future<List<WeatherLocation>> searchLocations(
    String query, {
    String language = 'id',
    int count = 8,
  }) async {
    final name = query.trim();
    if (name.length < 2) return const <WeatherLocation>[];
    final uri = Uri.https(
      'geocoding-api.open-meteo.com',
      '/v1/search',
      <String, String>{
        'name': name,
        'count': '${count.clamp(1, 20)}',
        'language': language.toLowerCase(),
        'format': 'json',
      },
    );
    final map = await _get(uri);
    final results = map['results'];
    if (results == null) return const <WeatherLocation>[];
    if (results is! List) {
      throw const WeatherServiceException(
        'Weather location search returned invalid data.',
        code: 'invalid-response',
      );
    }
    return List<WeatherLocation>.unmodifiable([
      for (final item in results)
        if (item is Map)
          WeatherLocation.fromMap(Map<Object?, Object?>.from(item)),
    ]);
  }

  Future<WeatherSnapshot> currentWeather({
    required WeatherLocation location,
    required String temperatureUnit,
  }) async {
    final uri = Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      <String, String>{
        'latitude': '${location.latitude}',
        'longitude': '${location.longitude}',
        'current': [
          'temperature_2m',
          'apparent_temperature',
          'relative_humidity_2m',
          'weather_code',
          'wind_speed_10m',
          'is_day',
        ].join(','),
        'temperature_unit': temperatureUnit == '°F' ? 'fahrenheit' : 'celsius',
        'wind_speed_unit': 'kmh',
        'timezone': location.timezone.isEmpty ? 'auto' : location.timezone,
        'forecast_days': '1',
      },
    );
    final map = await _get(uri);
    final current = map['current'];
    if (current is! Map) {
      throw const WeatherServiceException(
        'Current weather response is missing.',
        code: 'invalid-response',
      );
    }
    final values = Map<Object?, Object?>.from(current);
    final temperature = values['temperature_2m'];
    final code = values['weather_code'];
    final observedAt = '${values['time'] ?? ''}'.trim();
    if (temperature is! num || code is! num || observedAt.isEmpty) {
      throw const WeatherServiceException(
        'Current weather response is incomplete.',
        code: 'invalid-response',
      );
    }
    return WeatherSnapshot(
      temperature: temperature.toDouble(),
      apparentTemperature: _optionalNumber(values['apparent_temperature']),
      relativeHumidity: _optionalNumber(values['relative_humidity_2m']),
      windSpeed: _optionalNumber(values['wind_speed_10m']),
      weatherCode: code.toInt(),
      observedAt: observedAt,
      isDay: switch (values['is_day']) {
        final num value => value != 0,
        _ => null,
      },
      timezone: '${map['timezone'] ?? location.timezone}'.trim(),
    );
  }

  Future<Map<Object?, Object?>> _get(Uri uri) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw WeatherServiceException(
          'Weather service returned HTTP ${response.statusCode}.',
          code: 'http-${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const WeatherServiceException(
          'Weather service returned invalid data.',
          code: 'invalid-response',
        );
      }
      return Map<Object?, Object?>.from(decoded);
    } on TimeoutException {
      throw const WeatherServiceException(
        'Weather request timed out.',
        code: 'timeout',
      );
    } on FormatException {
      throw const WeatherServiceException(
        'Weather service returned malformed JSON.',
        code: 'invalid-response',
      );
    } on WeatherServiceException {
      rethrow;
    } on Object {
      throw const WeatherServiceException(
        'Weather service is unavailable.',
        code: 'unavailable',
      );
    }
  }
}

double? _optionalNumber(Object? value) =>
    value is num ? value.toDouble() : null;
