/// Var — a calendar-centric productivity app.
///
/// Entry point. Real bootstrap (theme, router, database) lands in Phase 1.
/// For now this renders a minimal placeholder so the project compiles and the
/// rebrand can be verified end-to-end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: VarApp(),
    ),
  );
}

class VarApp extends StatelessWidget {
  const VarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Var',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C8EEF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _PlaceholderPage(),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Var',
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Calendar-centric productivity',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Phase 0 complete — building the calendar next.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
