/// Location search and current-weather values used by weather nodes.
library;

final class WeatherLocation {
  const WeatherLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.country = '',
    this.admin1 = '',
    this.countryCode = '',
    this.timezone = '',
  });

  factory WeatherLocation.fromMap(Map<Object?, Object?> map) {
    final latitude = map['latitude'];
    final longitude = map['longitude'];
    if (latitude is! num || longitude is! num) {
      throw const WeatherServiceException(
        'Location result has invalid coordinates.',
        code: 'invalid-response',
      );
    }
    return WeatherLocation(
      id: '${map['id'] ?? '${latitude.toDouble()},${longitude.toDouble()}'}',
      name: '${map['name'] ?? ''}'.trim(),
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      country: '${map['country'] ?? ''}'.trim(),
      admin1: '${map['admin1'] ?? ''}'.trim(),
      countryCode: '${map['country_code'] ?? ''}'.trim().toUpperCase(),
      timezone: '${map['timezone'] ?? ''}'.trim(),
    );
  }

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String country;
  final String admin1;
  final String countryCode;
  final String timezone;

  String get displayName => <String>[
    name,
    if (admin1.isNotEmpty && admin1 != name) admin1,
    if (country.isNotEmpty) country,
  ].where((value) => value.isNotEmpty).join(', ');
}

final class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperature,
    required this.weatherCode,
    required this.observedAt,
    this.apparentTemperature,
    this.relativeHumidity,
    this.windSpeed,
    this.isDay,
    this.timezone = '',
  });

  final double temperature;
  final int weatherCode;
  final String observedAt;
  final double? apparentTemperature;
  final double? relativeHumidity;
  final double? windSpeed;
  final bool? isDay;
  final String timezone;

  String get conditionCode => switch (weatherCode) {
    0 => 'clear',
    1 || 2 || 3 => 'cloudy',
    45 || 48 => 'fog',
    51 ||
    53 ||
    55 ||
    56 ||
    57 ||
    61 ||
    63 ||
    65 ||
    66 ||
    67 ||
    80 ||
    81 ||
    82 => 'rain',
    71 || 73 || 75 || 77 || 85 || 86 => 'snow',
    95 || 96 || 99 => 'storm',
    _ => 'cloudy',
  };

  String get conditionLabel => switch (weatherCode) {
    0 => 'Clear sky',
    1 => 'Mainly clear',
    2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Fog',
    51 || 53 || 55 => 'Drizzle',
    56 || 57 => 'Freezing drizzle',
    61 || 63 || 65 => 'Rain',
    66 || 67 => 'Freezing rain',
    71 || 73 || 75 => 'Snowfall',
    77 => 'Snow grains',
    80 || 81 || 82 => 'Rain showers',
    85 || 86 => 'Snow showers',
    95 => 'Thunderstorm',
    96 || 99 => 'Thunderstorm with hail',
    _ => 'Unknown weather',
  };
}

final class WeatherServiceException implements Exception {
  const WeatherServiceException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => message;
}
