import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:var_app/core/router/app_router.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/sync_controller.dart';

class Collaborator {
  Collaborator({
    required this.id,
    required this.name,
    required this.color,
    required this.cursorPosition,
    this.selectedNodeId,
    this.isEditing = false,
  });

  final String id;
  final String name;
  final Color color;
  final Offset? cursorPosition;
  final String? selectedNodeId;
  final bool isEditing;

  Collaborator copyWith({
    Offset? cursorPosition,
    String? selectedNodeId,
    bool? isEditing,
  }) {
    return Collaborator(
      id: id,
      name: name,
      color: color,
      cursorPosition: cursorPosition ?? this.cursorPosition,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      isEditing: isEditing ?? this.isEditing,
    );
  }
}

/// Short-lived visual ping (ripple) emitted by a collaborator at a scene position.
class PingEvent {
  PingEvent({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.color,
    required this.scenePosition,
    required this.createdAt,
  });

  final String id;
  final String fromId;
  final String fromName;
  final Color color;
  final Offset scenePosition;
  final DateTime createdAt;
}

class CollaborationState {
  CollaborationState({
    required this.collaborators,
    required this.isDemoMode,
    required this.isConnected,
    this.roomId,
    required this.localUserId,
    required this.localName,
    required this.localColor,
    this.roomHistory = const [],
  });

  final Map<String, Collaborator> collaborators;
  final bool isDemoMode;
  final bool isConnected;
  final String? roomId;
  final String localUserId;
  final String localName;
  final Color localColor;
  final List<String> roomHistory;

  CollaborationState copyWith({
    Map<String, Collaborator>? collaborators,
    bool? isDemoMode,
    bool? isConnected,
    String? roomId,
    String? localUserId,
    String? localName,
    Color? localColor,
    List<String>? roomHistory,
  }) {
    return CollaborationState(
      collaborators: collaborators ?? this.collaborators,
      isDemoMode: isDemoMode ?? this.isDemoMode,
      isConnected: isConnected ?? this.isConnected,
      roomId: roomId ?? this.roomId,
      localUserId: localUserId ?? this.localUserId,
      localName: localName ?? this.localName,
      localColor: localColor ?? this.localColor,
      roomHistory: roomHistory ?? this.roomHistory,
    );
  }
}

class CollaborationNotifier extends StateNotifier<CollaborationState> {
  /// Time a ping document stays valid in Firestore before peers can drop it.
  /// Matches the maximum ripple animation duration (≈900ms) plus generous slack
  /// for late-joining clients and reconnect grace.
  static const Duration _pingTtl = Duration(seconds: 30);

  CollaborationNotifier(this._ref)
    : super(
        CollaborationState(
          collaborators: {},
          isDemoMode: false,
          isConnected: true,
          localUserId: const Uuid().v4(),
          localName: 'User',
          localColor: _randomColor(),
          roomHistory: const [],
        ),
      ) {
    _loadHistory();
    // Late init local name based on sync device name if available
    Future.microtask(() {
      try {
        final syncState = _ref.read(syncControllerProvider);
        final String? label = syncState.deviceIdentity?.label;
        if (label != null && label.trim().isNotEmpty) {
          state = state.copyWith(localName: label.trim());
        } else {
          state = state.copyWith(
            localName: 'User-${state.localUserId.substring(0, 4)}',
          );
        }
      } catch (_) {}
    });
  }

  final Ref _ref;
  Timer? _simulationTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _nodesFirestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pingsFirestoreSub;
  ProviderSubscription<AsyncValue<List<MindmapNode>>>? _localNodesSub;
  bool _isSyncingFromRemote = false;
  bool _isInitializingRoom = false;
  final Map<String, String> _lastSyncNodesJson = {};
  final _random = Random();

  /// Broadcast stream of pings received from peers. UI subscribes to render ripples.
  final StreamController<PingEvent> _pingsController =
      StreamController<PingEvent>.broadcast();
  Stream<PingEvent> get pingStream => _pingsController.stream;

  SharedPreferencesAsync? get _prefs {
    try {
      return SharedPreferencesAsync();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = _prefs;
      if (prefs == null) return;
      final list = await prefs.getStringList('collab_room_history');
      if (list != null) {
        state = state.copyWith(roomHistory: list);
      }
    } catch (_) {}
  }

