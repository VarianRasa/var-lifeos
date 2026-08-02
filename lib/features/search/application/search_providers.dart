import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/search_database.dart';
import '../data/search_privacy_preferences.dart';
import '../data/sqlite_search_index_repository.dart';
import '../domain/search_index_repository.dart';
import '../domain/search_query.dart';
import '../domain/search_result.dart';
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
