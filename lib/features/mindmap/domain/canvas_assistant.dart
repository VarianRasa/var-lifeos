import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'canvas_board.dart';
import 'mindmap_node.dart';

enum CanvasAssistantProposalKind { cluster, actionItem, duplicate, layout }

final class CanvasAssistantCluster {
  const CanvasAssistantCluster({
    required this.id,
    required this.label,
    required this.objectIds,
  });

  final String id;
  final String label;
  final List<String> objectIds;
}

final class CanvasAssistantDuplicate {
  const CanvasAssistantDuplicate({
    required this.primaryObjectId,
    required this.duplicateObjectId,
    required this.similarity,
  });

  final String primaryObjectId;
  final String duplicateObjectId;
  final double similarity;
}

final class CanvasAssistantProposal {
  const CanvasAssistantProposal({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    this.objectIds = const <String>[],
    this.createdObjects = const <CanvasObject>[],
    this.updatedObjects = const <CanvasObject>[],
    this.deletedObjectIds = const <String>[],
  });

  final String id;
  final CanvasAssistantProposalKind kind;
  final String title;
  final String description;
  final List<String> objectIds;
  final List<CanvasObject> createdObjects;
  final List<CanvasObject> updatedObjects;
  final List<String> deletedObjectIds;
}

final class CanvasAssistantAnalysis {
  CanvasAssistantAnalysis({
    required this.boardId,
    required this.boardUpdatedAt,
    required this.summary,
    required this.clusters,
    required this.actionItems,
    required this.duplicates,
    required this.proposals,
    required this.analyzedObjectIds,
    required CanvasBoard sourceBoard,
  }) : _sourceBoard = sourceBoard;

  final String boardId;
  final DateTime boardUpdatedAt;
  final String summary;
  final List<CanvasAssistantCluster> clusters;
  final List<String> actionItems;
  final List<CanvasAssistantDuplicate> duplicates;
  final List<CanvasAssistantProposal> proposals;
  final List<String> analyzedObjectIds;
  final CanvasBoard _sourceBoard;

  bool isCurrent(CanvasBoard board) =>
      board.id == boardId && board.updatedAt == boardUpdatedAt;

  CanvasBoard apply(Iterable<String> proposalIds, {required DateTime now}) {
    final selected = proposals
        .where((proposal) => proposalIds.contains(proposal.id))
        .toList(growable: false);
    var objects = <CanvasObject>[..._sourceBoard.objects];
    final replacementIds = <String, String>{};
    for (final proposal in selected) {
      if (proposal.kind == CanvasAssistantProposalKind.duplicate &&
          proposal.objectIds.length >= 2) {
        replacementIds[proposal.objectIds[1]] = proposal.objectIds[0];
      }
      final deletedIds = proposal.deletedObjectIds.toSet();
      objects = objects
          .where((object) => !deletedIds.contains(object.id))
          .toList();
      final updatedById = <String, CanvasObject>{
        for (final object in proposal.updatedObjects) object.id: object,
      };
      objects = <CanvasObject>[
        for (final object in objects)
          if (updatedById[object.id] case final replacement?)
            switch (proposal.kind) {
              CanvasAssistantProposalKind.layout => object.copyWith(
                geometry: replacement.geometry,
                updatedAt: now,
              ),
              CanvasAssistantProposalKind.cluster => object.copyWith(
                parentFrameId: replacement.parentFrameId,
                updatedAt: now,
              ),
              CanvasAssistantProposalKind.duplicate => replacement.copyWith(
                geometry: object.geometry,
                parentFrameId: object.parentFrameId,
                updatedAt: now,
              ),
              CanvasAssistantProposalKind.actionItem => replacement,
            }
          else
            object,
        ...proposal.createdObjects.where(
          (created) => objects.every((object) => object.id != created.id),
        ),
      ];
    }
    final allocations = <String, Set<String>>{
      for (final entry in _sourceBoard.votingSession.allocations.entries)
        entry.key: <String>{
          for (final objectId in entry.value)
            replacementIds[objectId] ?? objectId,
        },
    };
    objects = <CanvasObject>[
      for (final object in objects)
        if (object.type == CanvasObjectType.frame &&
            object.id.startsWith('assistant-frame-'))
          _fitFrameToChildren(object, objects, now)
        else
          object,
    ];
    return _sourceBoard.copyWith(
      objects: objects,
      votingSession: CanvasVotingSession(
        status: _sourceBoard.votingSession.status,
        maxVotesPerParticipant:
            _sourceBoard.votingSession.maxVotesPerParticipant,
        allocations: allocations,
      ),
      updatedAt: now,
    );
  }

