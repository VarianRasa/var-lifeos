import 'package:shared_preferences/shared_preferences.dart';

final class SearchPrivacyPreferences {
  SearchPrivacyPreferences(this._preferences);

  static const _cloudExtractionKey = 'search.cloudExtractionEnabled';

  final SharedPreferencesAsync _preferences;

  Future<bool> cloudExtractionEnabled() async =>
      await _preferences.getBool(_cloudExtractionKey) ?? false;

  Future<void> setCloudExtractionEnabled(bool value) =>
      _preferences.setBool(_cloudExtractionKey, value);
}
