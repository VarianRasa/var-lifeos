import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class AppThemeIconSet extends ThemeExtension<AppThemeIconSet> {
  const AppThemeIconSet({
    required this.close,
    required this.chevronDown,
    required this.chevronLeft,
    required this.chevronRight,
    required this.check,
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    required this.calendar,
    required this.clock,
    required this.externalLink,
    required this.menu,
    required this.moreHorizontal,
    required this.search,
    required this.arrowUp,
    required this.arrowDown,
    required this.arrowsUpDown,
    required this.funnel,
    required this.eyeSlash,
    required this.viewColumns,
    required this.copy,
    required this.checkDouble,
    required this.wrench,
    required this.stop,
    required this.microphone,
  });

  final IconData close;
  final IconData chevronDown;
  final IconData chevronLeft;
  final IconData chevronRight;
  final IconData check;
  final IconData success;
  final IconData error;
  final IconData warning;
  final IconData info;
  final IconData calendar;
  final IconData clock;
  final IconData externalLink;
  final IconData menu;
  final IconData moreHorizontal;
  final IconData search;
  final IconData arrowUp;
  final IconData arrowDown;
  final IconData arrowsUpDown;
  final IconData funnel;
  final IconData eyeSlash;
  final IconData viewColumns;
  final IconData copy;
  final IconData checkDouble;
  final IconData wrench;
  final IconData stop;
  final IconData microphone;

  IconData get more => moreHorizontal;

  static const lucideLike = AppThemeIconSet(
    close: Icons.close,
    chevronDown: Icons.keyboard_arrow_down,
    chevronLeft: Icons.chevron_left,
    chevronRight: Icons.chevron_right,
    check: Icons.check,
    success: Icons.check_circle_outline,
    error: Icons.cancel_outlined,
    warning: Icons.warning_amber_outlined,
    info: Icons.info_outline,
    calendar: Icons.calendar_today_outlined,
    clock: Icons.access_time,
    externalLink: Icons.open_in_new,
    menu: Icons.menu,
    moreHorizontal: Icons.more_horiz,
    search: Icons.search,
    arrowUp: Icons.arrow_upward,
    arrowDown: Icons.arrow_downward,
    arrowsUpDown: Icons.swap_vert,
    funnel: Icons.filter_alt_outlined,
    eyeSlash: Icons.visibility_off_outlined,
    viewColumns: Icons.view_column_outlined,
    copy: Icons.content_copy_outlined,
    checkDouble: Icons.done_all,
    wrench: Icons.build_outlined,
    stop: Icons.stop_outlined,
    microphone: Icons.mic_none,
  );

  static AppThemeIconSet forVariant(AppThemeVariant variant) => lucideLike;

  @override
  AppThemeIconSet copyWith({
    IconData? close,
    IconData? chevronDown,
    IconData? chevronLeft,
    IconData? chevronRight,
    IconData? check,
    IconData? success,
    IconData? error,
    IconData? warning,
    IconData? info,
    IconData? calendar,
    IconData? clock,
    IconData? externalLink,
    IconData? menu,
    IconData? moreHorizontal,
    IconData? search,
    IconData? arrowUp,
    IconData? arrowDown,
    IconData? arrowsUpDown,
    IconData? funnel,
    IconData? eyeSlash,
    IconData? viewColumns,
    IconData? copy,
    IconData? checkDouble,
    IconData? wrench,
    IconData? stop,
    IconData? microphone,
  }) => AppThemeIconSet(
    close: close ?? this.close,
    chevronDown: chevronDown ?? this.chevronDown,
    chevronLeft: chevronLeft ?? this.chevronLeft,
    chevronRight: chevronRight ?? this.chevronRight,
    check: check ?? this.check,
    success: success ?? this.success,
    error: error ?? this.error,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    calendar: calendar ?? this.calendar,
    clock: clock ?? this.clock,
    externalLink: externalLink ?? this.externalLink,
    menu: menu ?? this.menu,
    moreHorizontal: moreHorizontal ?? this.moreHorizontal,
    search: search ?? this.search,
    arrowUp: arrowUp ?? this.arrowUp,
    arrowDown: arrowDown ?? this.arrowDown,
    arrowsUpDown: arrowsUpDown ?? this.arrowsUpDown,
    funnel: funnel ?? this.funnel,
    eyeSlash: eyeSlash ?? this.eyeSlash,
    viewColumns: viewColumns ?? this.viewColumns,
    copy: copy ?? this.copy,
    checkDouble: checkDouble ?? this.checkDouble,
    wrench: wrench ?? this.wrench,
    stop: stop ?? this.stop,
    microphone: microphone ?? this.microphone,
  );

  @override
  AppThemeIconSet lerp(covariant AppThemeIconSet? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
