import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../core/utils/date_utils.dart';
import '../application/collaboration_controller.dart';
import '../application/mindmap_mutation_controller.dart';
import '../application/mindmap_providers.dart';
import '../domain/canvas_position.dart';
import '../domain/collaboration_room.dart';
import '../domain/inline_node_workspace_policy.dart';
import '../domain/kanban_board.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_mini_app_progress.dart';
import '../domain/node_presentation.dart';
import '../domain/node_type_payloads.dart';
import '../domain/project_plan.dart';
import 'collaboration_share_dialog.dart';
import 'node_editors/audio_node_editor.dart';
import 'node_editors/media_travel_node_editors.dart';
import 'node_mini_apps/knowledge_mini_apps.dart';
import 'node_mini_apps/life_mini_apps.dart';
import 'node_mini_apps/node_analytics_tab.dart';
import 'node_mini_apps/node_detail_global_tabs.dart';
import 'node_mini_apps/productivity_mini_apps.dart';
import 'node_type_inline_editor.dart';

abstract interface class NodeDetailCollaborationGateway {
  CollaborationState get state;
  Future<void> leaveRoom();
  Future<String> createRoom(DateTime day);
  Future<void> bindNode(MindmapNode node);
}

final class _ProviderNodeDetailCollaborationGateway
    implements NodeDetailCollaborationGateway {
  const _ProviderNodeDetailCollaborationGateway({
    required this.notifier,
    required this.state,
  });

  final CollaborationNotifier notifier;

  @override
  final CollaborationState state;

  @override
  Future<void> leaveRoom() => notifier.leaveRoom();

  @override
  Future<String> createRoom(DateTime day) => notifier.createRoom(day);

  @override
  Future<void> bindNode(MindmapNode node) => notifier.bindNode(node);
}

final class NodeDetailExitController {
  final List<Future<bool> Function()> _prepareExits = [];

  Future<bool> prepareExit() =>
      _prepareExits.isEmpty ? Future<bool>.value(true) : _prepareExits.last();

  void attach(Future<bool> Function() prepareExit) {
    _prepareExits.remove(prepareExit);
    _prepareExits.add(prepareExit);
  }

  void detach(Future<bool> Function() prepareExit) {
    _prepareExits.remove(prepareExit);
  }
}

/// Full-page dedicated app-like editor screen for a single [MindmapNode].
class NodeDetailPage extends ConsumerStatefulWidget {
  const NodeDetailPage({
    required this.date,
    required this.nodeId,
    this.collaborationGateway,
    this.exitController,
    super.key,
  });

  final DateTime date;
  final String nodeId;
  final NodeDetailCollaborationGateway? collaborationGateway;
  final NodeDetailExitController? exitController;

  @override
  ConsumerState<NodeDetailPage> createState() => _NodeDetailPageState();
}

