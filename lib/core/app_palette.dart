import 'package:flutter/material.dart';
import '../data/appearance.dart';
export '../data/appearance.dart';

/// Theme-dependent colours for custom surfaces as well as Material controls.
/// Artwork, channel logos and video are never recoloured.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.accent,
    required this.accentStrong,
    required this.glow,
    required this.gradientStart,
    required this.gradientMiddle,
  });

  final Color canvas, surface, surfaceRaised, border, accent, accentStrong;
  final Color glow, gradientStart, gradientMiddle;

  static AppPalette of(BuildContext context) => fromTheme(Theme.of(context));
  static AppPalette fromTheme(ThemeData theme) =>
      theme.extension<AppPalette>() ?? forAppearance(AppAppearance.midnight);

  static AppPalette forAppearance(AppAppearance appearance) =>
      switch (appearance) {
        AppAppearance.midnight => const AppPalette(
          canvas: Color(0xFF071B38),
          surface: Color(0xFF122F56),
          surfaceRaised: Color(0xFF183A60),
          border: Color(0xFF315176),
          accent: Color(0xFF69D9FF),
          accentStrong: Color(0xFF1B99CD),
          glow: Color(0xFF075568),
          gradientStart: Color(0xFF253A7B),
          gradientMiddle: Color(0xFF123951),
        ),
        AppAppearance.cinema => const AppPalette(
          canvas: Color(0xFF0B1019),
          surface: Color(0xFF171F2C),
          surfaceRaised: Color(0xFF232E3D),
          border: Color(0xFF455369),
          accent: Color(0xFFCFEDFF),
          accentStrong: Color(0xFF7EB4D4),
          glow: Color(0xFF263D4C),
          gradientStart: Color(0xFF232D3D),
          gradientMiddle: Color(0xFF141D2B),
        ),
        AppAppearance.cyberpunk => const AppPalette(
          canvas: Color(0xFF10091F),
          surface: Color(0xFF241337),
          surfaceRaised: Color(0xFF341D4C),
          border: Color(0xFF70517F),
          accent: Color(0xFF68F5FF),
          accentStrong: Color(0xFF18B9CE),
          glow: Color(0xFF762054),
          gradientStart: Color(0xFF49145E),
          gradientMiddle: Color(0xFF20133F),
        ),
        AppAppearance.aurora => const AppPalette(
          canvas: Color(0xFF11132B),
          surface: Color(0xFF242547),
          surfaceRaised: Color(0xFF343357),
          border: Color(0xFF626080),
          accent: Color(0xFFA4F5DC),
          accentStrong: Color(0xFF50BFA7),
          glow: Color(0xFF1B554F),
          gradientStart: Color(0xFF493B78),
          gradientMiddle: Color(0xFF252346),
        ),
        AppAppearance.emerald => const AppPalette(
          canvas: Color(0xFF071D1A),
          surface: Color(0xFF12352E),
          surfaceRaised: Color(0xFF21473C),
          border: Color(0xFF446B5C),
          accent: Color(0xFF8DE9BA),
          accentStrong: Color(0xFF3BB77B),
          glow: Color(0xFF285438),
          gradientStart: Color(0xFF1D4A43),
          gradientMiddle: Color(0xFF12352E),
        ),
        AppAppearance.sunset => const AppPalette(
          canvas: Color(0xFF24101F),
          surface: Color(0xFF3B2137),
          surfaceRaised: Color(0xFF50304A),
          border: Color(0xFF795772),
          accent: Color(0xFFFFC7A3),
          accentStrong: Color(0xFFDA8D66),
          glow: Color(0xFF713642),
          gradientStart: Color(0xFF63314D),
          gradientMiddle: Color(0xFF38203D),
        ),
      };

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? accent,
    Color? accentStrong,
    Color? glow,
    Color? gradientStart,
    Color? gradientMiddle,
  }) => AppPalette(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    border: border ?? this.border,
    accent: accent ?? this.accent,
    accentStrong: accentStrong ?? this.accentStrong,
    glow: glow ?? this.glow,
    gradientStart: gradientStart ?? this.gradientStart,
    gradientMiddle: gradientMiddle ?? this.gradientMiddle,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) => other == null
      ? this
      : AppPalette(
          canvas: Color.lerp(canvas, other.canvas, t)!,
          surface: Color.lerp(surface, other.surface, t)!,
          surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
          border: Color.lerp(border, other.border, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
          glow: Color.lerp(glow, other.glow, t)!,
          gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
          gradientMiddle: Color.lerp(gradientMiddle, other.gradientMiddle, t)!,
        );
}
