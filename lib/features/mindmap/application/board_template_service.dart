import 'package:uuid/uuid.dart';

import '../domain/canvas_board.dart';
import '../domain/canvas_board_repository.dart';
import '../domain/canvas_board_template.dart';
import '../domain/canvas_board_template_repository.dart';
import '../domain/canvas_object_clone.dart';

final class BoardTemplateService {
  BoardTemplateService({
    required CanvasBoardRepository boardRepository,
    required CanvasBoardTemplateRepository templateRepository,
    String Function()? idFactory,
  }) : _boardRepository = boardRepository,
       _templateRepository = templateRepository,
       _idFactory = idFactory ?? const Uuid().v4;

  final CanvasBoardRepository _boardRepository;
  final CanvasBoardTemplateRepository _templateRepository;
  final String Function() _idFactory;

  Future<List<CanvasBoardTemplate>> availableUserTemplates(
    String workspaceName, {
    required Iterable<CanvasBoard> workspaceBoards,
    Iterable<CanvasBoardTemplate>? storedTemplates,
  }) async {
    final templates =
        storedTemplates ?? await _templateRepository.listTemplates();
    final sources = <String, CanvasBoard>{
      for (final board in workspaceBoards) board.id: board,
    };
    return templates
        .where(
          (template) =>
              _isActiveSource(sources[template.sourceBoardId], workspaceName),
        )
        .toList(growable: false);
  }

  Future<CanvasBoardTemplate> saveSourceAsTemplate({
    required String sourceBoardId,
    required String workspaceName,
    required String name,
    required DateTime now,
  }) async {
    final source = await _boardRepository.getBoard(sourceBoardId);
    if (!_isActiveSource(source, workspaceName)) {
      throw StateError('Template source is unavailable.');
    }
    return _templateRepository.saveTemplate(
      CanvasBoardTemplate(
        id: _idFactory(),
        name: name,
        sourceBoardId: sourceBoardId,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<CanvasBoardTemplate> renameTemplate({
    required String templateId,
    required DateTime expectedUpdatedAt,
    required String name,
    required DateTime now,
  }) => _templateRepository.renameTemplate(
    templateId: templateId,
    expectedUpdatedAt: expectedUpdatedAt,
    name: name,
    updatedAt: now,
  );

  Future<void> deleteTemplate(String templateId) =>
      _templateRepository.deleteTemplate(templateId);

  Future<List<CanvasObject>> instantiateUserTemplate({
    required CanvasBoardTemplate template,
    required String workspaceName,
    required DateTime now,
  }) async {
    final source = await _boardRepository.getBoard(template.sourceBoardId);
    if (!_isActiveSource(source, workspaceName)) {
      throw StateError('Template source is unavailable.');
    }
    return _clone(source!.objects, now);
  }

  List<CanvasObject> instantiateBuiltInTemplate({
    required BuiltInCanvasBoardTemplate template,
    required DateTime now,
  }) => _clone(template.objects, now);

  List<CanvasObject> _clone(Iterable<CanvasObject> objects, DateTime now) =>
      cloneCanvasObjects(
        objects,
        idFactory: _idFactory,
        now: now,
        excludeBoardReferences: true,
      );

  bool _isActiveSource(CanvasBoard? board, String workspaceName) =>
      board != null &&
      board.kind == CanvasBoardKind.project &&
      board.workspaceName == workspaceName &&
      !board.isArchived &&
      !board.isTrashed;
}