  CanvasObject _fitFrameToChildren(
    CanvasObject frame,
    List<CanvasObject> objects,
    DateTime now,
  ) {
    final children = objects
        .where((object) => object.parentFrameId == frame.id)
        .toList(growable: false);
    if (children.isEmpty) return frame;
    final left = children.map((object) => object.geometry.x).reduce(math.min);
    final top = children.map((object) => object.geometry.y).reduce(math.min);
    final right = children
        .map((object) => object.geometry.x + object.geometry.width)
        .reduce(math.max);
    final bottom = children
        .map((object) => object.geometry.y + object.geometry.height)
        .reduce(math.max);
    return frame.copyWith(
      geometry: CanvasGeometry(
        x: left - 32,
        y: top - 72,
        width: right - left + 64,
        height: bottom - top + 104,
      ),
      updatedAt: now,
    );
  }
}

final class CanvasAssistantAnalyzer {
  const CanvasAssistantAnalyzer();

  CanvasAssistantAnalysis replaceClusters({
    required CanvasAssistantAnalysis analysis,
    required List<CanvasAssistantCluster> clusters,
    required DateTime now,
  }) {
    final analyzedIds = analysis.analyzedObjectIds.toSet();
    final validClusters = clusters
        .map(
          (cluster) => CanvasAssistantCluster(
            id: cluster.id,
            label: cluster.label,
            objectIds:
                cluster.objectIds.where(analyzedIds.contains).toSet().toList()
                  ..sort(),
          ),
        )
        .where((cluster) => cluster.objectIds.isNotEmpty)
        .toList(growable: false);
    return CanvasAssistantAnalysis(
      boardId: analysis.boardId,
      boardUpdatedAt: analysis.boardUpdatedAt,
      summary: analysis.summary,
      clusters: validClusters,
      actionItems: analysis.actionItems,
      duplicates: analysis.duplicates,
      proposals: <CanvasAssistantProposal>[
        ..._clusterProposals(validClusters, analysis._sourceBoard, now),
        ...analysis.proposals.where(
          (proposal) => proposal.kind != CanvasAssistantProposalKind.cluster,
        ),
      ],
      analyzedObjectIds: analysis.analyzedObjectIds,
      sourceBoard: analysis._sourceBoard,
    );
  }

  CanvasAssistantAnalysis analyze({
    required CanvasBoard board,
    required Iterable<MindmapNode> nodes,
    required DateTime now,
    Set<String>? objectIds,
  }) {
    final nodesById = <String, MindmapNode>{
      for (final node in nodes) node.id: node,
    };
    final source = board.objects
        .where(
          (object) =>
              object.isVisible &&
              (objectIds == null || objectIds.contains(object.id)) &&
              _textFor(object, nodesById).isNotEmpty,
        )
        .toList(growable: false);
    final texts = <String, String>{
      for (final object in source) object.id: _textFor(object, nodesById),
    };
    final tokens = <String, Set<String>>{
      for (final entry in texts.entries) entry.key: _tokens(entry.value),
    };
    final clusters = _clusters(source, texts, tokens);
    final duplicates = _duplicates(source, tokens);
    final actionItems = _actionItems(texts.values);
    final decisionCount = texts.values
        .expand((text) => text.split(RegExp(r'[\n;]+')))
        .where((line) => line.trim().toLowerCase().startsWith('decision:'))
        .length;
    final proposals = <CanvasAssistantProposal>[
      ..._clusterProposals(clusters, board, now),
      ..._actionProposals(actionItems, board, now),
      ..._duplicateProposals(duplicates, board, now),
      if (source
              .where(
                (object) =>
                    !object.isLocked &&
                    object.type != CanvasObjectType.connector,
              )
              .length >=
          2)
        _layoutProposal(source, clusters, board, now),
    ];
    final voteLeaders = source
        .map(
          (object) => (
            object: object,
            votes: board.votingSession.votesForObject(object.id),
          ),
        )
        .where((entry) => entry.votes > 0)
        .sorted((left, right) => right.votes.compareTo(left.votes));
    final summaryParts = <String>[
      '${source.length} analyzed objects',
      '${clusters.length} themes',
      '${actionItems.length} action items',
      '$decisionCount decisions',
      '${duplicates.length} possible duplicates',
      '${clusters.where((cluster) => cluster.objectIds.length == 1).length} ungrouped objects',
      if (voteLeaders.isNotEmpty)
        'top vote: ${texts[voteLeaders.first.object.id]} (${voteLeaders.first.votes})',
    ];
    return CanvasAssistantAnalysis(
      boardId: board.id,
      boardUpdatedAt: board.updatedAt,
      summary: summaryParts.join(' ? '),
      clusters: clusters,
      actionItems: actionItems,
      duplicates: duplicates,
      proposals: proposals,
      analyzedObjectIds: source.map((object) => object.id).toList(),
      sourceBoard: board,
    );
  }

