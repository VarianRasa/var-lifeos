import 'canvas_board_template.dart';

abstract interface class CanvasBoardTemplateRepository {
  Future<List<CanvasBoardTemplate>> listTemplates();

  Future<CanvasBoardTemplate> saveTemplate(CanvasBoardTemplate template);

  Future<CanvasBoardTemplate> renameTemplate({
    required String templateId,
    required DateTime expectedUpdatedAt,
    required String name,
    required DateTime updatedAt,
  });

  Future<void> deleteTemplate(String templateId);
}
