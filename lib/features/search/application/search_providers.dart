import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_content_extractors.dart';
import '../data/search_database.dart';
import '../data/search_privacy_preferences.dart';
import '../data/sqlite_search_index_repository.dart';
import '../domain/search_index_repository.dart';
import '../domain/search_query.dart';
import '../domain/search_result.dart';
import 'content_extraction_pipeline.dart';
import 'search_index_coordinator.dart';
import 'search_service.dart';

final searchPrivacyPreferencesProvider = Provider<SearchPrivacyPreferences>((
  ref,
) {
  return SearchPrivacyPreferences(SharedPreferencesAsync());
});

final cloudExtractionEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(searchPrivacyPreferencesProvider).cloudExtractionEnabled();
});

final contentExtractionPipelineProvider = Provider<ContentExtractionPipeline>((
  ref,
) {
  final prefs = ref.watch(searchPrivacyPreferencesProvider);
  return ContentExtractionPipeline(
    localExtractors: const [Utf8TextExtractor()],
    cloudExtractor: null,
    cloudEnabled: () => prefs.cloudExtractionEnabled(),
  );
});

final searchIndexRepositoryProvider = FutureProvider<SearchIndexRepository>((
  ref,
) async {
  final database = await openSearchDatabase();
  final repository = SqliteSearchIndexRepository(database);
  ref.onDispose(repository.close);
  return repository;
});

final searchServiceProvider = FutureProvider<SearchService>((ref) async {
  return SearchService(await ref.watch(searchIndexRepositoryProvider.future));
});

final searchIndexCoordinatorProvider = FutureProvider<SearchIndexCoordinator>((
  ref,
) async {
  return SearchIndexCoordinator(
    await ref.watch(searchIndexRepositoryProvider.future),
  );
});

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<SearchResult>, SearchQuery>((ref, query) async {
      final service = await ref.watch(searchServiceProvider.future);
      return service.search(query);
    });
