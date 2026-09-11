import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';

typedef CachedJson = ({Object? json, DateTime fetchedAt});

/// Small JSON blobs by key (pull request lists, pipeline lists) in the
/// `cache_entries` table: one row per key, replaced on each fetch, read
/// back to open a list offline before the network answers. With a
/// [namespace] (the signed-in account) keys are prefixed so two accounts
/// never share a personal list.
class JsonCache {
  const JsonCache(this._db, {String? namespace})
    : _namespace = namespace; // ignore: prefer_initializing_formals

  final AppDatabase? _db;
  final String? _namespace;

  static String prefixFor(String namespace) => '$namespace|';

  String _k(String key) =>
      _namespace == null ? key : '${prefixFor(_namespace)}$key';

  Future<CachedJson?> get(String key) async {
    final db = _db;
    if (db == null) return null;
    final row = await (db.select(
      db.cacheEntries,
    )..where((t) => t.key.equals(_k(key)))).getSingleOrNull();
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
            key: _k(key),
            json: jsonEncode(json),
            fetchedAt: DateTime.now(),
          ),
        );
  }

  /// Keys (without the namespace) starting with [prefix], newest first.
  Future<List<String>> keysWithPrefix(String prefix, {int? limit}) async {
    final db = _db;
    if (db == null) return const [];
    final full = _k(prefix);
    final query = db.select(db.cacheEntries)
      ..where((t) => t.key.like('$full%'))
      ..orderBy([(t) => OrderingTerm.desc(t.fetchedAt)]);
    if (limit != null) query.limit(limit);
    final rows = await query.get();
    final skip = full.length - prefix.length;
    return [for (final r in rows) r.key.substring(skip)];
  }

  /// Drops every entry of one account (sign-out).
  static Future<void> deleteNamespace(AppDatabase db, String namespace) =>
      (db.delete(
        db.cacheEntries,
      )..where((t) => t.key.like('${prefixFor(namespace)}%'))).go();
}
