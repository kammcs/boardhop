import 'dart:convert';
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
    this.tzOffsetMinutes,
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
    tzOffsetMinutes: row['tz_offset_minutes'] as int?,
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

  /// Minutes east of UTC, as the app reports it on registration and with the
  /// heartbeat. The quiet window of research/14 §6 is in the device's local
  /// time and the relay has no other way to know it. Range -840..840.
  final int? tzOffsetMinutes;

  final DateTime createdAt;
  final DateTime lastSeenAt;

  /// The only part of a device token that may appear in a log line.
  String get tokenTail => token.length <= 6 ? token : token.substring(token.length - 6);

  bool get isAndroid => platform == 'android';
}

/// One organization's hook settings: the kill switch and the hash of the basic
/// auth password its service hooks post with. The secret itself is never here.
class HookOrgRow {
  const HookOrgRow({required this.org, required this.enabled, this.hookSecretHash});

  final String org;
  final bool enabled;
  final String? hookSecretHash;
}

/// One registered service-hook subscription: which subscription id belongs to
/// this org and which routing label (`HookKind.label`) it produces.
///
/// `kind` is kept as a string so the store stays free of routing types; the
/// ingest parses it and treats an unparseable row as an unknown subscription.
class HookSubscriptionRow {
  const HookSubscriptionRow({
    required this.org,
    required this.subId,
    required this.eventType,
    required this.kind,
    this.projectId,
    this.projectName,
    this.createdAt,
  });

  factory HookSubscriptionRow.fromSql(Map<String, Object?> row) => HookSubscriptionRow(
    org: row['org']! as String,
    subId: row['sub_id']! as String,
    eventType: row['event_type']! as String,
    kind: row['kind']! as String,
    projectId: row['project_id'] as String?,
    projectName: row['project_name'] as String?,
    createdAt: row['created_at'] as String?,
  );

  final String org;
  final String subId;
  final String eventType;
  final String kind;
  final String? projectId;
  final String? projectName;
  final String? createdAt;

  Map<String, Object?> toJson() => {
    'subId': subId,
    'eventType': eventType,
    'kind': kind,
    'projectId': projectId,
    'projectName': projectName,
    'createdAt': createdAt,
  };
}

/// What the relay remembers about one pull request, so the R2.2 rules can tell
/// *what changed* (research/14 §5.1). The payload is rendered at delivery time
/// and carries no before/after, so "who was added as a reviewer" and "did the
/// source commit move" are diffs against this row.
///
/// Ids and votes only: no title, no description, no name.
class PrStateRow {
  const PrStateRow({
    required this.org,
    required this.prId,
    this.status,
    this.isDraft,
    this.sourceCommit,
    this.reviewers = const <String, int>{},
    this.authorId,
    this.updatedAt,
  });

  factory PrStateRow.fromSql(Map<String, Object?> row) => PrStateRow(
    org: row['org']! as String,
    prId: row['pr_id']! as String,
    status: row['status'] as String?,
    isDraft: row['is_draft'] == null ? null : (row['is_draft']! as int) != 0,
    sourceCommit: row['source_commit'] as String?,
    reviewers: _decodeVotes(row['reviewers_json'] as String?),
    authorId: row['author_id'] as String?,
    updatedAt: row['updated_at'] as String?,
  );

  final String org;
  final String prId;
  final String? status;
  final bool? isDraft;
  final String? sourceCommit;

  /// Reviewer identity id → the vote as last delivered (10, 5, 0, −5, −10).
  final Map<String, int> reviewers;
  final String? authorId;
  final String? updatedAt;
}

/// The participants of one pull request comment thread, accumulated from every
/// comment event the relay has seen on it. The v2 comment payload does not
/// carry the thread, so this is the only way to know who else is in it.
class PrThreadStateRow {
  const PrThreadStateRow({
    required this.org,
    required this.prId,
    required this.threadId,
    this.participantIds = const <String>[],
    this.updatedAt,
  });

