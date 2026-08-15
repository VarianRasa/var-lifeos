/// Banner widget for automated weekly/monthly periodic review prompt triggers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/utils/date_utils.dart';
import '../../insights/application/review_insights.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'periodic_review_wizard_dialog.dart';

enum PeriodicReviewTemplate {
  weeklyReflection(
    'Refleksi Mingguan',
    'Evaluasi pencapaian, rasa syukur, dan pelajaran minggu ini.',
  ),
  monthlyReview(
    'Review Bulanan',
    'Audit strategis target bulanan dan penyelarasan tujuan jangka panjang.',
  ),
  productiveRetrospective(
    'Retrospektif Produktivitas',
    'Analisis hambatan, laju kebiasaan, dan efisiensi waktu.',
  );

  const PeriodicReviewTemplate(this.label, this.description);

  final String label;
  final String description;
}

class PeriodicReviewTriggerBanner extends ConsumerStatefulWidget {
  const PeriodicReviewTriggerBanner({
    required this.today,
    required this.nodes,
    super.key,
  });

  final DateTime today;
  final Iterable<MindmapNode> nodes;

  @override
  ConsumerState<PeriodicReviewTriggerBanner> createState() =>
      _PeriodicReviewTriggerBannerState();
}

class _PeriodicReviewTriggerBannerState
    extends ConsumerState<PeriodicReviewTriggerBanner> {
  PeriodicReviewTemplate _selectedTemplate =
      PeriodicReviewTemplate.weeklyReflection;
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final today = widget.today.dateOnly;
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    final reviewSummary = buildReviewInsightSummary(
      start: startOfWeek,
      end: endOfWeek,
      today: today,
      nodes: widget.nodes,
    );

    final isWeeklyDue =
        (today.weekday == DateTime.sunday ||
            today.weekday == DateTime.monday) &&
        !reviewSummary.hasReviewThisWeek;
    final isMonthlyDue = (today.day >= 28 || today.day <= 2);

    if (!isWeeklyDue && !isMonthlyDue) {
      return const SizedBox.shrink();
    }

    final isMonthly = isMonthlyDue && !isWeeklyDue;
    final title = isMonthly
        ? 'Waktunya Review Bulanan!'
        : 'Waktunya Refleksi Mingguan!';

    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: semantic.card,
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _dismissed = true),
                tooltip: 'Tutup Banner',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Luangkan 3 menit untuk merefleksikan progres Anda agar tetap terarah.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<PeriodicReviewTemplate>(
                  initialValue: _selectedTemplate,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: PeriodicReviewTemplate.values.map((tmpl) {
                    return DropdownMenuItem(
                      value: tmpl,
                      child: Text(
                        tmpl.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedTemplate = val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Mulai Review'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: () {
                  showPeriodicReviewWizardDialog(
                    context,
                    isMonthly:
                        isMonthly ||
                        _selectedTemplate ==
                            PeriodicReviewTemplate.monthlyReview,
                    today: today,
                    start: startOfWeek,
                    end: endOfWeek,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
