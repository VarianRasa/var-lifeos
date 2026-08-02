import 'package:flutter/material.dart';

import '../domain/inline_node_workspace_policy.dart';
import '../domain/mindmap_node.dart';
import 'node_editors/life_data_node_editors.dart';
import 'node_type_inline_editor.dart';

enum InlineNodeSaveStatus { idle, dirty, saving, saved, error }

class InlineNodeWorkspace extends StatefulWidget {
  const InlineNodeWorkspace({
    required this.node,
    required this.editContext,
    required this.saveStatus,
    required this.onCollapse,
    required this.onRetrySave,
    required this.onDraftChanged,
    super.key,
  });

  final MindmapNode node;
  final NodeEditContext editContext;
  final InlineNodeSaveStatus saveStatus;
  final VoidCallback onCollapse;
  final VoidCallback onRetrySave;
  final ValueChanged<InlineNodeDraftPatch> onDraftChanged;

  @override
  State<InlineNodeWorkspace> createState() => _InlineNodeWorkspaceState();
}

class _InlineNodeWorkspaceState extends State<InlineNodeWorkspace> {
  final Set<String> _busyActions = <String>{};
  final FocusScopeNode _focusScopeNode = FocusScopeNode(
    debugLabel: 'Inline node workspace',
  );

  @override
  void initState() {
    super.initState();
    _requestInitialFocus();
  }

