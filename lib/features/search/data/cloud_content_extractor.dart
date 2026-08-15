import '../domain/content_extraction.dart';

abstract interface class CloudContentExtractor implements ContentExtractor {
  String get providerName;
}
