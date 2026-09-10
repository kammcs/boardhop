import 'package:drift/drift.dart';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../models/organization.dart';
import '../models/profile.dart';

/// Organization discovery through the cross-org Accounts API, cached in drift.
///
/// Both endpoints live on `app.vssps.visualstudio.com` and accept only Entra
/// tokens (spike s02); that is one reason the launch is Entra-only.
class OrgRepository {
  OrgRepository(this._client, this._db);

  final AdoClient _client;
  final AppDatabase _db;

  static const _apiVersion = '7.1';

  Future<Profile> me() async {
    final json = await _client.getJson(
      host: AdoHost.appVssps,
      path: '_apis/profile/profiles/me',
      apiVersion: _apiVersion,
    );
    return Profile.fromJson(json);
  }

  /// Fetches the organizations the user belongs to and replaces the cache.
  Future<List<Organization>> refresh() async {
    final profile = await me();
    final json = await _client.getJson(
      host: AdoHost.appVssps,
      path: '_apis/accounts',
      apiVersion: _apiVersion,
      query: {'memberId': profile.id},
    );
    final orgs =
        (json['value'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Organization.fromAccountJson(m.cast<String, dynamic>()))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final now = DateTime.now();
    await _db.transaction(() async {
      final keep = orgs.map((o) => o.name).toList();
      await (_db.delete(
        _db.organizations,
      )..where((t) => t.name.isNotIn(keep))).go();
      for (final org in orgs) {
        await _db
            .into(_db.organizations)
            .insert(
              OrganizationsCompanion.insert(
                name: org.name,
                uri: org.uri,
                accountId: org.accountId,
                tenantId: Value(org.tenantId),
                fetchedAt: now,
              ),
              onConflict: DoUpdate(
                (old) => OrganizationsCompanion(
                  uri: Value(org.uri),
                  accountId: Value(org.accountId),
                  tenantId: Value(org.tenantId),
                  fetchedAt: Value(now),
                ),
              ),
            );
      }
    });
    return orgs;
  }

  Stream<List<Organization>> watch() =>
      (_db.select(_db.organizations)..orderBy([
            (t) => OrderingTerm.desc(t.lastOpenedAt),
            (t) => OrderingTerm.asc(t.name),
          ]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => Organization(
                    name: r.name,
                    uri: r.uri,
                    accountId: r.accountId,
                    tenantId: r.tenantId,
                  ),
                )
                .toList(),
          );

  /// Name of the organization opened most recently, if any.
  Future<String?> lastOpened() async {
    final row =
        await (_db.select(_db.organizations)
              ..where((t) => t.lastOpenedAt.isNotNull())
              ..orderBy([(t) => OrderingTerm.desc(t.lastOpenedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.name;
  }

  Future<void> markOpened(String name) =>
      (_db.update(_db.organizations)..where((t) => t.name.equals(name))).write(
        OrganizationsCompanion(lastOpenedAt: Value(DateTime.now())),
      );
}
