import 'package:collection/collection.dart';

import 'mindmap_node.dart';
import 'node_presentation.dart';

const String nodeUiSizePresetKey = 'uiSizePreset';
const String nodeUiWidthKey = 'uiWidth';
const String nodeUiHeightKey = 'uiHeight';
const String nodeUiCollapsedSectionsKey = 'uiCollapsedSections';
const String nodeUiEditorVersionKey = 'uiEditorVersion';

const String inlineWorkspaceExpandedNodeIdKey = 'inlineWorkspaceExpandedNodeId';
const String inlineWorkspaceDraftKey = 'inlineWorkspaceDraft';
const String inlineWorkspaceDirtyKey = 'inlineWorkspaceDirty';
const String inlineWorkspaceSaveStatusKey = 'inlineWorkspaceSaveStatus';
const String inlineWorkspaceScrollKey = 'inlineWorkspaceScroll';
const String inlineWorkspaceDebounceKey = 'inlineWorkspaceDebounce';

const Set<String> _inlineWorkspaceEphemeralKeys = <String>{
  inlineWorkspaceExpandedNodeIdKey,
  inlineWorkspaceDraftKey,
  inlineWorkspaceDirtyKey,
  inlineWorkspaceSaveStatusKey,
  inlineWorkspaceScrollKey,
  inlineWorkspaceDebounceKey,
};

final class NodeUiState {
  NodeUiState({
    required this.sizePreset,
    required this.width,
    required this.height,
    Set<String> collapsedSections = const <String>{},
    this.editorVersion = currentEditorVersion,
  }) : collapsedSections = Set<String>.unmodifiable(collapsedSections);

  static const int currentEditorVersion = 1;

  final NodeSizePreset sizePreset;
  final double width;
  final double height;
  final Set<String> collapsedSections;
  final int editorVersion;

  @override
  bool operator ==(Object other) {
    return other is NodeUiState &&
        other.sizePreset == sizePreset &&
        other.width == width &&
        other.height == height &&
        const SetEquality<String>().equals(
          other.collapsedSections,
          collapsedSections,
        ) &&
        other.editorVersion == editorVersion;
  }

  @override
  int get hashCode => Object.hash(
    sizePreset,
    width,
    height,
    const SetEquality<String>().hash(collapsedSections),
    editorVersion,
  );
}

abstract final class NodeUiStateCodec {
  static NodeUiState read(MindmapNode node) {
    final NodePresentationSpec spec = NodePresentationSpec.forType(node.type);
    final NodeSizePreset preset =
        _presetFrom(node.data[nodeUiSizePresetKey]) ?? NodeSizePreset.auto;
    final double? width = _finiteDouble(node.data[nodeUiWidthKey]);
    final double? height = _finiteDouble(node.data[nodeUiHeightKey]);

    final NodePresentationState presentation;
    if (preset == NodeSizePreset.custom && (width != null || height != null)) {
      presentation = spec.resolve(
        preset: preset,
        customWidth: width,
        customHeight: height,
      );
    } else if (preset == NodeSizePreset.custom) {
      presentation = spec.resolve();
    } else {
      presentation = spec.resolve(preset: preset);
    }

    return NodeUiState(
      sizePreset: presentation.preset,
      width: presentation.width,
      height: presentation.height,
      collapsedSections: _collapsedSectionsFrom(
        node.data[nodeUiCollapsedSectionsKey],
      ),
      editorVersion: _editorVersionFrom(node.data[nodeUiEditorVersionKey]),
    );
  }

  static Map<String, Object?> write(MindmapNode node, NodeUiState state) {
    final NodePresentationSpec spec = NodePresentationSpec.forType(node.type);
    final NodePresentationState presentation =
        state.sizePreset == NodeSizePreset.custom
        ? spec.resolve(
            preset: state.sizePreset,
            customWidth: state.width,
            customHeight: state.height,
          )
        : spec.resolve(preset: state.sizePreset);
    final Set<String> collapsedSections = state.collapsedSections
        .where((String section) => section.trim().isNotEmpty)
        .toSet();

    final Map<String, Object?> persistentData = <String, Object?>{...node.data}
      ..removeWhere((String key, Object? _) {
        return _inlineWorkspaceEphemeralKeys.contains(key);
      });

    return <String, Object?>{
      ...persistentData,
      nodeUiSizePresetKey: presentation.preset.name,
      nodeUiWidthKey: presentation.width,
      nodeUiHeightKey: presentation.height,
      nodeUiCollapsedSectionsKey: collapsedSections.toList(growable: false),
      nodeUiEditorVersionKey: state.editorVersion > 0
          ? state.editorVersion
          : NodeUiState.currentEditorVersion,
    };
  }

  static NodeSizePreset? _presetFrom(Object? value) {
    if (value is! String) return null;
    for (final NodeSizePreset preset in NodeSizePreset.values) {
      if (preset.name == value) return preset;
    }
    return null;
  }

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final double result = value.toDouble();
    return result.isFinite ? result : null;
  }

  static Set<String> _collapsedSectionsFrom(Object? value) {
    if (value is! List<Object?> ||
        value.any((Object? item) => item is! String)) {
      return const <String>{};
    }
    return UnmodifiableSetView<String>(
      value
          .cast<String>()
          .where((String section) => section.trim().isNotEmpty)
          .toSet(),
    );
  }

  static int _editorVersionFrom(Object? value) {
    return value is int && value > 0 ? value : NodeUiState.currentEditorVersion;
  }
}

extension MindmapNodeUiState on MindmapNode {
  NodeUiState get uiState => NodeUiStateCodec.read(this);

  MindmapNode copyWithUiState(NodeUiState state) {
    return copyWith(data: NodeUiStateCodec.write(this, state));
  }
}
