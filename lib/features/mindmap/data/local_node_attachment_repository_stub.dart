library;

import '../domain/node_attachment.dart';

Future<NodeAttachmentRepository> openLocalNodeAttachmentRepository() {
  throw UnsupportedError('Attachment storage is unavailable on this platform.');
}
