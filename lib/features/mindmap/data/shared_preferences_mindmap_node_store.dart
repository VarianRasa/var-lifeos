/// SharedPreferences-backed store for persisted mindmap node JSON.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'persistent_mindmap_repository.dart';

final class SharedPreferencesMindmapNodeStore implements MindmapNodeStore {
  SharedPreferencesMindmapNodeStore({
    SharedPreferencesAsync? preferences,
    this.key = defaultKey,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const String defaultKey = 'var.mindmap.nodes.v1';

  final SharedPreferencesAsync _preferences;
  final String key;

  @override
  Future<String?> readNodesJson() {
    return _preferences.getString(key);
  }

  @override
  Future<void> writeNodesJson(String value) {
    return _preferences.setString(key, value);
  }
}
