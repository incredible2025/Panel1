import 'models.dart';
import 'subscription_expiry.dart';

enum PlayerEngine { native, compatibility }

class AppSettings {
  const AppSettings({
    this.engine = PlayerEngine.native,
    this.controlsSeconds = 5,
    this.picture = 'fit',
    this.reconnect = true,
    this.autoNext = true,
    this.audioLanguage = '',
    this.subtitleLanguage = '',
    this.subtitles = false,
    this.stereo = false,
    this.subtitleSize = 22,
    this.subtitleBackground = true,
    this.theme = 'midnight',
    this.largePosters = false,
    this.compact = false,
    this.reducedMotion = false,
    this.recommendations = true,
    this.hiddenCategories = const {},
    this.lockedCategories = const {},
    this.categoryOrder = const {},
    this.favoriteOrder = const [],
    this.playerOverrides = const {},
    this.lastSection = 'home',
    this.lastCategories = const {},
    this.lastChannel = '',
    this.lastItems = const {},
  });
  final PlayerEngine engine;
  final int controlsSeconds;
  final String picture;
  final bool reconnect, autoNext, subtitles, stereo, subtitleBackground;
  final String audioLanguage, subtitleLanguage, theme;
  final double subtitleSize;
  final bool largePosters, compact, reducedMotion, recommendations;
  final Set<String> hiddenCategories, lockedCategories;
  final Map<String, List<String>> categoryOrder;
  final List<String> favoriteOrder;
  final Map<String, String> playerOverrides;
  final String lastSection, lastChannel;
  final Map<String, String> lastCategories, lastItems;

  static String categoryKey(MediaKind kind, String id) => '${kind.name}:$id';
  static String mediaKey(MediaItem item) => '${item.kind.name}:${item.id}';
  bool hidden(MediaItem item) =>
      hiddenCategories.contains(categoryKey(item.kind, item.categoryId));
  bool locked(MediaItem item) =>
      lockedCategories.contains(categoryKey(item.kind, item.categoryId));
  PlayerEngine engineFor(MediaItem item) =>
      switch (playerOverrides[mediaKey(item)]) {
        'compatibility' => PlayerEngine.compatibility,
        'native' => PlayerEngine.native,
        _ => engine,
      };
  Map<String, dynamic> toJson() => {
    'engine': engine.name,
    'controlsSeconds': controlsSeconds,
    'picture': picture,
    'reconnect': reconnect,
    'autoNext': autoNext,
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
    'subtitles': subtitles,
    'stereo': stereo,
    'subtitleSize': subtitleSize,
    'subtitleBackground': subtitleBackground,
    'theme': theme,
    'largePosters': largePosters,
    'compact': compact,
    'reducedMotion': reducedMotion,
    'recommendations': recommendations,
    'hiddenCategories': hiddenCategories.toList(),
    'lockedCategories': lockedCategories.toList(),
    'categoryOrder': categoryOrder,
    'favoriteOrder': favoriteOrder,
    'playerOverrides': playerOverrides,
    'lastSection': lastSection,
    'lastCategories': lastCategories,
    'lastChannel': lastChannel,
    'lastItems': lastItems,
  };
  AppSettings patch(Map<String, dynamic> values) =>
      AppSettings.fromJson({...toJson(), ...values});
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) =>
        value is List ? value.whereType<String>().toSet().toList() : [];
    Map<String, String> map(dynamic value) => {
      for (final entry in objectValue(value).entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
    final seconds = intValue(json['controlsSeconds'], 5);
    final size =
        num.tryParse(textValue(json['subtitleSize']))?.toDouble() ?? 22;
    return AppSettings(
      engine: json['engine'] == 'compatibility'
          ? PlayerEngine.compatibility
          : PlayerEngine.native,
      controlsSeconds: {0, 3, 5, 8}.contains(seconds) ? seconds : 5,
      picture: {'fit', 'fill', 'stretch'}.contains(json['picture'])
          ? json['picture'] as String
          : 'fit',
      reconnect: json['reconnect'] != false,
      autoNext: json['autoNext'] != false,
      audioLanguage: textValue(json['audioLanguage']),
      subtitleLanguage: textValue(json['subtitleLanguage']),
      subtitles: json['subtitles'] == true,
      stereo: json['stereo'] == true,
      subtitleSize: size.isFinite ? size.clamp(16, 40) : 22,
      subtitleBackground: json['subtitleBackground'] != false,
      theme: json['theme'] == 'cinema' ? 'cinema' : 'midnight',
      largePosters: json['largePosters'] == true,
      compact: json['compact'] == true,
      reducedMotion: json['reducedMotion'] == true,
      recommendations: json['recommendations'] != false,
      hiddenCategories: strings(json['hiddenCategories']).toSet(),
      lockedCategories: strings(json['lockedCategories']).toSet(),
      categoryOrder: {
        for (final entry in objectValue(json['categoryOrder']).entries)
          entry.key: strings(entry.value),
      },
      favoriteOrder: strings(json['favoriteOrder']),
      playerOverrides: map(json['playerOverrides']),
      lastSection: textValue(json['lastSection'], 'home'),
      lastCategories: map(json['lastCategories']),
      lastChannel: textValue(json['lastChannel']),
      lastItems: map(json['lastItems']),
    );
  }
}

class AccountInfo {
  AccountInfo(Session session, {DateTime? now})
    : values = session.userInfo,
      now = now ?? DateTime.now();
  final Map<String, dynamic> values;
  final DateTime now;
  bool get neverExpires => SubscriptionExpiry(values).neverExpires;
  DateTime? get expiry {
    final seconds = SubscriptionExpiry(values).seconds;
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toLocal();
  }

  int? get remainingDays => expiry == null
      ? null
      : (expiry!.difference(now).inSeconds / 86400).ceil();
  bool get expiring => remainingDays != null && remainingDays! <= 7;
  String get status => textValue(values['status'], 'Not supplied');
  String count(String key) =>
      int.tryParse(textValue(values[key]))?.toString() ?? 'Not supplied';
  String get expiryLabel => neverExpires
      ? 'Doesn’t expire'
      : expiry == null
      ? 'Not supplied'
      : '${expiry!.day.toString().padLeft(2, '0')}/${expiry!.month.toString().padLeft(2, '0')}/${expiry!.year}';
}

String canonicalLanguage(String value) {
  final language = value.toLowerCase().split(RegExp('[-_]')).first;
  return const {
        'eng': 'en',
        'spa': 'es',
        'fra': 'fr',
        'fre': 'fr',
        'deu': 'de',
        'ger': 'de',
        'ita': 'it',
        'por': 'pt',
        'ara': 'ar',
        'hin': 'hi',
        'tur': 'tr',
        'pol': 'pl',
        'nld': 'nl',
        'dut': 'nl',
      }[language] ??
      language;
}
