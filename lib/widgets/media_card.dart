import 'package:flutter/material.dart';

import '../data/models.dart';
import 'tv_focus_card.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.icon = Icons.movie_outlined,
    this.fit = BoxFit.cover,
  });

  final String url;
  final IconData icon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
      color: const Color(0xFF182638),
      child: Center(
        child: Icon(icon, size: 42, color: const Color(0xFF6E8A9C)),
      ),
    );
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) {
      return placeholder();
    }
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (_, __, ___) => placeholder(),
      loadingBuilder: (_, child, loading) =>
          loading == null ? child : placeholder(),
    );
  }
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
  Widget build(BuildContext context) {
    return TvFocusCard(
      autofocus: autofocus,
      label: item.name,
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Artwork(
                  url: item.imageUrl,
                  icon: item.kind == MediaKind.series
                      ? Icons.video_library_outlined
                      : Icons.movie_outlined,
                ),
                if (item.rating.isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xDD080E1B),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '★ ${item.rating}',
                        style: const TextStyle(
                          color: Color(0xFFFFC677),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (progress != null)
            LinearProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: const Color(0xFF263447),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Color(0xFF91A4B9),
                      fontSize: 12,
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
}
