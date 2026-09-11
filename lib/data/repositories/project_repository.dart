import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
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
    final listed =
        (json['value'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Project.fromJson(m.cast<String, dynamic>()))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final projects = await _withDefaultTeams(org, tenantId, listed);

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
                defaultTeamId: Value(p.defaultTeamId),
                defaultTeamDescriptor: Value(p.defaultTeamDescriptor),
                fetchedAt: now,
              ),
            );
      }
    });
    return projects;
  }

  /// The list call omits `defaultTeam`, whose avatar is the project's
  /// picture; read it once per project (single-project GET, then the
  /// team's Graph descriptor) and keep both in the cache so later
  /// refreshes cost nothing extra. A failed read leaves the tile on its
  /// drawn initials.
  Future<List<Project>> _withDefaultTeams(
    String org,
    String? tenantId,
    List<Project> listed,
  ) async {
    final known = {
      for (final row
          in await (_db.select(_db.projects)..where(
                (t) =>
                    t.orgName.equals(org) & t.defaultTeamDescriptor.isNotNull(),
              ))
              .get())
        row.id: row,
    };
    return Future.wait(
      listed.map((p) async {
        final cached = known[p.id];
        if (cached != null) {
          return p.withDefaultTeam(
            id: cached.defaultTeamId,
            descriptor: cached.defaultTeamDescriptor,
          );
        }
        try {
          final json = await _client.getJson(
            org: org,
            tenantId: tenantId,
            path: '_apis/projects/${p.id}',
            apiVersion: _apiVersion,
          );
          final teamId = Project.fromJson(json).defaultTeamId;
          if (teamId == null) return p;
          final descriptor = await _client.getJson(
            host: AdoHost.vssps,
            org: org,
            tenantId: tenantId,
            path: '_apis/graph/descriptors/$teamId',
            apiVersion: '7.1-preview.1',
          );
          return p.withDefaultTeam(
            id: teamId,
            descriptor: descriptor['value'] as String?,
          );
        } on AdoException catch (e) {
          debugPrint('default team for ${p.name}: ${e.message}');
          return p;
        }
      }),
    );
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
                    defaultTeamId: r.defaultTeamId,
                    defaultTeamDescriptor: r.defaultTeamDescriptor,
                  ),
                )
                .toList(),
          );
}
