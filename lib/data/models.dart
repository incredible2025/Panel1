import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'provider_addresses.dart';

/// A provider's credentials. Passwords are never included in [toString].
class Credentials {
  const Credentials({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  final String serverUrl;
  final String username;
  final String password;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
  };

  factory Credentials.fromJson(Map<String, dynamic> json) => Credentials(
    serverUrl: textValue(json['serverUrl']),
    username: textValue(json['username']),
    password: textValue(json['password']),
  );

  @override
  String toString() => 'Credentials(<redacted>)';
}

/// Accept a provider root or a pasted player_api.php/get.php endpoint.
/// Missing schemes use HTTPS; providers using HTTP must specify it explicitly.
Uri normalizeServerUri(String input) {
  var value = input.trim();
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Enter a valid HTTP or HTTPS server URL.');
  }
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  path = path.replaceFirst(
    RegExp(r'/(?:player_api|get)\.php$', caseSensitive: false),
    '',
  );
  // Rebuild instead of retaining query strings containing pasted credentials.
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
}

class Session {
  const Session({
    required this.credentials,
    required this.userInfo,
    required this.serverInfo,
  });

  final Credentials credentials;
  final Map<String, dynamic> userInfo;
  final Map<String, dynamic> serverInfo;

  /// Keep this operator's storage scope stable across its approved address move.
  /// Different users and unrelated providers retain separate account identities.
  String get accountId => sha256
      .convert(
        utf8.encode(jsonEncode([_accountPortal, credentials.username.trim()])),
      )
      .toString();

  String get _accountPortal {
    final address = normalizeServerUri(credentials.serverUrl);
    return (isConfiguredProviderUri(address) || isRetiredProviderUri(address)
            ? normalizeServerUri(previousProviderPortalUrl)
            : address)
        .toString();
  }

  Map<String, dynamic> toJson() => {
    'credentials': credentials.toJson(),
    'userInfo': userInfo,
    'serverInfo': serverInfo,
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    credentials: Credentials.fromJson(objectValue(json['credentials'])),
    userInfo: objectValue(json['userInfo']),
    serverInfo: objectValue(json['serverInfo']),
  );
}

enum MediaKind { live, movie, series }

enum CatalogSort { recentlyAdded, titleAscending, titleDescending }

/// Returns a new list; a provider's original catalog order is never mutated.
/// Unknown dates appear after all dated items when sorting by recently added.
List<MediaItem> sortMediaItems(List<MediaItem> items, CatalogSort sort) {
  final sorted = List<MediaItem>.of(items);
  sorted.sort((first, second) {
    if (sort == CatalogSort.recentlyAdded) {
      final firstDate = first.addedAt;
      final secondDate = second.addedAt;
      if (firstDate == null && secondDate != null) return 1;
      if (firstDate != null && secondDate == null) return -1;
      if (firstDate != null && secondDate != null) {
        final byDate = secondDate.compareTo(firstDate);
        if (byDate != 0) return byDate;
      }
    }
    final byTitle = first.name.trim().toLowerCase().compareTo(
      second.name.trim().toLowerCase(),
    );
    if (byTitle != 0) {
      return sort == CatalogSort.titleDescending ? -byTitle : byTitle;
    }
    final byId = first.id.compareTo(second.id);
    if (byId != 0) return byId;
    final byKind = first.kind.index.compareTo(second.kind.index);
    return byKind != 0 ? byKind : first.name.compareTo(second.name);
  });
  return sorted;
}

/// A recently-added row uses actual provider dates, not list positions or IDs.
List<MediaItem> recentlyAddedMovies(List<MediaItem> items, {int limit = 20}) =>
    sortMediaItems(
      items
          .where((item) => item.kind == MediaKind.movie && item.addedAt != null)
          .toList(),
      CatalogSort.recentlyAdded,
    ).take(limit < 0 ? 0 : limit).toList();