  factory PrThreadStateRow.fromSql(Map<String, Object?> row) => PrThreadStateRow(
    org: row['org']! as String,
    prId: row['pr_id']! as String,
    threadId: row['thread_id']! as String,
    participantIds: _decodeIds(row['participant_ids_json'] as String?),
    updatedAt: row['updated_at'] as String?,
  );

  final String org;
  final String prId;
  final String threadId;
  final List<String> participantIds;
  final String? updatedAt;
}

/// One pipeline run's requester, kept from `run-state-changed` at queue time:
/// the approval events name the requester only by display name (w25).
class RunStateRow {
  const RunStateRow({
    required this.org,
    required this.runId,
    this.pipelineId,
    this.requestedForId,
    this.requestedById,
    this.createdAt,
  });

  factory RunStateRow.fromSql(Map<String, Object?> row) => RunStateRow(
    org: row['org']! as String,
    runId: row['run_id']! as String,
    pipelineId: row['pipeline_id'] as String?,
    requestedForId: row['requested_for_id'] as String?,
    requestedById: row['requested_by_id'] as String?,
    createdAt: row['created_at'] as String?,
  );

  final String org;
  final String runId;
  final String? pipelineId;
  final String? requestedForId;
  final String? requestedById;
  final String? createdAt;
}

/// The last known result of one definition on one branch, which is all that
/// "fixed" detection needs (research/14 §2.3, D3).
class BuildStateRow {
  const BuildStateRow({
    required this.org,
    required this.projectId,
    required this.definitionId,
    required this.branch,
    this.lastResult,
    this.buildId,
    this.updatedAt,
  });

  factory BuildStateRow.fromSql(Map<String, Object?> row) => BuildStateRow(
    org: row['org']! as String,
    projectId: row['project_id']! as String,
    definitionId: row['definition_id']! as String,
    branch: row['branch']! as String,
    lastResult: row['last_result'] as String?,
    buildId: row['build_id'] as String?,
    updatedAt: row['updated_at'] as String?,
  );

  final String org;
  final String projectId;
  final String definitionId;
  final String branch;
  final String? lastResult;
  final String? buildId;
  final String? updatedAt;

  /// The three results a later success counts as a fix of.
  bool get wasFailure => const {'failed', 'partiallysucceeded', 'canceled'}.contains(lastResult?.toLowerCase());
}

/// The one deliberate exception to "no names in the state tables": the app's
/// routes take a project **name** and the pipelines publisher sends only an id
/// (research/14 §5.1, §2.1 note), so the relay keeps the map it sees.
class ProjectRow {
  const ProjectRow({required this.org, required this.projectId, required this.projectName, this.updatedAt});

  final String org;
  final String projectId;
  final String projectName;
  final String? updatedAt;
}

Map<String, int> _decodeVotes(String? json) {
  if (json == null || json.isEmpty) return const <String, int>{};
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const <String, int>{};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is int) entry.key! as String: entry.value! as int,
    };
  } catch (_) {
    return const <String, int>{};
  }
}

List<String> _decodeIds(String? json) {
  if (json == null || json.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const <String>[];
    return [
      for (final value in decoded)
        if (value is String) value,
    ];
  } catch (_) {
    return const <String>[];
  }
}

/// The relay's store: organizations (kill switch, hook secret), the devices
/// registered for them, the service-hook registry and the small per-artifact
/// routing state of research/14 §5.1.
class RelayDb {
  RelayDb._(this._db, this.path);

  final Database _db;
  final String path;

  /// 1 — the R0 skeleton (`meta` only).
  /// 2 — R1: `orgs` and `devices`.
  /// 3 — R2.1: `hook_subscriptions` and `hook_deliveries`.
  /// 4 — R2.2: the routing state of research/14 §5.1 plus `notification_sends`.
  /// 5 — R2.3: `user_prefs` (research/14 §6) and `devices.tz_offset_minutes`.
  static const schemaVersion = 5;

  /// Delivery rows older than this are pruned; Azure DevOps stops retrying one
  /// delivery long before it (research/14 §5.2 rule 4).
  static const deliveryRetention = Duration(hours: 24);

