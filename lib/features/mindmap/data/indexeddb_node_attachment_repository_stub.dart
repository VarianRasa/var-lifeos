library;

import '../domain/node_attachment.dart';

final class IndexedDbNodeAttachmentRepository {
  static Future<NodeAttachmentRepository> open() {
    throw UnsupportedError('IndexedDB attachment storage requires Web.');
  }
}
