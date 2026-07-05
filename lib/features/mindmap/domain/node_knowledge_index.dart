/// Fast local knowledge index for node links, backlinks, and mentions.
library;

import 'mindmap_node.dart';

final class NodeKnowledgeIndex {
  NodeKnowledgeIndex(Iterable<MindmapNode> nodes)
    : nodes = List.unmodifiable(nodes),
      _nodesById = {for (final node in nodes) node.id: node};

  final List<MindmapNode> nodes;
  final Map<String, MindmapNode> _nodesById;

  MindmapNode? nodeById(String id) => _nodesById[id];

  NodeKnowledgeLinks linksFor(String nodeId, {bool includeArchived = false}) {
    final node = _nodesById[nodeId];
    if (node == null) return NodeKnowledgeLinks(nodeId: nodeId);

    final outgoingNodes = <MindmapNode>[];
    final brokenOutgoingIds = <String>[];
    for (final relatedId in node.relatedNodeIds) {
      final related = _nodesById[relatedId];
      if (related == null) {
        brokenOutgoingIds.add(relatedId);
      } else if (includeArchived || !related.isArchived) {
        outgoingNodes.add(related);
      }
    }

    final backlinks = <NodeBacklink>[];
    for (final candidate in nodes) {
      if (candidate.id == nodeId) continue;
      if (!includeArchived && candidate.isArchived) continue;
      final hasRelation = candidate.relatedNodeIds.contains(nodeId);
      final hasWikiLink = hasBracketedTitle(candidate.body, node.title);
      if (!hasRelation && !hasWikiLink) continue;
      backlinks.add(
        NodeBacklink(
          node: candidate,
          hasRelation: hasRelation,
          hasWikiLink: hasWikiLink,
        ),
      );
    }

    final unlinkedMentions = <MindmapNode>[];
    for (final candidate in nodes) {
      if (candidate.id == nodeId) continue;
      if (!includeArchived && candidate.isArchived) continue;
      if (node.relatedNodeIds.contains(candidate.id)) continue;
      final title = candidate.title.trim();
      if (title.length < 4) continue;
      if (hasBracketedTitle(node.body, title)) continue;
      if (hasPlainTitleMention(node.body, title)) {
        unlinkedMentions.add(candidate);
      }
    }

    return NodeKnowledgeLinks(
      nodeId: nodeId,
      outgoingNodes: List.unmodifiable(outgoingNodes),
      brokenOutgoingIds: List.unmodifiable(brokenOutgoingIds),
      backlinks: List.unmodifiable(backlinks),
      unlinkedMentions: List.unmodifiable(unlinkedMentions),
    );
  }
}

final class NodeKnowledgeLinks {
  const NodeKnowledgeLinks({
    required this.nodeId,
    this.outgoingNodes = const [],
    this.brokenOutgoingIds = const [],
    this.backlinks = const [],
    this.unlinkedMentions = const [],
  });

  final String nodeId;
  final List<MindmapNode> outgoingNodes;
  final List<String> brokenOutgoingIds;
  final List<NodeBacklink> backlinks;
  final List<MindmapNode> unlinkedMentions;

  bool get hasBrokenOutgoing => brokenOutgoingIds.isNotEmpty;
}

final class NodeBacklink {
  const NodeBacklink({
    required this.node,
    required this.hasRelation,
    required this.hasWikiLink,
  });

  final MindmapNode node;
  final bool hasRelation;
  final bool hasWikiLink;

  String get reasonLabel {
    final reasons = <String>[];
    if (hasRelation) reasons.add('relation');
    if (hasWikiLink) reasons.add('[[link]]');
    return reasons.isEmpty ? 'mention' : reasons.join(' + ');
  }
}

bool hasBracketedTitle(String body, String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(
    r'\[\[' + RegExp.escape(trimmed) + r'\]\]',
    caseSensitive: false,
  ).hasMatch(body);
}

bool hasPlainTitleMention(String body, String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(
    r'(?<!\[\[)\b' + RegExp.escape(trimmed) + r'\b(?!\]\])',
    caseSensitive: false,
  ).hasMatch(body);
}

String bodyWithLinkedTitle(String body, String title) {
  if (hasBracketedTitle(body, title)) return body;
  final trimmed = title.trim();
  if (trimmed.isEmpty) return body;
  final pattern = RegExp(
    r'(?<!\[\[)\b' + RegExp.escape(trimmed) + r'\b(?!\]\])',
    caseSensitive: false,
  );
  return body.replaceFirstMapped(pattern, (match) => '[[${match.group(0)}]]');
}
