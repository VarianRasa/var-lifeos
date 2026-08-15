import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_ui_state_codec.dart';

void main() {
  MindmapNode node({
    NodeType type = NodeType.task,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    return MindmapNode.create(
      id: 'node-1',
      type: type,
      title: 'Node',
      day: DateTime(2026, 7, 13),
      data: data,
      now: DateTime(2026, 7, 13),
    );
  }

  test('legacy node uses auto preset and type defaults', () {
    final MindmapNode legacy = node(type: NodeType.itinerary);
    final NodeUiState state = legacy.uiState;
    final NodePresentationState expected = NodePresentationSpec.forType(
      NodeType.itinerary,
    ).resolve();

    expect(state.sizePreset, NodeSizePreset.auto);
    expect(state.width, expected.width);
    expect(state.height, expected.height);
    expect(state.collapsedSections, isEmpty);
    expect(state.editorVersion, NodeUiState.currentEditorVersion);
  });

  test('round trip writes exact reserved keys and preserves other data', () {
    final MindmapNode original = node(
      data: const <String, Object?>{'featureValue': 42},
    );
    final NodeUiState state = NodeUiState(
      sizePreset: NodeSizePreset.custom,
      width: 360,
      height: 240,
      collapsedSections: <String>{'metadata', 'links'},
      editorVersion: 3,
    );

    final MindmapNode updated = original.copyWithUiState(state);

    expect(updated.data['featureValue'], 42);
    final Set<String> uiKeys = updated.data.keys
        .where((String key) => key.startsWith('ui'))
        .toSet();
    expect(uiKeys, <String>{
      'uiSizePreset',
      'uiWidth',
      'uiHeight',
      'uiCollapsedSections',
      'uiEditorVersion',
    });
    expect(updated.uiState, state);
  });

  test('write strips only namespaced inline workspace state', () {
    final MindmapNode original = node(
      data: const <String, Object?>{
        'featureValue': 42,
        'draft': <String, Object?>{'title': 'Legitimate'},
        'dirty': true,
        'scroll': 120.0,
        'debounce': 300,
        'inlineWorkspaceExpandedNodeId': 'node-1',
        'inlineWorkspaceDraft': <String, Object?>{'title': 'Ephemeral'},
        'inlineWorkspaceDirty': true,
        'inlineWorkspaceSaveStatus': 'saving',
        'inlineWorkspaceScroll': 80.0,
        'inlineWorkspaceDebounce': 250,
        'inlineWorkspaceDirtyBackup': true,
      },
    );
    final NodeUiState state = NodeUiState(
      sizePreset: NodeSizePreset.standard,
      width: 360,
      height: 280,
    );
    final Map<String, Object?> data = NodeUiStateCodec.write(original, state);
    expect(data['featureValue'], 42);
    expect(data['draft'], <String, Object?>{'title': 'Legitimate'});
    expect(data['dirty'], true);
    expect(data['scroll'], 120.0);
    expect(data['debounce'], 300);
    expect(data['inlineWorkspaceDirtyBackup'], true);
    for (final String key in <String>[
      'inlineWorkspaceExpandedNodeId',
      'inlineWorkspaceDraft',
      'inlineWorkspaceDirty',
      'inlineWorkspaceSaveStatus',
      'inlineWorkspaceScroll',
      'inlineWorkspaceDebounce',
    ]) {
      expect(data, isNot(contains(key)), reason: key);
    }
  });

  test('collapsed sections are defensively copied and unmodifiable', () {
    final Set<String> source = <String>{'metadata'};
    final NodeUiState state = NodeUiState(
      sizePreset: NodeSizePreset.standard,
      width: 300,
      height: 200,
      collapsedSections: source,
    );

    source.add('links');

    expect(state.collapsedSections, <String>{'metadata'});
    expect(
      () => state.collapsedSections.add('attachments'),
      throwsUnsupportedError,
    );
  });

  test('decoded collapsed sections reject mutation', () {
    final NodeUiState state = node(
      data: const <String, Object?>{
        'uiCollapsedSections': <String>['metadata'],
      },
    ).uiState;

    expect(
      () => state.collapsedSections.remove('metadata'),
      throwsUnsupportedError,
    );
  });

  test('malformed values fall back without losing valid unrelated data', () {
    final MindmapNode malformed = node(
      data: <String, Object?>{
        'featureValue': 'keep',
        'uiSizePreset': 'giant',
        'uiWidth': double.nan,
        'uiHeight': double.infinity,
        'uiCollapsedSections': <Object?>['valid', 7],
        'uiEditorVersion': 'two',
      },
    );
    final NodePresentationState expected = NodePresentationSpec.forType(
      NodeType.task,
    ).resolve();

    expect(malformed.uiState.sizePreset, NodeSizePreset.auto);
    expect(malformed.uiState.width, expected.width);
    expect(malformed.uiState.height, expected.height);
    expect(malformed.uiState.collapsedSections, isEmpty);
    expect(malformed.uiState.editorVersion, NodeUiState.currentEditorVersion);
    expect(malformed.data['featureValue'], 'keep');
  });

  test('stored dimensions are clamped using node type specification', () {
    final MindmapNode oversized = node(
      type: NodeType.image,
      data: const <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 99999,
        'uiHeight': -10,
      },
    );
    final NodePresentationSpec spec = NodePresentationSpec.forType(
      NodeType.image,
    );

    expect(oversized.uiState.sizePreset, NodeSizePreset.custom);
    expect(oversized.uiState.width, spec.maxWidth);
    expect(oversized.uiState.height, spec.minHeight);
  });

  test('custom state preserves valid width when height is malformed', () {
    final MindmapNode partial = node(
      data: <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 360,
        'uiHeight': double.nan,
      },
    );
    final NodePresentationSpec spec = NodePresentationSpec.forType(
      NodeType.task,
    );
    final NodePresentationState fallback = spec.resolve(
      preset: NodeSizePreset.custom,
    );

    expect(partial.uiState.sizePreset, NodeSizePreset.custom);
    expect(partial.uiState.width, 360);
    expect(partial.uiState.height, fallback.height);
  });

  test('custom state preserves valid height when width is missing', () {
    final MindmapNode partial = node(
      data: const <String, Object?>{'uiSizePreset': 'custom', 'uiHeight': 260},
    );
    final NodePresentationSpec spec = NodePresentationSpec.forType(
      NodeType.task,
    );
    final NodePresentationState fallback = spec.resolve(
      preset: NodeSizePreset.custom,
    );

    expect(partial.uiState.sizePreset, NodeSizePreset.custom);
    expect(partial.uiState.width, fallback.width);
    expect(partial.uiState.height, 260);
  });

  test('preset dimensions ignore stale custom dimensions', () {
    final MindmapNode standard = node(
      data: const <String, Object?>{
        'uiSizePreset': 'standard',
        'uiWidth': 500,
        'uiHeight': 400,
      },
    );
    final NodePresentationState expected = NodePresentationSpec.forType(
      NodeType.task,
    ).resolve(preset: NodeSizePreset.standard);

    expect(standard.uiState.sizePreset, NodeSizePreset.standard);
    expect(standard.uiState.width, expected.width);
    expect(standard.uiState.height, expected.height);
  });
}
