import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../mindmap/domain/workspace_context.dart';

final workspaceSortProvider =
    StateNotifierProvider<WorkspaceSortNotifier, WorkspaceSortState>((ref) {
      return WorkspaceSortNotifier();
    });

class WorkspaceSortState {
  final List<String> projectsOrder;
  final List<String> areasOrder;

  const WorkspaceSortState({
    this.projectsOrder = const [],
    this.areasOrder = const [],
  });

  WorkspaceSortState copyWith({
    List<String>? projectsOrder,
    List<String>? areasOrder,
  }) {
    return WorkspaceSortState(
      projectsOrder: projectsOrder ?? this.projectsOrder,
      areasOrder: areasOrder ?? this.areasOrder,
    );
  }
}

class WorkspaceSortNotifier extends StateNotifier<WorkspaceSortState> {
  WorkspaceSortNotifier() : super(const WorkspaceSortState()) {
    _loadOrders();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _projectsKey = 'workspaces_project_order';
  static const _areasKey = 'workspaces_area_order';

  Future<void> _loadOrders() async {
    final projects = await _prefs.getStringList(_projectsKey);
    final areas = await _prefs.getStringList(_areasKey);
    state = WorkspaceSortState(
      projectsOrder: projects ?? [],
      areasOrder: areas ?? [],
    );
  }

  Future<void> updateProjectsOrder(List<String> newOrder) async {
    await _prefs.setStringList(_projectsKey, newOrder);
    state = state.copyWith(projectsOrder: newOrder);
  }

  Future<void> updateAreasOrder(List<String> newOrder) async {
    await _prefs.setStringList(_areasKey, newOrder);
    state = state.copyWith(areasOrder: newOrder);
  }
}

List<WorkspaceContext> sortWorkspaces(
  List<WorkspaceContext> original,
  List<String> order,
) {
  if (order.isEmpty) return original;
  final Map<String, int> orderMap = {
    for (int i = 0; i < order.length; i++) order[i]: i,
  };
  final sorted = List<WorkspaceContext>.from(original);
  sorted.sort((a, b) {
    final indexA = orderMap[a.name] ?? 9999;
    final indexB = orderMap[b.name] ?? 9999;
    if (indexA != indexB) {
      return indexA.compareTo(indexB);
    }
    return a.name.compareTo(b.name);
  });
  return sorted;
}
