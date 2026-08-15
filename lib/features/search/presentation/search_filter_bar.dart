import 'package:flutter/material.dart';

import '../domain/search_document.dart';
import '../domain/search_query.dart';

class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    required this.filters,
    required this.onChanged,
    super.key,
  });

  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      PopupMenuButton<SearchSourceKind?>(
        onSelected: (value) => onChanged(
          filters.copyWith(sourceKinds: value == null ? const {} : {value}),
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(value: null, child: Text('All types')),
          for (final value in SearchSourceKind.values)
            PopupMenuItem(value: value, child: Text(value.name)),
        ],
        child: _FilterChipLabel(
          label: 'Type',
          value: filters.sourceKinds.firstOrNull?.name,
        ),
      ),
      _TextFilterChip(
        label: 'Workspace',
        values: filters.workspaceIds,
        onChanged: (values) =>
            onChanged(filters.copyWith(workspaceIds: values)),
      ),
      _TextFilterChip(
        label: 'Board',
        values: filters.boardIds,
        onChanged: (values) => onChanged(filters.copyWith(boardIds: values)),
      ),
      _TextFilterChip(
        label: 'Creator',
        values: filters.creatorIds,
        onChanged: (values) => onChanged(filters.copyWith(creatorIds: values)),
      ),
      _TextFilterChip(
        label: 'Status',
        values: filters.statuses,
        onChanged: (values) => onChanged(filters.copyWith(statuses: values)),
      ),
      InputChip(
        label: Text(
          filters.dateFrom == null
              ? 'Date'
              : '${_date(filters.dateFrom!)} – ${_date(filters.dateTo!)}',
        ),
        avatar: const Icon(Icons.date_range_outlined, size: 18),
        onPressed: () async {
          final now = DateTime.now();
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime(1970),
            lastDate: DateTime(now.year + 20),
            initialDateRange: filters.dateFrom == null
                ? null
                : DateTimeRange(
                    start: filters.dateFrom!,
                    end: filters.dateTo ?? filters.dateFrom!,
                  ),
          );
          if (range != null) {
            onChanged(
              filters.copyWith(dateFrom: range.start, dateTo: range.end),
            );
          }
        },
        onDeleted: filters.dateFrom == null
            ? null
            : () => onChanged(filters.copyWith(clearDates: true)),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 768) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(spacing: 8, children: controls),
          );
        }
        return Wrap(spacing: 8, runSpacing: 8, children: controls);
      },
    );
  }
}

class _TextFilterChip extends StatelessWidget {
  const _TextFilterChip({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final Set<String> values;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(values.isEmpty ? label : '$label: ${values.first}'),
      avatar: const Icon(Icons.arrow_drop_down, size: 18),
      onPressed: () async {
        final controller = TextEditingController(
          text: values.isEmpty ? '' : values.first,
        );
        final value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Filter by $label'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: '$label ID or name'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Clear'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Apply'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (value != null) {
          final normalized = value.trim();
          onChanged(normalized.isEmpty ? const {} : {normalized});
        }
      },
    );
  }
}

class _FilterChipLabel extends StatelessWidget {
  const _FilterChipLabel({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(value == null ? label : '$label: $value'),
    avatar: const Icon(Icons.arrow_drop_down, size: 18),
  );
}

extension<T> on Set<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
