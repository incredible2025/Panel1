import 'dart:convert';
import 'dart:math' as math;

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
        version: 1,
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

  Future<void> close() => _database.close();
}