  List<CanvasAssistantCluster> _clusters(
    List<CanvasObject> objects,
    Map<String, String> texts,
    Map<String, Set<String>> tokens,
  ) {
    final remaining = objects.map((object) => object.id).toSet();
    final result = <CanvasAssistantCluster>[];
    while (remaining.isNotEmpty) {
      final seed = remaining.first;
      final members = <String>{seed};
      remaining.remove(seed);
      var changed = true;
      while (changed) {
        changed = false;
        for (final candidate in remaining.toList()) {
          if (members.any(
            (member) =>
                _similarity(tokens[member]!, tokens[candidate]!) >= 0.25,
          )) {
            members.add(candidate);
            remaining.remove(candidate);
            changed = true;
          }
        }
      }
      final frequencies = <String, int>{};
      for (final member in members) {
        for (final token in tokens[member]!) {
          frequencies[token] = (frequencies[token] ?? 0) + 1;
        }
      }
      final label = frequencies.entries
          .sorted((left, right) {
            final count = right.value.compareTo(left.value);
            return count != 0 ? count : left.key.compareTo(right.key);
          })
          .firstOrNull
          ?.key;
      result.add(
        CanvasAssistantCluster(
          id: 'cluster-${result.length + 1}',
          label: label == null
              ? texts[seed]!.split(RegExp(r'\s+')).take(3).join(' ')
              : '${label[0].toUpperCase()}${label.substring(1)}',
          objectIds: members.toList()..sort(),
        ),
      );
    }
    return result;
  }

  List<CanvasAssistantDuplicate> _duplicates(
    List<CanvasObject> objects,
    Map<String, Set<String>> tokens,
  ) {
    final result = <CanvasAssistantDuplicate>[];
    final pairedIds = <String>{};
    for (var left = 0; left < objects.length; left++) {
      if (pairedIds.contains(objects[left].id)) continue;
      for (var right = left + 1; right < objects.length; right++) {
        if (pairedIds.contains(objects[right].id)) continue;
        final similarity = _similarity(
          tokens[objects[left].id]!,
          tokens[objects[right].id]!,
        );
        if (similarity >= 0.8) {
          result.add(
            CanvasAssistantDuplicate(
              primaryObjectId: objects[left].id,
              duplicateObjectId: objects[right].id,
              similarity: similarity,
            ),
          );
          pairedIds
            ..add(objects[left].id)
            ..add(objects[right].id);
          break;
        }
      }
    }
    return result;
  }

  List<String> _actionItems(Iterable<String> texts) {
    final result = <String>{};
    final labeledPattern = RegExp(
      r'^(?:[-*]\s*)?(?:\[[ xX]?\]\s*)?(?:todo|action|next|follow up|follow-up)[:\s-]+(.+)$',
      caseSensitive: false,
    );
    final checkboxPattern = RegExp(r'^(?:[-*]\s*)?\[\s\]\s+(.+)$');
    for (final text in texts) {
      for (final rawLine in text.split(RegExp(r'[\n;]+'))) {
        final line = rawLine.trim();
        final labeled = labeledPattern.firstMatch(line);
        final checkbox = checkboxPattern.firstMatch(line);
        final candidate =
            labeled?.group(1)?.trim() ?? checkbox?.group(1)?.trim();
        if (candidate != null && candidate.isNotEmpty) {
          result.add(candidate);
          continue;
        }
        final firstWord = line.toLowerCase().split(RegExp(r'\s+')).firstOrNull;
        if (line.split(RegExp(r'\s+')).length >= 2 &&
            _actionVerbs.contains(firstWord)) {
          result.add(line);
        }
      }
    }
    return result.toList()..sort();
  }

