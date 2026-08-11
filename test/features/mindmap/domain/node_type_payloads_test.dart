import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_block_document.dart';
import 'package:var_app/features/mindmap/domain/hybrid_timer.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';

void main() {
  test('ImagePayload round-trips edit state and annotations', () {
    final day = DateTime(2026, 7, 18);
    final base = MindmapNode.create(
      id: 'image-edit-state',
      type: NodeType.image,
      title: 'Edited image',
      day: day,
      now: day,
    );
    const payload = ImagePayload(
      attachmentId: '12345678-1234-1234-1234-123456789abc',
      altText: 'Annotated image',
      originalAttachmentId: '87654321-4321-4321-4321-cba987654321',
      sourceUrl: 'https://example.test/source',
      tags: <String>['reference', 'draft'],
      rotationQuarterTurns: 1,
      flipHorizontal: true,
      brightness: 0.2,
      contrast: 0.3,
      saturation: -0.4,
      filter: ImageFilterPreset.warm,
      annotations: <ImageAnnotation>[
        ImageAnnotation(
          id: 'annotation-1',
          type: ImageAnnotationType.freehand,
          strokeWidth: 5,
          positionX: 0.2,
          positionY: 0.3,
          width: 0.4,
          height: 0.25,
          rotationDegrees: 15,
          points: <CanvasPoint>[
            CanvasPoint(0, 0.25),
            CanvasPoint(0.5, 0.75),
            CanvasPoint(1, 0),
          ],
        ),
      ],
    );

    final decoded = ImagePayload.fromNode(
      base.copyWith(data: payload.toData(base.data)),
    );

    expect(decoded.tags, <String>['reference', 'draft']);
    expect(decoded.rotationQuarterTurns, 1);
    expect(decoded.flipHorizontal, isTrue);
    expect(decoded.filter, ImageFilterPreset.warm);
    expect(decoded.annotations.single.type, ImageAnnotationType.freehand);
    expect(decoded.annotations.single.strokeWidth, 5);
    expect(decoded.annotations.single.positionX, 0.2);
    expect(decoded.annotations.single.positionY, 0.3);
    expect(decoded.annotations.single.width, 0.4);
    expect(decoded.annotations.single.height, 0.25);
    expect(decoded.annotations.single.rotationDegrees, 15);
    expect(decoded.annotations.single.points, hasLength(3));
    expect(decoded.annotations.single.points[1].x, 0.5);
    expect(decoded.annotations.single.points[1].y, 0.75);
  });

  MindmapNode node(NodeType type, Map<String, Object?> data) =>
      MindmapNode.create(
        id: type.name,
        type: type,
        title: 'Typed node',
        day: DateTime(2026, 7, 13),
        data: data,
        now: DateTime(2026, 7, 13, 9),
      );

  test('task/checklist reads checklist and preserves unrelated data', () {
    final source = node(NodeType.task, const {'foreign': 7});
    final payload = TaskChecklistPayload.fromNode(source).copyWith(
      items: const [TaskChecklistItem(id: '1', title: 'First', isDone: true)],
    );
    final data = payload.toData(source.data);
    expect(data['foreign'], 7);
    expect(payload.validate(title: source.title), isEmpty);
    expect(data.containsKey('checklist'), isFalse);
    final applied = payload.toNode(source);
    expect(applied.checklist, payload.items);
    expect(applied.data, {'foreign': 7});
    expect(TaskChecklistPayload.fromNode(applied).items, payload.items);
  });

  test('task metadata round trips and preserves nested sentinels', () {
    final source = node(NodeType.task, const {
      'task': {'color': 'fuchsia'},
      'foreign': true,
    });
    final payload = TaskChecklistPayload.fromNode(source).copyWith(
      assignees: const ['Alya', 'Bima'],
      attachments: const [
        TaskAttachmentReference(
          id: 'attachment-1',
          fileName: 'brief.pdf',
          mimeType: 'application/octet-stream',
          byteLength: 2048,
        ),
      ],
    );

    final applied = payload.toNode(source);
    final decoded = TaskChecklistPayload.fromNode(applied);

    expect(decoded.assignees, ['Alya', 'Bima']);
    expect(decoded.attachments.single.fileName, 'brief.pdf');
    expect((applied.data['task'] as Map)['color'], 'fuchsia');
    expect(applied.data['foreign'], isTrue);
  });
  test('checklist uses top-level authority with safe legacy fallback', () {
    final authoritative =
        node(NodeType.checklist, const {
          'checklist': [
            {'id': 'legacy', 'title': 'Legacy', 'isDone': false},
          ],
        }).copyWith(
          checklist: const [
            TaskChecklistItem(id: 'top', title: 'Top level', isDone: true),
          ],
        );
    expect(TaskChecklistPayload.fromNode(authoritative).items.single.id, 'top');

    final legacy = node(NodeType.checklist, const {
      'checklist': [
        {'id': 'ok', 'title': 'Legacy', 'isDone': false},
        {'id': 2, 'title': 'Wrong value types', 'isDone': 'yes'},
        {1: 'malformed'},
        'invalid',
      ],
    });
    expect(
      TaskChecklistPayload.fromNode(legacy).items.map((item) => item.title),
      ['Legacy', 'Wrong value types'],
    );
    expect(TaskChecklistPayload.fromNode(legacy).toData(legacy.data), isEmpty);
  });

  test(
    'dedicated checklist payload migrates legacy and round trips metadata',
    () {
      final legacy = node(NodeType.checklist, const <String, Object?>{})
          .copyWith(
            checklist: const <TaskChecklistItem>[
              TaskChecklistItem(id: 'legacy', title: 'Legacy item'),
            ],
          );

      final migrated = ChecklistPayload.fromNode(legacy);
      expect(migrated.items.single.title, 'Legacy item');
      expect(migrated.items.single.priority, ChecklistPriority.none);

      final applied = migrated
          .copyWith(
            items: <ChecklistEntry>[
              migrated.items.single.copyWith(
                priority: ChecklistPriority.high,
                dueDate: DateTime(2026, 7, 20, 18),
              ),
            ],
          )
          .toNode(legacy);
      final decoded = ChecklistPayload.fromNode(applied);

      expect(decoded.items.single.priority, ChecklistPriority.high);
      expect(decoded.items.single.dueDate, DateTime(2026, 7, 20));
      expect(applied.checklist.single.id, 'legacy');
      expect((applied.data['checklist'] as Map)['version'], 1);
      expect(
        TaskChecklistPayload.fromNode(applied).items.single.title,
        'Legacy item',
      );
    },
  );
  test('kanban keeps existing kanban section keys', () {
    const data = {
      'kanban': {
        'cards': [
          {'id': 'a', 'title': 'Ship', 'column': 'doing'},
        ],
        'swimlane': 'mobile',
      },
      'foreign': true,
    };
    final payload = KanbanPayload.fromNode(node(NodeType.kanban, data));
    final encoded = payload.toData(data);
    expect(payload.cards.single.title, 'Ship');
    expect((encoded['kanban'] as Map)['swimlane'], 'mobile');
    expect(encoded['foreign'], isTrue);
  });

  test('malformed nested payload maps do not throw', () {
    final malformedKanban = node(NodeType.kanban, {
      'kanban': {
        1: 'bad key',
        'cards': [
          {1: 'bad'},
          {'id': 2, 'title': 'Wrong values', 'column': 3},
          {'id': 'ok', 'title': 'Safe', 'column': 'todo'},
        ],
      },
    });
    final malformedPlan = node(NodeType.plan, {
      'plan': {
        1: 'bad key',
        'steps': ['Safe', 2],
      },
    });
    final malformedLink = node(NodeType.link, {
      'link': {1: 'bad key', 'url': 'https://safe.test'},
    });

    expect(
      KanbanPayload.fromNode(malformedKanban).cards.map((card) => card.title),
      ['Wrong values', 'Safe'],
    );
    expect(PlanPayload.fromNode(malformedPlan).steps, ['Safe']);
    expect(
      LinkResourcePayload.fromNode(malformedLink).url,
      'https://safe.test',
    );
  });

  test('plan and goal preserve nested legacy sections', () {
    const data = {
      'plan': {
        'steps': ['Draft'],
        'completedSteps': <String>[],
        'owner': 'A',
      },
      'goal': {
        'milestones': ['Beta'],
        'completedMilestones': <String>[],
        'metric': 'users',
      },
    };
    final plan = PlanPayload.fromNode(node(NodeType.plan, data));
    final goal = GoalPayload.fromNode(node(NodeType.goal, data));
    expect(plan.steps, ['Draft']);
    expect(goal.milestones, ['Beta']);
    expect((plan.toData(data)['plan'] as Map)['owner'], 'A');
    expect((goal.toData(data)['goal'] as Map)['metric'], 'users');
  });

  test('habit/routine uses existing habit keys and validates recurrence', () {
    const data = {
      'habit': {
        'target': '8 glasses',
        'recurrence': 'daily',
        'completions': ['2026-07-13'],
        'color': 'pink',
      },
    };
    final habitNode = node(NodeType.habit, data);
    expect(habitNode.data['habit'], isA<Map<String, Object?>>());
    final payload = HabitRoutinePayload.fromNode(habitNode);
    expect(payload.completions, ['2026-07-13']);
    expect(payload.validate(title: 'Hydrate'), isEmpty);
    expect((payload.toData(data)['habit'] as Map)['color'], 'pink');
    final roundTrip = node(NodeType.habit, payload.toData(habitNode.data));
    expect(HabitRoutinePayload.fromNode(roundTrip).completions, ['2026-07-13']);
  });

  test('event/calendar reads flat calendar compatibility keys', () {
    const data = {
      'calendar_kind': 'event',
      'location': 'Jakarta',
      'startDate': '2026-07-13',
      'endDate': '2026-07-14',
      'startTime': '09:00',
      'endTime': '10:00',
      'foreign': 1,
    };
    final payload = EventCalendarPayload.fromNode(node(NodeType.event, data));
    expect(payload.location, 'Jakarta');
    expect(payload.validate(title: 'Meet'), isEmpty);
    expect(payload.toData(data)['calendar_kind'], 'event');
    expect(payload.toData(data)['foreign'], 1);
  });

  test('event validates combined local date and time range', () {
    const overnight = EventCalendarPayload(
      startDate: '2026-07-13',
      endDate: '2026-07-14',
      startTime: '23:00',
      endTime: '01:00',
    );
    const reversed = EventCalendarPayload(
      startDate: '2026-07-13',
      endDate: '2026-07-13',
      startTime: '23:00',
      endTime: '01:00',
    );
    const allDay = EventCalendarPayload(
      startDate: '2026-07-13',
      endDate: '2026-07-14',
    );

    expect(overnight.validate(title: 'Trip'), isEmpty);
    expect(allDay.validate(title: 'Trip'), isEmpty);
    expect(
      reversed.validate(title: 'Trip'),
      contains('End time must not precede start time.'),
    );
  });

  test('expense receipts round-trip attachment references', () {
    final source = node(NodeType.expense, const {
      'amount': 45000,
      'currency': 'idr',
      'expense': {
        'receipts': [
          {
            'id': 'receipt-1',
            'kind': 'file',
            'attachmentId': 'attachment-1',
            'fileName': 'receipt.png',
            'mimeType': 'image/png',
            'sizeBytes': 128,
          },
        ],
      },
      'foreign': 'kept',
    });

    final payload = ExpensePayload.fromNode(source);
    expect(payload.receipts, hasLength(1));
    expect(payload.receipts.single.attachmentId, 'attachment-1');
    final data = payload.toData(source.data);
    expect(data['currency'], 'IDR');
    expect(data['foreign'], 'kept');
    expect(
      ((data['expense']! as Map<String, Object?>)['receipts']! as List).single,
      containsPair('attachmentId', 'attachment-1'),
    );
  });

  test('contact metric expense preserve flat legacy keys', () {
    const data = {
      'role': 'Designer',
      'email': 'a@example.com',
      'value': 12.5,
      'unit': 'km',
      'target': 20,
      'amount': 45000,
      'category': 'Food',
      'foreign': 'kept',
    };
    final contact = ContactPayload.fromNode(node(NodeType.contact, data));
    final metric = MetricPayload.fromNode(node(NodeType.metric, data));
    final expense = ExpensePayload.fromNode(node(NodeType.expense, data));
    expect(contact.role, 'Designer');
    expect(metric.value, 12.5);
    expect(expense.amount, 45000);
    expect(metric.validate(title: 'Run'), isEmpty);
    expect(expense.toData(data)['foreign'], 'kept');
  });

  test('mood preserves emoji and weather uses production keys', () {
    final mood = MoodPayload.fromNode(
      node(NodeType.mood, const {
        'mood':
            'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â°ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¥',
        'energy': 3,
      }),
    );
    final weather = WeatherPayload.fromNode(
      node(NodeType.weather, const {
        'temp': '31Ãƒâ€šÃ‚Â°C',
        'weather': 'Sunny',
        'temperature': 10,
        'condition': 'Stale',
      }),
    );
    final fit = FitPayload.fromNode(
      node(NodeType.fit, const {'steps': 5000, 'water': 6, 'workout': 'Run'}),
    );
    expect(
      mood.mood,
      'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â°ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¥',
    );
    expect(mood.validate(title: 'Mood'), isEmpty);
    expect(weather.temp, '31');
    expect(weather.weather, 'Sunny');
    expect(fit.steps, 5000);
    expect(mood.copyWith(energy: 99).validate(title: 'Mood'), isNotEmpty);
    final weatherData = weather.toData(const {
      'foreign': 1,
      'temperature': 10,
      'condition': 'Stale',
    });
    expect(weatherData['foreign'], 1);
    expect(weatherData['temp'], '31');
    expect(weatherData['weather'], 'Sunny');
    expect(weatherData['weatherUnit'], '°C');
    expect(weatherData.containsKey('temperature'), isFalse);
    expect(weatherData.containsKey('condition'), isFalse);
  });

  test('weather validates observation metadata and clears stale GPS', () {
    const payload = WeatherPayload(
      temp: '24',
      apparentTemp: '26',
      humidity: 78,
      windSpeed: 9.5,
      weather: 'Rain',
      unit: '°C',
      weatherCode: 'rain',
      weatherDate: '2026-07-19',
      latitude: -6.9175,
      longitude: 107.6191,
      location: 'Bandung',
      timezone: 'Asia/Jakarta',
      isDay: true,
    );

    expect(payload.validate(title: 'Bandung weather'), isEmpty);
    final manual = payload.copyWith(
      location: 'Jakarta',
      clearCoordinates: true,
    );
    expect(manual.latitude, isNull);
    expect(manual.longitude, isNull);
    final data = payload.toData(const <String, Object?>{});
    expect(data['weatherApparentTemp'], '26');
    expect(data['weatherHumidity'], 78);
    expect(data['weatherWindSpeed'], 9.5);
    expect(data['weatherTimezone'], 'Asia/Jakarta');
    expect(data['weatherIsDay'], isTrue);
    expect(
      payload
          .copyWith(weatherDate: '2026-02-31')
          .validate(title: 'Invalid weather'),
      contains('Date is invalid.'),
    );
  });

  test('weather body normalizes legacy degree encodings', () {
    expect(
      normalizeLegacyWeatherBody('Temp: 25Ãƒâ€šÃ‚Â°C / 77Ã‚Â°F / 18Â°C'),
      'Temp: 25°C / 77°F / 18°C',
    );
  });

  test('fitness payload round trips goals workout and recovery metrics', () {
    final source = node(NodeType.fit, const <String, Object?>{
      'foreign': true,
      'stepTarget': 8000,
      'waterTarget': 8,
    });
    const payload = FitPayload(
      steps: 6200,
      stepGoal: 10000,
      water: 1.5,
      waterGoal: 2.5,
      distance: 4.2,
      durationMinutes: 45,
      durationGoalMinutes: 60,
      calories: 360,
      calorieGoal: 600,
      sleepHours: 7.5,
      restingHeartRate: 58,
      workout: 'Run',
      intensity: 'high',
      completed: true,
      syncEnabled: true,
      syncSource: 'Health Connect',
      syncedAt: '2026-07-20T08:30:00.000',
      waterUnit: 'L',
      distanceUnit: 'km',
    );

    final data = payload.toData(source.data);
    final decoded = FitPayload.fromNode(source.copyWith(data: data));

    expect(data['foreign'], isTrue);
    expect(data.containsKey('stepTarget'), isFalse);
    expect(data.containsKey('waterTarget'), isFalse);
    expect(decoded.stepGoal, 10000);
    expect(decoded.waterGoal, 2.5);
    expect(decoded.distance, 4.2);
    expect(decoded.durationMinutes, 45);
    expect(decoded.durationGoalMinutes, 60);
    expect(decoded.calories, 360);
    expect(decoded.calorieGoal, 600);
    expect(decoded.sleepHours, 7.5);
    expect(decoded.restingHeartRate, 58);
    expect(decoded.workout, 'Run');
    expect(decoded.intensity, 'high');
    expect(decoded.completed, isTrue);
    expect(decoded.syncEnabled, isTrue);
    expect(decoded.syncSource, 'Health Connect');
    expect(decoded.syncedAt, '2026-07-20T08:30:00.000');
    expect(payload.validate(title: 'Morning run'), isEmpty);
    expect(
      payload.copyWith(intensity: 'extreme').validate(title: 'Invalid'),
      contains('Fitness intensity is invalid.'),
    );
    expect(
      payload.copyWith(sleepHours: 25).validate(title: 'Invalid'),
      contains('Value must be at most 24.'),
    );
  });

  test('fitness exercise sets round trip and validate', () {
    final base = node(NodeType.fit, const <String, Object?>{});
    const payload = FitPayload(
      exercises: <FitnessExercise>[
        FitnessExercise(
          id: 'squat',
          name: 'Squat',
          sets: <FitnessWorkoutSet>[
            FitnessWorkoutSet(
              id: 'set-1',
              reps: 8,
              weight: 60,
              completed: true,
            ),
          ],
        ),
      ],
    );

    final decoded = FitPayload.fromNode(
      base.copyWith(data: payload.toData(base.data)),
    );

    expect(decoded.exercises.single.name, 'Squat');
    expect(decoded.exercises.single.sets.single.reps, 8);
    expect(decoded.exercises.single.sets.single.weight, 60);
    expect(decoded.exercises.single.sets.single.completed, isTrue);
    expect(decoded.validate(title: 'Workout'), isEmpty);
    expect(
      payload
          .copyWith(
            exercises: const <FitnessExercise>[
              FitnessExercise(
                id: 'bad',
                name: '',
                sets: <FitnessWorkoutSet>[
                  FitnessWorkoutSet(id: 'set', reps: 0),
                ],
              ),
            ],
          )
          .validate(title: 'Workout'),
      isNotEmpty,
    );
  });

  test(
    'ExpensePayload round-trips amount category payment and receipt assets',
    () {
      final day = DateTime(2026, 7, 30);
      final base = MindmapNode.create(
        id: 'expense-test',
        type: NodeType.expense,
        title: 'Lunch with client',
        day: day,
        now: day,
      );
      const payload = ExpensePayload(
        amount: 150000,
        category: 'Food & Dining',
        merchant: 'Warung Kopi',
        payment: 'E-wallet',
        currency: 'IDR',
      );

      final data = payload.toData(base.data);
      final decoded = ExpensePayload.fromNode(base.copyWith(data: data));

      expect(decoded.amount, 150000);
      expect(decoded.category, 'Food & Dining');
      expect(decoded.merchant, 'Warung Kopi');
      expect(decoded.payment, 'E-wallet');
      expect(decoded.currency, 'IDR');
      expect(payload.validate(title: 'Lunch'), isEmpty);
      expect(
        const ExpensePayload(amount: -50).validate(title: 'Negative'),
        contains('Value must be at least 0.'),
      );
    },
  );

  test(
    'JournalPayload round trips weather dailyHighlight and prompt templates',
    () {
      final day = DateTime(2026, 7, 25);
      final base = MindmapNode.create(
        id: 'journal-test',
        type: NodeType.journal,
        title: 'Daily Journal',
        day: day,
        now: day,
      );
      final payload = JournalPayload(
        date: day,
        mood: 9,
        energy: 8,
        prompt: '3 Things I am grateful for today',
        gratitude: const <String>['Family', 'Flutter Code'],
        weather: 'sunny',
        dailyHighlight: 'Built Journal Enhancement',
        isWeeklyReview: true,
        isMonthlyReview: false,
      );

      final data = payload.toData(base.data);
      final decoded = JournalPayload.fromNode(base.copyWith(data: data));

      expect(decoded.mood, 9);
      expect(decoded.energy, 8);
      expect(decoded.prompt, '3 Things I am grateful for today');
      expect(decoded.gratitude, <String>['Family', 'Flutter Code']);
      expect(decoded.weather, 'sunny');
      expect(decoded.dailyHighlight, 'Built Journal Enhancement');
      expect(decoded.isWeeklyReview, isTrue);
      expect(decoded.isMonthlyReview, isFalse);
    },
  );

  test(
    'bookmark and resource write flat production keys without stale nested keys',
    () {
      const data = {
        'link': {'url': 'https://example.com', 'label': 'Docs'},
        'note': {'source': 'https://resource.test', 'author': 'Var'},
        'url': 'https://bookmark.test',
        'source': 'C:/docs/resource.pdf',
        'foreign': true,
      };
      final link = LinkResourcePayload.fromNode(node(NodeType.link, data));
      final bookmark = LinkResourcePayload.fromNode(
        node(NodeType.bookmark, data),
      );
      final resource = LinkResourcePayload.fromNode(
        node(NodeType.resource, data),
      );
      expect(link.url, 'https://example.com');
      expect(bookmark.url, 'https://bookmark.test');
      expect(resource.url, 'C:/docs/resource.pdf');
      expect(link.validate(title: 'Docs'), isEmpty);
      expect((link.toData(data)['link'] as Map)['label'], 'Docs');
      final bookmarkData = bookmark.toData(data);
      final resourceData = resource.toData(data);
      expect(bookmarkData['url'], 'https://bookmark.test');
      expect(bookmarkData['link'], {'label': 'Docs'});
      expect(resourceData['source'], 'C:/docs/resource.pdf');
      expect(resourceData['note'], {'author': 'Var'});
      expect(bookmarkData['foreign'], isTrue);
      expect(resourceData['foreign'], isTrue);
    },
  );

  test('resource payload round trips assets folders and unknown keys', () {
    final source = node(NodeType.resource, const <String, Object?>{
      'foreign': true,
      'resource': <String, Object?>{'foreignNested': 7},
    }).copyWith(tags: const <String>['old']);
    const payload = ResourcePayload(
      primaryAsset: ResourceAsset(
        id: 'primary',
        kind: 'file',
        label: 'Architecture PDF',
        attachmentId: 'attachment-1',
        mimeType: 'application/pdf',
        sizeBytes: 2048,
        fileName: 'architecture.pdf',
        extension: 'pdf',
      ),
      relatedAssets: <ResourceAsset>[
        ResourceAsset(
          id: 'related-1',
          kind: 'url',
          label: 'Reference',
          location: 'https://example.com/reference',
        ),
      ],
      folderPath: <String>['Research', 'Flutter', 'Rendering'],
      description: 'Rendering architecture reference.',
      tags: <String>['flutter', 'graphics'],
    );

    final updated = payload.toNode(source);
    final restored = ResourcePayload.fromNode(updated);

    expect(updated.data['foreign'], isTrue);
    expect((updated.data['resource'] as Map)['foreignNested'], 7);
    expect(updated.tags, <String>['flutter', 'graphics']);
    expect(restored.primaryAsset?.attachmentId, 'attachment-1');
    expect(restored.primaryAsset?.displayName, 'Architecture PDF');
    expect(
      restored.relatedAssets.single.location,
      'https://example.com/reference',
    );
    expect(restored.folderPath, <String>['Research', 'Flutter', 'Rendering']);
    expect(restored.description, 'Rendering architecture reference.');
    expect(restored.tags, <String>['flutter', 'graphics']);
  });

  test('resource folders persist asset membership and allow empty drafts', () {
    final source = node(NodeType.resource, const <String, Object?>{});
    const payload = ResourcePayload(
      folders: <ResourceFolder>[
        ResourceFolder(id: 'research', name: 'Research'),
        ResourceFolder(id: 'flutter', name: 'Flutter', parentId: 'research'),
      ],
      primaryAsset: ResourceAsset(
        id: 'primary',
        kind: 'url',
        label: 'Flutter docs',
        location: 'https://docs.flutter.dev',
        folderId: 'flutter',
      ),
      relatedAssets: <ResourceAsset>[
        ResourceAsset(
          id: 'related',
          kind: 'url',
          label: 'Dart docs',
          location: 'https://dart.dev',
          folderId: 'research',
        ),
      ],
    );

    final restored = ResourcePayload.fromNode(payload.toNode(source));

    expect(restored.folders, hasLength(2));
    expect(restored.primaryAsset?.folderId, 'flutter');
    expect(restored.relatedAssets.single.folderId, 'research');
    expect(restored.folderPathFor('flutter'), <String>['Research', 'Flutter']);
    expect(restored.validate(title: 'References'), isEmpty);
    expect(
      const ResourcePayload(
        description: 'Draft before choosing a file.',
      ).validate(title: 'New resource'),
      isEmpty,
    );
  });

  test('resource payload migrates legacy fields deterministically', () {
    final legacy = node(NodeType.resource, const <String, Object?>{
      'source': 'https://example.com/manual.pdf',
      'category': 'Research',
      'description': 'Legacy summary',
      'links': <String>['https://example.com/a', 'invalid'],
      'foreign': true,
    });

    final first = ResourcePayload.fromNode(legacy);
    final second = ResourcePayload.fromNode(legacy);
    final data = first.toData(legacy.data);

    expect(first.primaryAsset?.id, 'legacy-primary');
    expect(first.primaryAsset?.kind, 'url');
    expect(first.relatedAssets, hasLength(1));
    expect(first.relatedAssets.single.id, 'legacy-related-1');
    expect(first.folderPath, <String>['Research']);
    expect(first.description, 'Legacy summary');
    expect(second.primaryAsset?.id, first.primaryAsset?.id);
    expect(second.relatedAssets.single.id, first.relatedAssets.single.id);
    expect(data['foreign'], isTrue);
  });

  test('resource payload validates malformed assets folders and tags', () {
    const payload = ResourcePayload(
      schemaVersion: 2,
      primaryAsset: ResourceAsset(id: '', kind: 'unknown'),
      relatedAssets: <ResourceAsset>[
        ResourceAsset(id: 'same', kind: 'url', location: 'file://unsafe'),
        ResourceAsset(
          id: 'same',
          kind: 'file',
          mimeType: 'invalid',
          sizeBytes: -1,
        ),
      ],
      folderPath: <String>['Research', 'research', 'bad/name', ''],
      tags: <String>[''],
    );

    final errors = payload.validate(title: 'Resource');

    expect(errors, contains('Resource schema version is not supported.'));
    expect(errors, contains('Resource asset ID is required.'));
    expect(errors, contains('Resource asset kind is not supported.'));
    expect(errors, contains('Resource URL must use HTTP or HTTPS.'));
    expect(errors, contains('Resource asset IDs must be unique.'));
    expect(errors, contains('Resource file is unavailable.'));
    expect(errors, contains('Resource file size must not be negative.'));
    expect(errors, contains('Resource MIME type is invalid.'));
    expect(errors, contains('Resource folder supports at most three levels.'));
    expect(
      errors,
      contains('Adjacent Resource folder names must be different.'),
    );
    expect(
      errors,
      contains('Resource folder name must not contain path separators.'),
    );
    expect(errors, contains('Resource folder name is required.'));
    expect(errors, contains('Resource tag must not be empty.'));
  });

  test('timer audio canvas read and write production keys', () {
    const data = {
      'timerSeconds': 1200,
      'timerInitialSeconds': 1500,
      'audioPath': 'C:/recordings/memo.m4a',
      'audioDuration': '2:31',
      'audioTranscript': 'Hello',
      'durationMinutes': 25,
      'elapsedSeconds': 60,
      'source': 'https://stale.test/audio.mp3',
      'transcript': 'Stale',
      'strokes': ['a'],
      'background': 'grid',
      'foreign': false,
    };
    final timer = TimerPayload.fromNode(node(NodeType.timer, data));
    final audio = AudioPayload.fromNode(node(NodeType.audio, data));
    final canvas = CanvasPayload.fromNode(node(NodeType.canvas, data));
    expect(timer.timerSeconds, 1200);
    expect(timer.timerInitialSeconds, 1500);
    expect(audio.audioPath, 'C:/recordings/memo.m4a');
    expect(audio.audioDuration, '2:31');
    expect(audio.audioTranscript, 'Hello');
    expect(canvas.strokes, ['a']);
    expect(timer.validate(title: 'Focus'), isEmpty);
    expect(audio.validate(title: 'Memo'), isEmpty);
    expect(timer.toData(data)['timerSeconds'], 1200);
    expect(timer.toData(data).containsKey('durationMinutes'), isFalse);
    expect(audio.toData(data)['audioPath'], 'C:/recordings/memo.m4a');
    expect(audio.toData(data).containsKey('source'), isFalse);
    expect(audio.toData(data).containsKey('transcript'), isFalse);
    expect(canvas.toData(data)['foreign'], isFalse);
  });

  test('audio payload migrates legacy URL source', () {
    final payload = AudioPayload.fromNode(
      node(NodeType.audio, const <String, Object?>{
        'audioPath': 'https://cdn.example.test/memo.mp3',
        'audioDuration': '2:31',
        'audioTranscript': 'Hello world',
      }),
    );
    expect(payload.sourceType, AudioSourceType.url);
    expect(payload.remoteUrl, 'https://cdn.example.test/memo.mp3');
    expect(payload.durationMilliseconds, 151000);
    expect(payload.transcriptText, 'Hello world');
  });

  test('timer migrates legacy countdown and preserves nested sentinels', () {
    const data = <String, Object?>{
      'timerSeconds': 1200,
      'timerInitialSeconds': 1500,
      'timer': <String, Object?>{'theme': 'fuchsia'},
      'foreign': true,
    };
    final payload = TimerPayload.fromNode(node(NodeType.timer, data));
    final encoded = payload.toData(data);

    expect(payload.timer.mode, TimerMode.countdown);
    expect(payload.timer.status, TimerRunStatus.paused);
    expect(payload.timer.plannedSeconds, 1500);
    expect(payload.timer.accumulatedSeconds, 300);
    expect((encoded['timer'] as Map)['theme'], 'fuchsia');
    expect(encoded['foreign'], isTrue);
  });

  test('timer safely defaults fractional and non-finite legacy values', () {
    for (final value in [1.9, double.infinity, double.nan]) {
      final payload = TimerPayload.fromNode(
        node(NodeType.timer, {
          'timerSeconds': value,
          'timerInitialSeconds': value,
        }),
      );
      expect(payload.timerSeconds, 1500, reason: '$value');
      expect(payload.timerInitialSeconds, 1500, reason: '$value');
    }
  });

  test('journal payload round-trips nested production keys', () {
    const data = {
      'journal': {
        'mood': 8,
        'energy': 6,
        'prompt': 'What changed?',
        'gratitude': ['Health'],
        'isWeeklyReview': true,
        'isMonthlyReview': true,
        'foreign': 'kept',
      },
      'rootForeign': true,
    };
    final payload = JournalPayload.fromNode(node(NodeType.journal, data));
    expect(payload.mood, 8);
    expect(payload.energy, 6);
    expect(payload.date, DateTime(2026, 7, 13));
    final written = payload
        .copyWith(prompt: 'What worked?', isMonthlyReview: false)
        .toData(data);
    expect((written['journal'] as Map)['prompt'], 'What worked?');
    expect((written['journal'] as Map)['foreign'], 'kept');
    expect((written['journal'] as Map)['isMonthlyReview'], isFalse);
    expect(written['rootForeign'], isTrue);
    expect(payload.validate(title: 'Journal'), isEmpty);
    expect(payload.copyWith(mood: 11).validate(title: 'Journal'), isNotEmpty);
  });

  test('canvas payload round trips structured visual elements', () {
    const payload = CanvasPayload(
      background: 'grid',
      activeTool: 'pen',
      penColor: 'blue',
      penWidth: 4,
      elementGroups: <String, String>{'stroke': 'Sketches'},
      elements: <CanvasElement>[
        CanvasStroke(
          id: 'stroke',
          color: 'blue',
          width: 3,
          points: <CanvasPoint>[CanvasPoint(0.1, 0.2), CanvasPoint(0.3, 0.4)],
        ),
        CanvasTextElement(
          id: 'text',
          color: 'neutral',
          position: CanvasPoint(0.2, 0.3),
          text: 'Label',
        ),
        CanvasStickyElement(
          id: 'sticky',
          color: 'neutral',
          position: CanvasPoint(0.4, 0.3),
          text: 'Note',
        ),
        CanvasShapeElement(
          id: 'rect',
          color: 'green',
          shape: 'rectangle',
          start: CanvasPoint(0.1, 0.1),
          end: CanvasPoint(0.5, 0.5),
        ),
        CanvasShapeElement(
          id: 'ellipse',
          color: 'rose',
          shape: 'ellipse',
          start: CanvasPoint(0.5, 0.2),
          end: CanvasPoint(0.8, 0.6),
        ),
        CanvasArrowElement(
          id: 'arrow',
          color: 'amber',
          start: CanvasPoint(0.2, 0.8),
          end: CanvasPoint(0.8, 0.8),
        ),
      ],
    );

    final data = payload.toData(const <String, Object?>{
      'foreign': true,
      'canvas': <String, Object?>{'nestedForeign': 'kept'},
    });
    final decoded = CanvasPayload.fromNode(node(NodeType.canvas, data));

    expect(decoded.background, 'grid');
    expect(decoded.activeTool, 'pen');
    expect(decoded.elements, hasLength(6));
    expect(decoded.elementGroups['stroke'], 'Sketches');
    expect(decoded.elements[0], isA<CanvasStroke>());
    expect(decoded.elements[1], isA<CanvasTextElement>());
    expect(decoded.elements[2], isA<CanvasStickyElement>());
    expect(decoded.elements[3], isA<CanvasShapeElement>());
    expect(decoded.elements[5], isA<CanvasArrowElement>());
    expect(decoded.drawingCount, 1);
    expect(decoded.textCount, 2);
    expect(decoded.shapeCount, 3);
    expect(data['foreign'], isTrue);
    expect((data['canvas'] as Map)['nestedForeign'], 'kept');
    expect(data['strokes'], isNotEmpty);
    expect(decoded.validate(title: 'Sketch'), isEmpty);
  });

  test('canvas element removal prunes groups and clears legacy strokes', () {
    const payload = CanvasPayload(
      strokes: <String>['0.1,0.1;0.2,0.2'],
      elementGroups: <String, String>{
        'keep': ' Notes ',
        'remove': 'Sketches',
        'missing': 'Invalid',
      },
      elements: <CanvasElement>[
        CanvasTextElement(
          id: 'keep',
          color: 'neutral',
          position: CanvasPoint(0.2, 0.3),
          text: 'Keep',
        ),
        CanvasTextElement(
          id: 'remove',
          color: 'neutral',
          position: CanvasPoint(0.4, 0.3),
          text: 'Remove',
        ),
      ],
    );

    final reduced = payload.copyWith(
      elements: <CanvasElement>[payload.elements.first],
    );
    final cleared = reduced.copyWith(elements: const <CanvasElement>[]);

    expect(reduced.elementGroups, const <String, String>{'keep': 'Notes'});
    expect(cleared.elementGroups, isEmpty);
    expect(cleared.strokes, isEmpty);
    expect(
      CanvasPayload.fromNode(
        node(NodeType.canvas, cleared.toData(const <String, Object?>{})),
      ).elements,
      isEmpty,
    );
  });

  test('canvas block document round trips and preserves unknown blocks', () {
    final decoded = CanvasPayload.fromNode(
      node(NodeType.canvas, const <String, Object?>{
        'canvas': <String, Object?>{
          'viewMode': 'blocks',
          'blocks': <String, Object?>{
            'schemaVersion': 1,
            'blocks': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'known',
                'type': 'checklist',
                'text': 'Ship',
                'checked': true,
              },
              <String, Object?>{
                'id': 'future',
                'type': 'futureType',
                'cells': <String>['A'],
              },
            ],
          },
        },
      }),
    );

    expect(decoded.viewMode, 'blocks');
    expect(decoded.blocks.blocks, hasLength(2));
    expect(decoded.blocks.blocks.first.checked, isTrue);
    final encoded = decoded.toData(const <String, Object?>{});
    final canvas = encoded['canvas']! as Map<String, Object?>;
    final document = canvas['blocks']! as Map<String, Object?>;
    final blocks = document['blocks']! as List<Object?>;
    expect((blocks.last! as Map<String, Object?>)['type'], 'futureType');
    expect(decoded.validate(title: 'Document'), isEmpty);
  });

  test('canvas block validation rejects duplicate and oversized content', () {
    final payload = CanvasPayload(
      blocks: CanvasBlockDocument(
        blocks: <CanvasBlock>[
          const CanvasBlock(
            id: 'same',
            type: CanvasBlockType.paragraph,
            text: 'ok',
          ),
          CanvasBlock(
            id: 'same',
            type: CanvasBlockType.code,
            text: 'x' * 10001,
          ),
        ],
      ),
    );

    expect(payload.validate(title: 'Document'), hasLength(2));
  });

  test('drawing payload limits reject oversized and non-finite geometry', () {
    final canvas = CanvasPayload(
      elements: <CanvasElement>[
        CanvasStroke(
          id: 'stroke',
          color: 'blue',
          points: List<CanvasPoint>.filled(
            maxDrawingPointsPerItem + 1,
            const CanvasPoint(0.5, 0.5),
          ),
        ),
      ],
    );
    const image = ImagePayload(
      url: 'https://example.test/image.png',
      annotations: <ImageAnnotation>[
        ImageAnnotation(
          id: 'bad',
          type: ImageAnnotationType.arrow,
          positionX: double.nan,
        ),
      ],
    );

    expect(
      canvas.validate(title: 'Canvas'),
      contains('Canvas stroke contains too many points.'),
    );
    expect(
      image.validate(title: 'Image'),
      contains('Image annotation geometry is invalid.'),
    );
  });

  test('canvas payload migrates safe legacy strokes', () {
    final decoded = CanvasPayload.fromNode(
      node(NodeType.canvas, const <String, Object?>{
        'strokes': <String>['0.1,0.2;0.3,0.4', 'malformed'],
        'background': 'dots',
      }),
    );

    expect(decoded.background, 'dots');
    expect(decoded.elements, hasLength(1));
    expect(decoded.elements.single.id, 'legacy-stroke-1');
  });

  test('canvas payload validates malformed visual elements', () {
    const payload = CanvasPayload(
      schemaVersion: 2,
      background: 'paper',
      activeTool: 'spray',
      penColor: 'invalid',
      penWidth: 0,
      elements: <CanvasElement>[
        CanvasStroke(
          id: 'same',
          color: 'invalid',
          points: <CanvasPoint>[CanvasPoint(-1, 2)],
          width: 0,
        ),
        CanvasTextElement(
          id: 'same',
          color: 'neutral',
          position: CanvasPoint(0.2, 0.3),
          text: '',
          fontSize: 0,
        ),
        CanvasUnknownElement(id: '', color: 'neutral'),
      ],
    );

    expect(payload.validate(title: 'Canvas'), hasLength(14));
  });

  test('thinking payloads use stable flat production-compatible keys', () {
    const data = {'foreign': 'kept'};
    const idea = IdeaPayload(
      maturity: 'forming',
      evidence: 'Interview notes',
      nextAction: 'Prototype',
    );
    const question = QuestionPayload(
      investigationStatus: 'researching',
      answer: 'Not yet',
      evidence: 'Paper A',
    );
    const decision = DecisionPayload(
      criteria: <DecisionCriterion>[
        DecisionCriterion(id: 'criterion-1', name: 'Risk and value'),
      ],
      options: <DecisionOption>[
        DecisionOption(id: 'ship', title: 'Ship'),
        DecisionOption(id: 'wait', title: 'Wait'),
      ],
      selectedOptionId: 'ship',
      rationale: 'Value wins',
    );
    const quote = QuotePayload(author: 'Grace Hopper', source: 'Speech');
    expect(
      IdeaPayload.fromNode(node(NodeType.idea, idea.toData(data))).maturity,
      'forming',
    );
    expect(
      QuestionPayload.fromNode(
        node(NodeType.question, question.toData(data)),
      ).answer,
      'Not yet',
    );
    final decisionData = decision.toData(data);
    expect(decisionData['options'], 'Ship\nWait');
    expect(decisionData['selectedOption'], 'Ship');
    expect(decisionData['reason'], 'Value wins');
    expect(
      DecisionPayload.fromNode(
        node(NodeType.decision, decisionData),
      ).options.map((option) => option.title),
      ['Ship', 'Wait'],
    );
    expect(
      QuotePayload.fromNode(node(NodeType.quote, quote.toData(data))).source,
      'Speech',
    );
    expect(decisionData['foreign'], 'kept');
  });

  test('quote payload supports collection tags and favorite', () {
    const payload = QuotePayload(
      author: 'Grace Hopper',
      source: 'Speech',
      collection: 'Computing',
      tags: <String>[' wisdom ', 'Computing', 'WISDOM', ''],
      isFavorite: true,
    );

    final data = payload.toData(const <String, Object?>{'foreign': 'kept'});
    final decoded = QuotePayload.fromNode(node(NodeType.quote, data));

    expect(decoded.author, 'Grace Hopper');
    expect(decoded.source, 'Speech');
    expect(decoded.collection, 'Computing');
    expect(decoded.tags, <String>['wisdom', 'Computing']);
    expect(decoded.isFavorite, isTrue);
    expect(data['foreign'], 'kept');
  });

  test('idea payload supports incubation and experiment guidance', () {
    const payload = IdeaPayload(
      maturity: 'exploring',
      hypothesis: 'Users need faster capture',
      impact: 'high',
      effort: 'medium',
      confidence: 70,
      evidence: 'Five interviews',
      nextAction: 'Build prototype',
    );

    final data = payload.toData(const {'foreign': 'kept'});
    final decoded = IdeaPayload.fromNode(node(NodeType.idea, data));

    expect(decoded.hypothesis, payload.hypothesis);
    expect(decoded.impact, 'high');
    expect(decoded.effort, 'medium');
    expect(decoded.confidence, 70);
    expect(decoded.validationCompleted, 3);
    expect(decoded.suggestedMaturity, 'validated');
    expect(data['foreign'], 'kept');
    expect(decoded.validate(title: 'Capture'), isEmpty);
    expect(
      decoded.copyWith(confidence: 101).validate(title: 'Capture'),
      isNotEmpty,
    );
  });

  test('idea stage suggestion remains non-destructive', () {
    const payload = IdeaPayload(
      maturity: 'spark',
      hypothesis: 'A testable idea',
    );

    expect(payload.suggestedMaturity, 'exploring');
    expect(payload.maturity, 'spark');
    expect(payload.validationCompleted, 1);
  });

  test('question payload supports structured research workflow', () {
    const payload = QuestionPayload(
      investigationStatus: 'researching',
      questionText: 'Which capture flow is fastest?',
      questionContext: 'Compare keyboard-first options.',
      possibleAnswers: <String>['Global shortcut', 'Quick panel'],
      answer: 'Global shortcut',
      evidence: 'Median capture time was lower.',
      questionSources: <String>['Usability study', 'Analytics report'],
      nextResearchAction: 'Validate on mobile.',
      questionConfidence: 82,
    );

    final data = payload.toData(const <String, Object?>{'foreign': 'kept'});
    final decoded = QuestionPayload.fromNode(node(NodeType.question, data));

    expect(decoded.questionText, payload.questionText);
    expect(decoded.questionContext, payload.questionContext);
    expect(decoded.possibleAnswers, payload.possibleAnswers);
    expect(decoded.answer, payload.answer);
    expect(decoded.evidence, payload.evidence);
    expect(decoded.questionSources, payload.questionSources);
    expect(decoded.nextResearchAction, payload.nextResearchAction);
    expect(decoded.questionConfidence, 82);
    expect(decoded.researchCompleted, 4);
    expect(decoded.suggestedInvestigationStatus, 'answered');
    expect(data['foreign'], 'kept');
    expect(decoded.validate(title: 'Capture flow'), isEmpty);
  });

  test('question payload suggestion remains non-destructive', () {
    const payload = QuestionPayload(
      investigationStatus: 'open',
      questionText: 'What should ship?',
      possibleAnswers: <String>['Option A'],
    );

    expect(payload.suggestedInvestigationStatus, 'researching');
    expect(payload.investigationStatus, 'open');
    expect(payload.researchCompleted, 2);
  });

  test('question payload validates status lists and confidence', () {
    const payload = QuestionPayload(
      investigationStatus: 'unknown',
      possibleAnswers: <String>[''],
      questionSources: <String>[''],
      questionConfidence: 101,
    );

    expect(payload.validate(title: 'Question'), hasLength(4));
  });
  test('decision payload supports weighted decision records', () {
    const payload = DecisionPayload(
      status: 'evaluating',
      question: 'Which option should ship?',
      context: 'Choose for the beta release.',
      owner: 'Product',
      deadline: '2026-07-20',
      reviewDate: '2026-08-20',
      confidence: 75,
      criteria: <DecisionCriterion>[
        DecisionCriterion(id: 'impact', name: 'Impact', weight: 2),
        DecisionCriterion(id: 'effort', name: 'Effort', weight: 1),
      ],
      options: <DecisionOption>[
        DecisionOption(
          id: 'a',
          title: 'Option A',
          pros: <String>['High value'],
          scores: <String, int>{'impact': 9, 'effort': 6},
        ),
        DecisionOption(
          id: 'b',
          title: 'Option B',
          cons: <String>['Lower reach'],
          risks: <String>['Migration'],
          riskAssessments: <DecisionRisk>[
            DecisionRisk(
              id: 'migration',
              title: 'Migration delay',
              probability: 3,
              impact: 4,
            ),
          ],
          scores: <String, int>{'impact': 7, 'effort': 9},
        ),
      ],
      selectedOptionId: 'a',
      rationale: 'Higher weighted value.',
      assumptions: 'Team capacity remains stable.',
      expectedOutcome: 'Faster activation.',
      reviewNotes: 'Review after one month.',
      reviewEntries: <DecisionReviewEntry>[
        DecisionReviewEntry(
          id: 'review-1',
          date: '2026-08-20',
          notes: 'Outcome met expectations.',
          rating: 4,
        ),
      ],
    );

    final data = payload.toData(const <String, Object?>{
      'foreign': 'kept',
      'decision': <String, Object?>{'nestedForeign': true},
    });
    final decoded = DecisionPayload.fromNode(node(NodeType.decision, data));

    expect(decoded.status, 'evaluating');
    expect(decoded.question, payload.question);
    expect(decoded.criteria, hasLength(2));
    expect(decoded.options, hasLength(2));
    expect(decoded.options.last.riskExposure, 12);
    expect(decoded.reviewEntries.single.rating, 4);
    expect(decoded.selectedOption?.title, 'Option A');
    expect(decoded.weightedScores['a'], closeTo(8, 0.001));
    expect(decoded.weightedScores['b'], closeTo(7.666, 0.001));
    expect(decoded.recommendedOptionId, 'a');
    expect(decoded.decisionCompleted, 5);
    expect(decoded.suggestedStatus, 'decided');
    expect(data['foreign'], 'kept');
    expect((data['decision'] as Map)['nestedForeign'], isTrue);
    expect(data['options'], 'Option A\nOption B');
    expect(data['selectedOption'], 'Option A');
    expect(decoded.validate(title: 'Release decision'), isEmpty);
  });

  test('decision payload reads legacy keys deterministically', () {
    final decoded = DecisionPayload.fromNode(
      node(NodeType.decision, const <String, Object?>{
        'options': 'Ship\nWait',
        'criteria': 'Risk\nValue',
        'selectedOption': 'Wait',
        'reason': 'Lower risk',
      }),
    );

    expect(decoded.criteria.map((item) => item.id), <String>[
      'criterion-1',
      'criterion-2',
    ]);
    expect(decoded.options.map((item) => item.id), <String>[
      'option-1',
      'option-2',
    ]);
    expect(decoded.selectedOptionId, 'option-2');
    expect(decoded.rationale, 'Lower risk');
  });

  test(
    'decision payload keeps recommendation non-destructive and cleans IDs',
    () {
      const payload = DecisionPayload(
        status: 'draft',
        criteria: <DecisionCriterion>[
          DecisionCriterion(id: 'value', name: 'Value'),
        ],
        options: <DecisionOption>[
          DecisionOption(
            id: 'a',
            title: 'A',
            scores: <String, int>{'value': 5},
          ),
          DecisionOption(
            id: 'b',
            title: 'B',
            scores: <String, int>{'value': 9},
          ),
        ],
        selectedOptionId: 'a',
      );

      expect(payload.recommendedOptionId, 'b');
      expect(payload.selectedOptionId, 'a');
      expect(payload.suggestedStatus, 'evaluating');
      expect(payload.removeCriterion('value').options.first.scores, isEmpty);
      expect(payload.removeOption('a').selectedOptionId, isEmpty);
    },
  );

  test('decision payload validates malformed records', () {
    const payload = DecisionPayload(
      status: 'invalid',
      deadline: '2026-02-30',
      reviewDate: 'tomorrow',
      confidence: 101,
      criteria: <DecisionCriterion>[
        DecisionCriterion(id: 'same', name: '', weight: 0),
        DecisionCriterion(id: 'same', name: 'Duplicate'),
      ],
      options: <DecisionOption>[
        DecisionOption(
          id: 'option',
          title: '',
          scores: <String, int>{'unknown': 11},
        ),
        DecisionOption(id: 'option', title: 'Duplicate'),
      ],
      selectedOptionId: 'missing',
    );

    expect(payload.validate(title: 'Decision'), hasLength(12));
  });

  test('bookmark and resource extended fields preserve node metadata', () {
    final bookmarkNode = node(NodeType.bookmark, const {
      'url': 'https://example.com',
      'collection': 'Research',
      'description': 'Useful Flutter reference',
      'bookmarkStatus': 'reading',
      'bookmarkFavorite': true,
      'foreign': true,
    }).copyWith(tags: const ['flutter', 'ux']);
    final bookmark = LinkResourcePayload.fromNode(bookmarkNode);
    expect(bookmark.collection, 'Research');
    expect(bookmark.description, 'Useful Flutter reference');
    expect(bookmark.bookmarkStatus, 'reading');
    expect(bookmark.isFavorite, isTrue);
    expect(bookmark.tags, ['flutter', 'ux']);
    final updatedBookmark = bookmark
        .copyWith(tags: const ['saved'])
        .toNode(bookmarkNode);
    expect(updatedBookmark.tags, ['saved']);
    expect(updatedBookmark.data['foreign'], isTrue);
    expect(updatedBookmark.data['bookmarkStatus'], 'reading');
    expect(updatedBookmark.data['bookmarkFavorite'], isTrue);
    expect(
      bookmark.copyWith(bookmarkStatus: 'invalid').validate(title: 'Saved'),
      contains('Bookmark status is invalid.'),
    );

    final resource = LinkResourcePayload.fromNode(
      node(NodeType.resource, const {
        'source': 'Paper',
        'category': 'Research',
        'description': 'Useful summary',
        'links': ['https://example.com/a'],
      }),
    );
    expect(resource.category, 'Research');
    expect(resource.description, 'Useful summary');
    expect(resource.links, ['https://example.com/a']);
  });

  test('note payload round trips metadata and rejects malformed URLs', () {
    final source = node(NodeType.note, const <String, Object?>{'foreign': 7});
    const payload = NotePayload(
      color: 'violet',
      sourceLinks: <NoteSourceLink>[
        NoteSourceLink(
          id: 'source-1',
          label: 'Spec',
          url: 'https://example.test/spec',
        ),
      ],
      attachments: <TaskAttachmentReference>[
        TaskAttachmentReference(
          id: 'attachment-1',
          fileName: 'brief.pdf',
          mimeType: 'application/pdf',
          byteLength: 42,
        ),
      ],
    );

    final data = payload.toData(source.data);
    final roundTrip = NotePayload.fromNode(source.copyWith(data: data));

    expect(data['foreign'], 7);
    expect(roundTrip.color, 'violet');
    expect(roundTrip.sourceLinks.single.url, 'https://example.test/spec');
    expect(roundTrip.attachments.single.id, 'attachment-1');
    expect(payload.validate(title: source.title), isEmpty);
    expect(
      payload
          .copyWith(
            sourceLinks: const <NoteSourceLink>[
              NoteSourceLink(id: 'bad', label: 'Bad', url: 'file:///tmp/a'),
            ],
          )
          .validate(title: source.title),
      contains('Source URL must use http or https.'),
    );
  });
}