  @override
  void didUpdateWidget(covariant InlineNodeWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) _requestInitialFocus();
  }

  void _requestInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusScopeNode.context != null) {
        _focusScopeNode.requestFocus();
        _focusScopeNode.nextFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  Future<void> _runAction(String key, Future<void> Function() action) async {
    if (_busyActions.contains(key)) return;
    setState(() => _busyActions.add(key));
    try {
      await action();
    } catch (error, stackTrace) {
      widget.editContext.onActionError?.call(error, stackTrace);
    } finally {
      if (mounted) setState(() => _busyActions.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final MindmapNode node = widget.node;
    final NodeEditContext editContext = widget.editContext;
    final String semanticsLabel = <String>[
      node.title,
      node.type.label,
      'expanded',
      _saveStatusLabel(widget.saveStatus),
    ].join(', ');
    final NodeEditContext routedContext = NodeEditContext(
      node: editContext.node,
      typedDraft: editContext.typedDraft,
      cachedPayload: editContext.cachedPayload,
      effectivePreset: editContext.effectivePreset,
      validationErrors: editContext.validationErrors,
      onTitleChanged: (String value) {
        editContext.onTitleChanged(value);
        widget.onDraftChanged(InlineNodeDraftPatch(title: value));
      },
      onBodyChanged: (String value) {
        editContext.onBodyChanged(value);
        widget.onDraftChanged(InlineNodeDraftPatch(body: value));
      },
      onDraftChanged: (Object value) {
        editContext.onDraftChanged(value);
        final MindmapNode resulting = applyNodeTypeInlineDraft(
          editContext.node,
          value,
        );
        widget.onDraftChanged(
          InlineNodeDraftPatch.between(editContext.node, resulting),
        );
      },
      onNodeDraftChanged: (MindmapNode value) {
        editContext.onNodeDraftChanged(value);
        widget.onDraftChanged(
          InlineNodeDraftPatch.between(editContext.node, value),
        );
      },
      attachmentBytes: editContext.attachmentBytes,
      attachmentLoading: editContext.attachmentLoading,
      attachmentError: editContext.attachmentError,
      onMediaAction: editContext.onMediaAction == null
          ? null
          : (Object value) => _runAction(
              'media-${value.runtimeType}',
              () => editContext.onMediaAction!(value),
            ),
      onTaskChecklistAction: (MindmapNode value) =>
          _runAction('task-checklist', () async {
            await editContext.onTaskChecklistAction?.call(value);
            widget.onDraftChanged(
              InlineNodeDraftPatch.between(editContext.node, value),
            );
          }),
      onTaskAttachmentAdd: editContext.onTaskAttachmentAdd,
      onTaskAttachmentOpen: editContext.onTaskAttachmentOpen,
      onTaskAttachmentRemove: editContext.onTaskAttachmentRemove,
      onResourceAssetAdd: editContext.onResourceAssetAdd,
      onResourceAssetOpen: editContext.onResourceAssetOpen,
      resourceFolderSuggestions: editContext.resourceFolderSuggestions,
      onKanbanAttachmentAdd: editContext.onKanbanAttachmentAdd,
      onKanbanAttachmentOpen: editContext.onKanbanAttachmentOpen,
      onKanbanAttachmentRemove: editContext.onKanbanAttachmentRemove,
      onPlanAttachmentAdd: editContext.onPlanAttachmentAdd,
      onPlanAttachmentOpen: editContext.onPlanAttachmentOpen,
      onPlanAttachmentRemove: editContext.onPlanAttachmentRemove,
      onKanbanAction: (Object value) => _runAction('kanban', () async {
        await editContext.onKanbanAction?.call(value);
        final MindmapNode resulting = applyNodeTypeInlineDraft(
          editContext.node,
          value,
        );
        widget.onDraftChanged(
          InlineNodeDraftPatch.between(editContext.node, resulting),
        );
      }),
      onPlanAction: (MindmapNode value) => _runAction('plan', () async {
        await editContext.onPlanAction?.call(value);
        widget.onDraftChanged(
          InlineNodeDraftPatch.between(editContext.node, value),
        );
      }),
      onGoalAction: (MindmapNode value) => _runAction('goal', () async {
        await editContext.onGoalAction?.call(value);
        widget.onDraftChanged(
          InlineNodeDraftPatch.between(editContext.node, value),
        );
      }),
      onHabitAction: (Object value) => _runAction('habit', () async {
        await editContext.onHabitAction?.call(value);
        final MindmapNode resulting = value is MindmapNode
            ? value
            : applyNodeTypeInlineDraft(editContext.node, value);
        widget.onDraftChanged(
          InlineNodeDraftPatch.between(editContext.node, resulting),
        );
      }),
      onTimerAction: (Object value) => _runAction('timer', () async {
        await editContext.onTimerAction?.call(value);
        final MindmapNode resulting = applyNodeTypeInlineDraft(
          editContext.node,
          value,
        );
        widget.onDraftChanged(
          InlineNodeDraftPatch.between(editContext.node, resulting),
        );
      }),
      onKnowledgeAction: editContext.onKnowledgeAction == null
          ? null
          : (Object value) => _runAction(
              'knowledge-${value.runtimeType}',
              () => editContext.onKnowledgeAction!(value),
            ),
      onItineraryAction: editContext.onItineraryAction == null
          ? null
          : (Object value) => _runAction(
              'itinerary-${value.runtimeType}',
              () => editContext.onItineraryAction!(value),
            ),
      onEmptyAction: (Object value) => _runAction('empty', () async {
        await editContext.onEmptyAction?.call(value);
        if (value is! ConvertEmptyNodeAction) {
          throw ArgumentError.value(value, 'value', 'Unsupported empty action');
        }
        widget.onDraftChanged(InlineNodeDraftPatch(type: value.targetType));
      }),
      onActionError: editContext.onActionError,
      videoPlaybackScheduler: editContext.videoPlaybackScheduler,
      videoPlaybackDebounce: editContext.videoPlaybackDebounce,
    );

    return FocusScope(
      node: _focusScopeNode,
      child: Semantics(
        label: semanticsLabel,
        container: true,
        explicitChildNodes: true,
        child: InlineNodeWorkspaceSurface(
          header: _InlineNodeWorkspaceHeader(
            key: ValueKey<String>('inline-workspace-header-${node.id}'),
            node: node,
            saveStatus: widget.saveStatus,
            onCollapse: widget.onCollapse,
          ),
          bodyKey: ValueKey<String>('inline-workspace-scroll-${node.id}'),
          body: buildNodeTypeInlineEditor(routedContext),
          footer: _InlineNodeWorkspaceFooter(
            key: ValueKey<String>('inline-workspace-footer-${node.id}'),
            node: node,
            saveStatus: widget.saveStatus,
            validationErrors: editContext.validationErrors,
            onRetrySave: widget.onRetrySave,
          ),
        ),
      ),
    );
  }
}

class InlineNodeWorkspaceSurface extends StatelessWidget {
  const InlineNodeWorkspaceSurface({
    required this.header,
    required this.body,
    required this.footer,
    this.bodyKey,
    this.bodyPadding = const EdgeInsets.all(12),
    this.bodyOwnsScroll = true,
    super.key,
  });

  final Widget header;
  final Widget body;
  final Widget footer;
  final Key? bodyKey;
  final EdgeInsetsGeometry bodyPadding;
  final bool bodyOwnsScroll;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      header,
      const Divider(height: 1),
      Expanded(
        child: InlineNodeWorkspaceScrollBody(
          key: bodyKey,
          padding: bodyPadding,
          childOwnsScroll: bodyOwnsScroll,
          child: body,
        ),
      ),
      const Divider(height: 1),
      footer,
    ],
  );
}