  Iterable<CanvasAssistantProposal> _clusterProposals(
    List<CanvasAssistantCluster> clusters,
    CanvasBoard board,
    DateTime now,
  ) sync* {
    final frameZIndex = board.objects.isEmpty
        ? 0
        : board.objects.map((object) => object.zIndex).reduce(math.min) - 1;
    for (final (index, cluster) in clusters.indexed) {
      if (cluster.objectIds.length < 2) continue;
      final members = board.objects.where(
        (object) => cluster.objectIds.contains(object.id),
      );
      final left =
          members.map((object) => object.geometry.x).reduce(math.min) - 32;
      final top =
          members.map((object) => object.geometry.y).reduce(math.min) - 72;
      final right =
          members
              .map((object) => object.geometry.x + object.geometry.width)
              .reduce(math.max) +
          32;
      final bottom =
          members
              .map((object) => object.geometry.y + object.geometry.height)
              .reduce(math.max) +
          32;
      final frame = CanvasObject(
        id: 'assistant-frame-${now.microsecondsSinceEpoch}-$index',
        type: CanvasObjectType.frame,
        geometry: CanvasGeometry(
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
        ),
        zIndex: frameZIndex - index,
        payload: <String, Object?>{'text': cluster.label, 'color': 'purple'},
        createdAt: now,
        updatedAt: now,
      );
      yield CanvasAssistantProposal(
        id: 'cluster:${cluster.id}',
        kind: CanvasAssistantProposalKind.cluster,
        title: 'Group ${cluster.label}',
        description: '${cluster.objectIds.length} related objects',
        objectIds: cluster.objectIds,
        createdObjects: <CanvasObject>[frame],
        updatedObjects: <CanvasObject>[
          for (final object in members)
            if (!object.isLocked)
              object.copyWith(parentFrameId: frame.id, updatedAt: now),
        ],
      );
    }
  }

  Iterable<CanvasAssistantProposal> _actionProposals(
    List<String> items,
    CanvasBoard board,
    DateTime now,
  ) sync* {
    final right = board.objects.isEmpty
        ? 0.0
        : board.objects
                  .map((object) => object.geometry.x + object.geometry.width)
                  .reduce(math.max) +
              80;
    var zIndex = board.objects.fold<int>(
      -1,
      (value, object) => math.max(value, object.zIndex),
    );
    for (final (index, item) in items.indexed) {
      final object = CanvasObject(
        id: 'assistant-action-${now.microsecondsSinceEpoch}-$index',
        type: CanvasObjectType.stickyNote,
        geometry: CanvasGeometry(
          x: right,
          y: index * 190,
          width: 240,
          height: 160,
        ),
        zIndex: ++zIndex,
        payload: <String, Object?>{'text': 'Action: $item', 'color': 'amber'},
        createdAt: now,
        updatedAt: now,
      );
      yield CanvasAssistantProposal(
        id: 'action:$index',
        kind: CanvasAssistantProposalKind.actionItem,
        title: item,
        description: 'Create action sticky note',
        createdObjects: <CanvasObject>[object],
      );
    }
  }

