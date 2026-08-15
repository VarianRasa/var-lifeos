/// Persisted metadata for resumable attachment transfers.
library;

import 'attachment_sync.dart';

enum AttachmentRemoteStoreKind { http, firebase }

enum AttachmentSyncProgressState {
  pending,
  running,
  waitingRetry,
  waitingAuth,
  completed,
  skipped,
  conflict,
  failed,
}

final class AttachmentSyncProgress {
  const AttachmentSyncProgress({
    required this.attachmentId,
    required this.direction,
    required this.remoteStoreKind,
    required this.attempt,
    required this.state,
    this.nextRetryAt,
    this.lastError = '',
  });

  factory AttachmentSyncProgress.fromJson(Map<String, Object?> json) {
    final attachmentId = json['attachmentId'];
    final direction = json['direction'];
    final remoteStoreKind = json['remoteStoreKind'];
    final attempt = json['attempt'];
    final state = json['state'];
    final nextRetryAt = json['nextRetryAt'];
    final lastError = json['lastError'];
    if (attachmentId is! String ||
        direction is! String ||
        remoteStoreKind is! String ||
        attempt is! int ||
        attempt < 0 ||
        state is! String ||
        lastError is! String) {
      throw const FormatException('Attachment sync progress is invalid.');
    }
    return AttachmentSyncProgress(
      attachmentId: attachmentId,
      direction: AttachmentSyncDirection.values.byName(direction),
      remoteStoreKind: AttachmentRemoteStoreKind.values.byName(remoteStoreKind),
      attempt: attempt,
      state: AttachmentSyncProgressState.values.byName(state),
      nextRetryAt: nextRetryAt is String
          ? DateTime.tryParse(nextRetryAt)?.toUtc()
          : null,
      lastError: lastError,
    );
  }

  final String attachmentId;
  final AttachmentSyncDirection direction;
  final AttachmentRemoteStoreKind remoteStoreKind;
  final int attempt;
  final DateTime? nextRetryAt;
  final String lastError;
  final AttachmentSyncProgressState state;

  String get key => '${remoteStoreKind.name}:${direction.name}:$attachmentId';

  bool get isResumable => switch (state) {
    AttachmentSyncProgressState.pending ||
    AttachmentSyncProgressState.running ||
    AttachmentSyncProgressState.waitingRetry => true,
    AttachmentSyncProgressState.waitingAuth => true,
    AttachmentSyncProgressState.completed ||
    AttachmentSyncProgressState.skipped ||
    AttachmentSyncProgressState.conflict ||
    AttachmentSyncProgressState.failed => false,
  };

  AttachmentSyncProgress copyWith({
    int? attempt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    String? lastError,
    AttachmentSyncProgressState? state,
  }) => AttachmentSyncProgress(
    attachmentId: attachmentId,
    direction: direction,
    remoteStoreKind: remoteStoreKind,
    attempt: attempt ?? this.attempt,
    nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
    lastError: lastError ?? this.lastError,
    state: state ?? this.state,
  );

  Map<String, Object?> toJson() => {
    'attachmentId': attachmentId,
    'direction': direction.name,
    'remoteStoreKind': remoteStoreKind.name,
    'attempt': attempt,
    'nextRetryAt': nextRetryAt?.toUtc().toIso8601String(),
    'lastError': lastError,
    'state': state.name,
  };
}

abstract interface class AttachmentSyncProgressStore {
  Future<List<AttachmentSyncProgress>> readAll();

  Future<void> write(AttachmentSyncProgress progress);

  Future<void> remove(String key);
}
