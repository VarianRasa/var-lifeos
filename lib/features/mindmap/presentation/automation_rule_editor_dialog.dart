/// Editor dialog for creating and updating Smart Routine & Automation Rules.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/mindmap_mutation_controller.dart';
import '../domain/automation_rule.dart';
import '../domain/recurring_routine.dart';

Future<void> showAutomationRuleEditorDialog(
  BuildContext context, {
  AutomationRuleRecord? existingRule,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        AutomationRuleEditorDialog(existingRule: existingRule),
  );
}

class AutomationRuleEditorDialog extends ConsumerStatefulWidget {
  const AutomationRuleEditorDialog({super.key, this.existingRule});

  final AutomationRuleRecord? existingRule;

  @override
  ConsumerState<AutomationRuleEditorDialog> createState() =>
      _AutomationRuleEditorDialogState();
}

class _AutomationRuleEditorDialogState
    extends ConsumerState<AutomationRuleEditorDialog> {
  final _labelController = TextEditingController();
  final _triggerTagController = TextEditingController();
  final _actionTagController = TextEditingController();
  final _followupTitleController = TextEditingController();

  AutomationTriggerType _triggerType = AutomationTriggerType.scheduled;
  AutomationActionType _actionType = AutomationActionType.createFromTemplate;
  String _selectedTemplateId = 'daily-plan';
  bool _enabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingRule != null) {
      final rule = widget.existingRule!;
      _labelController.text = rule.label;
      _triggerType = rule.triggerType;
      _triggerTagController.text = rule.triggerTag ?? '';
      _actionType = rule.actionType;
      _actionTagController.text = rule.actionTag ?? '';
      _followupTitleController.text = rule.followupTitle ?? '';
      _selectedTemplateId = rule.templateId;
      _enabled = rule.enabled;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _triggerTagController.dispose();
    _actionTagController.dispose();
    _followupTitleController.dispose();
    super.dispose();
  }

  Future<void> _saveRule() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) return;

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final id =
          widget.existingRule?.id ??
          'custom-rule-${now.microsecondsSinceEpoch}';

      final node = createAutomationRuleNode(
        id: id,
        label: label,
        templateId: _selectedTemplateId,
        rule: RecurringRule.daily(),
        day: now,
        enabled: _enabled,
        now: now,
      );

      final updatedData = Map<String, Object?>.from(node.data);
      final ruleMap = Map<String, Object?>.from(
        (updatedData[automationRuleDataKey] as Map?)?.cast<String, Object?>() ??
            {},
      );

      ruleMap['triggerType'] = _triggerType.name;
      ruleMap['triggerTag'] = _triggerTagController.text.trim();
      ruleMap['actionType'] = _actionType.name;
      ruleMap['actionTag'] = _actionTagController.text.trim();
      ruleMap['followupTitle'] = _followupTitleController.text.trim();

      updatedData[automationRuleDataKey] = ruleMap;
      final finalNode = node.copyWith(data: updatedData);

      await ref.read(mindmapMutationControllerProvider).saveNode(finalNode);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Aturan otomatisasi "$label" disimpan')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.precision_manufacturing, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            widget.existingRule == null
                ? 'Buat Aturan Otomatisasi'
                : 'Edit Aturan Otomatisasi',
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Nama Aturan / Deskripsi',
                  hintText: 'Contoh: Otomatis buat task follow-up',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AutomationTriggerType>(
                isExpanded: true,
                initialValue: _triggerType,
                decoration: const InputDecoration(
                  labelText: 'Pemicu (Trigger)',
                  isDense: true,
                ),
                items: AutomationTriggerType.values.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(t.label, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _triggerType = val);
                },
              ),
              if (_triggerType == AutomationTriggerType.nodeCreatedWithTag) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _triggerTagController,
                  decoration: const InputDecoration(
                    labelText: 'Trigger Tag (tanpa #)',
                    hintText: 'misal: urgent',
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<AutomationActionType>(
                isExpanded: true,
                initialValue: _actionType,
                decoration: const InputDecoration(
                  labelText: 'Aksi (Action)',
                  isDense: true,
                ),
                items: AutomationActionType.values.map((a) {
                  return DropdownMenuItem(
                    value: a,
                    child: Text(a.label, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _actionType = val);
                },
              ),
              if (_actionType == AutomationActionType.autoTag) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _actionTagController,
                  decoration: const InputDecoration(
                    labelText: 'Tag yang Ditambahkan (tanpa #)',
                    hintText: 'misal: reviewed',
                    isDense: true,
                  ),
                ),
              ],
              if (_actionType == AutomationActionType.createFollowupTask) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _followupTitleController,
                  decoration: const InputDecoration(
                    labelText: 'Judul Task Lanjutan',
                    hintText: 'misal: Review hasil meeting',
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text(
                  'Aktifkan Aturan ini',
                  style: TextStyle(fontSize: 14),
                ),
                value: _enabled,
                onChanged: (val) => setState(() => _enabled = val),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _saveRule,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan Aturan'),
        ),
      ],
    );
  }
}
