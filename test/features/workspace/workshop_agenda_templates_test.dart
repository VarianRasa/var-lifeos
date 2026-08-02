import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';
import 'package:var_app/features/workspace/data/workshop_agenda_templates.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('saves, restores, and deletes templates', () async {
    final preferences = SharedPreferencesAsync();
    final notifier = WorkshopAgendaTemplatesNotifier(preferences: preferences);
    await notifier.ready;
    final template = WorkshopAgendaTemplate(
      id: 'planning',
      name: 'Planning',
      stages: [
        CanvasWorkshopStage(
          id: 'scope',
          title: 'Scope',
          type: CanvasWorkshopStageType.intro,
          durationSeconds: 300,
        ),
      ],
    );

    await notifier.save(template);
    final restored = WorkshopAgendaTemplatesNotifier(preferences: preferences);
    await restored.ready;

    expect(restored.state.single.name, 'Planning');
    expect(restored.state.single.stages.single.title, 'Scope');
    await restored.delete('planning');
    expect(restored.state, isEmpty);
  });

  test('renames, duplicates, and reorders templates', () async {
    final notifier = WorkshopAgendaTemplatesNotifier();
    await notifier.ready;
    CanvasWorkshopStage stage(String id) => CanvasWorkshopStage(
      id: id,
      title: id,
      type: CanvasWorkshopStageType.intro,
      durationSeconds: 60,
    );
    await notifier.save(
      WorkshopAgendaTemplate(id: 'one', name: 'One', stages: [stage('one')]),
    );
    await notifier.save(
      WorkshopAgendaTemplate(id: 'two', name: 'Two', stages: [stage('two')]),
    );

    await notifier.rename('one', 'Renamed');
    await notifier.duplicate('one', newId: 'copy');
    await notifier.reorder('copy', 0);

    expect(notifier.state.map((template) => template.id), [
      'copy',
      'two',
      'one',
    ]);
    expect(notifier.state.last.name, 'Renamed');
    expect(notifier.state.first.name, 'Renamed copy');
  });

  test(
    'skips malformed templates and rejects agendas over 12 stages',
    () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString(
        WorkshopAgendaTemplatesNotifier.storageKey,
        jsonEncode(<String, Object?>{
          'templates': <Object?>[
            <String, Object?>{'id': 2, 'name': 'Bad', 'stages': <Object?>[]},
            <String, Object?>{
              'id': 'too-many',
              'name': 'Too many',
              'stages': List<Object?>.generate(
                13,
                (index) => <String, Object?>{
                  'id': '$index',
                  'title': 'Stage $index',
                  'type': 'intro',
                  'durationSeconds': 60,
                },
              ),
            },
            <String, Object?>{
              'id': 'valid',
              'name': 'Valid',
              'stages': <Object?>[
                <String, Object?>{
                  'id': 'one',
                  'title': 'One',
                  'type': 'review',
                  'durationSeconds': 60,
                },
              ],
            },
          ],
        }),
      );
      final notifier = WorkshopAgendaTemplatesNotifier(
        preferences: preferences,
      );
      await notifier.ready;

      expect(notifier.state.map((template) => template.id), <String>['valid']);
    },
  );

  test('malformed document decodes as empty', () {
    expect(const WorkshopAgendaTemplateCodec().decode('{broken'), isEmpty);
  });
}
