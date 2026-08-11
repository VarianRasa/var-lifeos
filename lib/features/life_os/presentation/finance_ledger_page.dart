/// Financial Ledger roll-up dashboard for NodeType.expense and financial metrics.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/error_message.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/mindmap_node.dart';

class FinanceLedgerPage extends ConsumerWidget {
  const FinanceLedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nodesAsync = ref.watch(allMindmapNodesProvider);

    return Scaffold(
      body: nodesAsync.when(
        data: (nodes) {
          final expenseNodes = nodes
              .where((n) => !n.isArchived && n.type == NodeType.expense)
              .toList();

          double parseAmount(MindmapNode n) {
            final valFromData = n.data['amount'];
            if (valFromData is num) return valFromData.toDouble();
            final matches = RegExp(r'(\d+[\d,.]*)').firstMatch(n.title);
            if (matches != null) {
              final raw = matches.group(1)?.replaceAll(',', '');
              return double.tryParse(raw ?? '0') ?? 0.0;
            }
            return 0.0;
          }

          final totalExpense = expenseNodes.fold(
            0.0,
            (sum, n) => sum + parseAmount(n),
          );

          final monthlyBuckets = <String, double>{};
          for (final n in expenseNodes) {
            final monthKey =
                '${n.day.year}-${n.day.month.toString().padLeft(2, '0')}';
            monthlyBuckets[monthKey] =
                (monthlyBuckets[monthKey] ?? 0.0) + parseAmount(n);
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Financial Ledger',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Roll-up expense summaries from day canvas expense nodes.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Tracked Expenses',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$${totalExpense.toStringAsFixed(2)}',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                        Chip(
                          avatar: const Icon(Icons.receipt_long, size: 16),
                          label: Text('${expenseNodes.length} Entries'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: expenseNodes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.payments_outlined,
                              size: 48,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No expense nodes recorded',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add Expense nodes on day canvases to track budgets.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: expenseNodes.length,
                        itemBuilder: (context, index) {
                          final node = expenseNodes[index];
                          final amount = parseAmount(node);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.redAccent,
                              ),
                              title: Text(node.title),
                              subtitle: Text(
                                '${dayKey(node.day)} ${node.project.isNotEmpty ? '• ${node.project}' : ''}',
                              ),
                              trailing: Text(
                                '-\$${amount.toStringAsFixed(2)}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent,
                                ),
                              ),
                              onTap: () => goToDay(
                                context,
                                node.day,
                                highlightNodeId: node.id,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => ErrorMessage(
          message: 'Failed to load financial ledger',
          onRetry: () => ref.invalidate(allMindmapNodesProvider),
        ),
      ),
    );
  }
}
