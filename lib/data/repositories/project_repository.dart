import 'package:drift/drift.dart';

import '../../core/http/ado_client.dart';
import '../db/app_database.dart';
import '../models/project.dart';

class ProjectRepository {
  ProjectRepository(this._client, this._db);

  final AdoClient _client;
  final AppDatabase _db;

  static const _apiVersion = '7.1';

  /// `GET {org}/_apis/projects` (well-formed projects only), cached per org.
  Future<List<Project>> refresh(String org, {String? tenantId}) async {
    final json = await _client.getJson(
      org: org,
      tenantId: tenantId,
      path: '_apis/projects',
      apiVersion: _apiVersion,
      query: {'\$top': '500', 'stateFilter': 'wellFormed'},
    );
    final projects =
        (json['value'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Project.fromJson(m.cast<String, dynamic>()))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.delete(_db.projects)..where(
            (t) =>
                t.orgName.equals(org) &
                t.id.isNotIn(projects.map((p) => p.id).toList()),
          ))
          .go();
      for (final p in projects) {
        await _db
            .into(_db.projects)
            .insertOnConflictUpdate(
              ProjectsCompanion.insert(
                id: p.id,
                orgName: org,
                name: p.name,
                description: Value(p.description),
                state: Value(p.state),
                lastUpdateTime: Value(p.lastUpdateTime),
                fetchedAt: now,
              ),
            );
      }
    });
    return projects;
  }

  Stream<List<Project>> watch(String org) =>
      (_db.select(_db.projects)
            ..where((t) => t.orgName.equals(org))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => Project(
                    id: r.id,
                    name: r.name,
                    description: r.description,
                    state: r.state,
                    lastUpdateTime: r.lastUpdateTime,
                  ),
                )
                .toList(),
          );
}
