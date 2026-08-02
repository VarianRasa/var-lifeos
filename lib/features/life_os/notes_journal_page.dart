/// Dedicated Life OS hub for Notes, Knowledge Base, and Daily Journals.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/node_visuals.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/error_message.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';

class NotesJournalPage extends ConsumerStatefulWidget {
  const NotesJournalPage({super.key});

  @override
  ConsumerState<NotesJournalPage> createState() => _NotesJournalPageState();
}

class _NotesJournalPageState extends ConsumerState<NotesJournalPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodesAsync = ref.watch(allMindmapNodesProvider);

    return Scaffold(
      body: nodesAsync.when(
        data: (nodes) {
          final queryNorm = _query.trim().toLowerCase();
          bool matches(MindmapNode n) {
            if (queryNorm.isEmpty) return true;
            return n.title.toLowerCase().contains(queryNorm) ||
                n.body.toLowerCase().contains(queryNorm) ||
                n.tags.any((t) => t.toLowerCase().contains(queryNorm));
          }

          final notes = nodes
              .where((n) => n.type == NodeType.note && !n.isArchived)
              .where(matches)
              .toList();
          final journals = nodes
              .where((n) => n.type == NodeType.journal && !n.isArchived)
              .where(matches)
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notes & Journal Hub',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Knowledge base, atomic notes, and reflection archive.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: SearchField(
                        controller: _searchController,
                        hintText: 'Search notes/journals...',
                        onChanged: (val) => setState(() => _query = val),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.notes_outlined, size: 18),
                    text: 'Notes (${notes.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.book_outlined, size: 18),
                    text: 'Journal (${journals.length})',
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _NotesList(notes: notes),
                    _JournalsList(journals: journals),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => ErrorMessage(
          message: 'Failed to load notes & journal',
          onRetry: () => ref.invalidate(allMindmapNodesProvider),
        ),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({required this.notes});
  final List<MindmapNode> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notes_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('No notes found', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Add Note nodes on any day canvas to view knowledge items here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      NodeVisuals.icon(note.type),
                      color: NodeVisuals.color(context, note.type),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      dayKey(note.day),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      tooltip: 'Open in Calendar',
                      onPressed: () =>
                          goToDay(context, note.day, highlightNodeId: note.id),
                    ),
                  ],
                ),
                if (note.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    note.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final tag in note.tags)
                        Chip(
                          label: Text('#$tag'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JournalsList extends StatelessWidget {
  const _JournalsList({required this.journals});
  final List<MindmapNode> journals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (journals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.book_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('No journal entries found', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Add Journal or reflection nodes to record your daily journey.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: journals.length,
      itemBuilder: (context, index) {
        final journal = journals[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      NodeVisuals.icon(journal.type),
                      color: NodeVisuals.color(context, journal.type),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        journal.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(dayKey(journal.day)),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      tooltip: 'Open in Calendar',
                      onPressed: () => goToDay(
                        context,
                        journal.day,
                        highlightNodeId: journal.id,
                      ),
                    ),
                  ],
                ),
                if (journal.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    journal.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
