import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';

final captureServiceProvider = Provider<CaptureService>((ref) {
  final repository = ref.watch(mindmapRepositoryProvider);
  return CaptureService(mindmapRepository: repository);
});

final availableCaptureDestinationsProvider =
    FutureProvider.autoDispose<List<CaptureDestination>>((ref) async {
      final repository = ref.watch(canvasBoardRepositoryProvider);
      final boards = await repository.listBoards();
      final destinations =
          boards.map((board) {
            final title =
                board.title.trim().isEmpty ? 'Untitled Board' : board.title;
            final workspaceName = board.workspaceName?.trim() ?? '';
            final workspace =
                workspaceName.isEmpty ? 'Default Workspace' : workspaceName;
            return CaptureDestination(
              boardId: board.id,
              boardTitle: title,
              workspaceId: workspace,
            );
          }).toList();

      if (destinations.isEmpty) {
        return const [
          CaptureDestination(
            boardId: 'default-inbox',
            boardTitle: 'Inbox Board',
            workspaceId: 'default',
          ),
        ];
      }
      return destinations;
    });
