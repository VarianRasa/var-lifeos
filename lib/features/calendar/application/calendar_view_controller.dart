library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CalendarViewMode {
  month('Month'),
  week('Week'),
  agenda('Agenda');

  const CalendarViewMode(this.label);

  final String label;
}

enum AgendaFilter {
  all('All'),
  tasks('Tasks'),
  events('Events'),
  habits('Habits'),
  routines('Routines'),
  done('Done');

  const AgendaFilter(this.label);

  final String label;
}

final calendarViewModeProvider =
    StateNotifierProvider<CalendarViewModeNotifier, CalendarViewMode>((ref) {
      return CalendarViewModeNotifier();
    });

final agendaFilterProvider =
    StateNotifierProvider<AgendaFilterNotifier, AgendaFilter>((ref) {
      return AgendaFilterNotifier();
    });

class CalendarViewModeNotifier extends StateNotifier<CalendarViewMode> {
  CalendarViewModeNotifier() : super(CalendarViewMode.month) {
    _load();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _key = 'calendar_view_mode';

  Future<void> _load() async {
    final stored = await _prefs.getString(_key);
    final mode = _calendarViewModeFromName(stored);
    if (mode != null) state = mode;
  }

  Future<void> setViewMode(CalendarViewMode mode) async {
    await _prefs.setString(_key, mode.name);
    state = mode;
  }
}

class AgendaFilterNotifier extends StateNotifier<AgendaFilter> {
  AgendaFilterNotifier() : super(AgendaFilter.all) {
    _load();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _key = 'calendar_agenda_filter';

  Future<void> _load() async {
    final stored = await _prefs.getString(_key);
    final filter = _agendaFilterFromName(stored);
    if (filter != null) state = filter;
  }

  Future<void> setFilter(AgendaFilter filter) async {
    await _prefs.setString(_key, filter.name);
    state = filter;
  }
}

CalendarViewMode? _calendarViewModeFromName(String? name) {
  for (final mode in CalendarViewMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

AgendaFilter? _agendaFilterFromName(String? name) {
  for (final filter in AgendaFilter.values) {
    if (filter.name == name) return filter;
  }
  return null;
}
