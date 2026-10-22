import 'package:flutter/material.dart';

/// Shared visual tokens for the mobile and ten-foot interfaces.
abstract final class AppColors {
  static const canvas = Color(0xFF060E1B);
  static const surface = Color(0xFF101D30);
  static const surfaceRaised = Color(0xFF172840);
  static const border = Color(0xFF25384F);
  static const accent = Color(0xFF64D9F5);
  static const accentStrong = Color(0xFF1B99CD);
  static const text = Color(0xFFF4F8FF);
  static const muted = Color(0xFFABB0B8);
  static const subdued = Color(0xFF6B737F);
  static const danger = Color(0xFFF0A09B);
  static const live = Color(0xFFE78277);
}

abstract final class StreamlineTheme {
  static ThemeData get dark => _create(false);
  static ThemeData get cinema => _create(true);
  static ThemeData _create(bool cinema) {
    final accent = cinema ? Color(0xFFF3EEE3) : AppColors.accent;
    final canvas = cinema ? Color(0xFF090A0C) : AppColors.canvas;
    final surface = cinema ? Color(0xFF191A1D) : AppColors.surface;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Streamline Sans',
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.dark(
        primary: accent,
        onPrimary: canvas,
        secondary: accent,
        onSecondary: canvas,
        surface: surface,
        onSurface: AppColors.text,
        error: AppColors.danger,
        outline: AppColors.border,
      ),
    );
    final text = base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );
    TextStyle display(double size, {double height = 1.05}) => TextStyle(
      fontFamily: 'Streamline Display',
      fontSize: size,
      height: height,
      letterSpacing: -.7,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    );
    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: display(76),
        displayMedium: display(60),
        displaySmall: display(48),
        headlineLarge: display(42),
        headlineMedium: display(34),
        headlineSmall: display(28),
        titleLarge: display(24, height: 1.15),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.6),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
        bodySmall: text.bodySmall?.copyWith(
          color: AppColors.muted,
          height: 1.5,
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: .1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: AppColors.subdued, fontSize: 14),
        labelStyle: TextStyle(color: AppColors.muted, fontSize: 14),
        prefixIconColor: AppColors.subdued,
        suffixIconColor: AppColors.muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(48, 52)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppColors.border;
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return AppColors.text;
            }
            return accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.muted
                : canvas,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Streamline Sans',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: BorderSide(color: AppColors.border),
          minimumSize: Size(48, 50),
          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.text),
          overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: .15)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: .12),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? accent
                : AppColors.subdued,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Streamline Sans',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: .3,
            color: states.contains(WidgetState.selected)
                ? AppColors.text
                : AppColors.subdued,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white.withValues(alpha: .15),
        thumbColor: AppColors.text,
        trackHeight: 3,
        overlayColor: accent.withValues(alpha: .12),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: AppColors.border,
      ),
      dividerColor: AppColors.border,
      focusColor: accent.withValues(alpha: .16),
      hoverColor: Colors.white.withValues(alpha: .04),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

class StreamlineMark extends StatelessWidget {
  const StreamlineMark({super.key, this.size = 32, this.wordmark = false});
  final double size;
  final bool wordmark;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _MarkPainter()),
      ),
      if (wordmark) ...[
        SizedBox(width: size * .34),
        Text(
          'STREAMLINE',
          style: TextStyle(
            fontFamily: 'Streamline Sans',
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: size * .39,
            letterSpacing: size * .062,
          ),
        ),
      ],
    ],
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final path = Path()
      ..moveTo(s * .13, s * .04)
      ..lineTo(s * .87, s * .5)
      ..lineTo(s * .13, s * .96)
      ..lineTo(s * .13, s * .71)
      ..lineTo(s * .48, s * .5)
      ..lineTo(s * .13, s * .29)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.text, AppColors.accent, AppColors.accentStrong],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: color ?? AppColors.accent,
      fontSize: 10,
      letterSpacing: 2.2,
      fontWeight: FontWeight.w700,
    ),
  );
}

class MetaPill extends StatelessWidget {
  const MetaPill(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .22),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: AppColors.accent),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}
