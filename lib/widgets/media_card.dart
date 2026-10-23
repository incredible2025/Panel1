import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/design_system.dart';
import '../data/models.dart';
import 'tv_focus_card.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.icon = Icons.movie_outlined,
    this.fit = BoxFit.cover,
    this.title = '',
    this.darken = 0,
    this.alignment = Alignment.center,
  });
  final String url;
  final IconData icon;
  final BoxFit fit;
  final String title;
  final double darken;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final placeholder = CustomPaint(
      painter: _CoverPainter(title.isEmpty ? icon.codePoint.toString() : title),
      child: const SizedBox.expand(),
    );
    final uri = Uri.tryParse(url);
    final valid =
        uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
    final art = valid
        ? Image.network(
            url,
            fit: fit,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => placeholder,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : placeholder,
          )
        : placeholder;
    return Stack(
      fit: StackFit.expand,
      children: [
        art,
        if (darken > 0)
          ColoredBox(color: Colors.black.withValues(alpha: darken.clamp(0, 1))),
      ],
    );
  }
}

/// A title-seeded cover treatment when the provider supplies no artwork.
class _CoverPainter extends CustomPainter {
  const _CoverPainter(this.title);
  final String title;
  @override
  void paint(Canvas canvas, Size size) {
    final seed = title.codeUnits.fold<int>(
      0,
      (a, b) => (a * 31 + b) & 0x7fffffff,
    );
    const colors = [
      Color(0xFF53413B),
      Color(0xFF263E43),
      Color(0xFF343B56),
      Color(0xFF454631),
      Color(0xFF463349),
      Color(0xFF3B4249),
    ];
    final color = colors[seed % colors.length];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xFF101824), color, .3)!,
            const Color(0xFF080D15),
          ],
        ).createShader(rect),
    );
    final center = Offset(size.width * .8, size.height * .22);
    canvas.drawCircle(
      center,
      size.longestSide * .58,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppColors.accent.withValues(alpha: .055),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(center: center, radius: size.longestSide * .58),
            ),
    );
    final initials = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => String.fromCharCode(w.runes.first))
        .join()
        .toUpperCase();
    final text = TextPainter(
      text: TextSpan(
        text: initials,
        style: TextStyle(
          fontFamily: 'Streamline Display',
          fontWeight: FontWeight.w700,
          fontSize: math.min(size.width * .2, size.height * .23),
          color: AppColors.text.withValues(alpha: .2),
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * .8);
    text.paint(
      canvas,
      Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) =>
      oldDelegate.title != title;
}

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onPressed,
    this.progress,
    this.autofocus = false,
  });
  final MediaItem item;
  final VoidCallback onPressed;
  final double? progress;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusCard(
    autofocus: autofocus,
    label: item.name,
    onPressed: onPressed,
    transparent: true,
    borderRadius: 12,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Artwork(
                  url: item.imageUrl,
                  title: item.name,
                  icon: item.kind == MediaKind.series
                      ? Icons.video_library_outlined
                      : Icons.movie_outlined,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x17000000),
                        Colors.transparent,
                        Color(0x99000000),
                      ],
                      stops: [0, .6, 1],
                    ),
                  ),
                ),
                if (item.rating.isNotEmpty)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .75),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            item.rating,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (progress != null)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 11,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0, 1),
                        minHeight: 2,
                        backgroundColor: Colors.white.withValues(alpha: .2),
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 11, 3, 8),
          child: Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              color: AppColors.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.subdued,
                    fontSize: 12,
                    letterSpacing: .15,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}
