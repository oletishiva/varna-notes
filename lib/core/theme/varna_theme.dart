import 'package:flutter/material.dart';

import 'varna_colors.dart';

/// Corner radii and sizes from the design spec.
class VarnaMetrics {
  VarnaMetrics._();

  static const double cardRadius = 20;
  static const double sheetRadius = 28;
  static const double buttonRadius = 16;
  static const double pillRadius = 22;

  /// Minimum touch target.
  static const double minTouch = 44;

  /// Height of the primary (ink) button.
  static const double primaryButtonHeight = 56;
}

/// Font family names (the font files are bundled via pubspec `fonts:` in a
/// later step; these strings must match the `family:` entries there).
class VarnaFonts {
  VarnaFonts._();

  static const String display = 'Bricolage Grotesque';
  static const String body = 'Figtree';
  static const String telugu = 'Noto Sans Telugu';
  static const List<String> fallback = <String>[telugu];
}

/// Builds the Material 3 light [ThemeData] for Varna.
class VarnaTheme {
  VarnaTheme._();

  static ThemeData light() {
    const VarnaColors c = VarnaColors.light;

    final ColorScheme scheme = ColorScheme.light(
      primary: c.ink,
      onPrimary: Colors.white,
      secondary: c.link,
      onSecondary: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      error: c.danger,
      onError: Colors.white,
      outline: c.hairline,
      outlineVariant: c.hairline,
    );

    TextStyle display(double size, {double spacing = -0.5}) => TextStyle(
          fontFamily: VarnaFonts.display,
          fontFamilyFallback: VarnaFonts.fallback,
          fontWeight: FontWeight.w700,
          fontSize: size,
          letterSpacing: spacing,
          height: 1.15,
          color: c.ink,
        );

    TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
        TextStyle(
          fontFamily: VarnaFonts.body,
          fontFamilyFallback: VarnaFonts.fallback,
          fontWeight: weight,
          fontSize: size,
          height: 1.4,
          color: c.ink,
        );

    final TextTheme textTheme = TextTheme(
      displayLarge: display(40),
      displayMedium: display(34),
      displaySmall: display(30),
      headlineLarge: display(28),
      headlineMedium: display(24),
      headlineSmall: display(22),
      titleLarge: display(20, spacing: -0.3),
      titleMedium: body(16, weight: FontWeight.w600),
      titleSmall: body(14, weight: FontWeight.w600),
      bodyLarge: body(16),
      bodyMedium: body(14),
      bodySmall: body(12).copyWith(color: c.muted),
      labelLarge: body(14, weight: FontWeight.w600),
      labelMedium: body(12, weight: FontWeight.w600),
      labelSmall: body(11, weight: FontWeight.w600),
    );

    final RoundedRectangleBorder buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VarnaMetrics.buttonRadius),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: VarnaFonts.body,
      fontFamilyFallback: VarnaFonts.fallback,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.ground,
      canvasColor: c.ground,
      textTheme: textTheme,
      extensions: const <ThemeExtension<dynamic>>[VarnaColors.light],
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: display(22),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(VarnaMetrics.sheetRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(88, VarnaMetrics.primaryButtonHeight),
          shape: buttonShape,
          textStyle: body(16, weight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(88, VarnaMetrics.primaryButtonHeight),
          side: BorderSide(color: c.hairline),
          shape: buttonShape,
          textStyle: body(16, weight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.link,
          minimumSize: const Size(VarnaMetrics.minTouch, VarnaMetrics.minTouch),
          textStyle: body(14, weight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(VarnaMetrics.minTouch, VarnaMetrics.minTouch),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: body(14).copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
