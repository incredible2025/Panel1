import 'package:flutter/material.dart';

import 'app_brand.dart';

/// Shared visual tokens for the mobile and ten-foot interfaces.
abstract final class AppColors {
  static const canvas = Color(0xFF071B38);
  static const surface = Color(0xFF122F56);
  static const surfaceRaised = Color(0xFF183A60);
  static const border = Color(0xFF315176);
  static const accent = Color(0xFF69D9FF);
  static const accentStrong = Color(0xFF1B99CD);
  static const text = Color(0xFFF5F8FF);
  static const muted = Color(0xFFB6C7E1);
  static const subdued = Color(0xFF8EA6C7);
  static const danger = Color(0xFFF0A09B);
  static const live = Color(0xFFE78277);
}

abstract final class StreamlineTheme {
  static ThemeData get dark => _create(false);
  static ThemeData get cinema => _create(true);
  static ThemeData _create(bool cinema) {
    final accent = cinema ? Color(0xFFCFEDFF) : AppColors.accent;
    final canvas = cinema ? Color(0xFF0B1422) : AppColors.canvas;
    final surface = cinema ? Color(0xFF151E2E) : AppColors.surface;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Glass Sans',
      scaffoldBackgroundColor: Colors.transparent,
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
      fontFamily: 'Glass Sans',
      fontSize: size,
      height: height,
      letterSpacing: -.7,
      fontWeight: FontWeight.w500,
      color: AppColors.text,
    );
    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: display(56),
        displayMedium: display(48),
        displaySmall: display(40),
        headlineLarge: display(32),
        headlineMedium: display(28),
        headlineSmall: display(24),
        titleLarge: display(22, height: 1.15),
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
            TextStyle(fontFamily: 'Glass Sans', fontWeight: FontWeight.w700),
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
            fontFamily: 'Glass Sans',
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
          borderRadius: BorderRadius.circular(12),
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

/// Shared branded background for every route, including startup and failures.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.cinema = false});
  final Widget child;
  final bool cinema;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: cinema
            ? const [Color(0xFF151E2E), Color(0xFF0B1422), Color(0xFF050A12)]
            : const [Color(0xFF253A7B), Color(0xFF123951), AppColors.canvas],
        stops: const [0, .5, 1],
      ),
    ),
    child: child,
  );
}

// Keep the internal widget name stable while the public brand changes.
class StreamlineMark extends StatelessWidget {
  const StreamlineMark({super.key, this.size = 32, this.wordmark = false});
  final double size;
  final bool wordmark;

  @override
  Widget build(BuildContext context) => Semantics(
    label: appBrandName,
    image: true,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          appBrandMark,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        ),
        if (wordmark) ...[
          SizedBox(width: size * .3),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ULTRAVPN',
                style: TextStyle(
                  fontFamily: 'Glass Sans',
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: size * .49,
                  letterSpacing: size * .025,
                ),
              ),
              Text(
                'PLAYER',
                style: TextStyle(
                  fontFamily: 'Glass Sans',
                  color: const Color(0xFFA6DAEF),
                  fontWeight: FontWeight.w700,
                  fontSize: size * .28,
                  letterSpacing: size * .13,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// Shared with the Android TV launcher banner export, so launcher and UI agree.
class UltraVpnBanner extends StatelessWidget {
  const UltraVpnBanner({super.key});
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF253A7B), Color(0xFF071B38), Color(0xFF123951)],
      ),
    ),
    child: Center(child: StreamlineMark(size: 76, wordmark: true)),
  );
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
