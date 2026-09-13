import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

import 'log.dart';

/// The relay's store. Empty in this skeleton beyond a schema marker: opening it
/// at startup proves the native SQLite library is present in the runtime image,
/// and the device/registration tables land here in the next phase.
class RelayDb {
  RelayDb._(this._db, this.path);

  final Database _db;
  final String path;

  static const schemaVersion = 1;

  /// Opens (and creates) the database at [path]. Returns null and logs when the
  /// file or the native library is unusable; the relay still serves /healthz so
  /// the failure is visible rather than a crash loop.
  static var _libraryResolved = false;

  /// Debian ships the runtime library as `libsqlite3.so.0`; the bare
  /// `libsqlite3.so` the package looks for belongs to the -dev package, which
  /// has no business in a runtime image.
  static void _resolveLibrary() {
    if (_libraryResolved || !Platform.isLinux) return;
    _libraryResolved = true;
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } catch (_) {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
  }

  static RelayDb? open(String path) {
    try {
      _resolveLibrary();
      final dir = File(path).parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final db = sqlite3.open(path);
      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);');
      db.execute(
        'INSERT INTO meta (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value;',
        ['schema_version', '$schemaVersion'],
      );
      return RelayDb._(db, path);
    } catch (e) {
      logEvent('database open failed', level: 'error', fields: {'path': path, 'error': '$e'});
      return null;
    }
  }

  String get sqliteVersion => sqlite3.version.libVersion;

  void close() => _db.dispose();
}
