import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

import 'log.dart';

/// One registered phone: which organization it was registered for, which
/// Azure DevOps identity owns it, and the APNs/FCM token to wake it with.
///
/// The bearer token the app presented at registration is **not** part of this
/// row: it is validated once against the org and then thrown away.
class DeviceRow {
  const DeviceRow({
    required this.id,
    required this.org,
    required this.userId,
    required this.platform,
    required this.token,
    required this.createdAt,
    required this.lastSeenAt,
    this.userDescriptor,
    this.appVersion,
    this.locale,
  });

  factory DeviceRow.fromSql(Map<String, Object?> row) => DeviceRow(
    id: row['id']! as String,
    org: row['org']! as String,
    userId: row['user_id']! as String,
    platform: row['platform']! as String,
    token: row['token']! as String,
    userDescriptor: row['user_descriptor'] as String?,
    appVersion: row['app_version'] as String?,
    locale: row['locale'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String),
    lastSeenAt: DateTime.parse(row['last_seen_at']! as String),
  );

  final String id;
  final String org;
  final String userId;

  /// `android` or `ios`.
  final String platform;

  /// The APNs or FCM device token. Never logged in full: see [tokenTail].
  final String token;
  final String? userDescriptor;
  final String? appVersion;
  final String? locale;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  /// The only part of a device token that may appear in a log line.
  String get tokenTail => token.length <= 6 ? token : token.substring(token.length - 6);

  bool get isAndroid => platform == 'android';
}

/// The relay's store: organizations (kill switch, hook secret) and the devices
/// registered for them.
class RelayDb {
  RelayDb._(this._db, this.path);

  final Database _db;
  final String path;

  /// 1 — the R0 skeleton (`meta` only).
  /// 2 — R1: `orgs` and `devices`.
  static const schemaVersion = 2;

  static var _libraryResolved = false;

