import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/media_travel_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_type_content.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  for (final preset in const [
    NodeSizePreset.compact,
    NodeSizePreset.standard,
    NodeSizePreset.large,
    NodeSizePreset.wide,
  ]) {
    testWidgets('renders ${preset.name} without overflow', (tester) async {
      await tester.pumpWidget(
        _app(
          buildNodeTypeContent(
            NodeRenderContext(node: _node(), effectivePreset: preset),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('itinerary-content-${preset.name}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('content presets expose progressive information', (tester) async {
    Future<void> show(NodeSizePreset preset) => tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(node: _node(), effectivePreset: preset),
        ),
      ),
    );
    await show(NodeSizePreset.compact);
    expect(
      find.byKey(const ValueKey('itinerary-content-compact-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('Timezone:'), findsNothing);
    await show(NodeSizePreset.standard);
    expect(
      find.byKey(const ValueKey('itinerary-content-standard-core')),
      findsOneWidget,
    );
    expect(find.text('Timezone: Asia/Tokyo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('itinerary-content-budget')),
      findsNothing,
    );
    await show(NodeSizePreset.large);
    expect(
      find.byKey(const ValueKey('itinerary-content-large-detail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('itinerary-content-budget')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('itinerary-content-agenda')),
      findsOneWidget,
    );
    await show(NodeSizePreset.wide);
    expect(
      find.byKey(const ValueKey('itinerary-content-wide-columns')),
      findsOneWidget,
    );
  });

  testWidgets('wide preview shows trip status travel details and agenda', (
    tester,
  ) async {
    final payload = _payload().copyWith(
      status: 'booked',
      travelers: 3,
      transport: 'Shinkansen',
      accommodation: 'Kyoto Station Hotel',
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(
            node: _node(payload: payload),
            typedPayload: payload,
            effectivePreset: NodeSizePreset.wide,
          ),
        ),
      ),
    );

    expect(find.text('Booked'), findsOneWidget);
    expect(find.text('3 travelers'), findsOneWidget);
    expect(find.text('Shinkansen'), findsOneWidget);
    expect(find.text('Kyoto Station Hotel'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('itinerary-content-budget')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('itinerary-content-agenda')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide preview adapts to collapsed card constraints', (
    tester,
  ) async {
    final payload = _payload().copyWith(
      timezone: 'America/Argentina/Buenos_Aires',
      travelers: 12,
      transport: 'International sleeper train',
      accommodation: 'Long accommodation name near central station',
    );
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 292,
            height: 128,
            child: buildNodeTypeContent(
              NodeRenderContext(
                node: _node(payload: payload),
                typedPayload: payload,
                effectivePreset: NodeSizePreset.wide,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('itinerary-content-condensed-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('itinerary-content-wide-columns')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced preview shows readiness booking and packing status', (
    tester,
  ) async {
    final payload = _payload().copyWith(
      bookings: [
        ItineraryBooking(
          id: 'flight',
          title: 'Flight to Osaka',
          type: 'flight',
          startAt: DateTime(2026, 10, 2, 8),
          endAt: DateTime(2026, 10, 2, 10),
          status: 'confirmed',
        ),
      ],
      packing: const [
        ItineraryPackingItem(
          id: 'passport',
          title: 'Passport',
          category: 'documents',
          packed: true,
          essential: true,
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(
            node: _node(payload: payload),
            typedPayload: payload,
            effectivePreset: NodeSizePreset.standard,
          ),
        ),
      ),
    );

    expect(find.textContaining('% ready'), findsOneWidget);
    expect(find.text('1/1 bookings'), findsOneWidget);
    expect(find.text('1/1 packed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor presets expose progressive fields and layouts', (
    tester,
  ) async {
    Future<void> show(NodeSizePreset preset) => tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(_context(<Object>[], preset))),
    );
    await show(NodeSizePreset.compact);
    expect(
      find.byKey(const ValueKey('itinerary-editor-compact-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('itinerary-timezone-field')),
      findsNothing,
    );
    await show(NodeSizePreset.standard);
    expect(
      find.byKey(const ValueKey('itinerary-editor-standard-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('itinerary-timezone-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('itinerary-budget-field')), findsNothing);
    await show(NodeSizePreset.large);
    expect(
      find.byKey(const ValueKey('itinerary-editor-large-agenda')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('itinerary-budget-field')),
      findsOneWidget,
    );
    await show(NodeSizePreset.wide);
    expect(
      find.byKey(const ValueKey('itinerary-editor-wide-columns')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('itinerary-timeline')), findsOneWidget);
  });

  testWidgets('wide reorders toggles and emits conversion callbacks', (
    tester,
  ) async {
    final drafts = <Object>[];
    final actions = <Object>[];
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(drafts, NodeSizePreset.wide, actions: actions),
        ),
      ),
    );
    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('itinerary-timeline')),
    );
    list.onReorderItem!(0, 1);
    await tester.pump();
    expect((drafts.last as ItineraryPayload).agenda.first.id, 'second');
    final completion = find.bySemanticsLabel('Complete Second item 1');
    await tester.ensureVisible(completion);
    await tester.pump();
    await tester.tap(completion);
    await tester.pump();
    expect((drafts.last as ItineraryPayload).agenda.first.completed, isTrue);
    final taskAction = find.byTooltip('Convert Second to task');
    await tester.ensureVisible(taskAction);
    await tester.pump();
    await tester.tap(taskAction);
    expect(
      (actions.last as ConvertItineraryAgendaAction).target,
      ItineraryConversionTarget.task,
    );
    final eventAction = find.byTooltip('Convert Second to event');
    await tester.ensureVisible(eventAction);
    await tester.pump();
    await tester.tap(eventAction);
    expect(
      (actions.last as ConvertItineraryAgendaAction).target,
      ItineraryConversionTarget.event,
    );
  });

  testWidgets(
    'sequential fields keep latest draft and invalid input stays local',
    (tester) async {
      final drafts = <Object>[];
      await tester.pumpWidget(
        _app(buildNodeTypeInlineEditor(_context(drafts, NodeSizePreset.large))),
      );
      await tester.enterText(
        find.byKey(const ValueKey('itinerary-destination-field')),
        'Osaka',
      );
      await tester.enterText(
        find.byKey(const ValueKey('itinerary-timezone-field')),
        'Asia/Osaka',
      );
      final latest = drafts.last as ItineraryPayload;
      expect(latest.destination, 'Osaka');
      expect(latest.timezone, 'Asia/Osaka');
      final before = drafts.length;
      await tester.enterText(
        find.byKey(const ValueKey('itinerary-budget-field')),
        '-2',
      );
      await tester.pump();
      expect(find.text('Enter a non-negative finite number.'), findsOneWidget);
      expect(drafts, hasLength(before));
    },
  );

  testWidgets('wide edits travel details and supports agenda CRUD', (
    tester,
  ) async {
    final drafts = <Object>[];
    await tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(_context(drafts, NodeSizePreset.wide))),
    );

    Future<void> enter(String key, String value) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.enterText(finder, value);
      await tester.pump();
    }

    await enter('itinerary-travelers-field', '3');
    await enter('itinerary-transport-field', 'Train and metro');
    await enter('itinerary-accommodation-field', 'Kyoto Station Hotel');
    await enter('itinerary-booking-reference-field', 'JP-TRIP-2026');

    var latest = drafts.last as ItineraryPayload;
    expect(latest.travelers, 3);
    expect(latest.transport, 'Train and metro');
    expect(latest.accommodation, 'Kyoto Station Hotel');
    expect(latest.bookingReference, 'JP-TRIP-2026');

    await enter('itinerary-time-0-first', '10:30');
    await enter('itinerary-duration-0-first', '90');
    await enter('itinerary-cost-0-first', '45.5');
    await enter('itinerary-location-0-first', 'Arashiyama');
    await enter('itinerary-item-notes-0-first', 'Bring reservation QR');

    latest = drafts.last as ItineraryPayload;
    expect(latest.agenda.first.startMinutes, 630);
    expect(latest.agenda.first.durationMinutes, 90);
    expect(latest.agenda.first.cost, 45.5);
    expect(latest.agenda.first.location, 'Arashiyama');
    expect(latest.agenda.first.notes, 'Bring reservation QR');

    final add = find.byKey(const ValueKey<String>('itinerary-add-agenda'));
    await tester.ensureVisible(add);
    await tester.pump();
    await tester.tap(add);
    await tester.pump();
    latest = drafts.last as ItineraryPayload;
    expect(latest.agenda, hasLength(3));

    final duplicate = find.byTooltip('Duplicate Temple');
    await tester.ensureVisible(duplicate);
    await tester.pump();
    await tester.tap(duplicate);
    await tester.pump();
    latest = drafts.last as ItineraryPayload;
    expect(latest.agenda, hasLength(4));
    expect(latest.agenda[1].title, 'Temple copy');

    final delete = find.byTooltip('Delete Temple copy');
    await tester.ensureVisible(delete);
    await tester.pump();
    await tester.tap(delete);
    await tester.pump();
    latest = drafts.last as ItineraryPayload;
    expect(latest.agenda, hasLength(3));
    expect(latest.agenda.where((item) => item.title == 'Temple copy'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide manages bookings packing and readiness in real time', (
    tester,
  ) async {
    final drafts = <Object>[];
    await tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(_context(drafts, NodeSizePreset.wide))),
    );

    Future<void> tapKey(String key) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    Future<void> enter(String key, String value) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.enterText(finder, value);
      await tester.pump();
    }

    await tapKey('itinerary-add-booking');
    var latest = drafts.last as ItineraryPayload;
    expect(latest.bookings, hasLength(1));
    final bookingId = latest.bookings.single.id;
    await enter('itinerary-booking-title-0-$bookingId', 'Flight to Osaka');
    await enter('itinerary-booking-provider-0-$bookingId', 'ANA');
    await enter('itinerary-booking-code-0-$bookingId', 'ANA-123');
    await enter('itinerary-booking-cost-0-$bookingId', '125.5');

    latest = drafts.last as ItineraryPayload;
    expect(latest.bookings.single.title, 'Flight to Osaka');
    expect(latest.bookings.single.provider, 'ANA');
    expect(latest.bookings.single.confirmationCode, 'ANA-123');
    expect(latest.bookings.single.cost, 125.5);

    await tapKey('itinerary-add-packing');
    latest = drafts.last as ItineraryPayload;
    expect(latest.packing, hasLength(1));
    final packingId = latest.packing.single.id;
    await enter('itinerary-packing-title-0-$packingId', 'Travel adapter');
    await enter('itinerary-packing-quantity-0-$packingId', '2');
    final essential = find.byTooltip('Mark Travel adapter essential');
    await tester.ensureVisible(essential);
    await tester.pump();
    await tester.tap(essential);
    await tester.pump();
    final packed = find.bySemanticsLabel('Pack Travel adapter');
    await tester.tap(packed);
    await tester.pump();

    latest = drafts.last as ItineraryPayload;
    expect(latest.packing.single.quantity, 2);
    expect(latest.packing.single.essential, isTrue);
    expect(latest.packing.single.packed, isTrue);
    expect(
      find.byKey(const ValueKey('itinerary-readiness-score')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded workspace keeps every section reachable', (
    tester,
  ) async {
    final payload = _payload().copyWith(
      bookings: [
        ItineraryBooking(
          id: 'hotel',
          title: 'Kyoto hotel',
          type: 'hotel',
          startAt: DateTime(2026, 10, 2, 15),
          endAt: DateTime(2026, 10, 6, 11),
          status: 'confirmed',
        ),
      ],
      packing: const [
        ItineraryPackingItem(
          id: 'passport',
          title: 'Passport',
          category: 'documents',
          packed: true,
          essential: true,
        ),
      ],
    );
    final node = _node(payload: payload);
    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    await tester.binding.setSurfaceSize(
      Size(size.width + 80, size.height + 80),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: InlineNodeWorkspace(
                node: node,
                editContext: NodeEditContext(
                  node: node,
                  typedDraft: payload,
                  effectivePreset: NodeSizePreset.compact,
                  validationErrors: payload.validate(title: node.title),
                  onTitleChanged: (_) {},
                  onBodyChanged: (_) {},
                  onDraftChanged: (_) {},
                  onNodeDraftChanged: (_) {},
                ),
                saveStatus: InlineNodeSaveStatus.idle,
                onCollapse: () {},
                onRetrySave: () {},
                onDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = find.byKey(const ValueKey('itinerary-editor-compact'));
    expect(editor, findsOneWidget);
    expect(
      find.descendant(of: editor, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('itinerary-agenda-section')),
      240,
      scrollable: find
          .descendant(of: editor, matching: find.byType(Scrollable))
          .first,
    );
    final agenda = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('itinerary-timeline')),
    );
    expect(agenda.shrinkWrap, isTrue);
    expect(agenda.physics, isA<NeverScrollableScrollPhysics>());
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Packing checklist'), findsOneWidget);
    expect(find.text('Agenda'), findsOneWidget);
    final bottomGap =
        tester.getRect(editor).bottom -
        tester
            .getRect(find.byKey(const ValueKey('itinerary-agenda-section')))
            .bottom;
    expect(bottomGap, lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty expanded workspace keeps bottom gap compact', (
    tester,
  ) async {
    final payload = ItineraryPayload(
      destination: '',
      startDate: DateTime(2026, 7, 20),
      endDate: DateTime(2026, 7, 20),
      timezone: 'Local time',
    );
    final node = _node(payload: payload);
    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    await tester.binding.setSurfaceSize(
      Size(size.width + 80, size.height + 80),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: InlineNodeWorkspace(
                node: node,
                editContext: NodeEditContext(
                  node: node,
                  typedDraft: payload,
                  effectivePreset: NodeSizePreset.compact,
                  validationErrors: payload.validate(title: node.title),
                  onTitleChanged: (_) {},
                  onBodyChanged: (_) {},
                  onDraftChanged: (_) {},
                  onNodeDraftChanged: (_) {},
                ),
                saveStatus: InlineNodeSaveStatus.idle,
                onCollapse: () {},
                onRetrySave: () {},
                onDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = find.byKey(const ValueKey('itinerary-editor-compact'));
    final bottomGap =
        tester.getRect(editor).bottom -
        tester
            .getRect(find.byKey(const ValueKey('itinerary-agenda-section')))
            .bottom;
    expect(bottomGap, lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty policy follows natural editor height', (tester) async {
    final payload = ItineraryPayload(
      destination: '',
      startDate: DateTime(2026, 7, 20),
      endDate: DateTime(2026, 7, 20),
      timezone: 'Local time',
    );
    final node = _node(payload: payload);
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 796,
              child: buildNodeTypeInlineEditor(
                NodeEditContext(
                  node: node,
                  typedDraft: payload,
                  effectivePreset: NodeSizePreset.compact,
                  validationErrors: payload.validate(title: node.title),
                  onTitleChanged: (_) {},
                  onBodyChanged: (_) {},
                  onDraftChanged: (_) {},
                  onNodeDraftChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorHeight = tester
        .getSize(find.byKey(const ValueKey('itinerary-editor-compact')))
        .height;
    final policyHeight = InlineNodeWorkspacePolicy.expandedSizeForNode(
      node,
    ).height;
    expect(policyHeight - editorHeight, inInclusiveRange(95, 115));
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate agenda ids render and edit exact occurrences', (
    tester,
  ) async {
    final drafts = <Object>[];
    final malformed = _payload().copyWith(
      agenda: const [
        ItineraryAgendaItem(
          id: 'duplicate',
          title: 'First duplicate',
          startMinutes: 540,
          durationMinutes: 60,
        ),
        ItineraryAgendaItem(
          id: 'duplicate',
          title: 'Second duplicate',
          startMinutes: 660,
          durationMinutes: 60,
        ),
      ],
    );
    final node = _node(payload: malformed);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: malformed,
            effectivePreset: NodeSizePreset.wide,
            validationErrors: malformed.validate(title: node.title),
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onDraftChanged: drafts.add,
            onNodeDraftChanged: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('agenda-0-duplicate')), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-1-duplicate')), findsOneWidget);
    expect(find.text('Agenda IDs must be unique.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('itinerary-wide-title-1-duplicate')),
      'Changed second',
    );
    var latest = drafts.last as ItineraryPayload;
    expect(latest.agenda[0].title, 'First duplicate');
    expect(latest.agenda[1].title, 'Changed second');

    final firstToggle = find.bySemanticsLabel(
      'Complete First duplicate item 1',
    );
    await tester.ensureVisible(firstToggle);
    await tester.pump();
    await tester.tap(firstToggle);
    await tester.pump();
    latest = drafts.last as ItineraryPayload;
    expect(latest.agenda[0].completed, isTrue);
    expect(latest.agenda[1].completed, isFalse);
    expect(
      latest.validate(title: node.title),
      contains('Agenda IDs must be unique.'),
    );
  });

  testWidgets(
    'parent draft echo keeps active field focused for continued typing',
    (tester) async {
      final key = GlobalKey<_EchoEditorHarnessState>();
      await tester.pumpWidget(_app(_EchoEditorHarness(key: key)));
      final destination = find.byKey(
        const ValueKey('itinerary-destination-field'),
      );

      await tester.tap(destination);
      await tester.enterText(destination, 'O');
      await tester.pump();

      expect(key.currentState!.external.destination, 'O');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: destination,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'Osaka'),
      );
      await tester.pump();
      expect(key.currentState!.external.destination, 'Osaka');
    },
  );

  testWidgets(
    'node id and external draft reset fields while local edit remains',
    (tester) async {
      final key = GlobalKey<_EditorHarnessState>();
      final drafts = <Object>[];
      await tester.pumpWidget(_app(_EditorHarness(key: key, drafts: drafts)));
      await tester.enterText(
        find.byKey(const ValueKey('itinerary-destination-field')),
        'Local Osaka',
      );
      key.currentState!.rebuildSameInput();
      await tester.pump();
      expect(find.text('Local Osaka'), findsOneWidget);

      key.currentState!.setExternal(_payload(destination: 'External Seoul'));
      await tester.pump();
      expect(find.text('External Seoul'), findsOneWidget);

      key.currentState!.setNode('trip-2', _payload(destination: 'Node Paris'));
      await tester.pump();
      expect(find.text('Node Paris'), findsOneWidget);
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
  home: Scaffold(body: SizedBox(width: 720, height: 560, child: child)),
);
MindmapNode _node({String id = 'trip', ItineraryPayload? payload}) {
  final now = DateTime(2026, 7, 13);
  return MindmapNode.create(
    id: id,
    type: NodeType.itinerary,
    title: 'Japan',
    body: '',
    day: now,
    now: now,
    data: (payload ?? _payload()).toData(),
  );
}

ItineraryPayload _payload({String destination = 'Kyoto'}) => ItineraryPayload(
  destination: destination,
  startDate: DateTime(2026, 10, 2),
  endDate: DateTime(2026, 10, 6),
  timezone: 'Asia/Tokyo',
  budget: 1000,
  actualCost: 200,
  agenda: const [
    ItineraryAgendaItem(
      id: 'first',
      title: 'Temple',
      startMinutes: 540,
      durationMinutes: 60,
    ),
    ItineraryAgendaItem(
      id: 'second',
      title: 'Second',
      startMinutes: 660,
      durationMinutes: 90,
    ),
  ],
);
NodeEditContext _context(
  List<Object> drafts,
  NodeSizePreset preset, {
  List<Object>? actions,
}) => NodeEditContext(
  node: _node(),
  typedDraft: _payload(),
  effectivePreset: preset,
  validationErrors: const [],
  onTitleChanged: (_) {},
  onBodyChanged: (_) {},
  onDraftChanged: drafts.add,
  onNodeDraftChanged: (_) {},
  onItineraryAction: actions == null
      ? null
      : (action) async => actions.add(action),
);

final class _EditorHarness extends StatefulWidget {
  const _EditorHarness({super.key, required this.drafts});
  final List<Object> drafts;
  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

final class _EchoEditorHarness extends StatefulWidget {
  const _EchoEditorHarness({super.key});

  @override
  State<_EchoEditorHarness> createState() => _EchoEditorHarnessState();
}

final class _EchoEditorHarnessState extends State<_EchoEditorHarness> {
  ItineraryPayload external = _payload();

  @override
  Widget build(BuildContext context) => buildNodeTypeInlineEditor(
    NodeEditContext(
      node: _node(payload: external),
      typedDraft: external,
      effectivePreset: NodeSizePreset.large,
      validationErrors: const [],
      onTitleChanged: (_) {},
      onBodyChanged: (_) {},
      onDraftChanged: (value) => setState(() {
        external = value as ItineraryPayload;
      }),
      onNodeDraftChanged: (_) {},
    ),
  );
}

final class _EditorHarnessState extends State<_EditorHarness> {
  String nodeId = 'trip';
  ItineraryPayload external = _payload();
  void rebuildSameInput() => setState(() {});
  void setExternal(ItineraryPayload value) => setState(() => external = value);
  void setNode(String id, ItineraryPayload value) => setState(() {
    nodeId = id;
    external = value;
  });

  @override
  Widget build(BuildContext context) => buildNodeTypeInlineEditor(
    NodeEditContext(
      node: _node(id: nodeId, payload: external),
      typedDraft: external,
      effectivePreset: NodeSizePreset.standard,
      validationErrors: const [],
      onTitleChanged: (_) {},
      onBodyChanged: (_) {},
      onDraftChanged: widget.drafts.add,
      onNodeDraftChanged: (_) {},
    ),
  );
}
