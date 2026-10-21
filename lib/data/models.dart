import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  /// Password changes keep history, while different users/providers are isolated.
  String get accountId => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            normalizeServerUri(credentials.serverUrl).toString(),
            credentials.username.trim(),
          ]),
        ),
      )
      .toString();

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
  });

  final String id;
  final String name;
  final MediaKind kind;
  final String categoryId;
  final String imageUrl;
  final String containerExtension;
  final String rating;

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
  };

  @override
  bool operator ==(Object other) =>
      other is MediaItem && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

class MovieDetail {
  const MovieDetail({
    required this.item,
    this.plot = '',
    this.cast = '',
    this.genre = '',
    this.rating = '',
    this.duration = '',
  });

  final MediaItem item;
  final String plot;
  final String cast;
  final String genre;
  final String rating;
  final String duration;

  factory MovieDetail.fromJson(MediaItem item, Map<String, dynamic> json) {
    final info = objectValue(json['info']);
    return MovieDetail(
      item: item,
      plot: textValue(info['plot'] ?? info['description']),
      cast: textValue(info['cast'] ?? info['actors']),
      genre: textValue(info['genre']),
      rating: textValue(info['rating'] ?? info['rating_5based'], item.rating),
      duration: textValue(info['duration'] ?? info['duration_secs']),
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
  });

  final MediaItem item;
  final String plot;
  final String cast;
  final Map<String, List<Episode>> seasons;

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
    );
  }
}

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
  if (number != null && number > 0) {
    final millis = number > 100000000000
        ? number.toInt()
        : (number * 1000).toInt();
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
