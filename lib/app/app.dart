import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../core/providers.dart';
import '../core/theme/varna_theme.dart';
import '../shared/app_state.dart';
import 'router.dart';

/// Light theme (fonts are applied inside [VarnaTheme] itself).
ThemeData buildVarnaTheme() => VarnaTheme.light();

/// The root widget.
///
/// It also watches the app lifecycle: unlocked notebooks lock again when the
/// app goes to the background, and coming back to the foreground starts a
/// silent sync (at most once a minute, see `SyncController.onAppResumed`).
class VarnaApp extends ConsumerStatefulWidget {
  const VarnaApp({super.key});

  @override
  ConsumerState<VarnaApp> createState() => _VarnaAppState();
}

class _VarnaAppState extends ConsumerState<VarnaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (ref.read(unlockedNotebooksProvider).isNotEmpty) {
        ref.read(unlockedNotebooksProvider.notifier).state = <String>{};
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(syncControllerProvider)
            .onAppResumed()
            .then<void>((Object? _) {}, onError: (Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildVarnaTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
