/// In-memory device identity store for tests and local development.
library;

import '../domain/mindmap_backup_document.dart';
import '../domain/sync_device_identity_store.dart';

final class InMemorySyncDeviceIdentityStore implements SyncDeviceIdentityStore {
  InMemorySyncDeviceIdentityStore([SyncDeviceIdentity? identity])
    : _identity =
          identity ??
          const SyncDeviceIdentity(id: 'device-memory', label: 'This device');

  SyncDeviceIdentity _identity;

  @override
  Future<SyncDeviceIdentity> readOrCreateIdentity() async => _identity;

  @override
  Future<SyncDeviceIdentity> updateLabel(String label) async {
    final trimmed = label.trim();
    _identity = SyncDeviceIdentity(
      id: _identity.id,
      label: trimmed.isEmpty ? 'This device' : trimmed,
    );
    return _identity;
  }
}
