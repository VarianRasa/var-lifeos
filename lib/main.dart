/// Entry point. Bootstraps any async initialization, then runs the app inside
/// a [ProviderScope]. The real layout (router, theme) lives in [VarApp].
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_shouldInitializeFirebase) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }
  runApp(const ProviderScope(child: VarApp()));
}

bool get _shouldInitializeFirebase {
  if (kIsWeb) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux => false,
  };
}
