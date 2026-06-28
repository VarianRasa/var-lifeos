/// Local sync activity log contracts.
library;

enum SyncActivityAction {
  signIn,
  signOut,
  push,
  pull,
  syncNow,
  resolveRemote,
  resolveLocal,
  resolveNewest,
  exportPortable,
  importPortable,
  restorePoint,
}

enum SyncActivityStatus { success, blocked, failed }

final class SyncActivityEntry {
  const SyncActivityEntry({
    required this.id,
    required this.action,
    required this.status,
    required this.message,
    required this.occurredAt,
    this.savedCount = 0,
    this.deletedCount = 0,
    this.conflictCount = 0,
    this.accountEmail = '',
  });

  factory SyncActivityEntry.fromJson(Map<String, Object?> json) {
    final rawOccurredAt = json['occurredAt'];
    final occurredAt = rawOccurredAt is String
        ? DateTime.tryParse(rawOccurredAt)
        : null;

    return SyncActivityEntry(
      id: json['id'] as String? ?? '',
      action: _actionFromName(json['action'] as String?),
      status: _statusFromName(json['status'] as String?),
      message: json['message'] as String? ?? '',
      occurredAt: occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      savedCount: json['savedCount'] as int? ?? 0,
      deletedCount: json['deletedCount'] as int? ?? 0,
      conflictCount: json['conflictCount'] as int? ?? 0,
      accountEmail: json['accountEmail'] as String? ?? '',
    );
  }

  final String id;
  final SyncActivityAction action;
  final SyncActivityStatus status;
  final String message;
  final DateTime occurredAt;
  final int savedCount;
  final int deletedCount;
  final int conflictCount;
  final String accountEmail;

  String get actionLabel {
    return switch (action) {
      SyncActivityAction.signIn => 'Sign in',
      SyncActivityAction.signOut => 'Sign out',
      SyncActivityAction.push => 'Push',
      SyncActivityAction.pull => 'Pull',
      SyncActivityAction.syncNow => 'Sync now',
      SyncActivityAction.resolveRemote => 'Use remote',
      SyncActivityAction.resolveLocal => 'Keep local',
      SyncActivityAction.resolveNewest => 'Use newest',
      SyncActivityAction.exportPortable => 'Export',
      SyncActivityAction.importPortable => 'Import',
      SyncActivityAction.restorePoint => 'Restore',
    };
  }

  String get statusLabel {
    return switch (status) {
      SyncActivityStatus.success => 'Success',
      SyncActivityStatus.blocked => 'Blocked',
      SyncActivityStatus.failed => 'Failed',
    };
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'action': action.name,
    'status': status.name,
    'message': message,
    'occurredAt': occurredAt.toIso8601String(),
    'savedCount': savedCount,
    'deletedCount': deletedCount,
    'conflictCount': conflictCount,
    'accountEmail': accountEmail,
  };
}

abstract interface class SyncActivityStore {
  Future<void> add(SyncActivityEntry entry);

  Future<List<SyncActivityEntry>> recent({int limit = 5});

  Future<void> clear();
}

SyncActivityAction _actionFromName(String? name) {
  return SyncActivityAction.values.firstWhere(
    (action) => action.name == name,
    orElse: () => SyncActivityAction.syncNow,
  );
}

SyncActivityStatus _statusFromName(String? name) {
  return SyncActivityStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => SyncActivityStatus.failed,
  );
}
