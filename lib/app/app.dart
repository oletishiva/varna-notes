import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../core/theme/varna_theme.dart';
import 'router.dart';

/// Light theme (fonts are applied inside [VarnaTheme] itself).
ThemeData buildVarnaTheme() => VarnaTheme.light();

/// The root widget.
class VarnaApp extends ConsumerWidget {
  const VarnaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildVarnaTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
