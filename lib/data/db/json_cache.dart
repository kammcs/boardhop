import 'dart:convert';

import 'app_database.dart';

typedef CachedJson = ({Object? json, DateTime fetchedAt});

/// Small JSON blobs by key (pull request lists, pipeline lists) in the
/// `cache_entries` table: one row per key, replaced on each fetch, read
/// back to open a list offline before the network answers.
class JsonCache {
  const JsonCache(this._db);

  final AppDatabase? _db;

  Future<CachedJson?> get(String key) async {
    final db = _db;
    if (db == null) return null;
    final row = await (db.select(
      db.cacheEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    return (json: jsonDecode(row.json), fetchedAt: row.fetchedAt);
  }

  Future<void> put(String key, Object json) async {
    final db = _db;
    if (db == null) return;
    await db
        .into(db.cacheEntries)
        .insertOnConflictUpdate(
          CacheEntriesCompanion.insert(
            key: key,
            json: jsonEncode(json),
            fetchedAt: DateTime.now(),
          ),
        );
  }
}
