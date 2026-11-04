/// Stable preference keys; existing installations retain their selected theme.
enum AppAppearance {
  midnight(
    'Glass',
    'Blue & cyan',
    'The original blue glass with cool cyan highlights.',
  ),
  cinema(
    'Midnight',
    'Charcoal & ice',
    'A quiet charcoal canvas that lets the artwork take centre stage.',
  ),
  cyberpunk(
    'Cyberpunk',
    'Neon cyan & magenta',
    'Deep violet, electric cyan and a magenta glow.',
  ),
  aurora(
    'Aurora',
    'Violet & mint',
    'Soft violet light with fresh mint highlights.',
  ),
  emerald(
    'Emerald',
    'Forest & jade',
    'Rich forest tones with luminous jade accents.',
  ),
  sunset(
    'Sunset',
    'Plum & peach',
    'Warm plum shadows and soft peach highlights.',
  );

  const AppAppearance(this.label, this.subtitle, this.description);
  final String label, subtitle, description;

  static AppAppearance parse(String? value) =>
      values.firstWhere((theme) => theme.name == value, orElse: () => midnight);
}
