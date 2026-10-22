import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Safe to display to users: never includes request URLs or provider responses.
class XtreamApiException implements Exception {
  const XtreamApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class XtreamApi {
  XtreamApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 25);

  Future<Session> authenticate(Credentials credentials) async {
    final Uri base;
    try {
      base = normalizeServerUri(credentials.serverUrl);
    } on FormatException {
      throw const XtreamApiException('Enter a valid HTTP or HTTPS server URL.');
    }
    final normalized = Credentials(
      serverUrl: base.toString(),
      username: credentials.username.trim(),
      password: credentials.password,
    );
    if (normalized.username.isEmpty || normalized.password.isEmpty) {
      throw const XtreamApiException('Enter your username and password.');
    }
    final payload = objectValue(await _request(normalized));
    final user = objectValue(payload['user_info']);
    final authorized = user['auth'] == true || textValue(user['auth']) == '1';
    if (!authorized) {
      throw const XtreamApiException(
        'Sign-in failed. Check your server and credentials.',
      );
    }
    final status = textValue(user['status']).toLowerCase();
    if (status.isNotEmpty && status != 'active') {
      throw const XtreamApiException(
        'This subscription is inactive. Contact your provider.',
      );
    }
    final expires = intValue(user['exp_date']);
    if (expires > 0 &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expires) {
      throw const XtreamApiException(
        'This subscription has expired. Contact your provider.',
      );
    }
    return Session(
      credentials: normalized,
      userInfo: user,
      serverInfo: objectValue(payload['server_info']),
    );
  }

  Future<List<Category>> categories(Session session, MediaKind kind) async {
    final payload = await _request(session.credentials, {
      'action': _categoryAction(kind),
    });
    return _collection(payload)
        .map(Category.fromJson)
        .where((category) => category.id.isNotEmpty)
        .toList();
  }

