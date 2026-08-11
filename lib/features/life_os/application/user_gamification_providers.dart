/// Riverpod StateNotifier/Notifier for User Gamification.
library;

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_gamification.dart';

const String _gamificationPrefsKey = 'var_user_gamification_stats_v1';

/// AsyncNotifier to manage Gamification Stats state.
final userGamificationProvider =
    AsyncNotifierProvider<UserGamificationNotifier, UserGamificationStats>(
      UserGamificationNotifier.new,
    );

class UserGamificationNotifier extends AsyncNotifier<UserGamificationStats> {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<UserGamificationStats> build() async {
    final rawJson = await _prefs.getString(_gamificationPrefsKey);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final Map<String, Object?> decoded =
            jsonDecode(rawJson) as Map<String, Object?>;
        return UserGamificationStats.fromJson(decoded);
      } catch (_) {
        // Fallback to initial if corrupted
      }
    }
    return UserGamificationStats.initial();
  }

  Future<void> _save(UserGamificationStats stats) async {
    state = AsyncData(stats);
    await _prefs.setString(_gamificationPrefsKey, jsonEncode(stats.toJson()));
  }

  Future<void> recordTaskCompletion() async {
    final current = state.valueOrNull ?? UserGamificationStats.initial();
    await _save(current.recordTaskCompletion());
  }

  Future<void> recordHabitCompletion() async {
    final current = state.valueOrNull ?? UserGamificationStats.initial();
    await _save(current.recordHabitCompletion());
  }

  Future<void> recordFlashcardReview() async {
    final current = state.valueOrNull ?? UserGamificationStats.initial();
    await _save(current.recordFlashcardReview());
  }

  Future<void> recordFocusMinutes(int minutes) async {
    final current = state.valueOrNull ?? UserGamificationStats.initial();
    await _save(current.recordFocusMinutes(minutes));
  }

  Future<void> addXp(int xp) async {
    final current = state.valueOrNull ?? UserGamificationStats.initial();
    await _save(current.addXp(xp));
  }
}
