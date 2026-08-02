import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/canvas_board_template.dart';
import '../domain/canvas_board_template_repository.dart';

final class InMemoryCanvasBoardTemplateRepository
    implements CanvasBoardTemplateRepository {
  final Map<String, CanvasBoardTemplate> _templates =
      <String, CanvasBoardTemplate>{};

  @override
  Future<List<CanvasBoardTemplate>> listTemplates() async =>
      _sortedTemplates(_templates.values);

  @override
  Future<CanvasBoardTemplate> saveTemplate(CanvasBoardTemplate template) async {
    _templates[template.id] = template;
    return template;
  }

  @override
  Future<CanvasBoardTemplate> renameTemplate({
    required String templateId,
    required DateTime expectedUpdatedAt,
    required String name,
    required DateTime updatedAt,
  }) async {
    final existing = _templates[templateId];
    if (existing == null || existing.updatedAt != expectedUpdatedAt) {
      throw StateError('Template changed concurrently.');
    }
    final renamed = CanvasBoardTemplate(
      id: existing.id,
      name: name,
      sourceBoardId: existing.sourceBoardId,
      createdAt: existing.createdAt,
      updatedAt: updatedAt,
    );
    _templates[templateId] = renamed;
    return renamed;
  }

  @override
  Future<void> deleteTemplate(String templateId) async {
    _templates.remove(templateId);
  }
}

final class SembastCanvasBoardTemplateRepository
    implements CanvasBoardTemplateRepository {
  SembastCanvasBoardTemplateRepository({required FutureOr<Database> database})
    : _databaseSource = database;

  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _store = stringMapStoreFactory
      .store('canvas_board_templates');
  Database? _database;

  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);

  @override
  Future<List<CanvasBoardTemplate>> listTemplates() async {
    final records = await _store.find(await _db);
    final templates = <CanvasBoardTemplate>[];
    for (final record in records) {
      try {
        final template = CanvasBoardTemplate.fromJson(record.value);
        if (template.id == record.key) templates.add(template);
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return _sortedTemplates(templates);
  }

  @override
  Future<CanvasBoardTemplate> saveTemplate(CanvasBoardTemplate template) async {
    await _store.record(template.id).put(await _db, template.toJson());
    return template;
  }

  @override
  Future<CanvasBoardTemplate> renameTemplate({
    required String templateId,
    required DateTime expectedUpdatedAt,
    required String name,
    required DateTime updatedAt,
  }) async {
    final db = await _db;
    return db.transaction((transaction) async {
      final record = await _store.record(templateId).get(transaction);
      if (record == null) throw StateError('Template not found.');
      final existing = CanvasBoardTemplate.fromJson(record);
      if (existing.id != templateId ||
          existing.updatedAt != expectedUpdatedAt) {
        throw StateError('Template changed concurrently.');
      }
      final renamed = CanvasBoardTemplate(
        id: existing.id,
        name: name,
        sourceBoardId: existing.sourceBoardId,
        createdAt: existing.createdAt,
        updatedAt: updatedAt,
      );
      await _store.record(templateId).put(transaction, renamed.toJson());
      return renamed;
    });
  }

  @override
  Future<void> deleteTemplate(String templateId) async {
    await _store.record(templateId).delete(await _db);
  }
}

List<CanvasBoardTemplate> _sortedTemplates(
  Iterable<CanvasBoardTemplate> templates,
) => templates.toList()
  ..sort((left, right) {
    final updatedAt = right.updatedAt.compareTo(left.updatedAt);
    return updatedAt != 0 ? updatedAt : left.id.compareTo(right.id);
  });
