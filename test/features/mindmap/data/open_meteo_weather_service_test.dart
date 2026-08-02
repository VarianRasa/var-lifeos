import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/features/mindmap/data/open_meteo_weather_service.dart';
import 'package:var_app/features/mindmap/domain/weather_snapshot.dart';

void main() {
  test('searchLocations maps worldwide geocoding results', () async {
    final service = OpenMeteoWeatherService(
      client: MockClient((request) async {
        expect(request.url.host, 'geocoding-api.open-meteo.com');
        expect(request.url.queryParameters['name'], 'Bandung');
        expect(request.url.queryParameters['language'], 'id');
        return http.Response(
          jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'id': 1650357,
                'name': 'Bandung',
                'latitude': -6.9175,
                'longitude': 107.6191,
                'country': 'Indonesia',
                'admin1': 'West Java',
                'country_code': 'ID',
                'timezone': 'Asia/Jakarta',
              },
            ],
          }),
          200,
        );
      }),
    );

    final results = await service.searchLocations('Bandung');

    expect(results, hasLength(1));
    expect(results.single.displayName, 'Bandung, West Java, Indonesia');
    expect(results.single.latitude, -6.9175);
    expect(results.single.timezone, 'Asia/Jakarta');
  });

  test('currentWeather maps realtime values and WMO condition', () async {
    final service = OpenMeteoWeatherService(
      client: MockClient((request) async {
        expect(request.url.host, 'api.open-meteo.com');
        expect(request.url.queryParameters['temperature_unit'], 'celsius');
        expect(request.url.queryParameters['timezone'], 'Asia/Jakarta');
        return http.Response(
          jsonEncode(<String, Object?>{
            'timezone': 'Asia/Jakarta',
            'current': <String, Object?>{
              'time': '2026-07-19T14:15',
              'temperature_2m': 25.4,
              'apparent_temperature': 27.1,
              'relative_humidity_2m': 83,
              'weather_code': 61,
              'wind_speed_10m': 8.6,
              'is_day': 1,
            },
          }),
          200,
        );
      }),
    );
    const location = WeatherLocation(
      id: 'bandung',
      name: 'Bandung',
      latitude: -6.9175,
      longitude: 107.6191,
      timezone: 'Asia/Jakarta',
    );

    final snapshot = await service.currentWeather(
      location: location,
      temperatureUnit: '°C',
    );

    expect(snapshot.temperature, 25.4);
    expect(snapshot.conditionLabel, 'Rain');
    expect(snapshot.conditionCode, 'rain');
    expect(snapshot.relativeHumidity, 83);
    expect(snapshot.isDay, isTrue);
  });

  test('currentWeather reports malformed service response', () async {
    final service = OpenMeteoWeatherService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    const location = WeatherLocation(
      id: 'invalid',
      name: 'Invalid',
      latitude: 0,
      longitude: 0,
    );

    await expectLater(
      service.currentWeather(location: location, temperatureUnit: '°C'),
      throwsA(
        isA<WeatherServiceException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });
}
