/// Customer-facing copy only. Unsafe legacy feeds must not block an update.
const defaultReleaseNotes = 'Improvements and fixes for Ultravpn-player.';

String publicReleaseNotes(String source) {
  final notes = source.trim();
  final lines = notes.split('\n').where((line) => line.trim().isNotEmpty);
  if (notes.isEmpty ||
      notes.length > 600 ||
      lines.length > 5 ||
      lines.any((line) => line.length > 160) ||
      RegExp(r'[\x00-\x08\x0b-\x1f\x7f]').hasMatch(notes) ||
      RegExp(
        r'://|www\.|\b(?:\d{1,3}\.){3}\d{1,3}\b|'
        r'(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.%]*|'
        r'\b[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9-]+)*\.[a-z][a-z0-9-]{1,}\b|'
        r'\b(?:password|username|token|secret|api[ _-]?key|sha[ -]?256|keystore|certificate)\b',
        caseSensitive: false,
      ).hasMatch(notes)) {
    return defaultReleaseNotes;
  }
  return notes
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .join('\n');
}
