import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'app_settings.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqlite;

import 'models.dart';

/// Local history and cache, with the credential-bearing session kept separately
/// in Android Keystore-backed encrypted storage rather than the SQLite database.
class LocalStore {
  LocalStore._(this._database, this._secureStorage);

  final sqlite.Database _database;
  final FlutterSecureStorage _secureStorage;
  static const _sessionKey = 'streamline.session.v1';

  static Future<LocalStore> open({
    sqlite.DatabaseFactory? databaseFactory,
    String? databasePath,
    FlutterSecureStorage? secureStorage,
  }) async {
    final factory = databaseFactory ?? sqlite.databaseFactory;
    final database = await factory.openDatabase(
      databasePath ??
          path.join(await factory.getDatabasesPath(), 'streamline.db'),
      options: sqlite.OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE watch_history (
              account_id TEXT NOT NULL,
              media_id TEXT NOT NULL,
              item_json TEXT NOT NULL,
              position_ms INTEGER NOT NULL DEFAULT 0,
              duration_ms INTEGER NOT NULL DEFAULT 0,
              last_accessed INTEGER NOT NULL,
              PRIMARY KEY (account_id, media_id)
            )
          ''');
          await db.execute('''
            CREATE INDEX history_recent
            ON watch_history (account_id, last_accessed DESC)
          ''');
          await db.execute('''
            CREATE TABLE provider_cache (
              account_id TEXT NOT NULL,
              cache_key TEXT NOT NULL,
              data_json TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (account_id, cache_key)
            )
          ''');
          await _createCollections(db);
          await _createEpisodeHistory(db);
          await _createPreferences(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createCollections(db);
          if (oldVersion < 3) await _createEpisodeHistory(db);
          if (oldVersion < 4) await _createPreferences(db);
        },
      ),
    );
    return LocalStore._(
      database,
      secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          ),
    );
  }

  static Future<void> _createCollections(sqlite.DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE favorites (
        account_id TEXT NOT NULL,
        media_kind TEXT NOT NULL,
        media_id TEXT NOT NULL,
        item_json TEXT NOT NULL,
        saved_at INTEGER NOT NULL,
        PRIMARY KEY (account_id, media_kind, media_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX favorites_saved ON favorites (account_id, saved_at DESC)
    ''');
    await db.execute('''
      CREATE TABLE live_recent (
        account_id TEXT NOT NULL,
        media_id TEXT NOT NULL,
        item_json TEXT NOT NULL,
        last_played INTEGER NOT NULL,
        PRIMARY KEY (account_id, media_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX channels_recent ON live_recent (account_id, last_played DESC)
    ''');
  }