  /// `pr_state`, `pr_thread_state`, `run_state` and `build_state` rows expire
  /// this long after their last update (research/14 §5.1).
  static const routingStateRetention = Duration(days: 90);

  /// Long enough for the hourly per-user cap and for "one notification per
  /// person per event" to outlive every retry of that event.
  static const sendLedgerRetention = Duration(hours: 24);

  /// Pruning is opportunistic: one sweep every this many inserts.
  static const _pruneEvery = 200;

  var _deliveryInserts = 0;
  var _routingWrites = 0;

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

    // R2.1. The subscription registry: a post whose subscription id is not here
    // is answered 404 and dropped, exactly like a wrong secret.
    db.execute(
      'CREATE TABLE IF NOT EXISTS hook_subscriptions ('
      '  org          TEXT NOT NULL,'
      '  sub_id       TEXT NOT NULL,'
      '  event_type   TEXT NOT NULL,'
      '  kind         TEXT NOT NULL,'
      '  project_id   TEXT,'
      '  project_name TEXT,'
      '  created_at   TEXT NOT NULL,'
      '  PRIMARY KEY (org, sub_id)'
      ');',
    );
    // Idempotency across the retries of one delivery. Ids only: no body, no
    // name, nothing that came out of a payload's content.
    db.execute(
      'CREATE TABLE IF NOT EXISTS hook_deliveries ('
      '  org         TEXT NOT NULL,'
      '  sub_id      TEXT NOT NULL,'
      '  activity_id TEXT NOT NULL,'
      '  received_at TEXT NOT NULL,'
      '  PRIMARY KEY (org, sub_id, activity_id)'
      ');',
    );
    db.execute('CREATE INDEX IF NOT EXISTS hook_deliveries_age ON hook_deliveries (received_at);');

    // R2.2, research/14 §5.1. Every column below is an id, a status word, a
    // commit sha, a branch ref, a vote or a timestamp — deliberately nothing
    // that could hold a title, a display name or any text from a body. The one
    // exception is `projects.project_name`, which exists because the app's
    // routes take a project name and the pipelines publisher sends only an id.
    db.execute(
      'CREATE TABLE IF NOT EXISTS pr_state ('
      '  org           TEXT NOT NULL,'
      '  pr_id         TEXT NOT NULL,'
      '  status        TEXT,'
      '  is_draft      INTEGER,'
      '  source_commit TEXT,'
      '  reviewers_json TEXT NOT NULL DEFAULT \'{}\','
      '  author_id     TEXT,'
      '  updated_at    TEXT NOT NULL,'
      '  PRIMARY KEY (org, pr_id)'
      ');',
    );
    db.execute('CREATE INDEX IF NOT EXISTS pr_state_age ON pr_state (updated_at);');
    db.execute(
      'CREATE TABLE IF NOT EXISTS pr_thread_state ('
      '  org                  TEXT NOT NULL,'
      '  pr_id                TEXT NOT NULL,'
      '  thread_id            TEXT NOT NULL,'
      '  participant_ids_json TEXT NOT NULL DEFAULT \'[]\','
      '  updated_at           TEXT NOT NULL,'
      '  PRIMARY KEY (org, pr_id, thread_id)'
      ');',
    );
    db.execute('CREATE INDEX IF NOT EXISTS pr_thread_state_age ON pr_thread_state (updated_at);');
    db.execute(
      'CREATE TABLE IF NOT EXISTS run_state ('
      '  org               TEXT NOT NULL,'
      '  run_id            TEXT NOT NULL,'
      '  pipeline_id       TEXT,'
      '  requested_for_id  TEXT,'
      '  requested_by_id   TEXT,'
      '  created_at        TEXT NOT NULL,'
      '  PRIMARY KEY (org, run_id)'
      ');',
    );
    db.execute('CREATE INDEX IF NOT EXISTS run_state_age ON run_state (created_at);');
    db.execute(
      'CREATE TABLE IF NOT EXISTS build_state ('
      '  org           TEXT NOT NULL,'
      '  project_id    TEXT NOT NULL,'
      '  definition_id TEXT NOT NULL,'
      '  branch        TEXT NOT NULL,'
      '  last_result   TEXT,'
      '  build_id      TEXT,'
      '  updated_at    TEXT NOT NULL,'
      '  PRIMARY KEY (org, project_id, definition_id, branch)'
      ');',
    );
    db.execute('CREATE INDEX IF NOT EXISTS build_state_age ON build_state (updated_at);');
    db.execute(
      'CREATE TABLE IF NOT EXISTS projects ('
      '  org          TEXT NOT NULL,'
      '  project_id   TEXT NOT NULL,'
      '  project_name TEXT NOT NULL,'
      '  updated_at   TEXT NOT NULL,'
      '  PRIMARY KEY (org, project_id)'
      ');',
    );
    // The per-user hourly cap and the "one notification per person per event"
    // guarantee of research/14 §5.2 rules 2 and 6, as four columns of ids.
    db.execute(
      'CREATE TABLE IF NOT EXISTS notification_sends ('
      '  org       TEXT NOT NULL,'
      '  event_key TEXT NOT NULL,'
      '  user_id   TEXT NOT NULL,'
      '  sent_at   TEXT NOT NULL,'
      '  PRIMARY KEY (org, event_key, user_id)'
      ');',
    );
    db.execute('CREATE INDEX IF NOT EXISTS notification_sends_user ON notification_sends (org, user_id, sent_at);');

