import 'package:flutter/material.dart';

/// The approved 1024 × 576 Glass concept, expressed in television design units.
abstract final class TvGlass {
  static const canvas = Color(0xFF071B38);
  static const ink = Color(0xFFF5F8FF);
  static const muted = Color(0xFFB6C7E1);
  static const accent = Color(0xFF69D9FF);
  static const panel = Color(0xFF122F56);
  static const rowHeight = 35.0;

  static ThemeData theme(ThemeData base) => base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Glass Sans'),
    scaffoldBackgroundColor: canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      surface: panel,
      onSurface: ink,
    ),
  );

  static const background = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF253A7B), Color(0xFF123951), canvas],
      stops: [0, .5, 1],
    ),
  );
}

class TvGlassScope extends InheritedWidget {
  const TvGlassScope({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvGlassScope>() != null;
  @override
  bool updateShouldNotify(TvGlassScope oldWidget) => false;
}