class Category {
  const Category({required this.id, required this.name});
  final String id;
  final String name;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: textValue(json['category_id'] ?? json['id']),
    name: textValue(json['category_name'] ?? json['name'], 'Uncategorized'),
  );

  Map<String, dynamic> toJson() => {'category_id': id, 'category_name': name};
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.kind,
    this.categoryId = '',
    this.imageUrl = '',
    this.containerExtension = 'mp4',
    this.rating = '',
    this.addedAt,
  });

  final String id;
  final String name;
  final MediaKind kind;
  final String categoryId;
  final String imageUrl;
  final String containerExtension;
  final String rating;
  final DateTime? addedAt;

  factory MediaItem.fromJson(Map<String, dynamic> json, {MediaKind? kind}) {
    final savedKind = textValue(json['kind']);
    final parsedKind =
        kind ??
        MediaKind.values.firstWhere(
          (value) => value.name == savedKind,
          orElse: () => MediaKind.movie,
        );
    return MediaItem(
      id: textValue(json['id'] ?? json['stream_id'] ?? json['series_id']),
      name: textValue(json['name'] ?? json['title'], 'Untitled'),
      kind: parsedKind,
      categoryId: textValue(json['categoryId'] ?? json['category_id']),
      imageUrl: textValue(
        json['imageUrl'] ?? json['stream_icon'] ?? json['cover'],
      ),
      containerExtension: textValue(
        json['containerExtension'] ?? json['container_extension'],
        parsedKind == MediaKind.live ? 'm3u8' : 'mp4',
      ),
      rating: textValue(json['rating'] ?? json['rating_5based']),
      addedAt:
          _catalogDate(json['addedAt']) ??
          _catalogDate(json['added']) ??
          _catalogDate(json['last_modified']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'categoryId': categoryId,
    'imageUrl': imageUrl,
    'containerExtension': containerExtension,
    'rating': rating,
    'addedAt': addedAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is MediaItem && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

DateTime? _catalogDate(dynamic value) {
  if (value is DateTime) return value.toUtc();
  final text = textValue(value).trim();
  if (text.isEmpty) return null;
  final seconds = num.tryParse(text);
  if (seconds != null) {
    if (!seconds.isFinite || seconds <= 0) return null;
    final milliseconds = seconds * 1000;
    if (!milliseconds.isFinite || milliseconds > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds.toInt(),
      isUtc: true,
    );
  }
  return DateTime.tryParse(text)?.toUtc();
}

class MovieDetail {
  const MovieDetail({
    required this.item,
    this.plot = '',
    this.cast = '',
    this.genre = '',
    this.rating = '',
    this.duration = '',
    this.backdropUrl = '',
    this.year = '',
  });

  final MediaItem item;
  final String plot;
  final String cast;
  final String genre;
  final String rating;
  final String duration;
  final String backdropUrl;
  final String year;

  factory MovieDetail.fromJson(MediaItem item, Map<String, dynamic> json) {
    final info = objectValue(json['info']);
    return MovieDetail(
      item: item,
      plot: textValue(info['plot'] ?? info['description']),
      cast: textValue(info['cast'] ?? info['actors']),
      genre: textValue(info['genre']),
      rating: textValue(info['rating'] ?? info['rating_5based'], item.rating),
      duration: textValue(info['duration'] ?? info['duration_secs']),
      backdropUrl: artworkValue(
        info['backdrop_path'] ?? info['backdrop'] ?? info['cover_big'],
      ),
      year: releaseYear(
        info['releasedate'] ??
            info['releaseDate'] ??
            info['release_date'] ??
            info['year'],
      ),
    );
  }
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.episodeNumber,
    this.containerExtension = 'mp4',
    this.imageUrl = '',
  });

  final String id;
  final String title;
  final String season;
  final int episodeNumber;
  final String containerExtension;
  final String imageUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'season': season,
    'episodeNumber': episodeNumber,
    'container_extension': containerExtension,
    'imageUrl': imageUrl,
  };

  factory Episode.fromJson(Map<String, dynamic> json, {String season = ''}) {
    final info = objectValue(json['info']);
    final number = intValue(json['episode_num'] ?? json['episodeNumber']);
    return Episode(
      id: textValue(json['id'] ?? json['stream_id']),
      title: textValue(json['title'] ?? json['name'], 'Episode $number'),
      season: textValue(json['season'], season),
      episodeNumber: number,
      containerExtension: textValue(json['container_extension'], 'mp4'),
      imageUrl: textValue(
        info['movie_image'] ?? info['cover_big'] ?? json['imageUrl'],
      ),
    );
  }
}

class SeriesDetail {
  const SeriesDetail({
    required this.item,
    this.plot = '',
    this.cast = '',
    this.seasons = const {},
    this.backdropUrl = '',
    this.genre = '',
    this.rating = '',
    this.year = '',
  });

  final MediaItem item;
  final String plot;
  final String cast;
  final Map<String, List<Episode>> seasons;
  final String backdropUrl;
  final String genre;
  final String rating;
  final String year;

  List<Episode> get orderedEpisodes {
    final episodes = seasons.values.expand((value) => value).toList();
    episodes.sort((a, b) {
      final season = (int.tryParse(a.season) ?? 0).compareTo(
        int.tryParse(b.season) ?? 0,
      );
      if (season != 0) return season;
      final number = a.episodeNumber.compareTo(b.episodeNumber);
      return number != 0 ? number : a.id.compareTo(b.id);
    });
    final ids = <String>{};
    return episodes
        .where((episode) => episode.id.isNotEmpty && ids.add(episode.id))
        .toList();
  }

