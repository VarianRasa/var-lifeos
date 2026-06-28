import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';

final workspaceTitleProvider =
    StateNotifierProvider<WorkspaceTitleNotifier, Map<String, String>>((ref) {
      return WorkspaceTitleNotifier();
    });

class WorkspaceTitleNotifier extends StateNotifier<Map<String, String>> {
  WorkspaceTitleNotifier() : super({}) {
    _loadTitles();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _keyPrefix = 'workspace_title_';

  Future<void> _loadTitles() async {
    final Map<String, String> titles = {};
    final keys = await _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_keyPrefix)) {
        final value = await _prefs.getString(key);
        if (value != null) {
          final titleKey = key.substring(_keyPrefix.length);
          titles[titleKey] = value;
        }
      }
    }
    state = titles;
  }

  Future<void> setTitle(
    WorkspaceContextType type,
    String name,
    String title,
  ) async {
    final key = _getKey(type, name);
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove('$_keyPrefix$key');
      final newState = Map<String, String>.from(state)..remove(key);
      state = newState;
    } else {
      await _prefs.setString('$_keyPrefix$key', trimmed);
      final newState = Map<String, String>.from(state)..[key] = trimmed;
      state = newState;
    }
  }

  String? getTitle(WorkspaceContextType type, String name) {
    return state[_getKey(type, name)];
  }

  String _getKey(WorkspaceContextType type, String name) {
    return '${type.name}_$name';
  }
}