    // R2.3, research/14 §6 and D5. The document is a JSON blob of switches and
    // closed vocabularies — `on`, `mentionsOnly`, `failures`, `"22:00"`, a list
    // of `(family, id, until)` mutes — so this table holds no content either.
    db.execute(
      'CREATE TABLE IF NOT EXISTS user_prefs ('
      '  org        TEXT NOT NULL,'
      '  user_id    TEXT NOT NULL,'
      '  prefs_json TEXT NOT NULL,'
      '  updated_at TEXT NOT NULL,'
      '  PRIMARY KEY (org, user_id)'
      ');',
    );
    // Additive, and guarded: a database created at schema 2 already has
    // `devices` and only needs the column.
    _addColumn(db, 'devices', 'tz_offset_minutes', 'INTEGER');

    db.execute('INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;', [
      'schema_version',
      '$schemaVersion',
    ]);
  }

  /// `ALTER TABLE ... ADD COLUMN`, but only when the column is not there yet:
  /// SQLite has no `IF NOT EXISTS` for a column and the migration re-runs on
  /// every start.
  static void _addColumn(Database db, String table, String column, String type) {
    for (final row in db.select('PRAGMA table_info($table);')) {
      if (row['name'] == column) return;
    }
    db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
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

  /// The hook settings for one org, or null when the org has never been seen.
  HookOrgRow? hookOrg(String org) {
    final rows = _db.select('SELECT org, enabled, hook_secret_hash FROM orgs WHERE org = ?;', [org]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return HookOrgRow(
      org: row['org']! as String,
      enabled: (row['enabled'] as int? ?? 1) != 0,
      hookSecretHash: row['hook_secret_hash'] as String?,
    );
  }

  /// Stores the **hash** of an org's hook secret, creating the org enabled if
  /// it is new. The secret itself never reaches this class.
  void setHookSecretHash(String org, String hash) {
    ensureOrg(org);
    _db.execute('UPDATE orgs SET hook_secret_hash = ? WHERE org = ?;', [hash, org]);
  }

  // ------------------------------------------------------ hook subscriptions

  HookSubscriptionRow? hookSubscription(String org, String subId) {
    final rows = _db.select('SELECT * FROM hook_subscriptions WHERE org = ? AND sub_id = ?;', [org, subId]);
    return rows.isEmpty ? null : HookSubscriptionRow.fromSql(rows.first);
  }

  List<HookSubscriptionRow> hookSubscriptions(String org) => [
    for (final row in _db.select('SELECT * FROM hook_subscriptions WHERE org = ? ORDER BY sub_id;', [org]))
      HookSubscriptionRow.fromSql(row),
  ];

  /// Replaces an org's whole set in one transaction: either the new set is
  /// there or the old one still is, never a half-applied mixture.
  int replaceHookSubscriptions(String org, List<HookSubscriptionRow> rows) {
    ensureOrg(org);
    final now = _now();
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute('DELETE FROM hook_subscriptions WHERE org = ?;', [org]);
      for (final row in rows) {
        _db.execute(
          'INSERT INTO hook_subscriptions (org, sub_id, event_type, kind, project_id, project_name, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?);',
          [org, row.subId, row.eventType, row.kind, row.projectId, row.projectName, row.createdAt ?? now],
        );
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
    return rows.length;
  }

  // --------------------------------------------------------- hook deliveries

  /// Records one delivery attempt. False means this `(org, subId, activityId)`
  /// has been seen already: a retry, to be answered 200 and processed no
  /// further (research/14 §5.2 rule 4).
  bool recordHookDelivery({required String org, required String subId, required String activityId}) {
    _db.execute(
      'INSERT INTO hook_deliveries (org, sub_id, activity_id, received_at) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (org, sub_id, activity_id) DO NOTHING;',
      [org, subId, activityId, _now()],
    );
    final inserted = _db.updatedRows > 0;
    if (inserted && ++_deliveryInserts % _pruneEvery == 0) {
      pruneHookDeliveries(DateTime.now().toUtc().subtract(deliveryRetention));
    }
    return inserted;
  }

  /// Drops delivery rows received before [before]. Returns how many went.
  int pruneHookDeliveries(DateTime before) {
    _db.execute('DELETE FROM hook_deliveries WHERE received_at < ?;', [before.toUtc().toIso8601String()]);
    return _db.updatedRows;
  }

  int hookDeliveryCount() {
    final rows = _db.select('SELECT COUNT(*) AS n FROM hook_deliveries;');
    return rows.isEmpty ? 0 : rows.first['n']! as int;
  }

  // --------------------------------------------------------- routing state

  PrStateRow? prState(String org, String prId) {
    final rows = _db.select('SELECT * FROM pr_state WHERE org = ? AND pr_id = ?;', [org, prId]);
    return rows.isEmpty ? null : PrStateRow.fromSql(rows.first);
  }

  void savePrState(PrStateRow row) {
    _db.execute(
      'INSERT INTO pr_state (org, pr_id, status, is_draft, source_commit, reviewers_json, author_id, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (org, pr_id) DO UPDATE SET '
      '  status = excluded.status, is_draft = excluded.is_draft, source_commit = excluded.source_commit, '
      '  reviewers_json = excluded.reviewers_json, author_id = excluded.author_id, '
      '  updated_at = excluded.updated_at;',
      [
        row.org,
        row.prId,
        row.status,
        row.isDraft == null ? null : (row.isDraft! ? 1 : 0),
        row.sourceCommit,
        jsonEncode(row.reviewers),
        row.authorId,
        row.updatedAt ?? _now(),
      ],
    );
    _afterRoutingWrite();
  }

  PrThreadStateRow? prThreadState(String org, String prId, String threadId) {
    final rows = _db.select('SELECT * FROM pr_thread_state WHERE org = ? AND pr_id = ? AND thread_id = ?;', [
      org,
      prId,
      threadId,
    ]);
    return rows.isEmpty ? null : PrThreadStateRow.fromSql(rows.first);
  }

  void savePrThreadState(PrThreadStateRow row) {
    _db.execute(
      'INSERT INTO pr_thread_state (org, pr_id, thread_id, participant_ids_json, updated_at) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT (org, pr_id, thread_id) DO UPDATE SET '
      '  participant_ids_json = excluded.participant_ids_json, updated_at = excluded.updated_at;',
      [row.org, row.prId, row.threadId, jsonEncode(row.participantIds), row.updatedAt ?? _now()],
    );
    _afterRoutingWrite();
  }

  RunStateRow? runState(String org, String runId) {
    final rows = _db.select('SELECT * FROM run_state WHERE org = ? AND run_id = ?;', [org, runId]);
    return rows.isEmpty ? null : RunStateRow.fromSql(rows.first);
  }

  void saveRunState(RunStateRow row) {
    _db.execute(
      'INSERT INTO run_state (org, run_id, pipeline_id, requested_for_id, requested_by_id, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (org, run_id) DO UPDATE SET '
      '  pipeline_id = COALESCE(excluded.pipeline_id, run_state.pipeline_id), '
      '  requested_for_id = COALESCE(excluded.requested_for_id, run_state.requested_for_id), '
      '  requested_by_id = COALESCE(excluded.requested_by_id, run_state.requested_by_id);',
      [row.org, row.runId, row.pipelineId, row.requestedForId, row.requestedById, row.createdAt ?? _now()],
    );
    _afterRoutingWrite();
  }

  BuildStateRow? buildState(String org, String projectId, String definitionId, String branch) {
    final rows = _db.select(
      'SELECT * FROM build_state WHERE org = ? AND project_id = ? AND definition_id = ? AND branch = ?;',
      [org, projectId, definitionId, branch],
    );
    return rows.isEmpty ? null : BuildStateRow.fromSql(rows.first);
  }

  void saveBuildState(BuildStateRow row) {
    _db.execute(
      'INSERT INTO build_state (org, project_id, definition_id, branch, last_result, build_id, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (org, project_id, definition_id, branch) DO UPDATE SET '
      '  last_result = excluded.last_result, build_id = excluded.build_id, updated_at = excluded.updated_at;',
      [row.org, row.projectId, row.definitionId, row.branch, row.lastResult, row.buildId, row.updatedAt ?? _now()],
    );
    _afterRoutingWrite();
  }

  /// The project name for an id, when some payload has carried both.
  String? projectName(String org, String projectId) {
    final rows = _db.select('SELECT project_name FROM projects WHERE org = ? AND project_id = ?;', [org, projectId]);
    return rows.isEmpty ? null : rows.first['project_name'] as String?;
  }

  void saveProject(String org, String projectId, String projectName) {
    _db.execute(
      'INSERT INTO projects (org, project_id, project_name, updated_at) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (org, project_id) DO UPDATE SET project_name = excluded.project_name, '
      '  updated_at = excluded.updated_at;',
      [org, projectId, projectName, _now()],
    );
  }

  /// Drops routing state untouched since [before]. Returns how many rows went.
  int pruneRoutingState(DateTime before) {
    final cutoff = before.toUtc().toIso8601String();
    var removed = 0;
    for (final statement in [
      'DELETE FROM pr_state WHERE updated_at < ?;',
      'DELETE FROM pr_thread_state WHERE updated_at < ?;',
      'DELETE FROM run_state WHERE created_at < ?;',
      'DELETE FROM build_state WHERE updated_at < ?;',
    ]) {
      _db.execute(statement, [cutoff]);
      removed += _db.updatedRows;
    }
    return removed;
  }

  void _afterRoutingWrite() {
    if (++_routingWrites % _pruneEvery != 0) return;
    final now = DateTime.now().toUtc();
    pruneRoutingState(now.subtract(routingStateRetention));
    pruneNotificationSends(now.subtract(sendLedgerRetention));
  }

  // ------------------------------------------------------ notification sends

  /// Claims the right to notify [userId] about [eventKey]. False means this
  /// person has already been notified about this event (research/14 §5.2
  /// rule 2), which is also what makes a replayed event send nothing twice.
  bool claimNotificationSend({required String org, required String eventKey, required String userId, DateTime? at}) {
    _db.execute(
      'INSERT INTO notification_sends (org, event_key, user_id, sent_at) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (org, event_key, user_id) DO NOTHING;',
      [org, eventKey, userId, (at ?? DateTime.now().toUtc()).toIso8601String()],
    );
    return _db.updatedRows > 0;
  }

  /// How many notifications this identity has been sent in this org since
  /// [since] — the hourly cap of research/14 §5.2 rule 6.
  int notificationSendCount({required String org, required String userId, required DateTime since}) {
    final rows = _db.select(
      'SELECT COUNT(*) AS n FROM notification_sends WHERE org = ? AND user_id = ? AND sent_at >= ?;',
      [org, userId, since.toUtc().toIso8601String()],
    );
    return rows.isEmpty ? 0 : rows.first['n']! as int;
  }

  int pruneNotificationSends(DateTime before) {
    _db.execute('DELETE FROM notification_sends WHERE sent_at < ?;', [before.toUtc().toIso8601String()]);
    return _db.updatedRows;
  }

  // ------------------------------------------------------------ user prefs

  /// The stored preference document for one identity in one org, or null when
  /// they have never saved one (research/14 §6). The relay keeps the JSON as it
  /// was validated; parsing it is the routing layer's business.
  String? userPrefs(String org, String userId) {
    final rows = _db.select('SELECT prefs_json FROM user_prefs WHERE org = ? AND user_id = ?;', [org, userId]);
    return rows.isEmpty ? null : rows.first['prefs_json'] as String?;
  }

  void saveUserPrefs({required String org, required String userId, required String prefsJson}) {
    ensureOrg(org);
    _db.execute(
      'INSERT INTO user_prefs (org, user_id, prefs_json, updated_at) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (org, user_id) DO UPDATE SET prefs_json = excluded.prefs_json, '
      '  updated_at = excluded.updated_at;',
      [org, userId, prefsJson, _now()],
    );
  }

  /// The time-zone offset of this identity's most recently seen device, for the
  /// quiet window. Null when no device of theirs has reported one.
  int? timeZoneOffsetMinutes(String org, String userId) {
    final rows = _db.select(
      'SELECT tz_offset_minutes FROM devices WHERE org = ? AND user_id = ? AND tz_offset_minutes IS NOT NULL '
      'ORDER BY last_seen_at DESC LIMIT 1;',
      [org, userId],
    );
    return rows.isEmpty ? null : rows.first['tz_offset_minutes'] as int?;
  }

  /// Every column of every table, for the schema assertion in `dart test`.
  Map<String, List<String>> schemaColumns() {
    final out = <String, List<String>>{};
    for (final table in _db.select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;")) {
      final name = table['name']! as String;
      if (name.startsWith('sqlite_')) continue;
      out[name] = [for (final column in _db.select('PRAGMA table_info($name);')) column['name']! as String];
    }
    return out;
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
    int? tzOffsetMinutes,
  }) {
    final now = _now();
    final existing = _db.select('SELECT id, created_at FROM devices WHERE org = ? AND token = ?;', [org, token]);
    final id = existing.isEmpty ? newUuid() : existing.first['id']! as String;
    final createdAt = existing.isEmpty ? now : existing.first['created_at']! as String;
    _db.execute(
      'INSERT INTO devices (id, org, user_id, user_descriptor, platform, token, app_version, locale, '
      '                     tz_offset_minutes, created_at, last_seen_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (org, token) DO UPDATE SET '
      '  user_id = excluded.user_id, '
      '  user_descriptor = excluded.user_descriptor, '
      '  platform = excluded.platform, '
      '  app_version = excluded.app_version, '
      '  locale = excluded.locale, '
      '  tz_offset_minutes = COALESCE(excluded.tz_offset_minutes, devices.tz_offset_minutes), '
      '  last_seen_at = excluded.last_seen_at;',
      [id, org, userId, userDescriptor, platform, token, appVersion, locale, tzOffsetMinutes, createdAt, now],
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
  DeviceRow? heartbeat(String id, {String? token, String? appVersion, String? locale, int? tzOffsetMinutes}) {
    final current = deviceById(id);
    if (current == null) return null;
    _db.execute(
      'UPDATE devices SET last_seen_at = ?, token = ?, app_version = COALESCE(?, app_version), '
      'locale = COALESCE(?, locale), tz_offset_minutes = COALESCE(?, tz_offset_minutes) WHERE id = ?;',
      [_now(), token ?? current.token, appVersion, locale, tzOffsetMinutes, id],
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
