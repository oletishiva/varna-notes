import 'package:flutter/material.dart';

import '../../core/theme/varna_theme.dart';
import '../../core/theme/varna_colors.dart';

/// A few design values that are not part of `VarnaColors` (used on dark
/// surfaces, warnings and handles).
class VarnaExtras {
  VarnaExtras._();

  /// Secondary text on the ink (dark) background.
  static const Color onDarkMuted = Color(0xFFD5D8E4);

  /// Sheet drag handle and dashed outlines.
  static const Color handle = Color(0xFF7A7F94);

  /// "Needs your choice" text and chip colours.
  static const Color warnText = Color(0xFF8A3B12);
  static const Color warnBg = Color(0xFFFFE8D6);

  /// Widest content column on tablets and the web.
  static const double maxContentWidth = 560;
}

/// Display (Bricolage Grotesque) style for titles.
TextStyle displayStyle(
  BuildContext context,
  double size, {
  double letterSpacing = -0.5,
  Color? color,
  double height = 1.1,
}) {
  return TextStyle(
    fontFamily: VarnaFonts.display,
    fontFamilyFallback: VarnaFonts.fallback,
    fontWeight: FontWeight.w700,
    fontSize: size,
    letterSpacing: letterSpacing,
    height: height,
    color: color ?? VarnaColors.of(context).ink,
  );
}

/// Body (Figtree) style.
TextStyle bodyStyle(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double height = 1.4,
}) {
  return TextStyle(
    fontFamily: VarnaFonts.body,
    fontFamilyFallback: VarnaFonts.fallback,
    fontWeight: weight,
    fontSize: size,
    height: height,
    color: color ?? VarnaColors.of(context).ink,
  );
}