  /// Debian ships the runtime library as `libsqlite3.so.0`; the bare
  /// `libsqlite3.so` the package looks for belongs to the -dev package, which
  /// has no business in a runtime image. On Windows (a developer box running
  /// `dart test`) there is no `sqlite3.dll` either, but the OS ships
  /// `winsqlite3.dll`, which exports the same C API.
  static void _resolveLibrary() {
    if (_libraryResolved) return;
    _libraryResolved = true;
    if (Platform.isLinux) {
      sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
        try {
          return DynamicLibrary.open('libsqlite3.so');
        } catch (_) {
          return DynamicLibrary.open('libsqlite3.so.0');
        }
      });
    } else if (Platform.isWindows) {
      sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.windows, () {
        try {
          return DynamicLibrary.open('sqlite3.dll');
        } catch (_) {
          return DynamicLibrary.open('winsqlite3.dll');
        }
      });
    }
  }

  /// Opens (and creates) the database at [path]. Returns null and logs when the
  /// file or the native library is unusable; the relay still serves /healthz so
  /// the failure is visible rather than a crash loop.
  static RelayDb? open(String path) {
    try {
      _resolveLibrary();
      if (path != ':memory:') {
        final dir = File(path).parent;
        if (!dir.existsSync()) dir.createSync(recursive: true);
      }
      final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
      if (path != ':memory:') db.execute('PRAGMA journal_mode = WAL;');
      _migrate(db);
      return RelayDb._(db, path);
    } catch (e) {
      logEvent('database open failed', level: 'error', fields: {'path': path, 'error': '$e'});
      return null;
    }
  }

  /// An in-memory database, for tests.
  static RelayDb? openMemory() => open(':memory:');

  static void _migrate(Database db) {
    db.execute('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);');

    // R1. Everything here is additive and guarded, so the migration re-runs
    // harmlessly on a database that already has it.
    db.execute(
      'CREATE TABLE IF NOT EXISTS orgs ('
      '  org              TEXT PRIMARY KEY,'
      '  enabled          INTEGER NOT NULL DEFAULT 1,'
      '  hook_secret_hash TEXT,'
      '  created_at       TEXT NOT NULL'
      ');',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS devices ('
      '  id              TEXT PRIMARY KEY,'
      '  org             TEXT NOT NULL,'
      '  user_id         TEXT NOT NULL,'
      '  user_descriptor TEXT,'
      '  platform        TEXT NOT NULL,'
      '  token           TEXT NOT NULL,'
      '  app_version     TEXT,'
      '  locale          TEXT,'
      '  created_at      TEXT NOT NULL,'
      '  last_seen_at    TEXT NOT NULL,'
      '  UNIQUE (org, token)'
      ');',
    );
    db.execute('CREATE INDEX IF NOT EXISTS devices_org_user ON devices (org, user_id);');
    db.execute('CREATE INDEX IF NOT EXISTS devices_token ON devices (token);');

    db.execute('INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;', [
      'schema_version',
      '$schemaVersion',
    ]);
  }

  String get sqliteVersion => sqlite3.version.libVersion;

  static String _now() => DateTime.now().toUtc().toIso8601String();

  // ------------------------------------------------------------------ orgs

  /// Creates the org row on first sight. Organizations start enabled; the kill
  /// switch is `UPDATE orgs SET enabled = 0` on the box.
  void ensureOrg(String org) => _db.execute(
    'INSERT INTO orgs (org, enabled, created_at) VALUES (?, 1, ?) ON CONFLICT(org) DO NOTHING;',
    [org, _now()],
  );

  /// False only when an org row exists and has been switched off.
  bool orgEnabled(String org) {
    final rows = _db.select('SELECT enabled FROM orgs WHERE org = ?;', [org]);
    if (rows.isEmpty) return true;
    return (rows.first['enabled'] as int? ?? 1) != 0;
  }

  /// The kill switch: `enabled = 0` stops registration and pushes for one org
  /// without touching the others.
  void setOrgEnabled(String org, bool enabled) {
    ensureOrg(org);
    _db.execute('UPDATE orgs SET enabled = ? WHERE org = ?;', [enabled ? 1 : 0, org]);
  }

  // --------------------------------------------------------------- devices

  /// Idempotent on `(org, token)`: the same phone registering again keeps its
  /// device id and refreshes everything else.
  DeviceRow registerDevice({
    required String org,
    required String userId,
    required String platform,
    required String token,
    String? userDescriptor,
    String? appVersion,
    String? locale,
  }) {
    final now = _now();
    final existing = _db.select('SELECT id, created_at FROM devices WHERE org = ? AND token = ?;', [org, token]);
    final id = existing.isEmpty ? newUuid() : existing.first['id']! as String;
    final createdAt = existing.isEmpty ? now : existing.first['created_at']! as String;
    _db.execute(
      'INSERT INTO devices (id, org, user_id, user_descriptor, platform, token, app_version, locale, '
      '                     created_at, last_seen_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (org, token) DO UPDATE SET '
      '  user_id = excluded.user_id, '
      '  user_descriptor = excluded.user_descriptor, '
      '  platform = excluded.platform, '
      '  app_version = excluded.app_version, '
      '  locale = excluded.locale, '
      '  last_seen_at = excluded.last_seen_at;',
      [id, org, userId, userDescriptor, platform, token, appVersion, locale, createdAt, now],
    );
    return deviceById(id)!;
  }

  DeviceRow? deviceById(String id) {
    final rows = _db.select('SELECT * FROM devices WHERE id = ?;', [id]);
    return rows.isEmpty ? null : DeviceRow.fromSql(rows.first);
  }

  /// Every device the identity has registered for that org.
  List<DeviceRow> devicesFor(String org, String userId) => [
    for (final row in _db.select('SELECT * FROM devices WHERE org = ? AND user_id = ? ORDER BY created_at;', [
      org,
      userId,
    ]))
      DeviceRow.fromSql(row),
  ];

  /// Moves the device's `last_seen_at` and, when the platform rotated it, its
  /// token. Returns the refreshed row, or null when the device is gone.
  DeviceRow? heartbeat(String id, {String? token, String? appVersion, String? locale}) {
    final current = deviceById(id);
    if (current == null) return null;
    _db.execute(
      'UPDATE devices SET last_seen_at = ?, token = ?, app_version = COALESCE(?, app_version), '
      'locale = COALESCE(?, locale) WHERE id = ?;',
      [_now(), token ?? current.token, appVersion, locale, id],
    );
    return deviceById(id);
  }

  bool deleteDevice(String id) {
    _db.execute('DELETE FROM devices WHERE id = ?;', [id]);
    return _db.updatedRows > 0;
  }

  /// APNs `410 BadDeviceToken` and FCM `UNREGISTERED` mean the install is gone,
  /// so the token is dead everywhere, not only for the org that just pushed.
  int deleteByToken(String token) {
    _db.execute('DELETE FROM devices WHERE token = ?;', [token]);
    return _db.updatedRows;
  }

  /// Counts by platform for `/v1/admin/devices`. Never returns a token.
  Map<String, int> deviceCounts(String org) {
    final out = <String, int>{};
    for (final row in _db.select('SELECT platform, COUNT(*) AS n FROM devices WHERE org = ? GROUP BY platform;', [
      org,
    ])) {
      out[row['platform']! as String] = row['n']! as int;
    }
    return out;
  }

  /// Distinct identities registered for an org.
  int userCount(String org) {
    final rows = _db.select('SELECT COUNT(DISTINCT user_id) AS n FROM devices WHERE org = ?;', [org]);
    return rows.isEmpty ? 0 : rows.first['n']! as int;
  }

  void close() => _db.dispose();
}

final _random = Random.secure();

/// A random (version 4) UUID. One small function instead of a dependency.
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [for (var i = from; i < to; i++) bytes[i].toRadixString(16).padLeft(2, '0')].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