class _NodeDetailPageState extends ConsumerState<NodeDetailPage>
    with WidgetsBindingObserver {
  MindmapNode? _node;
  MindmapNode? _editBase;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  Timer? _debounceSaveTimer;
  MindmapNode? _pendingSave;
  Future<void>? _saveLoop;
  int _editGeneration = 0;
  int _persistedGeneration = 0;
  int? _revisionRestoreGeneration;
  bool _saveFailed = false;
  bool _isReceiptBusy = false;
  bool _isSharingNode = false;
  bool _allowBackPop = false;
  bool _isHandlingBackPop = false;
  bool _isDisposing = false;
  late final MindmapMutationController _mutationController;
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _mutationController = ref.read(mindmapMutationControllerProvider);
    _titleController = TextEditingController();
    WidgetsBinding.instance.addObserver(this);
    widget.exitController?.attach(_prepareRouteExit);
    _loadNode();
  }

  @override
  void didUpdateWidget(covariant NodeDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exitController == widget.exitController) return;
    oldWidget.exitController?.detach(_prepareRouteExit);
    widget.exitController?.attach(_prepareRouteExit);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _debounceSaveTimer?.cancel();
      _saveFailed = false;
      unawaited(_flushPendingSave());
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.exitController?.detach(_prepareRouteExit);
    _debounceSaveTimer?.cancel();
    if (_pendingSave != null) {
      _saveFailed = false;
      unawaited(_flushPendingSave());
    }
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadNode() async {
    try {
      final repository = ref.read(mindmapRepositoryProvider);
      final loadedNode = await repository.getNode(widget.nodeId);
      final matchesRouteDay =
          loadedNode != null && loadedNode.day.isSameDay(widget.date);
      if (mounted) {
        _titleController.text = matchesRouteDay ? loadedNode.title : '';
        setState(() {
          _node = matchesRouteDay ? loadedNode : null;
          _editBase = matchesRouteDay ? loadedNode : null;
          _isLoading = false;
          if (loadedNode == null) {
            _error = 'Node not found (${widget.nodeId})';
          } else if (!matchesRouteDay) {
            _error = 'Node belongs to another calendar day';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load node: $e';
        });
      }
    }
  }

  void _onNodeChanged(MindmapNode updated) {
    _editGeneration++;
    _saveFailed = false;
    _pendingSave = updated;
    _setCurrentNode(updated, isSaving: true);

    _debounceSaveTimer?.cancel();
    _debounceSaveTimer = Timer(
      const Duration(milliseconds: 500),
      _flushPendingSave,
    );
  }

  void _setCurrentNode(MindmapNode updated, {required bool isSaving}) {
    if (_titleController.text != updated.title) {
      _titleController.value = _titleController.value.copyWith(
        text: updated.title,
        selection: TextSelection.collapsed(offset: updated.title.length),
        composing: TextRange.empty,
      );
    }
    setState(() {
      _node = updated;
      _isSaving = isSaving;
    });
  }

  Future<void> _flushPendingSave() {
    final active = _saveLoop;
    if (active != null) return active;
    final loop = _drainPendingSaves();
    _saveLoop = loop;
    return loop.whenComplete(() {
      if (identical(_saveLoop, loop)) {
        _saveLoop = null;
      }
      if (_pendingSave != null && !_saveFailed) {
        unawaited(_flushPendingSave());
      }
    });
  }

  Future<void> _drainPendingSaves() async {
    while (!_saveFailed) {
      final pending = _pendingSave;
      if (pending == null) break;
      _pendingSave = null;
      final generation = _editGeneration;
      try {
        final latest = await ref
            .read(mindmapRepositoryProvider)
            .getNode(pending.id);
        if (latest == null) {
          throw StateError('Mindmap node not found: ${pending.id}');
        }
        final base = _editBase;
        if (base == null) {
          throw StateError('Mindmap edit base is unavailable: ${pending.id}');
        }
        final patch = InlineNodeDraftPatch.between(base, pending);
        final saved = await _mutationController.savePatch(
          pending.id,
          patch,
          now: DateTime.now(),
        );
        if (saved == null) {
          throw StateError('Mindmap node not found: ${pending.id}');
        }
        final synchronized = synchronizeNodeMiniAppProgress(saved);
        final persisted = synchronized == saved
            ? saved
            : await _mutationController.saveNode(synchronized);
        _editBase = persisted;
        _persistedGeneration = generation;
        if (!_isDisposing && mounted && generation == _editGeneration) {
          _setCurrentNode(persisted, isSaving: false);
        }
      } catch (e) {
        _saveFailed = true;
        _pendingSave ??= pending;
        if (!_isDisposing && mounted) {
          setState(() {
            _isSaving = false;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to save node: $e')));
        }
      }
    }
  }

  Future<bool> _prepareRouteExit() async {
    _debounceSaveTimer?.cancel();
    _saveFailed = false;
    await _flushPendingSave();
    return _pendingSave == null && !_saveFailed;
  }

  Future<void> _handleBackPop(Object? result) async {
    if (_isHandlingBackPop || _allowBackPop) return;
    _isHandlingBackPop = true;
    final canExit = await _prepareRouteExit();
    if (!mounted) return;
    _isHandlingBackPop = false;
    if (!canExit) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null || !navigator.canPop()) return;
    setState(() => _allowBackPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !navigator.mounted) return;
    navigator.pop(result);
  }

  Future<MindmapNode?> _persistNow(MindmapNode updated) async {
    _debounceSaveTimer?.cancel();
    _onNodeChanged(updated);
    final generation = _editGeneration;
    _debounceSaveTimer?.cancel();
    _saveFailed = false;
    await _flushPendingSave();
    return !_saveFailed &&
            _pendingSave == null &&
            _persistedGeneration >= generation
        ? _node
        : null;
  }

  Future<MindmapNode> _prepareDirectMutation() async {
    _debounceSaveTimer?.cancel();
    _saveFailed = false;
    await _flushPendingSave();
    final current = _node;
    if (current == null || _pendingSave != null || _saveFailed) {
      throw StateError('Pending edits could not be saved.');
    }
    return current;
  }

  Future<void> _prepareRevisionRestore() async {
    await _prepareDirectMutation();
    _revisionRestoreGeneration = _editGeneration;
  }

  void _handleRevisionRestored(MindmapNode restored) {
    final restoreGeneration = _revisionRestoreGeneration;
    _revisionRestoreGeneration = null;
    _editBase = restored;
    if (restoreGeneration != null && restoreGeneration != _editGeneration) {
      _pendingSave = _node;
      _saveFailed = false;
      unawaited(_flushPendingSave());
      return;
    }
    _editGeneration++;
    _persistedGeneration = _editGeneration;
    _pendingSave = null;
    _setCurrentNode(restored, isSaving: false);
  }

  Future<void> _addExpenseReceipt() async {
    if (_isReceiptBusy) return;
    setState(() => _isReceiptBusy = true);
    String? importedId;
    try {
      final attachment = await (await ref.read(
        mediaFileImportServiceProvider.future,
      )).pickAttachment();
      if (attachment == null) return;
      importedId = attachment.id;
      final current = _node;
      if (current == null || current.type != NodeType.expense) {
        throw StateError('Expense node is unavailable.');
      }
      final payload = ExpensePayload.fromNode(current);
      final asset = ResourceAsset(
        id: 'receipt-${const Uuid().v4()}',
        kind: 'file',
        label: attachment.fileName,
        attachmentId: attachment.id,
        mimeType: attachment.mimeType,
        sizeBytes: attachment.byteLength,
        fileName: attachment.fileName,
        extension: p.extension(attachment.fileName).replaceFirst('.', ''),
      );
      final saved = await _persistNow(
        current.copyWith(
          data: payload
              .copyWith(receipts: [...payload.receipts, asset])
              .toData(current.data),
        ),
      );
      if (saved == null) {
        // Pending autosave owns receipt metadata and may retry after next edit.
        importedId = null;
        return;
      }
      importedId = null;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Receipt added.')));
      }
    } on Object catch (error) {
      if (importedId != null) {
        try {
          await (await ref.read(
            nodeAttachmentRepositoryProvider.future,
          )).delete(importedId);
        } on Object {
          // App-owned orphan cleanup is best effort after failed node commit.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Receipt failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _isReceiptBusy = false);
    }
  }

  Future<void> _openExpenseReceipt(ResourceAsset receipt) async {
    try {
      final bytes = await _receiptBytes(receipt);
      if (!mounted) return;
      if (receipt.isImage) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      tooltip: 'Close receipt',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }
      await _exportExpenseReceipt(receipt, bytes: bytes);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Receipt open failed: $error')));
      }
    }
  }

  Future<Uint8List> _receiptBytes(ResourceAsset receipt) async {
    final bytes = await (await ref.read(
      nodeAttachmentRepositoryProvider.future,
    )).readBytes(receipt.attachmentId);
    if (bytes == null) throw const FormatException('Receipt is unavailable.');
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  Future<void> _exportExpenseReceipt(
    ResourceAsset receipt, {
    Uint8List? bytes,
  }) async {
    try {
      final data = bytes ?? await _receiptBytes(receipt);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export receipt',
        fileName: receipt.fileName.isEmpty
            ? receipt.displayName
            : receipt.fileName,
        bytes: data,
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt exported.')));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt export failed: $error')),
        );
      }
    }
  }

  Future<void> _deleteExpenseReceipt(ResourceAsset receipt) async {
    if (_isReceiptBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text('Remove "${receipt.displayName}" from this expense?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isReceiptBusy = true);
    try {
      final current = _node;
      if (current == null || current.type != NodeType.expense) return;
      final payload = ExpensePayload.fromNode(current);
      final saved = await _persistNow(
        current.copyWith(
          data: payload
              .copyWith(
                receipts: payload.receipts
                    .where((item) => item.id != receipt.id)
                    .toList(),
              )
              .toData(current.data),
        ),
      );
      if (saved == null) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Receipt removed. Its file remains available in version history.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt delete failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReceiptBusy = false);
    }
  }

  Future<TaskAttachmentReference?> _addTaskAttachment() async {
    try {
      final attachment = await (await ref.read(
        mediaFileImportServiceProvider.future,
      )).pickAttachment();
      if (attachment == null) return null;
      return TaskAttachmentReference(
        id: attachment.id,
        fileName: attachment.fileName,
        mimeType: attachment.mimeType,
        byteLength: attachment.byteLength,
      );
    } on Object catch (error) {
      if (!_isDisposing && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Attachment failed: $error')));
      }
      return null;
    }
  }

  Future<void> _openTaskAttachment(TaskAttachmentReference attachment) async {
    final repository = await ref.read(nodeAttachmentRepositoryProvider.future);
    final bytes = await repository.readBytes(attachment.id);
    if (bytes == null) {
      throw const FormatException('Attachment is unavailable.');
    }
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (attachment.mimeType.startsWith('image/')) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: InteractiveViewer(
                    child: Image.memory(data, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Close attachment',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    final lowerName = attachment.fileName.toLowerCase();
    final textFile = const <String>[
      '.txt',
      '.md',
      '.csv',
      '.json',
      '.yaml',
      '.yml',
    ].any(lowerName.endsWith);
    if (!textFile) {
      throw UnsupportedError('File preview is unavailable.');
    }
    final preview = String.fromCharCodes(data);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(attachment.fileName),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              preview.length > 20000 ? preview.substring(0, 20000) : preview,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<KanbanAttachmentReference?> _addKanbanAttachment() async {
    final attachment = await _addTaskAttachment();
    return attachment == null
        ? null
        : KanbanAttachmentReference(
            id: attachment.id,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            byteLength: attachment.byteLength,
          );
  }

  Future<void> _openKanbanAttachment(KanbanAttachmentReference attachment) =>
      _openTaskAttachment(
        TaskAttachmentReference(
          id: attachment.id,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          byteLength: attachment.byteLength,
        ),
      );

  Future<ProjectPlanAttachmentReference?> _addPlanAttachment() async {
    final attachment = await _addTaskAttachment();
    return attachment == null
        ? null
        : ProjectPlanAttachmentReference(
            id: attachment.id,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            byteLength: attachment.byteLength,
          );
  }

  Future<void> _openPlanAttachment(ProjectPlanAttachmentReference attachment) =>
      _openTaskAttachment(
        TaskAttachmentReference(
          id: attachment.id,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          byteLength: attachment.byteLength,
        ),
      );

  Future<void> _handleKnowledgeAction(Object action) async {
    if (action is PickAudioFileAction) {
      try {
        final service = await ref.read(mediaFileImportServiceProvider.future);
        action.result.complete(
          await service.pickAudio(existing: action.existing),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is ImportRecordedAudioAction) {
      try {
        final repository = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final attachment = await repository.importBytes(
          bytes: action.bytes,
          fileName: 'recording-${DateTime.now().millisecondsSinceEpoch}.wav',
          mimeType: 'audio/wav',
        );
        action.result.complete(
          action.existing.copyWith(
            sourceType: AudioSourceType.attachment,
            attachmentId: attachment.id,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            sizeBytes: attachment.byteLength,
            remoteUrl: '',
          ),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is LoadAudioAttachmentAction) {
      try {
        final repository = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final bytes = await repository.readBytes(action.attachmentId);
        action.result.complete(
          bytes == null
              ? null
              : bytes is Uint8List
              ? bytes
              : Uint8List.fromList(bytes),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is DeleteAudioVoiceNoteAction) {
      action.result.complete(
        action.payload.copyWith(
          sourceType: AudioSourceType.none,
          attachmentId: '',
          fileName: '',
          mimeType: '',
          sizeBytes: 0,
          remoteUrl: '',
          durationMilliseconds: 0,
          transcriptSegments: const <AudioTranscriptSegment>[],
          transcriptionStatus: 'idle',
          transcriptionError: '',
        ),
      );
    }
  }

  Future<void> _handleItineraryAction(Object action) async {
    if (action is! ConvertItineraryAgendaAction) return;
    final parent = await _prepareDirectMutation();
    final now = DateTime.now();
    final created = MindmapNode.create(
      id: const Uuid().v4(),
      type: action.target == ItineraryConversionTarget.task
          ? NodeType.task
          : NodeType.event,
      title: action.item.title,
      day: parent.day,
      body: action.item.location,
      position: CanvasPosition(
        parent.position.dx + 260,
        parent.position.dy + 80,
      ),
      relatedNodeIds: [parent.id],
      data: action.target == ItineraryConversionTarget.event
          ? EventCalendarPayload(
              startDate: dayKey(parent.day),
              endDate: dayKey(parent.day),
              startTime: _agendaClock(action.item.startMinutes),
              endTime: _agendaClock(action.item.startMinutes + 60),
            ).toData(const <String, Object?>{})
          : const <String, Object?>{},
      now: now,
    );
    await _mutationController.saveNode(created);
  }

  String _agendaClock(int minutes) {
    final hour = (minutes ~/ 60).clamp(0, 23);
    final minute = (minutes % 60).clamp(0, 59);
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Future<ResourceAsset?> _addResourceAsset() async {
    final attachment = await _addTaskAttachment();
    if (attachment == null) return null;
    return ResourceAsset(
      id: 'asset-${const Uuid().v4()}',
      kind: 'file',
      label: attachment.fileName,
      attachmentId: attachment.id,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.byteLength,
      fileName: attachment.fileName,
      extension: p.extension(attachment.fileName).replaceFirst('.', ''),
    );
  }

  Future<void> _openResourceAsset(ResourceAsset asset) {
    if (!asset.isFile || asset.attachmentId.isEmpty) {
      return Future<void>.error(
        const FormatException('Resource file is unavailable.'),
      );
    }
    return _openTaskAttachment(
      TaskAttachmentReference(
        id: asset.attachmentId,
        fileName: asset.fileName.isEmpty ? asset.displayName : asset.fileName,
        mimeType: asset.mimeType.isEmpty
            ? 'application/octet-stream'
            : asset.mimeType,
        byteLength: asset.sizeBytes ?? 0,
      ),
    );
  }

  void _handleActionError(Object error, StackTrace stackTrace) {
    if (_isDisposing || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Action failed: $error')));
  }

  Future<void> _shareNode() async {
    if (_isSharingNode) return;
    final current = _node;
    if (current == null) return;
    setState(() => _isSharingNode = true);
    try {
      final saved = await _persistNow(current);
      if (saved == null || !mounted) return;
      final expense = saved.type == NodeType.expense
          ? ExpensePayload.fromNode(saved)
          : null;
      final localReceiptCount = expense?.receipts.length ?? 0;
      if (localReceiptCount > 0) {
        final shareWithoutFiles = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Share without receipt files?'),
            content: Text(
              '$localReceiptCount local receipt file${localReceiptCount == 1 ? '' : 's'} cannot be opened by collaborators. Transaction data will still be shared.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Share data only'),
              ),
            ],
          ),
        );
        if (shareWithoutFiles != true || !mounted) return;
      }
      final collaboration =
          widget.collaborationGateway ??
          _ProviderNodeDetailCollaborationGateway(
            notifier: ref.read(collaborationProvider.notifier),
            state: ref.read(collaborationProvider),
          );
      final state = collaboration.state;
      final target = CollaborationTarget.day(dayKey(saved.day));
      final matchesRoom =
          state.roomId != null &&
          state.roomTarget?.kind == target.kind &&
          state.roomTarget?.id == target.id;
      if (state.roomId != null && !matchesRoom) {
        final switchRoom = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Switch collaboration room?'),
            content: const Text(
              'Current room will close before this node is shared.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Switch'),
              ),
            ],
          ),
        );
        if (switchRoom != true || !mounted) return;
        await collaboration.leaveRoom();
      }
      if (!matchesRoom) await collaboration.createRoom(saved.day);
      final shared = expense == null
          ? saved
          : saved.copyWith(
              data: expense.copyWith(receipts: const []).toData(saved.data),
            );
      await collaboration.bindNode(shared);
      if (!mounted) return;
      await showCollaborationShareDialog(
        context,
        targetLabel: saved.title.isEmpty
            ? 'Untitled ${saved.type.label}'
            : saved.title,
      );
    } on CollaborationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Node could not be shared.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharingNode = false);
    }
  }

  Future<void> _deleteNode() async {
    final node = _node;
    if (node == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Node'),
        content: Text('Are you sure you want to delete "${node.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _debounceSaveTimer?.cancel();
      _pendingSave = null;
      await _saveLoop;
      _pendingSave = null;
      _saveFailed = true;
      await _mutationController.deleteNodeById(node.id, day: node.day);
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/calendar/${dayKey(widget.date)}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final node = _node;
    if (node == null || _error != null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Node not found',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/calendar/${dayKey(widget.date)}');
                  }
                },
                child: const Text('Back to Calendar'),
              ),
            ],
          ),
        ),
      );
    }

    final nodeColor = NodeVisuals.color(context, node.type);
    final nodeIcon = NodeVisuals.icon(node.type);

    return PopScope<Object?>(
      canPop: _allowBackPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleBackPop(result));
      },
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/calendar/${dayKey(widget.date)}');
                }
              },
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: nodeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(nodeIcon, size: 20, color: nodeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    node.title.isEmpty
                        ? 'Untitled ${node.type.label}'
                        : node.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: Colors.green,
                  ),
                ),
              IconButton(
                key: const ValueKey('node-detail-share'),
                tooltip: 'Share node',
                onPressed: _isSharingNode
                    ? null
                    : () => unawaited(_shareNode()),
                icon: _isSharingNode
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_outlined),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete node',
                onPressed: _deleteNode,
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.apps), text: 'Main App'),
                Tab(icon: Icon(Icons.analytics_outlined), text: 'Analytics'),
                Tab(icon: Icon(Icons.hub_outlined), text: 'Relations'),
                Tab(icon: Icon(Icons.history), text: 'History'),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Node Header Summary (Compact)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _titleController,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Node Title...',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            onChanged: (title) {
                              _onNodeChanged(node.copyWith(title: title));
                            },
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                avatar: Icon(
                                  nodeIcon,
                                  size: 14,
                                  color: nodeColor,
                                ),
                                label: Text(
                                  node.type.label,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                backgroundColor: nodeColor.withValues(
                                  alpha: 0.15,
                                ),
                                side: BorderSide.none,
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                ),
                                label: Text(
                                  dayKey(node.day),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                side: BorderSide.none,
                              ),
                              if (node.isDone)
                                const Chip(
                                  avatar: Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Colors.green,
                                  ),
                                  label: Text(
                                    'Completed',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  side: BorderSide.none,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: Main App Editor
                      _buildMainAppTab(context, node),

                      // Tab 2: Analytics & Metrics Tab
                      NodeAnalyticsTab(node: node),

                      // Tab 3: Relations Tab
                      NodeRelationsTab(
                        node: node,
                        prepareMutation: _prepareDirectMutation,
                        onNodeSaved: (saved) {
                          _editBase = saved;
                          _setCurrentNode(saved, isSaving: false);
                        },
                      ),

                      // Tab 4: History & Restore Tab
                      NodeHistoryTab(
                        node: node,
                        prepareRestore: _prepareRevisionRestore,
                        onRestored: _handleRevisionRestored,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _extractPrimaryAttachmentId(MindmapNode node) {
    return switch (node.type) {
      NodeType.image => ImagePayload.fromNode(node).attachmentId,
      NodeType.video => VideoPayload.fromNode(node).attachmentId,
      NodeType.audio => AudioPayload.fromNode(node).attachmentId,
      _ => '',
    };
  }

  Widget _buildMainAppTab(BuildContext context, MindmapNode node) {
    final theme = Theme.of(context);
    final attachmentId = _extractPrimaryAttachmentId(node);
    final attachmentAsync = attachmentId.isEmpty
        ? null
        : ref.watch(nodeAttachmentPreviewBytesProvider(attachmentId));
    final attachmentBytes = attachmentAsync?.valueOrNull;
    final attachmentLoading = attachmentAsync?.isLoading ?? false;
    final attachmentError = attachmentAsync?.error?.toString();

    final editor = Card(
      key: ValueKey('node-detail-editor-${node.id}-${node.title}'),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: nodeTypeInlineDraftFor(node),
            effectivePreset: NodeSizePreset.large,
            validationErrors: const <String>[],
            attachmentBytes: attachmentBytes,
            attachmentLoading: attachmentLoading,
            attachmentError: attachmentError,
            onTitleChanged: (title) {
              _onNodeChanged(node.copyWith(title: title));
            },
            onBodyChanged: (body) {
              _onNodeChanged(node.copyWith(body: body));
            },
            onDraftChanged: (draft) {
              _onNodeChanged(applyNodeTypeInlineDraft(node, draft));
            },
            onNodeDraftChanged: _onNodeChanged,
            onTaskAttachmentAdd: _addTaskAttachment,
            onTaskAttachmentOpen: _openTaskAttachment,
            onTaskAttachmentRemove: (_) async {},
            onKanbanAttachmentAdd: _addKanbanAttachment,
            onKanbanAttachmentOpen: _openKanbanAttachment,
            onKanbanAttachmentRemove: (_) async {},
            onPlanAttachmentAdd: _addPlanAttachment,
            onPlanAttachmentOpen: _openPlanAttachment,
            onPlanAttachmentRemove: (_) async {},
            onResourceAssetAdd: _addResourceAsset,
            onResourceAssetOpen: _openResourceAsset,
            onKnowledgeAction: _handleKnowledgeAction,
            onItineraryAction: _handleItineraryAction,
            onActionError: _handleActionError,
          ),
        ),
      ),
    );
    final miniApp =
        buildProductivityMiniApp(
          node: node,
          onChanged: _onNodeChanged,
          editor: editor,
        ) ??
        buildKnowledgeMiniApp(
          node: node,
          onChanged: _onNodeChanged,
          editor: editor,
        ) ??
        buildLifeMiniApp(
          node: node,
          onChanged: _onNodeChanged,
          editor: editor,
          onReceiptAdd: _isReceiptBusy ? null : _addExpenseReceipt,
          onReceiptOpen: _isReceiptBusy ? null : _openExpenseReceipt,
          onReceiptExport: _isReceiptBusy ? null : _exportExpenseReceipt,
          onReceiptDelete: _isReceiptBusy ? null : _deleteExpenseReceipt,
        );
    if (miniApp != null) return miniApp;
    if (node.type == NodeType.image || node.type == NodeType.video) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: editor,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: editor,
        ),
      ),
    );
  }
}
