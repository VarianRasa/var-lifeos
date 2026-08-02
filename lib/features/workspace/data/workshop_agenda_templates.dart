import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mindmap/domain/canvas_workshop.dart';

final workshopAgendaTemplatesProvider =
    StateNotifierProvider<
      WorkshopAgendaTemplatesNotifier,
      List<WorkshopAgendaTemplate>
    >((ref) => WorkshopAgendaTemplatesNotifier());

final class WorkshopAgendaTemplate {
  WorkshopAgendaTemplate({
    required this.id,
    required String name,
    required List<CanvasWorkshopStage> stages,
  }) : name = name.trim(),
       stages = List<CanvasWorkshopStage>.unmodifiable(stages.take(12)) {
    if (id.trim().isEmpty || this.name.isEmpty || this.stages.isEmpty) {
      throw const FormatException('Invalid workshop agenda template.');
    }
  }

  final String id;
  final String name;
  final List<CanvasWorkshopStage> stages;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'stages': stages.map((stage) => stage.toJson()).toList(),
  };

  static WorkshopAgendaTemplate? tryFromJson(Object? value) {
    try {
      if (value is! Map) return null;
      final json = Map<String, Object?>.from(value);
      final rawStages = json['stages'];
      if (json['id'] is! String ||
          json['name'] is! String ||
          rawStages is! List ||
          rawStages.isEmpty ||
          rawStages.length > 12) {
        return null;
      }
      final stages = <CanvasWorkshopStage>[];
      for (final rawStage in rawStages) {
        try {
          stages.add(CanvasWorkshopStage.fromJson(rawStage));
        } on Object {
          return null;
        }
      }
      return WorkshopAgendaTemplate(
        id: json['id']! as String,
        name: json['name']! as String,
        stages: stages,
      );
    } on Object {
      return null;
    }
  }
}

final class WorkshopAgendaTemplateCodec {
  const WorkshopAgendaTemplateCodec();

  String encode(List<WorkshopAgendaTemplate> templates) =>
      jsonEncode(<String, Object?>{
        'version': 1,
        'templates': templates.map((template) => template.toJson()).toList(),
      });

  List<WorkshopAgendaTemplate> decode(String? source) {
    if (source == null || source.trim().isEmpty) return const [];
    try {
      final value = jsonDecode(source);
      if (value is! Map) return const [];
      final templates = value['templates'];
      if (templates is! List) return const [];
      return templates
          .map(WorkshopAgendaTemplate.tryFromJson)
          .whereType<WorkshopAgendaTemplate>()
          .toList();
    } on Object {
      return const [];
    }
  }
}

class WorkshopAgendaTemplatesNotifier
    extends StateNotifier<List<WorkshopAgendaTemplate>> {
  WorkshopAgendaTemplatesNotifier({
    SharedPreferencesAsync? preferences,
    WorkshopAgendaTemplateCodec codec = const WorkshopAgendaTemplateCodec(),
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _codec = codec,
       super(const []) {
    ready = _load();
  }

  static const storageKey = 'workshop_agenda_templates_v1';
  final SharedPreferencesAsync _preferences;
  final WorkshopAgendaTemplateCodec _codec;
  late final Future<void> ready;

  Future<void> _load() async {
    state = _codec.decode(await _preferences.getString(storageKey));
  }

  Future<void> save(WorkshopAgendaTemplate template) async {
    final next = <WorkshopAgendaTemplate>[
      for (final existing in state)
        if (existing.id != template.id) existing,
      template,
    ];
    await _preferences.setString(storageKey, _codec.encode(next));
    state = next;
  }

  Future<void> rename(String id, String name) async {
    final index = state.indexWhere((template) => template.id == id);
    if (index < 0) return;
    final existing = state[index];
    await save(
      WorkshopAgendaTemplate(id: id, name: name, stages: existing.stages),
    );
  }

  Future<void> duplicate(String id, {required String newId}) async {
    final index = state.indexWhere((template) => template.id == id);
    if (index < 0) return;
    final existing = state[index];
    await save(
      WorkshopAgendaTemplate(
        id: newId,
        name: '${existing.name} copy',
        stages: existing.stages,
      ),
    );
  }

  Future<void> reorder(String id, int newIndex) async {
    final index = state.indexWhere((template) => template.id == id);
    if (index < 0 ||
        newIndex < 0 ||
        newIndex >= state.length ||
        index == newIndex) {
      return;
    }
    final next = [...state];
    final template = next.removeAt(index);
    next.insert(newIndex, template);
    await _preferences.setString(storageKey, _codec.encode(next));
    state = next;
  }

  Future<void> delete(String id) async {
    final next = state.where((template) => template.id != id).toList();
    await _preferences.setString(storageKey, _codec.encode(next));
    state = next;
  }
}
