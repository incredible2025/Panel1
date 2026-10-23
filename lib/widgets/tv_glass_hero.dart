import 'package:flutter/material.dart';

import 'media_card.dart';
import 'tv_glass_theme.dart';

class TvGlassHero extends StatelessWidget {
  const TvGlassHero({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.imageUrl,
    this.metadata = '',
    this.description = '',
    this.action,
    this.height = 129,
    this.cinema = false,
  });
  final String title, eyebrow, imageUrl, metadata, description;
  final double height;
  final bool cinema;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: cinema ? 0 : 440,
          right: 0,
          top: 0,
          bottom: 0,
          child: Artwork(url: imageUrl, title: title),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF142B59),
                const Color(0xFF142B59).withValues(alpha: .9),
                const Color(0xFF142B59).withValues(alpha: .1),
              ],
              stops: [0, cinema ? .34 : .43, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xFF112D51)],
              stops: [.65, 1],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 26,
            vertical: cinema ? 20 : 14,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: cinema ? 410 : 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TvGlass.accent,
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    maxLines: cinema ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: cinema ? 36 : 27,
                      fontWeight: FontWeight.w500,
                      letterSpacing: cinema ? -1.3 : -.9,
                      height: 1.08,
                    ),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TvGlass.muted,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD1DCEF),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (action != null) ...[const SizedBox(height: 10), action!],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
