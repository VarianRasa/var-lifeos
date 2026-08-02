import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/fitness_health_providers.dart';
import 'package:var_app/features/mindmap/application/weather_providers.dart';
import 'package:var_app/features/mindmap/data/open_meteo_weather_service.dart';
import 'package:var_app/features/mindmap/domain/fitness_health.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/life_data_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_type_content.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  const types = [
    NodeType.event,
    NodeType.contact,
    NodeType.metric,
    NodeType.expense,
    NodeType.mood,
    NodeType.weather,
    NodeType.fit,
    NodeType.empty,
  ];
  for (final type in types) {
    for (final preset in const [
      NodeSizePreset.compact,
      NodeSizePreset.standard,
      NodeSizePreset.large,
      NodeSizePreset.wide,
    ]) {
      testWidgets('${type.name} renders ${preset.name} without overflow', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: preset == NodeSizePreset.compact ? 220 : 520,
              height: preset == NodeSizePreset.compact ? 130 : 360,
              child: buildNodeTypeContent(
                NodeRenderContext(node: _node(type), effectivePreset: preset),
              ),
            ),
          ),
        );
        expect(
          find.byKey(ValueKey('life-data-${type.name}-${preset.name}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('weather editor persists location and observation date', (
    tester,
  ) async {
    await _useTallEditorSurface(tester);
    final drafts = <Object>[];
    final node = _node(NodeType.weather);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            WeatherPayload.fromNode(node),
            drafts,
            preset: NodeSizePreset.large,
          ),
        ),
        height: 1100,
      ),
    );

    final locationField = find.byKey(
      const ValueKey('life-data-weather-location-field'),
    );
    final dateField = find.byKey(
      const ValueKey('life-data-weather-date-field'),
    );
    await tester.ensureVisible(locationField);
    await tester.enterText(locationField, 'Bandung');
    await tester.ensureVisible(dateField);
    await tester.enterText(dateField, '2026-07-19');

    final payload = drafts.last as WeatherPayload;
    expect(payload.location, 'Bandung');
    expect(payload.weatherDate, '2026-07-19');
    final updated = applyNodeTypeInlineDraft(node, payload);
    expect(updated.data['weatherLocation'], 'Bandung');
    expect(updated.data['weatherDate'], '2026-07-19');
  });

  testWidgets('weather editor repairs legacy degree encoding', (tester) async {
    await _useTallEditorSurface(tester);
    final bodies = <String>[];
    final node = _node(NodeType.weather).copyWith(body: 'Temp: 25Ãƒâ€šÃ‚Â°C');
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            WeatherPayload.fromNode(node),
            <Object>[],
            bodies: bodies,
            preset: NodeSizePreset.large,
          ),
        ),
        height: 1100,
      ),
    );
    await tester.pump();

    final notesField = find.byKey(
      const ValueKey('life-data-weather-notes-field'),
    );
    final editable = tester.widget<EditableText>(
      find.descendant(of: notesField, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'Temp: 25°C');
    expect(bodies, <String>['Temp: 25°C']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather editor applies presets and converts temperature unit', (
    tester,
  ) async {
    await _useTallEditorSurface(tester);
    final drafts = <Object>[];
    final node = _node(NodeType.weather);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            WeatherPayload.fromNode(node),
            drafts,
            preset: NodeSizePreset.large,
          ),
        ),
        height: 1100,
      ),
    );

    expect(
      find.byKey(const ValueKey('life-data-weather-summary-card')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-weather-temp-field')),
      '20',
    );
    await tester.pump();
    final rain = find.byKey(const ValueKey('life-data-weather-condition-rain'));
    await tester.ensureVisible(rain);
    await tester.tap(rain);
    await tester.pump();
    final fahrenheit = find.descendant(
      of: find.byKey(const ValueKey('life-data-weather-unit-toggle')),
      matching: find.text('°F'),
    );
    await tester.ensureVisible(fahrenheit);
    await tester.tap(fahrenheit);
    await tester.pump();

    final payload = drafts.last as WeatherPayload;
    expect(payload.temp, '68');
    expect(payload.unit, '°F');
    expect(payload.weather, 'Rain');
    expect(payload.weatherCode, 'rain');
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather editor searches a city and applies live weather', (
    tester,
  ) async {
    await _useTallEditorSurface(tester);
    final drafts = <Object>[];
    final node = _node(NodeType.weather);
    final service = OpenMeteoWeatherService(
      client: MockClient((request) async {
        if (request.url.host == 'geocoding-api.open-meteo.com') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'results': <Object?>[
                <String, Object?>{
                  'id': 1650357,
                  'name': 'Bandung',
                  'latitude': -6.9175,
                  'longitude': 107.6191,
                  'country': 'Indonesia',
                  'admin1': 'West Java',
                  'country_code': 'ID',
                  'timezone': 'Asia/Jakarta',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'timezone': 'Asia/Jakarta',
            'current': <String, Object?>{
              'time': '2026-07-19T14:15',
              'temperature_2m': 25.4,
              'apparent_temperature': 27.1,
              'relative_humidity_2m': 83,
              'weather_code': 61,
              'wind_speed_10m': 8.6,
              'is_day': 1,
            },
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            WeatherPayload.fromNode(node),
            drafts,
            preset: NodeSizePreset.large,
          ),
        ),
        height: 1100,
        overrides: <Override>[
          weatherServiceProvider.overrideWithValue(service),
        ],
      ),
    );

    final searchField = find.byKey(
      const ValueKey('life-data-weather-location-search-field'),
    );
    await tester.enterText(searchField, 'Bandung');
    await tester.tap(
      find.byKey(const ValueKey('life-data-weather-location-search')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final result = find.byKey(
      const ValueKey('life-data-weather-location-result-0'),
    );
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final payload = drafts.last as WeatherPayload;
    expect(payload.location, 'Bandung, West Java, Indonesia');
    expect(payload.temp, '25.4');
    expect(payload.apparentTemp, '27.1');
    expect(payload.humidity, 83);
    expect(payload.windSpeed, 8.6);
    expect(payload.weather, 'Rain');
    expect(payload.weatherCode, 'rain');
    expect(payload.weatherDate, '2026-07-19');
    expect(payload.latitude, -6.9175);
    expect(payload.longitude, 107.6191);
    expect(payload.timezone, 'Asia/Jakarta');
    expect(payload.isDay, isTrue);
    final updated = applyNodeTypeInlineDraft(node, payload);
    expect(updated.data['temp'], '25.4');
    expect(updated.data['weatherApparentTemp'], '27.1');
    expect(updated.data['weatherHumidity'], 83);
    expect(updated.data['weatherWindSpeed'], 8.6);
    expect(updated.data['weatherLocation'], 'Bandung, West Java, Indonesia');
    expect(find.text('25.4°C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather content summarizes location and observation date', (
    tester,
  ) async {
    final base = _node(NodeType.weather);
    final node = base.copyWith(
      data: WeatherPayload.fromNode(base)
          .copyWith(location: 'Bandung', weatherDate: '2026-07-19')
          .toData(base.data),
    );
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 520,
          height: 220,
          child: buildNodeTypeContent(
            NodeRenderContext(
              node: node,
              effectivePreset: NodeSizePreset.standard,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Bandung'), findsOneWidget);
    expect(find.textContaining('2026-07-19'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metric editor persists target direction and progress', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.metric);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, MetricPayload.fromNode(node), drafts),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.tap(find.text('Maximum'));
    await tester.pump();
    expect((drafts.last as MetricPayload).direction, 'atMost');
    expect(find.byKey(const ValueKey('metric-direction')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sequential metric edits keep latest local draft', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.metric);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, MetricPayload.fromNode(node), drafts),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-metric-value-field')),
      '12',
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-metric-unit-field')),
      'kg',
    );
    final latest = drafts.last as MetricPayload;
    expect(latest.value, 12);
    expect(latest.unit, 'kg');
  });

  testWidgets('invalid number displays error and emits no stale draft', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.expense);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, ExpensePayload.fromNode(node), drafts),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-expense-amount-field')),
      'NaN?',
    );
    await tester.pump();
    expect(find.text('Enter a finite number.'), findsOneWidget);
    expect(drafts, isEmpty);
  });

  testWidgets('event date picker writes selected value into visible field', (
    tester,
  ) async {
    final node = MindmapNode.create(
      id: 'event-picker',
      type: NodeType.event,
      title: 'Event',
      day: DateTime(2026, 7, 13),
      now: DateTime(2026, 7, 13),
    );
    final drafts = <Object>[];
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, EventCalendarPayload.fromNode(node), drafts),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('life-data-event-start-date-field')),
    );
    expect(field.controller?.text, '2026-07-13');
    expect((drafts.last as EventCalendarPayload).startDate, '2026-07-13');
    expect((drafts.last as EventCalendarPayload).endDate, '2026-07-13');
  });

  testWidgets('event picker values can be cleared safely', (tester) async {
    final drafts = <Object>[];
    final node = _node(NodeType.event);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, EventCalendarPayload.fromNode(node), drafts),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Clear Start date'));
    await tester.pump();
    var payload = drafts.last as EventCalendarPayload;
    expect(payload.startDate, isEmpty);
    expect(payload.endDate, isEmpty);

    await tester.tap(find.byTooltip('Clear Start time'));
    await tester.pump();
    payload = drafts.last as EventCalendarPayload;
    expect(payload.startTime, isEmpty);
    expect(payload.endTime, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('event picker buttons open native date and time dialogs', (
    tester,
  ) async {
    final node = _node(NodeType.event);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, EventCalendarPayload.fromNode(node), <Object>[]),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose Start date'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose Start time'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('event uses local day and rejects reversed range', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.event);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, EventCalendarPayload.fromNode(node), drafts),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-date-field')),
      '2026-07-14',
    );
    expect((drafts.last as EventCalendarPayload).startDate, '2026-07-14');
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-end-date-field')),
      '2026-07-13',
    );
    await tester.pump();
    expect(
      find.text('End date must not precede start date.'),
      findsNWidgets(2),
    );
  });

  testWidgets('event rejects invalid and same-day reversed start time', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.event);
    const payload = EventCalendarPayload(
      startDate: '2026-07-13',
      endDate: '2026-07-13',
      startTime: '09:00',
      endTime: '10:00',
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, payload, drafts, preset: NodeSizePreset.large),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-date-field')),
      'bad-date',
    );
    await tester.pump();
    expect(find.text('Date is invalid.'), findsOneWidget);
    expect(drafts, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-date-field')),
      '2026-07-14',
    );
    await tester.pump();
    expect(
      find.text('End date must not precede start date.'),
      findsNWidgets(2),
    );
    expect(drafts, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-date-field')),
      '2026-07-13',
    );
    final emittedBeforeInvalidTime = drafts.length;
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-time-field')),
      '11:00',
    );
    await tester.pump();
    expect(
      find.text('End time must not precede start time.'),
      findsNWidgets(2),
    );
    expect(drafts, hasLength(emittedBeforeInvalidTime));
  });

  testWidgets('event accepts cross-midnight multi-day range', (tester) async {
    final drafts = <Object>[];
    final node = _node(NodeType.event);
    const payload = EventCalendarPayload(
      startDate: '2026-07-13',
      endDate: '2026-07-14',
      startTime: '22:00',
      endTime: '01:00',
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, payload, drafts, preset: NodeSizePreset.large),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-time-field')),
      '23:00',
    );
    expect((drafts.last as EventCalendarPayload).startTime, '23:00');
    expect(find.text('End time must not precede start time.'), findsNothing);
  });

  testWidgets('correcting end date clears paired start date error', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.event);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            EventCalendarPayload.fromNode(node),
            drafts,
            preset: NodeSizePreset.large,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-date-field')),
      '2026-07-15',
    );
    await tester.pump();
    expect(
      find.text('End date must not precede start date.'),
      findsNWidgets(2),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-end-date-field')),
      '2026-07-16',
    );
    await tester.pump();
    expect(find.text('End date must not precede start date.'), findsNothing);
    final latest = drafts.last as EventCalendarPayload;
    expect(latest.startDate, '2026-07-15');
    expect(latest.endDate, '2026-07-16');
  });

  testWidgets('correcting end time clears paired start time error', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.event);
    const payload = EventCalendarPayload(
      startDate: '2026-07-13',
      endDate: '2026-07-13',
      startTime: '09:00',
      endTime: '10:00',
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, payload, drafts, preset: NodeSizePreset.large),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-start-time-field')),
      '11:00',
    );
    await tester.pump();
    expect(
      find.text('End time must not precede start time.'),
      findsNWidgets(2),
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-event-end-time-field')),
      '12:00',
    );
    await tester.pump();
    expect(find.text('End time must not precede start time.'), findsNothing);
    final latest = drafts.last as EventCalendarPayload;
    expect(latest.startTime, '11:00');
    expect(latest.endTime, '12:00');
  });

  testWidgets('content and editor expose distinct preset layouts', (
    tester,
  ) async {
    final node = _node(NodeType.event);
    for (final preset in const [
      NodeSizePreset.compact,
      NodeSizePreset.standard,
      NodeSizePreset.large,
      NodeSizePreset.wide,
    ]) {
      await tester.pumpWidget(
        _app(
          buildNodeTypeContent(
            NodeRenderContext(node: node, effectivePreset: preset),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('life-data-content-${preset.name}')),
        findsOneWidget,
      );
      await tester.pumpWidget(
        _app(
          buildNodeTypeInlineEditor(
            _context(
              node,
              EventCalendarPayload.fromNode(node),
              <Object>[],
              preset: preset,
            ),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('life-data-editor-preset-${preset.name}')),
        findsOneWidget,
      );
      for (final key in const [
        'life-data-event-title-field',
        'life-data-event-description-field',
        'life-data-event-start-date-field',
        'life-data-event-end-date-field',
        'life-data-event-start-time-field',
        'life-data-event-end-time-field',
        'life-data-event-location-field',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('life-data-event-editor-columns')),
        findsOneWidget,
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('contact sidebar filters and selects saved contacts', (
    tester,
  ) async {
    final node = _node(NodeType.contact);
    final drafts = <Object>[];
    const payload = ContactPayload(
      additionalContacts: [
        ContactRecord(
          id: 'alice',
          name: 'Alice',
          company: 'Acme',
          email: 'alice@example.com',
        ),
        ContactRecord(
          id: 'bob',
          name: 'Bob',
          company: 'Beta',
          email: 'bob@example.com',
        ),
      ],
    );
    await tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(_context(node, payload, drafts))),
    );

    expect(find.byKey(const ValueKey('contact-sidebar-list')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('contact-search-field')),
      'bob',
    );
    await tester.pump();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('contact-collapsed-toggle-bob')),
    );
    await tester.pump();
    expect(
      (drafts.last as ContactPayload).collapsedContactIds,
      contains('bob'),
    );

    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(find.text('Contact 3 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contact validates email and stores additional contacts', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.contact);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, ContactPayload.fromNode(node), drafts),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('life-data-contact-email-field')),
      'invalid-email',
    );
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('contact-add-record')));
    await tester.pump();
    final payload = drafts.last as ContactPayload;
    expect(payload.additionalContacts, hasLength(1));
    expect(find.text('Contact 2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fit tracks activity goals and quick updates', (tester) async {
    await _useTallEditorSurface(tester);
    final drafts = <Object>[];
    final node = _node(NodeType.fit);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            FitPayload.fromNode(node),
            drafts,
            preset: NodeSizePreset.large,
          ),
        ),
        height: 1130,
      ),
    );
    expect(find.byKey(const ValueKey('life-data-fit-editor')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('life-data-fit-editor')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('life-data-fit-activity-run')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('life-data-fit-add-steps')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('life-data-fit-add-water')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('life-data-fit-add-duration')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('life-data-fit-add-calories')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('life-data-fit-intensity')),
        matching: find.text('High'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('life-data-fit-completed')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('life-data-fit-distance-unit-field')),
      'mi',
    );
    final payload = drafts.last as FitPayload;
    expect(payload.workout, 'Run');
    expect(payload.steps, 6000);
    expect(payload.water, 2.25);
    expect(payload.durationMinutes, 10);
    expect(payload.calories, 50);
    expect(payload.intensity, 'high');
    expect(payload.completed, isTrue);
    expect(payload.distanceUnit, 'mi');
    expect(tester.takeException(), isNull);
  });

  testWidgets('fit imports and autosaves mobile health data', (tester) async {
    await _useTallEditorSurface(tester);
    final drafts = <Object>[];
    final service = _FakeFitnessHealthService();
    final node = _node(NodeType.fit);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            FitPayload.fromNode(node),
            drafts,
            preset: NodeSizePreset.large,
          ),
        ),
        height: 1130,
        overrides: <Override>[
          fitnessHealthServiceProvider.overrideWithValue(service),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('life-data-fit-sync-button')));
    await tester.pumpAndSettle();

    final payload = drafts.last as FitPayload;
    expect(service.requestedAuthorization, isTrue);
    expect(payload.steps, 8123);
    expect(payload.distance, 12.4);
    expect(payload.durationMinutes, 52);
    expect(payload.calories, 430);
    expect(payload.water, 1.75);
    expect(payload.sleepHours, 7.25);
    expect(payload.restingHeartRate, 57);
    expect(payload.workout, 'Cycling');
    expect(payload.syncEnabled, isTrue);
    expect(payload.syncSource, 'Health Connect');
    expect(payload.syncedAt, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fit refreshes connected health data when editor opens', (
    tester,
  ) async {
    await _useTallEditorSurface(tester);
    final drafts = <Object>[];
    final service = _FakeFitnessHealthService();
    final base = _node(NodeType.fit);
    final node = base.copyWith(
      data: const FitPayload(
        syncEnabled: true,
        syncSource: 'Health Connect',
      ).toData(base.data),
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            node,
            FitPayload.fromNode(node),
            drafts,
            preset: NodeSizePreset.large,
          ),
        ),
        height: 1130,
        overrides: <Override>[
          fitnessHealthServiceProvider.overrideWithValue(service),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(service.syncCalls, 1);
    expect(service.requestedAuthorization, isFalse);
    expect((drafts.last as FitPayload).steps, 8123);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mood choices and energy slider emit typed payload', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.mood);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(node, MoodPayload.fromNode(node), drafts),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mood-choice-great')));
    expect((drafts.last as MoodPayload).mood, '🤩');

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('mood-energy-slider')),
    );
    slider.onChanged?.call(5);
    await tester.pump();
    expect((drafts.last as MoodPayload).energy, 5);
    expect(find.text('Custom mood label or emoji'), findsNothing);
    expect(find.text('Energy 1-5'), findsNothing);
  });

  testWidgets('empty conversion emits explicit action', (tester) async {
    final drafts = <Object>[];
    final node = _node(NodeType.empty);
    await tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(_context(node, const Object(), drafts))),
    );
    await tester.tap(
      find.byKey(const ValueKey('life-data-empty-convert-task')),
    );
    expect((drafts.single as ConvertEmptyNodeAction).targetType, NodeType.task);
  });

  testWidgets('external draft and node change reset field state', (
    tester,
  ) async {
    final first = _node(NodeType.contact);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(first, const ContactPayload(role: 'Local'), <Object>[]),
        ),
      ),
    );
    expect(find.text('Local'), findsOneWidget);
    final second = _node(NodeType.contact).copyWith(id: 'second');
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(second, const ContactPayload(role: 'Remote'), <Object>[]),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Local'), findsNothing);
  });
}

