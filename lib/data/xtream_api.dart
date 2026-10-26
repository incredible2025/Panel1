import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'provider_addresses.dart';
import 'provider_connections.dart';
import 'subscription_expiry.dart';

/// Safe to display to users: never includes request URLs or provider responses.
class XtreamApiException implements Exception {
  const XtreamApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class XtreamApi {
  XtreamApi({
    http.Client? client,
    ProviderConnections? connections,
    Future<void> Function(Uri)? streamProbe,
    this.connectionTimeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       connections = connections ?? ProviderConnections(),
       _streamProbe = streamProbe ?? probeProviderStream;

  final http.Client _client;
  final ProviderConnections connections;
  final Future<void> Function(Uri) _streamProbe;
  final Duration connectionTimeout;
  static const _timeout = Duration(seconds: 25);

  Future<Session> authenticate(Credentials credentials) async {
    final Uri base;
    try {
      final supplied = normalizeServerUri(credentials.serverUrl);
      base = connections.manages(supplied)
          ? Uri.parse(providerPortalUrl)
          : supplied;
    } on FormatException {
      throw const XtreamApiException(
        'The service configuration is unavailable. Contact support.',
      );
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
        'Sign-in failed. Check your username and password.',
      );
    }
    final subscription = SubscriptionExpiry(user);
    if (!subscription.activeStatus) {
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
      if (payload['epg_listings'] is! List) {
        throw const XtreamApiException('Full schedule is unavailable.');
      }
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
    final supplied = normalizeServerUri(session.credentials.serverUrl);
    final base = connections.manages(supplied)
        ? connections.preferred(ProviderRoute.playback)
        : supplied;
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

  /// Playback uses its own reachability check, without changing a healthy API
  /// selection or persisting a weaker transport as the account's identity.
  Future<Uri> prepareStreamUri(
    Session session,
    MediaItem item, {
    Episode? episode,
  }) async {
    final supplied = normalizeServerUri(session.credentials.serverUrl);
    if (!connections.manages(supplied)) {
      return streamUri(session, item, episode: episode);
    }
    return connections.run(supplied, ProviderRoute.playback, (base) async {
      final uri = streamUri(session, item, episode: episode).replace(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
      );
      await _streamProbe(uri);
      return uri;
    });
  }

  Credentials diagnosticCredentials(Credentials credentials) {
    final base = normalizeServerUri(credentials.serverUrl);
    return Credentials(
      serverUrl: connections.manages(base)
          ? connections.preferred(ProviderRoute.api).toString()
          : base.toString(),
      username: credentials.username,
      password: credentials.password,
    );
  }

  void resetConnectionPreferences() => connections.reset();

  Future<dynamic> _request(
    Credentials credentials, [
    Map<String, String> query = const {},
  ]) async {
    try {
      final supplied = normalizeServerUri(credentials.serverUrl);
      return await connections.run(
        supplied,
        ProviderRoute.api,
        (base) => _requestAt(credentials, base, query),
      );
    } on XtreamApiException {
      rethrow;
    } on TimeoutException {
      throw const XtreamApiException(
        'The server took too long to respond. Try again.',
      );
    } on FormatException {
      throw const XtreamApiException(
        'The provider returned invalid data. Retry or contact support.',
      );
    } catch (error) {
      if (isCertificateFailure(error)) {
        throw const XtreamApiException(
          'The secure connection could not be verified. Check your device date and time or run Connection diagnosis.',
        );
      }
      throw const XtreamApiException(
        'Could not connect to the provider. Check your connection or run Connection diagnosis.',
      );
    }
  }

  Future<dynamic> _requestAt(
    Credentials credentials,
    Uri base,
    Map<String, String> query,
  ) async {
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
    final response = connections.manages(base)
        ? await _managedGet(uri)
        : await _client
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
  }

  Future<http.Response> _managedGet(Uri initial) async {
    final abort = Completer<void>();
    try {
      return await (() async {
        var uri = initial;
        for (var hop = 0; hop < 4; hop++) {
          final request =
              http.AbortableRequest('GET', uri, abortTrigger: abort.future)
                ..followRedirects = false
                ..headers['Accept'] = 'application/json';
          final headers = await _client
              .send(request)
              .timeout(connectionTimeout);
          final response = await http.Response.fromStream(
            headers,
          ).timeout(_timeout);
          if (!{301, 302, 303, 307, 308}.contains(response.statusCode)) {
            return response;
          }
          final location = response.headers['location'];
          if (location == null) {
            throw const XtreamApiException(
              'The provider returned an unsupported redirect.',
            );
          }
          final next = uri.resolve(location);
          final root = normalizeServerUri(next.toString());
          if (!isConfiguredProviderUri(root) ||
              next.userInfo.isNotEmpty ||
              next.fragment.isNotEmpty ||
              uri.scheme == 'https' && next.scheme != 'https') {
            throw const XtreamApiException(
              'The provider returned an unsupported redirect. Run Connection diagnosis.',
            );
          }
          uri = next;
        }
        throw const XtreamApiException(
          'The provider returned too many redirects.',
        );
      })();
    } on TimeoutException {
      abort.complete();
      rethrow;
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
