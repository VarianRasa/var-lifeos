import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  testWidgets('inline habit workspace renders completions heatmap', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final DateTime today = DateTime.now().dateOnly;
    final MindmapNode node =
        MindmapNode.create(
          id: 'habit-1',
          type: NodeType.habit,
          title: 'Workout Habit',
          day: today,
        ).copyWith(
          data: <String, Object?>{
            'habit': <String, Object?>{
              'target': 'Workout',
              'recurrence': 'daily',
              'completions': <String>[
                dayKey(today),
                dayKey(today.subtract(const Duration(days: 3))),
              ],
            },
          },
        );
    final InlineNodeWorkspaceSize size =
        InlineNodeWorkspacePolicy.expandedSizeFor(node.type);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: InlineNodeWorkspace(
              node: node,
              editContext: NodeEditContext(
                node: node,
                typedDraft: nodeTypeInlineDraftFor(node),
                effectivePreset: NodePresentationSpec.forType(
                  node.type,
                ).defaultPreset,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
              ),
              saveStatus: InlineNodeSaveStatus.saved,
              onCollapse: () {},
              onRetrySave: () {},
              onDraftChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workout Habit'), findsAtLeastNWidgets(1));
    expect(find.text('Completions Heatmap'), findsOneWidget);
    expect(find.byType(Tooltip), findsAtLeastNWidgets(371));
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Tooltip &&
            widget.message ==
                '${DateFormat('EEEE, MMM d, yyyy').format(today)}: Completed',
      ),
      findsOneWidget,
    );
    final DateTime incompleteDay = today.subtract(const Duration(days: 1));
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Tooltip &&
            widget.message ==
                '${DateFormat('EEEE, MMM d, yyyy').format(incompleteDay)}: '
                    'Not completed',
      ),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsWidgets);
    final Scrollbar scrollbar = tester.widget<Scrollbar>(
      find.byType(Scrollbar),
    );
    expect(scrollbar.controller?.position.maxScrollExtent, 0);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(Scrollbar)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