  Future<void> _addToHistory(String roomId) async {
    if (roomId.isEmpty) return;
    final current = List<String>.from(state.roomHistory);
    current.remove(roomId);
    current.insert(0, roomId);
    if (current.length > 5) {
      current.removeLast();
    }
    state = state.copyWith(roomHistory: current);
    try {
      final prefs = _prefs;
      if (prefs != null) {
        await prefs.setStringList('collab_room_history', current);
      }
    } catch (_) {}
  }

  static Color _randomColor() {
    final colors = [
      Colors.amberAccent,
      Colors.cyanAccent,
      Colors.pinkAccent,
      Colors.yellowAccent,
      Colors.lightGreenAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
    ];
    return colors[Random().nextInt(colors.length)];
  }

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  static String cleanRoomId(String urlOrId) {
    final uri = Uri.tryParse(urlOrId.trim());
    if (uri != null && uri.scheme == 'var-collab') {
      final pathSegments = uri.pathSegments;
      final roomIndex = pathSegments.indexOf('room');
      if (roomIndex != -1 && roomIndex + 1 < pathSegments.length) {
        return pathSegments[roomIndex + 1];
      }
      if (uri.host.isNotEmpty &&
          uri.host != 'var.app' &&
          uri.host != '[REDACTED]') {
        return uri.host;
      }
    }
    return urlOrId.trim();
  }

