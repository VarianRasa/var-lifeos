import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/native_reminder_notification_adapter.dart';

final nativeReminderNotificationAdapterProvider =
    Provider<NativeReminderNotificationAdapter>((ref) {
      return NativeReminderNotificationAdapter();
    });

final reminderNotificationTapProvider = StreamProvider<String>((ref) async* {
  final adapter = ref.watch(nativeReminderNotificationAdapterProvider);
  final initialPayload = await adapter.initialTapPayload();
  if (initialPayload != null && initialPayload.isNotEmpty) {
    yield initialPayload;
  }
  yield* adapter.tapPayloads;
});

String? reminderRouteFromPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, Object?>) return null;
    final rawDay = decoded['day'];
    if (rawDay is! String || !_isDayKey(rawDay)) return null;
    final details = decoded['payload'];
    final nodeId =
        decoded['nodeId'] ??
        (details is Map<String, Object?> ? details['nodeId'] : null);
    final highlight = nodeId is String && nodeId.isNotEmpty ? nodeId : null;
    return Uri(
      path: '/calendar/$rawDay',
      queryParameters: highlight == null ? null : {'highlight': highlight},
    ).toString();
  } on FormatException {
    return null;
  }
}

bool _isDayKey(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null || value.length != 10) return false;
  final normalized =
      '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
  return normalized == value;
}