  static Future<void> _createEpisodeHistory(sqlite.DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE episode_history (
        account_id TEXT NOT NULL,
        series_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        item_json TEXT NOT NULL,
        episode_json TEXT NOT NULL,
        next_episode_json TEXT,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        last_accessed INTEGER NOT NULL,
        PRIMARY KEY (account_id, series_id, episode_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX episodes_recent ON episode_history (account_id, last_accessed DESC)',
    );
  }

  Future<List<EpisodeWatchEntry>> seriesHistory(String accountId) async {
    final rows = await _database.query(
      'episode_history',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'last_accessed DESC, episode_id ASC',
    );
    final entries = <EpisodeWatchEntry>[];
    for (final row in rows) {
      try {
        final item = MediaItem.fromJson(
          objectValue(jsonDecode(row['item_json']! as String)),
        );
        final episode = Episode.fromJson(
          objectValue(jsonDecode(row['episode_json']! as String)),
        );
        if (item.kind != MediaKind.series || episode.id.isEmpty) continue;
        final next = row['next_episode_json'];
        entries.add(
          EpisodeWatchEntry(
            item: item,
            episode: episode,
            nextEpisode: next is String
                ? Episode.fromJson(objectValue(jsonDecode(next)))
                : null,
            positionMs: intValue(row['position_ms']),
            durationMs: intValue(row['duration_ms']),
            lastAccessed: DateTime.fromMillisecondsSinceEpoch(
              intValue(row['last_accessed']),
            ),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return entries;
  }

  Future<void> saveEpisodeProgress(
    String accountId,
    MediaItem item,
    Episode episode, {
    required int positionMs,
    required int durationMs,
    Episode? nextEpisode,
  }) async {
    if (item.kind != MediaKind.series ||
        item.id.isEmpty ||
        episode.id.isEmpty) {
      return;
    }
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'episode_history',
        where: 'account_id = ? AND series_id = ? AND episode_id = ?',
        whereArgs: [accountId, item.id, episode.id],
        limit: 1,
      );
      final existing = rows.firstOrNull;
      final oldDuration = intValue(existing?['duration_ms']);
      final duration = durationMs > 0 ? durationMs : oldDuration;
      final rawPosition = durationMs <= 0 && positionMs <= 0 && oldDuration > 0
          ? intValue(existing?['position_ms'])
          : math.max(0, positionMs);
      final position = duration > 0
          ? math.min(rawPosition, duration)
          : rawPosition;
      await txn.insert('episode_history', {
        'account_id': accountId,
        'series_id': item.id,
        'episode_id': episode.id,
        'item_json': jsonEncode(item.toJson()),
        'episode_json': jsonEncode(episode.toJson()),
        'next_episode_json': nextEpisode == null
            ? null
            : jsonEncode(nextEpisode.toJson()),
        'position_ms': position,
        'duration_ms': math.max(0, duration),
        'last_accessed': await _nextCollectionTime(
          txn,
          'episode_history',
          'last_accessed',
          accountId,
        ),
      }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
    });
  }

  Future<Session?> readSession() async {
    final value = await _secureStorage.read(key: _sessionKey);
    if (value == null) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map) throw const FormatException('Invalid session.');
      final session = Session.fromJson(objectValue(json));
      if (session.credentials.username.isEmpty ||
          session.credentials.password.isEmpty) {
        throw const FormatException('Invalid session.');
      }
      normalizeServerUri(session.credentials.serverUrl);
      return session;
    } on FormatException {
      await clearSession();
      return null;
    }
  }

  Future<void> saveSession(Session session) => _secureStorage.write(
    key: _sessionKey,
    value: jsonEncode(session.toJson()),
  );

  /// Signing out removes credentials. Account-scoped viewing history is retained
  /// for the next sign-in, without exposing it to a different provider/account.
  Future<void> clearSession() => _secureStorage.delete(key: _sessionKey);

  Future<List<MediaItem>> favorites(String accountId) async {
    final rows = await _database.query(
      'favorites',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'saved_at DESC, media_kind ASC, media_id ASC',
    );
    return _mediaRows(rows);
  }

  Future<void> setFavorite(
    String accountId,
    MediaItem item,
    bool favorite,
  ) async {
    if (item.id.trim().isEmpty) return;
    if (!favorite) {
      await _database.delete(
        'favorites',
        where: 'account_id = ? AND media_kind = ? AND media_id = ?',
        whereArgs: [accountId, item.kind.name, item.id],
      );
      return;
    }
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'favorites',
        columns: ['saved_at'],
        where: 'account_id = ? AND media_kind = ? AND media_id = ?',
        whereArgs: [accountId, item.kind.name, item.id],
        limit: 1,
      );
      final savedAt = existing.isNotEmpty
          ? intValue(existing.first['saved_at'])
          : await _nextCollectionTime(txn, 'favorites', 'saved_at', accountId);
      await txn.insert('favorites', {
        'account_id': accountId,
        'media_kind': item.kind.name,
        'media_id': item.id,
        'item_json': jsonEncode(item.toJson()),
        'saved_at': savedAt,
      }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
    });
  }

  /// Up to twenty distinct live channels, most recently played first.
  Future<List<MediaItem>> recentChannels(String accountId) async {
    final rows = await _database.query(
      'live_recent',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'last_played DESC, media_id ASC',
      limit: 20,
    );
    return _mediaRows(
      rows,
    ).where((item) => item.kind == MediaKind.live).toList();
  }

  Future<void> recordChannelPlayed(String accountId, MediaItem item) async {
    if (item.kind != MediaKind.live || item.id.trim().isEmpty) return;
    await _database.transaction((txn) async {
      final playedAt = await _nextCollectionTime(
        txn,
        'live_recent',
        'last_played',
        accountId,
      );
      await txn.insert('live_recent', {
        'account_id': accountId,
        'media_id': item.id,
        'item_json': jsonEncode(item.toJson()),
        'last_played': playedAt,
      }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
      await txn.rawDelete(
        '''
        DELETE FROM live_recent
        WHERE account_id = ? AND media_id NOT IN (
          SELECT media_id FROM live_recent WHERE account_id = ?
          ORDER BY last_played DESC, media_id ASC LIMIT 20
        )
      ''',
        [accountId, accountId],
      );
    });
  }

  List<MediaItem> _mediaRows(List<Map<String, Object?>> rows) {
    final items = <MediaItem>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row['item_json']! as String);
        if (json is! Map) continue;
        final item = MediaItem.fromJson(objectValue(json));
        if (item.id.isNotEmpty) items.add(item);
      } on FormatException {
        // A malformed local row should not hide the rest of a collection.
        continue;
      }
    }
    return items;
  }

  Future<int> _nextCollectionTime(
    sqlite.DatabaseExecutor db,
    String table,
    String column,
    String accountId,
  ) async {
    // Only fixed table/column names above enter this query. The clock tie-break
    // preserves access order even for rapid zapping within one millisecond.
    final rows = await db.rawQuery(
      'SELECT MAX($column) AS latest FROM $table WHERE account_id = ?',
      [accountId],
    );
    return math.max(
      DateTime.now().millisecondsSinceEpoch,
      intValue(rows.first['latest']) + 1,
    );
  }

  Future<List<WatchEntry>> history(String accountId) async {
    final rows = await _database.query(
      'watch_history',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'last_accessed DESC, media_id ASC',
    );
    final entries = <WatchEntry>[];
    for (final row in rows) {
      try {
        entries.add(
          WatchEntry(
            item: MediaItem.fromJson(
              objectValue(jsonDecode(row['item_json']! as String)),
            ),
            positionMs: intValue(row['position_ms']),
            durationMs: intValue(row['duration_ms']),
            lastAccessed: DateTime.fromMillisecondsSinceEpoch(
              intValue(row['last_accessed']),
            ),
          ),
        );
      } on FormatException {
        // A corrupt cache/history row should not prevent opening the app.
        continue;
      }
    }
    return entries;
  }

  Future<void> recordOpened(String accountId, MediaItem item) async {
    if (item.kind != MediaKind.movie) return;
    await _database.transaction((txn) async {
      final existing = await _progressRow(txn, accountId, item.id);
      await txn.insert('watch_history', {
        'account_id': accountId,
        'media_id': item.id,
        'item_json': jsonEncode(item.toJson()),
        'position_ms': intValue(existing?['position_ms']),
        'duration_ms': intValue(existing?['duration_ms']),
        'last_accessed': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
    });
  }

  Future<void> saveProgress(
    String accountId,
    MediaItem item, {
    required int positionMs,
    required int durationMs,
  }) async {
    if (item.kind != MediaKind.movie) return;
    await _database.transaction((txn) async {
      final existing = await _progressRow(txn, accountId, item.id);
      final previousDuration = intValue(existing?['duration_ms']);
      final duration = durationMs > 0 ? durationMs : previousDuration;
      // Failed initialization must not erase the position of a resumable movie.
      final rawPosition =
          durationMs <= 0 && positionMs <= 0 && previousDuration > 0
          ? intValue(existing?['position_ms'])
          : math.max(0, positionMs);
      final position = duration > 0
          ? math.min(rawPosition, duration)
          : rawPosition;
      await txn.insert('watch_history', {
        'account_id': accountId,
        'media_id': item.id,
        'item_json': jsonEncode(item.toJson()),
        'position_ms': position,
        'duration_ms': math.max(0, duration),
        'last_accessed': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
    });
  }

  Future<Map<String, Object?>?> _progressRow(
    sqlite.DatabaseExecutor executor,
    String accountId,
    String itemId,
  ) async {
    final rows = await executor.query(
      'watch_history',
      columns: ['position_ms', 'duration_ms'],
      where: 'account_id = ? AND media_id = ?',
      whereArgs: [accountId, itemId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<dynamic> cachedJson(
    String accountId,
    String key, {
    Duration maxAge = const Duration(hours: 6),
  }) async {
    final rows = await _database.query(
      'provider_cache',
      where: 'account_id = ? AND cache_key = ?',
      whereArgs: [accountId, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final age =
        DateTime.now().millisecondsSinceEpoch - intValue(row['updated_at']);
    if (age > maxAge.inMilliseconds || age < 0) return null;
    try {
      return jsonDecode(row['data_json']! as String);
    } on FormatException {
      return null;
    }
  }

  Future<void> cacheJson(String accountId, String key, dynamic data) async {
    await _database.insert('provider_cache', {
      'account_id': accountId,
      'cache_key': key,
      'data_json': jsonEncode(data),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
  }

  static Future<void> _createPreferences(
    sqlite.DatabaseExecutor db,
  ) => db.execute(
    'CREATE TABLE IF NOT EXISTS app_preferences (account_id TEXT PRIMARY KEY, data_json TEXT NOT NULL)',
  );
  Future<AppSettings> readSettings(String accountId) async {
    final rows = await _database.query(
      'app_preferences',
      where: 'account_id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty) return const AppSettings();
    return AppSettings.fromJson(
      objectValue(jsonDecode(rows.single['data_json']! as String)),
    );
  }

  Future<void> saveSettings(String accountId, AppSettings settings) =>
      _database.insert('app_preferences', {
        'account_id': accountId,
        'data_json': jsonEncode(settings.toJson()),
      }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
  Future<void> clearCache(String accountId) => _database.delete(
    'provider_cache',
    where: 'account_id = ?',
    whereArgs: [accountId],
  );
  String _pinKey(String accountId) => 'streamline.parental.$accountId';
  Future<bool> hasPin(String accountId) async =>
      await _secureStorage.read(key: _pinKey(accountId)) != null;
  Future<void> setPin(String accountId, String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const FormatException('Use four to eight digits.');
    }
    final salt = base64Encode(
      List<int>.generate(16, (_) => math.Random.secure().nextInt(256)),
    );
    final digest = await compute(deriveParentalPin, [pin, salt]);
    await _secureStorage.write(
      key: _pinKey(accountId),
      value: jsonEncode({
        'salt': salt,
        'digest': digest,
        'failures': 0,
        'until': 0,
      }),
    );
  }

  Future<void> _pinChecks = Future.value();
  Future<int> verifyPin(String accountId, String pin) {
    final check = _pinChecks.then((_) => _verifyPin(accountId, pin));
    _pinChecks = check.then<void>((_) {}, onError: (Object _) {});
    return check;
  }

  Future<int> _verifyPin(String accountId, String pin) async {
    final raw = await _secureStorage.read(key: _pinKey(accountId));
    if (raw == null) return 0;
    final record = objectValue(jsonDecode(raw));
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = intValue(record['until']);
    if (until > now) return ((until - now) / 1000).ceil();
    final digest = await compute(deriveParentalPin, [
      pin,
      textValue(record['salt']),
    ]);
    final expected = textValue(record['digest']);
    var difference = digest.length ^ expected.length;
    for (
      var index = 0;
      index < math.min(digest.length, expected.length);
      index++
    ) {
      difference |= digest.codeUnitAt(index) ^ expected.codeUnitAt(index);
    }
    if (difference == 0) {
      await _secureStorage.write(
        key: _pinKey(accountId),
        value: jsonEncode({...record, 'failures': 0, 'until': 0}),
      );
      return 0;
    }
    final failures = intValue(record['failures']) + 1;
    await _secureStorage.write(
      key: _pinKey(accountId),
      value: jsonEncode({
        ...record,
        'failures': failures,
        'until': failures >= 5 ? now + 30000 : 0,
      }),
    );
    return failures >= 5 ? 30 : -1;
  }

  Future<void> removePin(String accountId) =>
      _secureStorage.delete(key: _pinKey(accountId));
  Future<void> close() => _database.close();
}

/// PBKDF2-HMAC-SHA256 runs off the UI isolate. The salted result and lockout
/// counters are stored inside Android Keystore-backed encrypted storage.
String deriveParentalPin(List<String> input) {
  final hmac = Hmac(sha256, utf8.encode(input[0]));
  final salt = base64Decode(input[1]);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final output = List<int>.of(block);
  for (var iteration = 1; iteration < 120000; iteration++) {
    block = hmac.convert(block).bytes;
    for (var index = 0; index < output.length; index++) {
      output[index] ^= block[index];
    }
  }
  return base64Encode(output);
}