  Iterable<CanvasAssistantProposal> _duplicateProposals(
    List<CanvasAssistantDuplicate> duplicates,
    CanvasBoard board,
    DateTime now,
  ) sync* {
    for (final (index, duplicate) in duplicates.indexed) {
      final primary = board.objectById(duplicate.primaryObjectId);
      final other = board.objectById(duplicate.duplicateObjectId);
      if (primary == null || other == null || other.isLocked) continue;
      final comments = <CanvasObjectComment>[
        ...primary.comments,
        ...other.comments,
      ];
      yield CanvasAssistantProposal(
        id: 'duplicate:$index',
        kind: CanvasAssistantProposalKind.duplicate,
        title: 'Merge possible duplicate',
        description: '${(duplicate.similarity * 100).round()}% similar',
        objectIds: <String>[primary.id, other.id],
        updatedObjects: <CanvasObject>[
          primary
              .withComments(comments, updatedAt: now)
              .withVoteCount(
                primary.voteCount + other.voteCount,
                updatedAt: now,
              ),
        ],
        deletedObjectIds: <String>[other.id],
      );
    }
  }

  CanvasAssistantProposal _layoutProposal(
    List<CanvasObject> source,
    List<CanvasAssistantCluster> clusters,
    CanvasBoard board,
    DateTime now,
  ) {
    final clusterByObject = <String, int>{
      for (final (index, cluster) in clusters.indexed)
        for (final objectId in cluster.objectIds) objectId: index,
    };
    final startX = board.objects.isEmpty
        ? 0.0
        : board.objects
                  .map((object) => object.geometry.x + object.geometry.width)
                  .reduce(math.max) +
              80;
    final clusterWidths = <int, double>{};
    for (final object in source) {
      if (object.isLocked || object.type == CanvasObjectType.connector) {
        continue;
      }
      final cluster = clusterByObject[object.id] ?? 0;
      clusterWidths[cluster] = math.max(
        clusterWidths[cluster] ?? 0,
        object.geometry.width,
      );
    }
    final clusterXs = <int, double>{};
    var nextX = startX;
    final sortedClusters = clusterWidths.keys.toList()..sort();
    for (final cluster in sortedClusters) {
      clusterXs[cluster] = nextX;
      nextX += clusterWidths[cluster]! + 80;
    }
    final nextYs = <int, double>{};
    final updated = <CanvasObject>[];
    for (final object in source) {
      if (object.isLocked || object.type == CanvasObjectType.connector) {
        continue;
      }
      final cluster = clusterByObject[object.id] ?? 0;
      final y = nextYs[cluster] ?? 0;
      nextYs[cluster] = y + object.geometry.height + 40;
      updated.add(
        object.copyWith(
          geometry: object.geometry.copyWith(
            x: clusterXs[cluster] ?? startX,
            y: y,
          ),
          updatedAt: now,
        ),
      );
    }
    return CanvasAssistantProposal(
      id: 'layout',
      kind: CanvasAssistantProposalKind.layout,
      title: 'Organize board by theme',
      description: '${updated.length} movable objects',
      objectIds: updated.map((object) => object.id).toList(),
      updatedObjects: updated,
    );
  }

  String _textFor(CanvasObject object, Map<String, MindmapNode> nodesById) {
    if (object.type == CanvasObjectType.nodeReference) {
      final node = nodesById[object.mindmapNodeId];
      return node == null ? '' : '${node.title}\n${node.body}'.trim();
    }
    final values = <String>[];
    for (final key in const <String>[
      'text',
      'title',
      'description',
      'caption',
      'url',
    ]) {
      final value = object.payload[key];
      if (value is String && value.trim().isNotEmpty) values.add(value.trim());
    }
    return values.join('\n');
  }

  Set<String> _tokens(String value) => RegExp(r'[a-zA-Z0-9]{3,}')
      .allMatches(value.toLowerCase())
      .map((match) => match.group(0)!)
      .where((token) => !_stopWords.contains(token))
      .toSet();

  double _similarity(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final intersection = left.intersection(right).length;
    return intersection / left.union(right).length;
  }
}

const Set<String> _stopWords = <String>{
  'and',
  'atau',
  'dari',
  'dengan',
  'for',
  'from',
  'ini',
  'itu',
  'pada',
  'that',
  'the',
  'this',
  'untuk',
  'yang',
  'your',
  'you',
  'todo',
  'action',
  'next',
};

const Set<String> _actionVerbs = <String>{
  'add',
  'build',
  'call',
  'check',
  'create',
  'draft',
  'email',
  'finish',
  'fix',
  'follow',
  'implement',
  'launch',
  'prepare',
  'review',
  'send',
  'ship',
  'test',
  'update',
  'write',
};
