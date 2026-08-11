/// Main Life OS Hub integrating PARA, Goals, Habits, Notes, Finance, and Weekly Review.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../goals_habits_page.dart';
import '../notes_journal_page.dart';
import 'finance_ledger_page.dart';
import 'para_overview_page.dart';
import 'weekly_review_dialog.dart';

class LifeOsHubPage extends ConsumerStatefulWidget {
  const LifeOsHubPage({super.key});

  @override
  ConsumerState<LifeOsHubPage> createState() => _LifeOsHubPageState();
}

class _LifeOsHubPageState extends ConsumerState<LifeOsHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Life OS Hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rate_review_outlined),
            tooltip: 'Weekly Review Wizard',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => const WeeklyReviewDialog(),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.folder_special_outlined), text: 'PARA'),
            Tab(
              icon: Icon(Icons.track_changes_outlined),
              text: 'Goals & Habits',
            ),
            Tab(
              icon: Icon(Icons.auto_stories_outlined),
              text: 'Notes & Journal',
            ),
            Tab(
              icon: Icon(Icons.account_balance_wallet_outlined),
              text: 'Finance',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ParaOverviewPage(),
          GoalsHabitsPage(),
          NotesJournalPage(),
          FinanceLedgerPage(),
        ],
      ),
    );
  }
}
