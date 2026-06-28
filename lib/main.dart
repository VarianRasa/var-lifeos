/// Entry point. Bootstraps any async initialization, then runs the app inside
/// a [ProviderScope]. The real layout (router, theme) lives in [VarApp].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: VarApp()));
}
