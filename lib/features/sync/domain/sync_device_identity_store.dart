/// Local device identity contract for multi-device sync metadata.
library;

import 'mindmap_backup_document.dart';

abstract interface class SyncDeviceIdentityStore {
  Future<SyncDeviceIdentity> readOrCreateIdentity();

  Future<SyncDeviceIdentity> updateLabel(String label);
}
