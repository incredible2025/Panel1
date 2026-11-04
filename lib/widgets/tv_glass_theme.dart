import 'package:flutter/material.dart';
import '../core/app_palette.dart';
export '../core/app_palette.dart';

/// The approved 1024 × 576 Glass concept, expressed in television design units.
abstract final class TvGlass {
  static const canvas = Color(0xFF071B38);
  static const ink = Color(0xFFF5F8FF);
  static const muted = Color(0xFFB6C7E1);
  static const accent = Color(0xFF69D9FF);
  static const panel = Color(0xFF122F56);
  static const rowHeight = 35.0;

  static ThemeData theme(ThemeData base) {
    final palette = AppPalette.fromTheme(base);
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Glass Sans'),
      scaffoldBackgroundColor: palette.canvas,
      colorScheme: base.colorScheme.copyWith(
        primary: palette.accent,
        onPrimary: palette.canvas,
        surface: palette.surface,
        onSurface: ink,
      ),
    );
  }
}

class TvGlassScope extends InheritedWidget {
  const TvGlassScope({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvGlassScope>() != null;
  @override
  bool updateShouldNotify(TvGlassScope oldWidget) => false;
}

class TvGlassBackdrop extends StatelessWidget {
  const TvGlassBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppPalette.of(context).canvas,
    child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.9, -.6),
              radius: 1.3,
              colors: [
                AppPalette.of(context).glow,
                AppPalette.of(context).glow.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topLeft,
              radius: 1.15,
              colors: [
                AppPalette.of(context).gradientStart,
                AppPalette.of(context).gradientStart.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        child,
      ],
    ),
  );
}