  Future<List<MediaItem>> items(
    Session session,
    MediaKind kind, {
    String? categoryId,
  }) async {
    final payload = await _request(session.credentials, {
      'action': _itemsAction(kind),
      if (categoryId != null && categoryId.isNotEmpty)
        'category_id': categoryId,
    });
    return _collection(payload)
        .map((json) => MediaItem.fromJson(json, kind: kind))
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<MovieDetail> movieInfo(Session session, MediaItem item) async {
    final payload = objectValue(
      await _request(session.credentials, {
        'action': 'get_vod_info',
        'vod_id': item.id,
      }),
    );
    final movieData = objectValue(payload['movie_data']);
    final extension = textValue(
      movieData['container_extension'],
      item.containerExtension,
    );
    final enrichedItem = MediaItem(
      id: item.id,
      name: item.name,
      kind: item.kind,
      categoryId: item.categoryId,
      imageUrl: item.imageUrl,
      containerExtension: extension,
      addedAt: item.addedAt,
      rating: item.rating,
    );
    return MovieDetail.fromJson(enrichedItem, payload);
  }

  Future<SeriesDetail> seriesInfo(Session session, MediaItem item) async {
    final payload = objectValue(
      await _request(session.credentials, {
        'action': 'get_series_info',
        'series_id': item.id,
      }),
    );
    return SeriesDetail.fromJson(item, payload);
  }

  Future<GuideSchedule> fullEpg(Session session, String streamId) async {
    try {
      final payload = objectValue(
        await _request(session.credentials, {
          'action': 'get_simple_data_table',
          'stream_id': streamId,
        }),
      );
      final entries =
          objectList(
              payload['epg_listings'],
            ).map(EpgEntry.fromJson).whereType<EpgEntry>().toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      final seen = <String>{};
      return GuideSchedule(
        entries
            .where(
              (entry) => seen.add(
                '${entry.start.toIso8601String()}:${entry.end.toIso8601String()}',
              ),
            )
            .toList(),
      );
    } on XtreamApiException {
      return GuideSchedule(
        await shortEpg(session, streamId, limit: 192),
        limited: true,
      );
    }
  }

  Future<List<EpgEntry>> shortEpg(
    Session session,
    String streamId, {
    int limit = 6,
  }) async {
    final payload = objectValue(
      await _request(session.credentials, {
        'action': 'get_short_epg',
        'stream_id': streamId,
        'limit': limit.toString(),
      }),
    );
    return objectList(
        payload['epg_listings'],
      ).map(EpgEntry.fromJson).whereType<EpgEntry>().toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  Uri streamUri(Session session, MediaItem item, {Episode? episode}) {
    if (item.kind == MediaKind.series && episode == null) {
      throw const XtreamApiException('Choose an episode to play.');
    }
    final base = normalizeServerUri(session.credentials.serverUrl);
    final folder = switch (item.kind) {
      MediaKind.live => 'live',
      MediaKind.movie => 'movie',
      MediaKind.series => 'series',
    };
    var extension = (episode?.containerExtension ?? item.containerExtension)
        .toLowerCase();
    if (item.kind == MediaKind.live) {
      final rawFormats = session.userInfo['allowed_output_formats'];
      final formats = rawFormats is List
          ? rawFormats.map((format) => textValue(format).toLowerCase()).toSet()
          : <String>{};
      final requiresTs = formats.contains('ts') && !formats.contains('m3u8');
      if (extension != 'ts' && (extension != 'm3u8' || requiresTs)) {
        extension = requiresTs ? 'ts' : 'm3u8';
      }
    }
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension)) {
      extension = 'mp4';
    }
    final id = episode?.id ?? item.id;
    if (id.isEmpty) {
      throw const XtreamApiException('This item has no playable stream.');
    }
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        folder,
        session.credentials.username,
        session.credentials.password,
        '$id.$extension',
      ],
    );
  }

  Future<dynamic> _request(
    Credentials credentials, [
    Map<String, String> query = const {},
  ]) async {
    try {
      final base = normalizeServerUri(credentials.serverUrl);
      final uri = base.replace(
        pathSegments: [
          ...base.pathSegments.where((segment) => segment.isNotEmpty),
          'player_api.php',
        ],
        queryParameters: {
          'username': credentials.username,
          'password': credentials.password,
          ...query,
        },
      );
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const XtreamApiException(
          'Access denied. Check your subscription and credentials.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const XtreamApiException(
          'The provider is unavailable. Try again shortly.',
        );
      }
      // UTF-8 is used by Xtream even when the server omits its charset header.
      var body = utf8.decode(response.bodyBytes);
      if (body.startsWith('\uFEFF')) body = body.substring(1);
      final payload = jsonDecode(body);
      if (payload is! Map && payload is! List) {
        throw const XtreamApiException(
          'The server returned an unsupported response.',
        );
      }
      if (payload is Map && payload.containsKey('user_info')) {
        final user = objectValue(payload['user_info']);
        if (user.containsKey('auth') &&
            user['auth'] != true &&
            textValue(user['auth']) != '1') {
          throw const XtreamApiException(
            'Your session has expired. Please sign in again.',
          );
        }
      }
      if (payload is Map && payload['error'] != null) {
        throw const XtreamApiException(
          'The provider could not complete this request.',
        );
      }
      return payload;
    } on XtreamApiException {
      rethrow;
    } on TimeoutException {
      throw const XtreamApiException(
        'The server took too long to respond. Try again.',
      );
    } on FormatException {
      throw const XtreamApiException(
        'The server returned invalid data. Check the server URL.',
      );
    } catch (_) {
      // ClientException and SocketException often contain the credential URL.
      throw const XtreamApiException(
        'Could not connect to the provider. Check your connection and server URL.',
      );
    }
  }

  List<Map<String, dynamic>> _collection(dynamic payload) {
    if (payload is Map &&
        payload.isNotEmpty &&
        payload.values.any((value) => value is! Map)) {
      throw const XtreamApiException(
        'The server returned an unsupported listing.',
      );
    }
    return objectList(payload);
  }

  static String _categoryAction(MediaKind kind) => switch (kind) {
    MediaKind.live => 'get_live_categories',
    MediaKind.movie => 'get_vod_categories',
    MediaKind.series => 'get_series_categories',
  };

  static String _itemsAction(MediaKind kind) => switch (kind) {
    MediaKind.live => 'get_live_streams',
    MediaKind.movie => 'get_vod_streams',
    MediaKind.series => 'get_series',
  };

  void dispose() => _client.close();
}
