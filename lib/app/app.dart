import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../core/theme/varna_theme.dart';
import 'router.dart';

/// Light theme with the body font applied to the non-display text styles
/// (the display styles already carry Bricolage Grotesque).
ThemeData buildVarnaTheme() {
  final ThemeData base = VarnaTheme.light();
  TextStyle? body(TextStyle? s) => s?.copyWith(
        fontFamily: VarnaFonts.body,
        fontFamilyFallback: VarnaFonts.fallback,
      );
  final TextTheme t = base.textTheme;
  return base.copyWith(
    textTheme: t.copyWith(
      titleMedium: body(t.titleMedium),
      titleSmall: body(t.titleSmall),
      bodyLarge: body(t.bodyLarge),
      bodyMedium: body(t.bodyMedium),
      bodySmall: body(t.bodySmall),
      labelLarge: body(t.labelLarge),
      labelMedium: body(t.labelMedium),
      labelSmall: body(t.labelSmall),
    ),
  );
}

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
