import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/http/ado_exceptions.dart';
import 'db/app_database.dart';
import 'models/work_item.dart';
import 'repositories/work_item_repository.dart';

/// A write that could not reach the service and waits in drift
/// (decision from research/00: queued writes replayed with `test /rev`,
/// surfaced as conflicts on 412 rather than overwritten).
class PendingWrite {
  const PendingWrite({
    required this.id,
    required this.kind,
    required this.org,
    required this.project,
    required this.targetId,
    required this.description,
    required this.createdAt,
    required this.attempts,
    this.lastError,
    this.rev,
    this.ops = const [],
    this.text,
  });

  factory PendingWrite.fromRow(PendingWriteRow row) {
    final payload = (jsonDecode(row.payload) as Map).cast<String, dynamic>();
    return PendingWrite(
      id: row.id,
      kind: row.kind,
      org: row.orgName,
      project: payload['project'] as String? ?? '',
      targetId: int.tryParse(row.targetId) ?? 0,
      description: payload['description'] as String? ?? row.kind,
      createdAt: row.createdAt,
      attempts: row.attempts,
      lastError: row.lastError,
      rev: payload['rev'] as int?,
      ops: ((payload['ops'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList(),
      text: payload['text'] as String?,
    );
  }

  static const kindPatch = 'patch';
  static const kindComment = 'comment';
  static const conflictMarker = 'conflict';

  final int id;
  final String kind;
  final String org;
  final String project;
  final int targetId;
  final String description;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final int? rev;
  final List<Map<String, Object?>> ops;
  final String? text;

  bool get isConflict => lastError == conflictMarker;
}

class DrainResult {
  const DrainResult({
    required this.synced,
    required this.conflicts,
    required this.stoppedOffline,
  });

  final int synced;
  final int conflicts;
  final bool stoppedOffline;
}

class WriteQueue {
  WriteQueue(this._db, this._workItems, {this.userId});

  final AppDatabase _db;
  final WorkItemRepository _workItems;

  /// Writes queued by this account replay with its token; null (tests, or
  /// rows from before accounts existed) means every row.
  final String? userId;
  bool _draining = false;

  Expression<bool> _mine($PendingWritesTable t) =>
      userId == null ? const Constant(true) : t.userId.equalsNullable(userId);

  Stream<List<PendingWrite>> watch() =>
      (_db.select(_db.pendingWrites)
            ..where(_mine)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch()
          .map((rows) => rows.map(PendingWrite.fromRow).toList());

  Future<void> enqueuePatch({
    required String org,
    required String project,
    required WorkItem item,
    required List<Map<String, Object?>> ops,
    required String description,
  }) => _db
      .into(_db.pendingWrites)
      .insert(
        PendingWritesCompanion.insert(
          kind: PendingWrite.kindPatch,
          userId: Value(userId),
          orgName: org,
          targetId: '${item.id}',
          payload: jsonEncode({
            'project': project,
            'rev': item.rev,
            'ops': ops,
            'description': description,
          }),
          createdAt: DateTime.now(),
        ),
      );

  Future<void> enqueueComment({
    required String org,
    required String project,
    required int id,
    required String text,
    required String description,
  }) => _db
      .into(_db.pendingWrites)
      .insert(
        PendingWritesCompanion.insert(
          kind: PendingWrite.kindComment,
          userId: Value(userId),
          orgName: org,
          targetId: '$id',
          payload: jsonEncode({
            'project': project,
            'text': text,
            'description': description,
          }),
          createdAt: DateTime.now(),
        ),
      );

  Future<void> discard(int id) =>
      (_db.delete(_db.pendingWrites)..where((t) => t.id.equals(id))).go();

  /// Replays queued writes in order. Stops at the first network failure
  /// (still offline), marks a 412 as a conflict and keeps going, and leaves
  /// other failures in the queue with their message.
  Future<DrainResult> drain() async {
    if (_draining) {
      return const DrainResult(synced: 0, conflicts: 0, stoppedOffline: false);
    }
    _draining = true;
    var synced = 0;
    var conflicts = 0;
    try {
      final rows =
          await (_db.select(_db.pendingWrites)
                ..where(_mine)
                ..orderBy([(t) => OrderingTerm.asc(t.id)]))
              .get();
      for (final row in rows) {
        final w = PendingWrite.fromRow(row);
        if (w.isConflict) {
          conflicts++;
          continue;
        }
        try {
          await _replay(w);
          await discard(w.id);
          synced++;
        } on AdoNetworkException {
          return DrainResult(
            synced: synced,
            conflicts: conflicts,
            stoppedOffline: true,
          );
        } on AdoStaleRevisionException {
          conflicts++;
          await _fail(w, PendingWrite.conflictMarker);
        } on AdoException catch (e) {
          await _fail(w, e.message);
        }
      }
      return DrainResult(
        synced: synced,
        conflicts: conflicts,
        stoppedOffline: false,
      );
    } finally {
      _draining = false;
    }
  }

  Future<void> _replay(PendingWrite w) async {
    switch (w.kind) {
      case PendingWrite.kindPatch:
        await _workItems.patch(
          w.org,
          w.project,
          WorkItem(id: w.targetId, rev: w.rev ?? 0, fields: const {}),
          w.ops,
        );
      case PendingWrite.kindComment:
        await _workItems.addComment(w.org, w.project, w.targetId, w.text ?? '');
      default:
        throw AdoServerException('Unknown queued write kind ${w.kind}');
    }
  }

  Future<void> _fail(PendingWrite w, String error) =>
      (_db.update(_db.pendingWrites)..where((t) => t.id.equals(w.id))).write(
        PendingWritesCompanion(
          attempts: Value(w.attempts + 1),
          lastError: Value(error),
        ),
      );

  /// Field values from JSON Patch `add` ops, for the optimistic local copy.
  static Map<String, dynamic> fieldsFromOps(List<Map<String, Object?>> ops) => {
    for (final op in ops)
      if (op['op'] == 'add' &&
          (op['path'] as String? ?? '').startsWith('/fields/'))
        (op['path'] as String).substring('/fields/'.length): op['value'],
  };
}
