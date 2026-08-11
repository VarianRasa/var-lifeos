/// First-launch onboarding overlay for new users.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';
import 'onboarding_providers.dart';

class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({super.key});

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  final _focusScopeNode = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowAsync = ref.watch(shouldShowOnboardingProvider);
    return shouldShowAsync.when(
      data: (shouldShow) =>
          shouldShow ? _buildOverlay(context, ref) : const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }

  Widget _buildOverlay(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return BlockSemantics(
      child: Material(
        color: theme.colorScheme.scrim.withValues(alpha: 0.54),
        child: Semantics(
          container: true,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: 'Onboarding',
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: FocusScope(
              node: _focusScopeNode,
              autofocus: true,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {},
                },
                child: Center(
                  child: Dialog(
                    insetPadding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final padding = constraints.maxWidth < 360
                              ? 24.0
                              : 32.0;
                          return SingleChildScrollView(
                            padding: EdgeInsets.all(padding),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AppInfo.name,
                                  style: theme.textTheme.headlineLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppInfo.tagline,
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppInfo.description,
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    autofocus: true,
                                    onPressed: () => _startFresh(context, ref),
                                    icon: const Icon(Icons.edit_note_outlined),
                                    label: const Text('Create your first node'),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () => _dismiss(context, ref),
                                  child: const Text('Start fresh'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startFresh(BuildContext context, WidgetRef ref) async {
    await dismissOnboarding(ref);
    if (!context.mounted) return;
    final today = DateTime.now().dateOnly;
    context.go('/calendar/${dayKey(today)}');
  }

  void _dismiss(BuildContext context, WidgetRef ref) async {
    await dismissOnboarding(ref);
    if (context.mounted) {
      ref.invalidate(shouldShowOnboardingProvider);
    }
  }
}