NodeEditContext _context(
  MindmapNode node,
  Object draft,
  List<Object> drafts, {
  List<String>? bodies,
  NodeSizePreset preset = NodeSizePreset.standard,
}) => NodeEditContext(
  node: node,
  typedDraft: draft,
  effectivePreset: preset,
  validationErrors: const [],
  onTitleChanged: (_) {},
  onBodyChanged: bodies?.add ?? (_) {},
  onDraftChanged: drafts.add,
  onNodeDraftChanged: (_) {},
);
Future<void> _useTallEditorSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _app(
  Widget child, {
  double height = 500,
  List<Override> overrides = const <Override>[],
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
    home: Scaffold(
      body: SizedBox(width: 600, height: height, child: child),
    ),
  ),
);
MindmapNode _node(NodeType type) {
  final now = DateTime(2026, 7, 13, 23, 30);
  return MindmapNode.create(
    id: '${type.name}-node',
    type: type,
    title: '${type.label} title',
    day: now,
    now: now,
    data: const {
      'startDate': '2026-07-13',
      'endDate': '2026-07-14',
      'startTime': '09:00',
      'endTime': '10:00',
      'role': 'Designer',
      'company': 'Var',
      'value': 10.0,
      'unit': 'kg',
      'amount': 20.0,
      'currency': 'IDR',
      'category': 'Food',
      'mood': '🙂',
      'energy': 4.0,
      'temp': '28',
      'weather': 'Clear',
      'weatherUnit': '°C',
      'steps': 5000.0,
      'water': 2.0,
      'waterUnit': 'L',
      'distanceUnit': 'km',
      'workout': 'Walk',
    },
  );
}

final class _FakeFitnessHealthService implements FitnessHealthService {
  int syncCalls = 0;
  bool requestedAuthorization = false;

  @override
  bool get isSupported => true;

  @override
  String get sourceLabel => 'Health Connect';

  @override
  Future<FitnessSnapshot> syncDay(
    DateTime day, {
    required bool requestAuthorization,
  }) async {
    syncCalls += 1;
    requestedAuthorization = requestAuthorization;
    return FitnessSnapshot(
      source: sourceLabel,
      syncedAt: DateTime(2026, 7, 20, 8, 30),
      steps: 8123,
      distanceKilometers: 12.4,
      durationMinutes: 52,
      calories: 430,
      waterLiters: 1.75,
      sleepHours: 7.25,
      restingHeartRate: 57,
      workout: 'Cycling',
    );
  }
}