  factory SeriesDetail.fromJson(MediaItem item, Map<String, dynamic> json) {
    final info = objectValue(json['info']);
    final seasons = <String, List<Episode>>{};
    final episodes = json['episodes'];
    if (episodes is Map) {
      for (final entry in episodes.entries) {
        final season = entry.key.toString();
        seasons[season] =
            objectList(entry.value)
                .map((episode) => Episode.fromJson(episode, season: season))
                .where((episode) => episode.id.isNotEmpty)
                .toList()
              ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      }
    } else if (episodes is List) {
      // Some providers send episodes as a flat list instead of a season map.
      for (final value in objectList(episodes)) {
        final episode = Episode.fromJson(value, season: '1');
        if (episode.id.isNotEmpty) {
          seasons.putIfAbsent(episode.season, () => []).add(episode);
        }
      }
      for (final list in seasons.values) {
        list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      }
    }
    final sortedKeys = seasons.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return SeriesDetail(
      item: item,
      plot: textValue(info['plot'] ?? info['description']),
      cast: textValue(info['cast'] ?? info['actors']),
      seasons: {for (final key in sortedKeys) key: seasons[key]!},
      backdropUrl: artworkValue(
        info['backdrop_path'] ?? info['backdrop'] ?? info['cover_big'],
      ),
      genre: textValue(info['genre']),
      rating: textValue(info['rating'] ?? info['rating_5based'], item.rating),
      year: releaseYear(
        info['releaseDate'] ??
            info['releasedate'] ??
            info['release_date'] ??
            info['year'],
      ),
    );
  }
}

String artworkValue(dynamic value) {
  if (value is List) {
    for (final entry in value) {
      final artwork = artworkValue(entry);
      if (artwork.isNotEmpty) return artwork;
    }
    return '';
  }
  final text = textValue(value);
  final uri = Uri.tryParse(text);
  return uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty
      ? text
      : '';
}

String releaseYear(dynamic value) =>
    RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(textValue(value))?.group(0) ?? '';

class EpgEntry {
  const EpgEntry({
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  /// Timestamps avoid timezone ambiguity in provider-formatted date strings.
  static EpgEntry? fromJson(Map<String, dynamic> json) {
    final start = _epgDate(json['start_timestamp'] ?? json['start']);
    final end = _epgDate(
      json['stop_timestamp'] ?? json['end_timestamp'] ?? json['end'],
    );
    if (start == null || end == null || !end.isAfter(start)) return null;
    return EpgEntry(
      title: _decodeEpgText(textValue(json['title'], 'Programme')),
      description: _decodeEpgText(textValue(json['description'])),
      start: start,
      end: end,
    );
  }

  Map<String, dynamic> toJson() => {
    // Store the API shape, including base64 text, for a lossless roundtrip.
    'title': base64Encode(utf8.encode(title)),
    'description': base64Encode(utf8.encode(description)),
    'start_timestamp': start.millisecondsSinceEpoch ~/ 1000,
    'stop_timestamp': end.millisecondsSinceEpoch ~/ 1000,
  };
}

DateTime? _epgDate(dynamic value) {
  final number = num.tryParse(textValue(value));
  if (number != null && number.isFinite && number > 0) {
    final millis = number > 100000000000
        ? number.toInt()
        : (number * 1000).toInt();
    if (millis > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
  return DateTime.tryParse(textValue(value));
}

String _decodeEpgText(String value) {
  if (value.isEmpty) return value;
  try {
    final decoded = utf8.decode(base64.decode(base64.normalize(value)));
    // A provider may return plain text; reject decoded control characters.
    if (decoded.runes.any((c) => c < 32 && c != 9 && c != 10 && c != 13)) {
      return value;
    }
    return decoded;
  } on FormatException {
    return value;
  }
}

class WatchEntry {
  const WatchEntry({
    required this.item,
    required this.positionMs,
    required this.durationMs,
    required this.lastAccessed,
  });

  final MediaItem item;
  final int positionMs;
  final int durationMs;
  final DateTime lastAccessed;

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);
  bool get canResume => durationMs > 0 && progress > .05 && progress < .95;
}

class EpisodeWatchEntry {
  const EpisodeWatchEntry({
    required this.item,
    required this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.lastAccessed,
    this.nextEpisode,
  });
  final MediaItem item;
  final Episode episode;
  final int positionMs;
  final int durationMs;
  final DateTime lastAccessed;
  final Episode? nextEpisode;
  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);
  bool get watched => durationMs > 0 && progress >= .95;
  bool get canResume => durationMs > 0 && positionMs >= 10000 && !watched;
  Episode? get continueEpisode => canResume
      ? episode
      : watched
      ? nextEpisode
      : null;
  String get label => 'S${episode.season} · E${episode.episodeNumber}';
}

class GuideSchedule {
  const GuideSchedule(
    this.entries, {
    this.limited = false,
    this.cached = false,
  });
  final List<EpgEntry> entries;
  final bool limited;
  final bool cached;
}

String textValue(dynamic value, [String fallback = '']) {
  if (value == null || value == false || value is Map || value is List) {
    return fallback;
  }
  final text = value.toString();
  return text.isEmpty || text == 'null' ? fallback : text;
}

int intValue(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse(textValue(value)) ?? fallback;

Map<String, dynamic> objectValue(dynamic value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

List<Map<String, dynamic>> objectList(dynamic value) {
  if (value is List) return value.whereType<Map>().map(objectValue).toList();
  if (value is Map) {
    // Empty PHP arrays can serialize as {}; numeric-key collections as objects.
    return value.values.whereType<Map>().map(objectValue).toList();
  }
  return [];
}
