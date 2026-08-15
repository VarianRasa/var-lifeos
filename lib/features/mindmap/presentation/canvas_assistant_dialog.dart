import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/http_workshop_ai_client.dart';
import '../domain/canvas_assistant.dart';
import '../domain/canvas_board.dart';
import '../domain/mindmap_node.dart';
import '../domain/workshop_ai.dart';

final class CanvasAssistantDialogResult {
  const CanvasAssistantDialogResult(
    this.analysis,
    this.proposalIds, {
    this.aiSummarySnapshot,
  });

  final CanvasAssistantAnalysis analysis;
  final Set<String> proposalIds;
  final WorkshopAiSummarySnapshot? aiSummarySnapshot;
}

class CanvasAssistantDialog extends StatefulWidget {
  const CanvasAssistantDialog({
    super.key,
    required this.board,
    required this.nodes,
    required this.selectedObjectIds,
    required this.canApply,
    required this.onPreviewChanged,
    this.workshopAiEndpoint,
    this.workshopAiClient,
  });

  final CanvasBoard board;
  final List<MindmapNode> nodes;
  final Set<String> selectedObjectIds;
  final bool canApply;
  final ValueChanged<List<CanvasObject>> onPreviewChanged;
  final Uri? workshopAiEndpoint;
  final WorkshopAiClient? workshopAiClient;

  @override
  State<CanvasAssistantDialog> createState() => CanvasAssistantDialogState();
}

