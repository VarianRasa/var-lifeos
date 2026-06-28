/// Providers for first-launch onboarding state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/runtime_config.dart';
import '../mindmap/application/mindmap_providers.dart';

final onboardingSeenProvider = StateProvider<bool>((ref) => false);

final shouldShowOnboardingProvider = FutureProvider<bool>((ref) async {
  final config = ref.watch(runtimeConfigProvider);
  if (config.demoSeedEnabled) return false;

  final allNodes = await ref.watch(allMindmapNodesProvider.future);
  if (allNodes.isNotEmpty) return false;

  if (ref.watch(onboardingSeenProvider)) return false;

  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getBool('onboarding_seen') ?? false;
  ref.read(onboardingSeenProvider.notifier).state = seen;
  return !seen;
});

Future<void> dismissOnboarding(WidgetRef ref) async {
  ref.read(onboardingSeenProvider.notifier).state = true;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_seen', true);
}
