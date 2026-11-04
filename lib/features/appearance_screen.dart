import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_utility_scaffold.dart';

/// Previewing never changes the saved preference. OK / a tap applies a theme.
class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  final _list = GlobalKey<TvRemoteListState>();
  AppAppearance? _preview;
  bool _saving = false;

  Future<void> _apply(AppAppearance appearance) async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await ref.read(settingsProvider.notifier).patch({
      'theme': appearance.name,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? '${appearance.label} theme applied.'
              : 'Theme could not be saved. Please try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).asData?.value;
    final selected = AppAppearance.parse(settings?.theme);
    final preview = _preview ?? selected;
    if (ref.watch(isLargeScreenProvider)) {
      return TvUtilityScaffold(
        title: 'Themes',
        subtitle:
            'Find your atmosphere. Your artwork stays true to its original colours.',
        onEnter: () => _list.currentState?.focusSelected(remember: true),
        hint: 'Up / Down  Preview    OK  Apply theme    Back  Return',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 290,
              child: TvRemoteList(
                key: _list,
                label: 'Theme',
                autofocus: true,
                dense: true,
                fullRows: true,
                extent: 62,
                titleSize: 15,
                onLeft: () {},
                onRight: () {},
                onTop: () {},
                entries: [
                  for (final appearance in AppAppearance.values)
                    TvListEntry(
                      id: appearance.name,
                      title: appearance.label,
                      subtitle: appearance.subtitle,
                      trailing: selected == appearance ? 'Applied' : '',
                      selected: selected == appearance,
                      onFocused: () => setState(() => _preview = appearance),
                      onPressed: () => _apply(appearance),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(preview.label, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(
                    preview.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ThemePreview(appearance: preview),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _saving
                        ? 'Saving theme…'
                        : selected == preview
                        ? 'Current theme'
                        : 'Preview · Press OK to apply',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.of(context).accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 420,
          mainAxisExtent: 260,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: AppAppearance.values.length,
        itemBuilder: (context, index) {
          final appearance = AppAppearance.values[index];
          final applied = appearance == selected;
          return Semantics(
            selected: applied,
            button: true,
            label: '${appearance.label} theme${applied ? ", applied" : ""}',
            child: Card(
              margin: EdgeInsets.zero,
              color: AppPalette.of(context).surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: applied
                      ? AppPalette.of(context).accent
                      : AppPalette.of(context).border,
                  width: applied ? 2 : 1,
                ),
              ),
              child: InkWell(
                onTap: _saving ? null : () => _apply(appearance),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: ThemePreview(appearance: appearance)),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appearance.label,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  appearance.subtitle,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (applied)
                            Icon(
                              Icons.check_circle,
                              color: AppPalette.of(context).accent,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A local, decorative miniature. It never fetches a catalogue or changes focus.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.appearance});
  final AppAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.forAppearance(appearance);
    return MediaQuery.withNoTextScaling(
      child: ExcludeSemantics(
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 480,
              height: 270,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.gradientStart,
                      palette.gradientMiddle,
                      palette.canvas,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            size: 20,
                            color: palette.accent,
                          ),
                          const SizedBox(width: 18),
                          const Text(
                            'Home',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 18),
                          const Expanded(
                            child: Text(
                              'Live TV     Movies     Series',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOUR EVENING, REIMAGINED',
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: 8,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'A world to discover',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 25,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.accent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '▶  Watch now',
                                    style: TextStyle(
                                      color: palette.canvas,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 92,
                            height: 88,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                colors: [
                                  palette.glow,
                                  palette.accentStrong.withValues(alpha: .4),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.landscape_outlined,
                              color: palette.accent,
                              size: 42,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Text(
                        'Discover more',
                        style: TextStyle(color: AppColors.text, fontSize: 11),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          for (var i = 0; i < 5; i++)
                            Expanded(
                              child: Container(
                                height: 48,
                                margin: EdgeInsets.only(right: i == 4 ? 0 : 8),
                                decoration: BoxDecoration(
                                  color: i == 0
                                      ? palette.glow
                                      : palette.surfaceRaised,
                                  border: Border.all(
                                    color: i == 0
                                        ? palette.accent
                                        : palette.border,
                                    width: i == 0 ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  i == 0
                                      ? Icons.play_arrow
                                      : Icons.movie_outlined,
                                  color: AppColors.text,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