class CanvasAssistantDialogState extends State<CanvasAssistantDialog> {
  final CanvasAssistantAnalyzer _analyzer = const CanvasAssistantAnalyzer();
  late bool _selectionOnly;
  late CanvasAssistantAnalysis _analysis;
  final Set<String> _selectedProposalIds = <String>{};
  WorkshopAiAnalysis? _remoteAnalysis;
  bool _remoteLoading = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _selectionOnly = widget.selectedObjectIds.isNotEmpty;
    _analyze();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitPreview());
  }

  void _analyze() {
    _analysis = _analyzer.analyze(
      board: widget.board,
      nodes: widget.nodes,
      now: DateTime.now(),
      objectIds: _selectionOnly ? widget.selectedObjectIds : null,
    );
    _selectedProposalIds
      ..clear()
      ..addAll(
        _analysis.proposals
            .where(
              (proposal) =>
                  proposal.kind != CanvasAssistantProposalKind.duplicate,
            )
            .map((proposal) => proposal.id),
      );
  }

  List<CanvasAssistantProposal> _proposals(CanvasAssistantProposalKind kind) =>
      _analysis.proposals
          .where((proposal) => proposal.kind == kind)
          .toList(growable: false);

  void _emitPreview() {
    final byId = <String, CanvasObject>{};
    for (final proposal in _analysis.proposals) {
      if (!_selectedProposalIds.contains(proposal.id)) continue;
      for (final object in <CanvasObject>[
        ...proposal.createdObjects,
        ...proposal.updatedObjects,
      ]) {
        byId[object.id] = object;
      }
    }
    widget.onPreviewChanged(byId.values.toList(growable: false));
  }

  List<WorkshopAiSticky> _remoteSticky(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return widget.board.objects
        .where(
          (object) =>
              object.isVisible &&
              object.type == CanvasObjectType.stickyNote &&
              (!_selectionOnly || widget.selectedObjectIds.contains(object.id)),
        )
        .map(
          (object) => WorkshopAiSticky(
            id: object.id,
            text: (object.payload['text'] as String? ?? '').trim(),
            votes: widget.board.votingSession.votesForObject(object.id),
            locale: locale,
          ),
        )
        .where((sticky) => sticky.text.isNotEmpty)
        .take(300)
        .toList(growable: false);
  }

  Future<void> _runRemoteAnalysis() async {
    final endpoint = widget.workshopAiEndpoint;
    if (endpoint == null) return;
    final sticky = _remoteSticky(context);
    if (sticky.isEmpty) {
      setState(() => _remoteError = 'No visible sticky notes to send.');
      return;
    }
    final consented = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('workshop-ai-consent'),
        title: const Text('Send sticky notes for AI analysis?'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Host: ${endpoint.host}'),
              const SizedBox(height: 12),
              const Text('Exact sticky text to send:'),
              const SizedBox(height: 8),
              for (final item in sticky) SelectableText(item.text),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('workshop-ai-consent-send'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send and analyze'),
          ),
        ],
      ),
    );
    if (consented != true || !mounted) return;
    setState(() {
      _remoteLoading = true;
      _remoteError = null;
    });
    final ownedClient = widget.workshopAiClient == null ? http.Client() : null;
    try {
      final client =
          widget.workshopAiClient ??
          HttpWorkshopAiClient(endpoint: endpoint, client: ownedClient!);
      final remoteAnalysis = await client.analyze(sticky);
      if (!mounted) return;
      final convertedClusters = <CanvasAssistantCluster>[
        for (final (index, cluster) in remoteAnalysis.clusters.indexed)
          CanvasAssistantCluster(
            id: 'remote-${index + 1}',
            label: cluster.name,
            objectIds: cluster.sourceIds,
          ),
      ];
      final analysis = _analyzer.replaceClusters(
        analysis: _analysis,
        clusters: convertedClusters,
        now: DateTime.now(),
      );
      setState(() {
        _remoteAnalysis = remoteAnalysis;
        _analysis = analysis;
        _selectedProposalIds.addAll(
          analysis.proposals
              .where(
                (proposal) =>
                    proposal.kind == CanvasAssistantProposalKind.cluster,
              )
              .map((proposal) => proposal.id),
        );
      });
      _emitPreview();
    } on WorkshopAiException catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _remoteError = '${error.message} Local analysis remains available.',
      );
    } finally {
      ownedClient?.close();
      if (mounted) setState(() => _remoteLoading = false);
    }
  }

  Widget _remoteResults(WorkshopAiAnalysis analysis) => Card(
    key: const ValueKey('workshop-ai-results'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Remote summary', style: Theme.of(context).textTheme.titleSmall),
          Text(analysis.summary),
          if (analysis.themes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Themes: ${analysis.themes.map((item) => item.name).join(', ')}',
            ),
          ],
          if (analysis.actionItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Actions:'),
            for (final item in analysis.actionItems) Text('• ${item.text}'),
          ],
          if (analysis.risks.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Risks:'),
            for (final item in analysis.risks) Text('• ${item.text}'),
          ],
          const SizedBox(height: 8),
          const Text('Remote clusters added to preview.'),
        ],
      ),
    ),
  );

  Widget _proposalList(CanvasAssistantProposalKind kind) {
    final proposals = _proposals(kind);
    if (proposals.isEmpty) {
      return const Center(child: Text('No suggestions for this category.'));
    }
    return ListView(
      children: [
        for (final proposal in proposals)
          CheckboxListTile(
            key: ValueKey('canvas-assistant-proposal-${proposal.id}'),
            value: _selectedProposalIds.contains(proposal.id),
            onChanged: !widget.canApply
                ? null
                : (selected) {
                    setState(() {
                      if (selected ?? false) {
                        _selectedProposalIds.add(proposal.id);
                      } else {
                        _selectedProposalIds.remove(proposal.id);
                      }
                    });
                    _emitPreview();
                  },
            title: Text(proposal.title),
            subtitle: Text(proposal.description),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: AlertDialog(
      key: const ValueKey('canvas-assistant-dialog'),
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_outlined),
          SizedBox(width: 8),
          Text('Canvas assistant'),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              key: const ValueKey('canvas-assistant-scope'),
              segments: [
                const ButtonSegment<bool>(
                  value: false,
                  label: Text('Entire board'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  enabled: widget.selectedObjectIds.isNotEmpty,
                  label: Text('Selection (${widget.selectedObjectIds.length})'),
                ),
              ],
              selected: <bool>{_selectionOnly},
              onSelectionChanged: _remoteLoading
                  ? null
                  : (selection) {
                      setState(() {
                        _selectionOnly = selection.single;
                        _analyze();
                      });
                      _emitPreview();
                    },
            ),
            const SizedBox(height: 12),
            Text(
              _analysis.summary,
              key: const ValueKey('canvas-assistant-summary'),
            ),
            if (widget.workshopAiEndpoint != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('workshop-ai-analyze'),
                  onPressed: _remoteLoading ? null : _runRemoteAnalysis,
                  icon: _remoteLoading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_outlined),
                  label: const Text('Analyze remotely (opt-in)'),
                ),
              ),
            if (_remoteError case final error?)
              Text(error, key: const ValueKey('workshop-ai-error')),
            if (!widget.canApply)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Read-only: editor permission required to apply.'),
              ),
            const SizedBox(height: 12),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Summary'),
                Tab(text: 'Clusters'),
                Tab(text: 'Actions'),
                Tab(text: 'Duplicates'),
                Tab(text: 'Layout'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    children: [
                      if (_remoteAnalysis case final analysis?)
                        _remoteResults(analysis),
                      for (final cluster in _analysis.clusters)
                        ListTile(
                          leading: const Icon(Icons.hub_outlined),
                          title: Text(cluster.label),
                          subtitle: Text('${cluster.objectIds.length} objects'),
                        ),
                      if (_analysis.actionItems.isEmpty &&
                          _analysis.clusters.isEmpty)
                        const ListTile(title: Text('Nothing to analyze yet.')),
                    ],
                  ),
                  _proposalList(CanvasAssistantProposalKind.cluster),
                  _proposalList(CanvasAssistantProposalKind.actionItem),
                  _proposalList(CanvasAssistantProposalKind.duplicate),
                  _proposalList(CanvasAssistantProposalKind.layout),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_remoteAnalysis != null)
          FilledButton.icon(
            key: const ValueKey('canvas-assistant-save-summary'),
            onPressed: !widget.canApply
                ? null
                : () => Navigator.of(context).pop(
                    CanvasAssistantDialogResult(
                      _analysis,
                      const <String>{},
                      aiSummarySnapshot: WorkshopAiSummarySnapshot.fromAnalysis(
                        _remoteAnalysis!,
                      ),
                    ),
                  ),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save AI summary'),
          ),
        FilledButton.icon(
          key: const ValueKey('canvas-assistant-apply'),
          onPressed: !widget.canApply || _selectedProposalIds.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  CanvasAssistantDialogResult(
                    _analysis,
                    Set<String>.of(_selectedProposalIds),
                    aiSummarySnapshot: _remoteAnalysis == null
                        ? null
                        : WorkshopAiSummarySnapshot.fromAnalysis(
                            _remoteAnalysis!,
                          ),
                  ),
                ),
          icon: const Icon(Icons.check),
          label: Text('Apply selected (${_selectedProposalIds.length})'),
        ),
      ],
    ),
  );
}