class InlineNodeWorkspaceScrollBody extends StatelessWidget {
  const InlineNodeWorkspaceScrollBody({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.childOwnsScroll = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool childOwnsScroll;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) => Padding(
      padding: padding,
      child: SizedBox.expand(
        child: childOwnsScroll ? child : SingleChildScrollView(child: child),
      ),
    ),
  );
}

class _InlineNodeWorkspaceHeader extends StatelessWidget {
  const _InlineNodeWorkspaceHeader({
    required this.node,
    required this.saveStatus,
    required this.onCollapse,
    super.key,
  });

  final MindmapNode node;
  final InlineNodeSaveStatus saveStatus;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String statusLabel = _saveStatusLabel(saveStatus);
    final Color statusColor = switch (saveStatus) {
      InlineNodeSaveStatus.error => colors.error,
      InlineNodeSaveStatus.saving ||
      InlineNodeSaveStatus.dirty => colors.primary,
      InlineNodeSaveStatus.saved => colors.tertiary,
      InlineNodeSaveStatus.idle => colors.onSurfaceVariant,
    };

    return SizedBox(
      height: 63,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: 0.72),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(
                    Icons.edit_note_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      node.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      node.type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                key: ValueKey<String>(
                  'inline-workspace-save-status-${node.id}',
                ),
                liveRegion: true,
                label: statusLabel,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey<String>('inline-workspace-collapse-${node.id}'),
                tooltip: 'Collapse node',
                visualDensity: VisualDensity.compact,
                onPressed: onCollapse,
                icon: const Icon(Icons.unfold_less_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineNodeWorkspaceFooter extends StatelessWidget {
  const _InlineNodeWorkspaceFooter({
    required this.node,
    required this.saveStatus,
    required this.validationErrors,
    required this.onRetrySave,
    super.key,
  });

  final MindmapNode node;
  final InlineNodeSaveStatus saveStatus;
  final List<String> validationErrors;
  final VoidCallback onRetrySave;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: <Widget>[
        Expanded(
          child: validationErrors.isEmpty
              ? ExcludeSemantics(
                  child: Text(
                    _saveStatusLabel(saveStatus),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : Text(
                  validationErrors.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        if (saveStatus == InlineNodeSaveStatus.error)
          TextButton(
            key: ValueKey<String>('inline-workspace-retry-${node.id}'),
            onPressed: onRetrySave,
            child: const Text('Retry'),
          ),
      ],
    ),
  );
}

String _saveStatusLabel(InlineNodeSaveStatus status) => switch (status) {
  InlineNodeSaveStatus.idle => 'idle',
  InlineNodeSaveStatus.dirty => 'unsaved',
  InlineNodeSaveStatus.saving => 'saving',
  InlineNodeSaveStatus.saved => 'saved',
  InlineNodeSaveStatus.error => 'save failed',
};
