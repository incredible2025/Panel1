import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/models.dart';
import '../widgets/media_card.dart';
import '../widgets/status_view.dart';
import 'player_screen.dart' show PlayerScreen;

class MovieDetailScreen extends ConsumerStatefulWidget {
  const MovieDetailScreen({super.key, required this.item});

  final MediaItem item;

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordOpened());
  }

  Future<void> _recordOpened() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref
          .read(storeProvider)
          .recordOpened(session.accountId, widget.item);
      if (mounted) ref.invalidate(historyProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update your recently watched films.'),
          ),
        );
      }
    }
  }

  Future<void> _play() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final history = await ref.read(storeProvider).history(session.accountId);
      WatchEntry? saved;
      for (final entry in history) {
        if (entry.item.id == widget.item.id &&
            entry.item.kind == MediaKind.movie &&
            entry.canResume) {
          saved = entry;
          break;
        }
      }
      if (!mounted) return;
      Duration start = Duration.zero;
      if (saved != null) {
        final progress = saved;
        final answer = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pick up where you left off?'),
            content: Text(
              'Resume ${widget.item.name} from ${formatPlaybackTime(progress.positionMs)} of ${formatPlaybackTime(progress.durationMs)}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Start from beginning'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Resume from ${formatPlaybackTime(progress.positionMs)}',
                ),
              ),
            ],
          ),
        );
        if (answer == null || !mounted) return;
        if (answer) start = Duration(milliseconds: progress.positionMs);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(item: widget.item, startPosition: start),
        ),
      );
      if (mounted) ref.invalidate(historyProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this movie. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(movieDetailProvider(widget.item));
    final history = ref.watch(historyProvider).asData?.value;
    WatchEntry? saved;
    for (final entry in history ?? <WatchEntry>[]) {
      if (entry.item.id == widget.item.id &&
          entry.item.kind == MediaKind.movie &&
          entry.canResume) {
        saved = entry;
        break;
      }
    }
    final isTv = ref.watch(isTvProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movie details'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(movieDetailProvider(widget.item)),
            tooltip: 'Refresh details',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 650;
            return SingleChildScrollView(
              padding: EdgeInsets.all(isTv ? 34 : 22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: FocusTraversalGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: isTv ? 210 : 190,
                                child: _poster(),
                              ),
                              const SizedBox(width: 36),
                              Expanded(
                                child: _information(detail, saved, isTv),
                              ),
                            ],
                          )
                        else ...[
                          Center(child: SizedBox(width: 172, child: _poster())),
                          const SizedBox(height: 28),
                          _information(detail, saved, isTv),
                        ],
                        const SizedBox(height: 34),
                        detail.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (_, __) => StatusView(
                            title: 'Movie details are unavailable',
                            message: 'You can still try playing this title.',
                            onRetry: () => ref.invalidate(
                              movieDetailProvider(widget.item),
                            ),
                          ),
                          data: (movie) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionHeading('Synopsis'),
                              Text(
                                movie.plot.trim().isEmpty
                                    ? 'No synopsis supplied by your provider.'
                                    : movie.plot,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.7,
                                  color: Color(0xFFB9C7D5),
                                ),
                              ),
                              if (movie.cast.trim().isNotEmpty) ...[
                                const SizedBox(height: 24),
                                const SectionHeading('Cast'),
                                Text(
                                  movie.cast,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.6,
                                    color: Color(0xFF91A4B9),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _poster() => AspectRatio(
    aspectRatio: 2 / 3,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Artwork(url: widget.item.imageUrl),
    ),
  );

  Widget _information(
    AsyncValue<MovieDetail> detail,
    WatchEntry? saved,
    bool isTv,
  ) {
    final movie = detail.asData?.value;
    final rating = movie?.rating.isNotEmpty == true
        ? movie!.rating
        : widget.item.rating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MOVIE',
          style: TextStyle(
            color: Color(0xFF54E1C1),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.item.name,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: isTv ? 36 : 30,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            if (rating.isNotEmpty) _badge('★ $rating', const Color(0xFFFFC677)),
            if (movie?.duration.isNotEmpty == true)
              _badge(movie!.duration, const Color(0xFFB9C7D5)),
            if (movie?.genre.isNotEmpty == true)
              _badge(movie!.genre, const Color(0xFFB9C7D5)),
          ],
        ),
        const SizedBox(height: 24),
        if (saved != null) ...[
          Text(
            'Last watched at ${formatPlaybackTime(saved.positionMs)}',
            style: const TextStyle(color: Color(0xFF91A4B9), fontSize: 13),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 320,
            child: LinearProgressIndicator(
              value: saved.progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: const Color(0xFF243449),
            ),
          ),
          const SizedBox(height: 20),
        ],
        FilledButton.icon(
          autofocus: isTv,
          onPressed: _opening ? null : _play,
          icon: _opening
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(saved != null ? 'Resume movie' : 'Play movie'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
          ),
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF182638),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