  Future<bool> joinRoom(String urlOrId, {String? dayKey}) async {
    final roomId = cleanRoomId(urlOrId);
    if (roomId.isEmpty) return false;

    await leaveRoom();

    state = state.copyWith(
      roomId: roomId,
      isDemoMode: false,
      collaborators: {},
    );

    await _addToHistory(roomId);

    // Ensure anonymous auth
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        debugPrint('Collab: Initiating anonymous sign in...');
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint(
          'Collab: Anonymous sign in success: ${FirebaseAuth.instance.currentUser?.uid}',
        );
      }
    } catch (e, s) {
      debugPrint('Collab: Auth failed: $e\n$s');
    }

    final fs = _firestore;
    if (fs == null) {
      debugPrint('Collab: Firestore instance is null. Cannot join room.');
      return false;
    }

    try {
      final roomRef = fs.collection('rooms').doc(roomId);
      debugPrint('Collab: Fetching room metadata for $roomId...');
      final roomDoc = await roomRef.get();
      String? targetDayKey = dayKey;

      if (roomDoc.exists) {
        final data = roomDoc.data();
        if (data != null && data['dayKey'] != null) {
          targetDayKey = data['dayKey'] as String;
          debugPrint('Collab: Found existing room dayKey: $targetDayKey');
        }
      }

      if (targetDayKey == null) {
        targetDayKey = DateTime.now().toIso8601String().substring(0, 10);
        debugPrint('Collab: No dayKey found, using fallback: $targetDayKey');
      }

      // Set metadata
      await roomRef.set({
        'dayKey': targetDayKey,
        'ownerId': state.localUserId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Collab: Room metadata saved.');

      final nodesSnap = await roomRef.collection('nodes').get();
      final hasRemoteNodes = nodesSnap.docs.isNotEmpty;
      final repository = _ref.read(mindmapRepositoryProvider);

      if (hasRemoteNodes) {
        debugPrint(
          'Collab: Found remote nodes in Firestore room. Clearing local nodes for $targetDayKey...',
        );
        final localNodes = await repository.listNodes(
          day: DateTime.parse(targetDayKey),
        );
        for (final node in localNodes) {
          await repository.deleteNode(node.id);
        }
      } else {
        debugPrint(
          'Collab: Room has no remote nodes. Uploading initial local nodes...',
        );
        final localNodes = await repository.listNodes(
          day: DateTime.parse(targetDayKey),
        );
        if (localNodes.isNotEmpty) {
          await _uploadLocalNodesToFirestore(roomId, localNodes);
        }
      }

      // Auto-navigate to correct day
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          debugPrint('Collab: Navigating to day: $targetDayKey');
          _ref.read(appRouterProvider).go('/calendar/$targetDayKey');
        } catch (e) {
          debugPrint('Collab: GoRouter navigation failed: $e');
        }
      });

      // Subscribe to collaborators in this room
      _firestoreSub = roomRef
          .collection('collaborators')
          .snapshots()
          .listen(
            (snapshot) {
              final peers = <String, Collaborator>{};
              for (final doc in snapshot.docs) {
                if (doc.id == state.localUserId) continue;
                final data = doc.data();
                final name = data['name'] as String? ?? 'Unknown';
                final colorVal =
                    data['color'] as int? ?? Colors.blue.toARGB32();
                final cursorX = data['cursorX'] as num?;
                final cursorY = data['cursorY'] as num?;
                final selectedNodeId = data['selectedNodeId'] as String?;
                final isEditing = data['isEditing'] as bool? ?? false;

                peers[doc.id] = Collaborator(
                  id: doc.id,
                  name: name,
                  color: Color(colorVal),
                  cursorPosition: cursorX != null && cursorY != null
                      ? Offset(cursorX.toDouble(), cursorY.toDouble())
                      : null,
                  selectedNodeId: selectedNodeId,
                  isEditing: isEditing,
                );
              }
              state = state.copyWith(collaborators: peers);
            },
            onError: (_) {
              state = state.copyWith(isConnected: false);
            },
          );

      // Subscribe to Firestore nodes -> Local Sembast DB sync
      _nodesFirestoreSub = roomRef.collection('nodes').snapshots().listen((
        snapshot,
      ) async {
        final repository = _ref.read(mindmapRepositoryProvider);
        _isSyncingFromRemote = true;
        try {
          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;
            final nodeId = change.doc.id;

            if (change.type == DocumentChangeType.removed) {
              _lastSyncNodesJson.remove(nodeId);
              await repository.deleteNode(nodeId);
            } else {
              final jsonStr = jsonEncode(data);
              _lastSyncNodesJson[nodeId] = jsonStr;

              final node = MindmapNode.fromJson(data);
              await repository.saveNode(node);
            }
          }
          invalidateMindmapStateFromRef(
            _ref,
            day: DateTime.parse(targetDayKey!),
          );
        } catch (_) {
        } finally {
          _isSyncingFromRemote = false;
        }
      });

      // Subscribe to pings -> emit to local UI stream for ripple render
      _pingsFirestoreSub = roomRef
          .collection('pings')
          .orderBy('t', descending: true)
          .limit(20)
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data();
              if (data == null) continue;
              final fromId = data['fromId'] as String? ?? '';
              if (fromId == state.localUserId) continue; // ignore own echo
              final x = data['x'] as num?;
              final y = data['y'] as num?;
              if (x == null || y == null) continue;
              final t =
                  data['t'] as int? ?? DateTime.now().millisecondsSinceEpoch;
              if (DateTime.now().millisecondsSinceEpoch - t > 5000) continue;
              final colorVal = data['color'] as int? ?? Colors.cyan.toARGB32();
              _pingsController.add(
                PingEvent(
                  id: change.doc.id,
                  fromId: fromId,
                  fromName: data['fromName'] as String? ?? 'Peer',
                  color: Color(colorVal),
                  scenePosition: Offset(x.toDouble(), y.toDouble()),
                  createdAt: DateTime.fromMillisecondsSinceEpoch(t),
                ),
              );
            }
          }, onError: (_) {});

      _isInitializingRoom = true;
      Future.delayed(const Duration(milliseconds: 800), () {
        _isInitializingRoom = false;
      });

      // Listen to Local Sembast DB changes -> Firestore nodes sync
      final parsedDate = DateTime.parse(targetDayKey);
      _localNodesSub = _ref.listen<AsyncValue<List<MindmapNode>>>(
        nodesForDayProvider(parsedDate),
        (previous, next) {
          final list = next.valueOrNull;
          if (list != null && !_isSyncingFromRemote && !_isInitializingRoom) {
            _uploadLocalNodesToFirestore(roomId, list);
          }
        },
        fireImmediately: false,
      );

      // Upload our initial state
      await _uploadLocalState();

      // Sweep expired ping docs left by peers who disconnected mid-ripple.
      // Fire-and-forget; UI does not block on this housekeeping task.
      unawaited(_cleanupExpiredPings());

      return true;
    } catch (e, s) {
      debugPrint('Collab: Exception during joinRoom: $e\n$s');
      state = state.copyWith(isConnected: false);
      return false;
    }
  }

  Future<void> _uploadLocalNodesToFirestore(
    String roomId,
    List<MindmapNode> nodes,
  ) async {
    final fs = _firestore;
    if (fs == null) return;
    try {
      final batch = fs.batch();
      final nodesCol = fs.collection('rooms').doc(roomId).collection('nodes');

      final serverDocs = await nodesCol.get();
      final serverNodeIds = serverDocs.docs.map((d) => d.id).toSet();
      final localNodeIds = nodes.map((n) => n.id).toSet();

      bool hasChanges = false;

      for (final sId in serverNodeIds) {
        if (!localNodeIds.contains(sId)) {
          batch.delete(nodesCol.doc(sId));
          _lastSyncNodesJson.remove(sId);
          hasChanges = true;
        }
      }

      for (final node in nodes) {
        final nodeJson = node.toJson();
        final jsonStr = jsonEncode(nodeJson);
        final prevJsonStr = _lastSyncNodesJson[node.id];

        if (prevJsonStr != jsonStr) {
          batch.set(nodesCol.doc(node.id), nodeJson, SetOptions(merge: true));
          _lastSyncNodesJson[node.id] = jsonStr;
          hasChanges = true;
        }
      }

      if (hasChanges) {
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<void> leaveRoom() async {
    _lastSyncNodesJson.clear();
    _simulationTimer?.cancel();
    await _firestoreSub?.cancel();
    _firestoreSub = null;
    await _nodesFirestoreSub?.cancel();
    _nodesFirestoreSub = null;
    await _pingsFirestoreSub?.cancel();
    _pingsFirestoreSub = null;
    _localNodesSub?.close();
    _localNodesSub = null;

    final fs = _firestore;
    final rId = state.roomId;
    if (fs != null && rId != null) {
      try {
        // Remove our cursor from Firestore
        await fs
            .collection('rooms')
            .doc(rId)
            .collection('collaborators')
            .doc(state.localUserId)
            .delete();
      } catch (_) {}
    }

    state = state.copyWith(roomId: null, collaborators: {});
  }

  DateTime _lastUploadTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _uploadLocalState({
    Offset? cursorPosition,
    String? selectedNodeId,
    bool? isEditing,
  }) async {
    final fs = _firestore;
    final rId = state.roomId;
    if (fs == null || rId == null) return;

    // Rate-limit cursor moves, but allow click/edit changes immediately
    final now = DateTime.now();
    if (cursorPosition != null &&
        selectedNodeId == null &&
        isEditing == null &&
        now.difference(_lastUploadTime).inMilliseconds < 50) {
      return;
    }
    _lastUploadTime = now;

    try {
      await fs
          .collection('rooms')
          .doc(rId)
          .collection('collaborators')
          .doc(state.localUserId)
          .set({
            'name': state.localName,
            'color': state.localColor.toARGB32(),
            if (cursorPosition != null) 'cursorX': cursorPosition.dx,
            if (cursorPosition != null) 'cursorY': cursorPosition.dy,
            'selectedNodeId': selectedNodeId,
            'isEditing': isEditing ?? false,
            'lastActive': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  void toggleDemoMode(bool enable) {
    if (enable) {
      leaveRoom().then((_) {
        state = state.copyWith(isDemoMode: true);
        _startDemoSimulation();
      });
    } else {
      _simulationTimer?.cancel();
      state = state.copyWith(isDemoMode: false, collaborators: {});
    }
  }

  // Broadcast local user cursor position
  void updateLocalCursor(Offset position) {
    if (state.roomId != null) {
      _uploadLocalState(cursorPosition: position);
    }
  }

  // Broadcast local user node selection
  void updateLocalSelection(String? nodeId, {bool isEditing = false}) {
    if (state.roomId != null) {
      _uploadLocalState(selectedNodeId: nodeId, isEditing: isEditing);
    }
  }

  /// Broadcast a short-lived visual ping at a scene position. Peers see an
  /// expanding ripple — useful for "look here" callouts during a session.
  Future<void> broadcastPing(Offset scenePosition) async {
    final fs = _firestore;
    final rId = state.roomId;
    if (fs == null || rId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await fs.collection('rooms').doc(rId).collection('pings').add({
        'fromId': state.localUserId,
        'fromName': state.localName,
        'color': state.localColor.toARGB32(),
        'x': scenePosition.dx,
        'y': scenePosition.dy,
        't': now,
        // TTL window — clients garbage-collect expired pings on join.
        'expiresAt': now + _pingTtl.inMilliseconds,
      });
    } catch (_) {}
  }

  /// Best-effort one-shot sweep that removes expired ping docs left behind by
  /// peers who disconnected mid-ripple. Safe to call repeatedly — only runs
  /// when joined to a room and swallows firestore errors.
  Future<void> _cleanupExpiredPings() async {
    final fs = _firestore;
    final rId = state.roomId;
    if (fs == null || rId == null) return;
    try {
      final snapshot = await fs
          .collection('rooms')
          .doc(rId)
          .collection('pings')
          .where('expiresAt', isLessThan: DateTime.now().millisecondsSinceEpoch)
          .limit(50)
          .get();
      if (snapshot.docs.isEmpty) return;
      final batch = fs.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  void _startDemoSimulation() {
    _simulationTimer?.cancel();

    // Initialize demo peers: "Alice" (Purple) and "Budi" (Green)
    state = state.copyWith(
      collaborators: {
        'alice': Collaborator(
          id: 'alice',
          name: 'Alice',
          color: Colors.purpleAccent,
          cursorPosition: const Offset(400, 300),
        ),
        'budi': Collaborator(
          id: 'budi',
          name: 'Budi (UX)',
          color: Colors.tealAccent,
          cursorPosition: const Offset(600, 450),
        ),
      },
    );

    // Periodic random movement simulating live Figma peers
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!state.isDemoMode) {
        timer.cancel();
        return;
      }

      final updated = Map<String, Collaborator>.from(state.collaborators);

      // Simulating Alice moving cursor towards some node
      if (updated.containsKey('alice')) {
        final current = updated['alice']!;
        final pos = current.cursorPosition ?? const Offset(400, 300);
        final dx = (_random.nextDouble() - 0.5) * 20;
        final dy = (_random.nextDouble() - 0.5) * 20;

        // Randomly select/edit nodes sometimes
        String? sel = current.selectedNodeId;
        bool editing = current.isEditing;
        if (_random.nextDouble() < 0.02) {
          sel = _random.nextBool() ? 'node-a' : null;
          editing = sel != null && _random.nextBool();
        }

        updated['alice'] = current.copyWith(
          cursorPosition: Offset(
            (pos.dx + dx).clamp(100, 1000),
            (pos.dy + dy).clamp(100, 800),
          ),
          selectedNodeId: sel,
          isEditing: editing,
        );
      }

      // Simulating Budi moving cursor
      if (updated.containsKey('budi')) {
        final current = updated['budi']!;
        final pos = current.cursorPosition ?? const Offset(600, 450);
        final dx = (_random.nextDouble() - 0.5) * 15;
        final dy = (_random.nextDouble() - 0.5) * 15;

        String? sel = current.selectedNodeId;
        bool editing = current.isEditing;
        if (_random.nextDouble() < 0.015) {
          sel = _random.nextBool() ? 'node-b' : null;
          editing = sel != null && _random.nextBool();
        }

        updated['budi'] = current.copyWith(
          cursorPosition: Offset(
            (pos.dx + dx).clamp(200, 1200),
            (pos.dy + dy).clamp(200, 900),
          ),
          selectedNodeId: sel,
          isEditing: editing,
        );
      }

      state = state.copyWith(collaborators: updated);
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _firestoreSub?.cancel();
    _nodesFirestoreSub?.cancel();
    _pingsFirestoreSub?.cancel();
    _pingsController.close();
    super.dispose();
  }
}

final collaborationProvider =
    StateNotifierProvider<CollaborationNotifier, CollaborationState>((ref) {
      return CollaborationNotifier(ref);
    });
