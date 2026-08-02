import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';

void main() {
  test('manual dimensions become custom and clamp to type bounds', () {
    final NodePresentationSpec spec = NodePresentationSpec.forType(
      NodeType.task,
    );
    final NodePresentationState state = spec.resolve(
      preset: NodeSizePreset.standard,
      customWidth: 9999,
      customHeight: 1,
    );
    expect(state.preset, NodeSizePreset.custom);
    expect(state.width, spec.maxWidth);
    expect(state.height, spec.minHeight);
  });

  test('task custom resize can expose full inline workspace', () {
    final spec = NodePresentationSpec.forType(NodeType.task);
    final state = spec.resolve(
      preset: NodeSizePreset.custom,
      customWidth: 900,
      customHeight: 1100,
    );

    expect(spec.maxWidth, 900);
    expect(spec.maxHeight, 1100);
    expect(state.width, 900);
    expect(state.height, 1100);
  });
  test('kanban itinerary and video default to wide', () {
    expect(
      NodePresentationSpec.forType(NodeType.kanban).defaultPreset,
      NodeSizePreset.wide,
    );
    expect(
      NodePresentationSpec.forType(NodeType.itinerary).defaultPreset,
      NodeSizePreset.wide,
    );
    expect(
      NodePresentationSpec.forType(NodeType.video).defaultPreset,
      NodeSizePreset.wide,
    );
  });

  test('resource clamps custom height to information card minimum', () {
    final NodePresentationState state =
        NodePresentationSpec.forType(NodeType.resource).resolve(
          preset: NodeSizePreset.custom,
          customWidth: 357.5,
          customHeight: 243.7,
        );

    expect(state.width, 357.5);
    expect(state.height, 270);
  });

  test('every node type has valid finite bounds and default dimensions', () {
    for (final NodeType type in NodeType.values) {
      final NodePresentationSpec spec = NodePresentationSpec.forType(type);
      final NodePresentationState state = spec.resolve();
      expect(spec.minWidth.isFinite, isTrue, reason: type.name);
      expect(spec.minHeight.isFinite, isTrue, reason: type.name);
      expect(spec.maxWidth.isFinite, isTrue, reason: type.name);
      expect(spec.maxHeight.isFinite, isTrue, reason: type.name);
      expect(spec.minWidth, greaterThan(0), reason: type.name);
      expect(spec.minHeight, greaterThan(0), reason: type.name);
      expect(spec.maxWidth, greaterThanOrEqualTo(spec.minWidth));
      expect(spec.maxHeight, greaterThanOrEqualTo(spec.minHeight));
      expect(state.width, inInclusiveRange(spec.minWidth, spec.maxWidth));
      expect(state.height, inInclusiveRange(spec.minHeight, spec.maxHeight));
    }
  });

  test('every type has distinct valid dimensions for each preset', () {
    for (final NodeType type in NodeType.values) {
      final NodePresentationSpec spec = NodePresentationSpec.forType(type);
      final Map<NodeSizePreset, NodePresentationState> states = {
        for (final NodeSizePreset preset in <NodeSizePreset>[
          NodeSizePreset.compact,
          NodeSizePreset.standard,
          NodeSizePreset.large,
          NodeSizePreset.wide,
        ])
          preset: spec.resolve(preset: preset),
      };

      for (final MapEntry<NodeSizePreset, NodePresentationState> entry
          in states.entries) {
        expect(entry.value.preset, entry.key, reason: type.name);
        expect(entry.value.width.isFinite, isTrue, reason: type.name);
        expect(entry.value.height.isFinite, isTrue, reason: type.name);
        expect(
          entry.value.width,
          inInclusiveRange(spec.minWidth, spec.maxWidth),
          reason: '${type.name} ${entry.key.name} width',
        );
        expect(
          entry.value.height,
          inInclusiveRange(spec.minHeight, spec.maxHeight),
          reason: '${type.name} ${entry.key.name} height',
        );
      }

      final NodePresentationState compact = states[NodeSizePreset.compact]!;
      final NodePresentationState standard = states[NodeSizePreset.standard]!;
      final NodePresentationState large = states[NodeSizePreset.large]!;
      final NodePresentationState wide = states[NodeSizePreset.wide]!;
      expect(compact.width, lessThan(standard.width), reason: type.name);
      expect(standard.width, lessThan(large.width), reason: type.name);
      expect(compact.height, lessThan(standard.height), reason: type.name);
      expect(standard.height, lessThan(large.height), reason: type.name);
      expect(wide.width, greaterThan(large.width), reason: type.name);
    }
  });

  test('non-finite manual dimensions fall back to preset dimensions', () {
    final NodePresentationSpec spec = NodePresentationSpec.forType(
      NodeType.task,
    );
    final NodePresentationState standard = spec.resolve(
      preset: NodeSizePreset.standard,
    );
    final NodePresentationState state = spec.resolve(
      preset: NodeSizePreset.standard,
      customWidth: double.nan,
      customHeight: double.infinity,
    );
    expect(state.preset, NodeSizePreset.standard);
    expect(state.width, standard.width);
    expect(state.height, standard.height);
  });

  test('partial valid manual dimensions become custom', () {
    final NodePresentationSpec spec = NodePresentationSpec.forType(
      NodeType.task,
    );
    final NodePresentationState standard = spec.resolve(
      preset: NodeSizePreset.standard,
    );
    final NodePresentationState state = spec.resolve(
      preset: NodeSizePreset.standard,
      customWidth: 300,
      customHeight: double.nan,
    );
    expect(state.preset, NodeSizePreset.custom);
    expect(state.width, 300);
    expect(state.height, standard.height);
  });
}
