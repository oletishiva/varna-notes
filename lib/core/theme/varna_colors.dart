import 'package:flutter/material.dart';

/// Varna colour tokens as a [ThemeExtension], so a dark variant can be added
/// later without touching widgets. Read them with `VarnaColors.of(context)`.
@immutable
class VarnaColors extends ThemeExtension<VarnaColors> {
  const VarnaColors({
    required this.ground,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.cardColors,
    required this.successBg,
    required this.successText,
    required this.danger,
    required this.link,
  });

  /// The light theme (the only one in v1).
  static const VarnaColors light = VarnaColors(
    ground: Color(0xFFF3F4F8),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF171A2E),
    muted: Color(0xFF4A4F66),
    hairline: Color(0xFFE3E5EC),
    cardColors: <Color>[
      Color(0xFFFFD45C), // sun
      Color(0xFFBFD6FF), // sky
      Color(0xFFBDE8CF), // mint
      Color(0xFFFFC2B0), // coral
      Color(0xFFD9CCFF), // lilac
    ],
    successBg: Color(0xFFDDF3E6),
    successText: Color(0xFF14532D),
    danger: Color(0xFFB3261E),
    link: Color(0xFF2447C9),
  );

  /// Page background.
  final Color ground;

  /// White surfaces (cards, sheets, inputs).
  final Color surface;

  /// Primary text and the primary button background.
  final Color ink;

  /// Secondary text.
  final Color muted;

  /// 1px dividers and outlines.
  final Color hairline;

  /// The five card/notebook colours, index 0..4: sun, sky, mint, coral, lilac.
  final List<Color> cardColors;

  /// Success chip background / text.
  final Color successBg;
  final Color successText;

  final Color danger;

  /// Hyperlinks and text buttons.
  final Color link;

  /// Colour for a card/notebook `colorIndex`. Out-of-range and negative
  /// indexes wrap around.
  Color cardColor(int index) {
    final int n = cardColors.length;
    return cardColors[((index % n) + n) % n];
  }

  /// The theme's [VarnaColors] (falls back to [light] if the extension is
  /// missing, for example in a bare `MaterialApp`).
  static VarnaColors of(BuildContext context) {
    return Theme.of(context).extension<VarnaColors>() ?? light;
  }

  @override
  VarnaColors copyWith({
    Color? ground,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? hairline,
    List<Color>? cardColors,
    Color? successBg,
    Color? successText,
    Color? danger,
    Color? link,
  }) {
    return VarnaColors(
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      hairline: hairline ?? this.hairline,
      cardColors: cardColors ?? this.cardColors,
      successBg: successBg ?? this.successBg,
      successText: successText ?? this.successText,
      danger: danger ?? this.danger,
      link: link ?? this.link,
    );
  }

  @override
  VarnaColors lerp(ThemeExtension<VarnaColors>? other, double t) {
    if (other is! VarnaColors) {
      return this;
    }
    final int n = cardColors.length < other.cardColors.length
        ? cardColors.length
        : other.cardColors.length;
    return VarnaColors(
      ground: Color.lerp(ground, other.ground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      cardColors: <Color>[
        for (int i = 0; i < n; i++)
          Color.lerp(cardColors[i], other.cardColors[i], t)!,
      ],
      successBg: Color.lerp(successBg, other.successBg, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      link: Color.lerp(link, other.link, t)!,
    );
  }
}
