import 'package:flutter/foundation.dart';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/work_item.dart';

/// People, for every surface that needs one: the work item form's identity
/// picker, the mention picker, and the name behind a `@<guid>` in a pull
/// request comment (research/16 §4.2).
///
/// Promoted out of `WorkItemFormRepository`, which still delegates to it, so a
/// pull request page does not have to read a *work item form* repository to
/// look up a person. The cache keys came across unchanged (`form:members:…`,
/// `form:descriptor:…`), so a device that already has them keeps them.
///
/// Every read is cached in `cache_entries` under account-namespaced keys and
/// answered from the cache when the network fails, so a mention list opens
/// offline (M13).
class PeopleRepository {
  PeopleRepository(this._client, [AppDatabase? db, String? userId])
    : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final JsonCache _cache;

  static const apiVersion = '7.1';

  /// The Graph subject query and descriptor reads are preview-only.
  static const graphApiVersion = '7.1-preview.1';

  /// `_apis/identities` is documented as preview at 7.1.
  static const identitiesApiVersion = '7.1-preview.1';

  /// Team membership changes rarely; the form settled on a day (research/11).
  static const cacheTtl = Duration(hours: 24);

  /// A display name behind a GUID changes almost never and is only ever
  /// cosmetic, so it is kept far longer than a list.
  static const identityTtl = Duration(days: 30);

  /// `_apis/identities?identityIds=` takes a list; one call covers a whole
  /// pull request's worth of comment authors.
  static const maxIdentityBatch = 50;

  static String membersKey(String org, String projectId, String teamId) =>
      'form:members:$org:$projectId:$teamId';
  static String descriptorKey(String org, String projectId) =>
      'form:descriptor:$org:$projectId';
  static String identityKey(String org, String guid) =>
      'people:identity:$org:$guid';

  /// Resolved identities for this session, and the ones that could not be
  /// resolved, so a comment list of fifty `@<guid>` runs asks once.
  final Map<String, IdentityRef> _identities = {};
  final Set<String> _unknown = {};
  final Map<String, Future<IdentityRef?>> _inFlight = {};

  // -------------------------------------------------------------- lists

  /// The team's members, the people picker's offline list (spike s25: the
  /// type's identity `allowedValues` are empty, so this replaces them).
  ///
  /// Every row carries the identity GUID, which is what makes a team member
  /// insertable as a mention offline (M13).
  Future<List<IdentityRef>> teamMembers(
    String org,
    String projectId,
    String teamId, {
    bool refresh = false,
  }) async {
    final members = await _cached<List<IdentityRef>>(
      membersKey(org, projectId, teamId),
      () async => _list(
        await _client.getJson(
          org: org,
          path: '_apis/projects/$projectId/teams/$teamId/members',
          apiVersion: apiVersion,
        ),
      ),
      (json) => [
        for (final m in _asMaps(json))
          if (m['identity'] is Map)
            IdentityRef.fromJson(
              (m['identity'] as Map).cast<String, dynamic>(),
            ),
      ],
      refresh: refresh,
    );
    for (final m in members) {
      _seed(org, m);
    }
    return members;
  }

  /// The project's Graph scope descriptor, for a project-scoped search.
  ///
  /// Needs the project **id**, not its name (spike s30: the name answers 400
  /// and silently widens the search org-wide).
  Future<String?> projectDescriptor(String org, String projectId) =>
      _cached<String?>(
        descriptorKey(org, projectId),
        () async => await _client.getJson(
          host: AdoHost.vssps,
          org: org,
          path: '_apis/graph/descriptors/$projectId',
          apiVersion: graphApiVersion,
        ),
        (json) => json is Map ? json['value'] as String? : null,
      );

  /// Types-as-you-go people search, scoped to the project (spike s25).
  ///
  /// A `GraphUser` has no identity id, only a descriptor, so the rows come
  /// back without one and `assignedToValue` sends
  /// `"Display Name <unique>"`; call [resolveIdentityId] when the picked
  /// person should be sent by id — which a mention always must (M15).
  Future<List<IdentityRef>> searchPeople(
    String org,
    String projectId,
    String query,
  ) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final scope = await _maybeValue(() => projectDescriptor(org, projectId));
    final json = await _client.send(
      method: 'POST',
      host: AdoHost.vssps,
      org: org,
      path: '_apis/graph/subjectquery',
      apiVersion: graphApiVersion,
      body: {
        'query': text,
        'subjectKind': ['User'],
        'scopeDescriptor': ?scope,
      },
    );
    return [for (final u in _asMaps(json['value'])) identityFromGraphUser(u)];
  }

  /// `GraphUser` → [IdentityRef]: `mailAddress` (else `principalName`) is
  /// the unique name and the avatar link carries the descriptor.
  static IdentityRef identityFromGraphUser(Map<String, dynamic> json) {
    final links = json['_links'];
    final avatar = links is Map && links['avatar'] is Map
        ? (links['avatar'] as Map)['href'] as String?
        : null;
    return IdentityRef(
      displayName: json['displayName'] as String? ?? '',
      uniqueName:
          json['mailAddress'] as String? ?? json['principalName'] as String?,
      descriptor:
          json['descriptor'] as String? ??
          IdentityRef.descriptorFromAvatar(avatar),
      imageUrl: avatar,
    );
  }

  /// The identity id behind a Graph descriptor (`graph/storagekeys`), read
  /// only when the user picks someone the search found.
  Future<IdentityRef> resolveIdentityId(
    String org,
    IdentityRef person, {
    String? descriptor,
  }) async {
    final d = descriptor ?? person.descriptor;
    if (person.id != null || d == null || d.isEmpty) return person;
    final json = await _client.getJson(
      host: AdoHost.vssps,
      org: org,
      path: '_apis/graph/storagekeys/$d',
      apiVersion: graphApiVersion,
    );
    final id = json['value'] as String?;
    if (id == null || id.isEmpty) return person;
    final resolved = IdentityRef(
      displayName: person.displayName,
      uniqueName: person.uniqueName,
      id: id,
      imageUrl: person.imageUrl,
      descriptor: person.descriptor,
    );
    await rememberIdentity(org, resolved);
    return resolved;
  }

  // ---------------------------------------------------------- identities

  /// The person behind one identity GUID, or null when nobody answers.
  ///
  /// This is the name for a `@<guid>` in a pull request comment, which the
  /// service does not render for us (spike w30 §2): memory → [JsonCache] →
  /// `GET vssps …/_apis/identities?identityIds={guid}`. Null is a normal
  /// answer — the caller draws `@someone` (M9) — so nothing here throws, and
  /// a GUID that failed is not asked about again this session.
  ///
  /// Two failures are deliberately *not* remembered: a network error (the
  /// phone was offline; the name should appear once it is back) and an auth
  /// error (the page's own read raises `AuthInteractionRequired`, and a
  /// cosmetic name must not poison the cache behind it).
  Future<IdentityRef?> identityById(String org, String guid) {
    final id = guid.trim().toLowerCase();
    if (id.isEmpty) return Future.value(null);
    final key = '$org:$id';
    final hit = _identities[key];
    if (hit != null) return Future.value(hit);
    if (_unknown.contains(key)) return Future.value(null);
    final flight = _inFlight[key];
    if (flight != null) return flight;
    final future = identitiesByIds(org, [id]).then((found) => found[id]);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  /// [identityById] for a whole comment list at once: one HTTP call per
  /// [maxIdentityBatch] GUIDs that are not already known. The keys of the
  /// answer are lower-cased GUIDs, and a GUID nobody answered for is simply
  /// absent.
  Future<Map<String, IdentityRef>> identitiesByIds(
    String org,
    Iterable<String> guids,
  ) async {
    final found = <String, IdentityRef>{};
    final wanted = <String>[];
    for (final raw in guids) {
      final id = raw.trim().toLowerCase();
      if (id.isEmpty || found.containsKey(id) || wanted.contains(id)) continue;
      final hit = _identities['$org:$id'];
      if (hit != null) {
        found[id] = hit;
      } else if (!_unknown.contains('$org:$id')) {
        wanted.add(id);
      }
    }
    final missing = <String>[];
    for (final id in wanted) {
      final cached = await _cache.get(identityKey(org, id));
      final ref =
          cached == null ||
              DateTime.now().difference(cached.fetchedAt) >= identityTtl
          ? null
          : _identityOf(cached.json);
      if (ref == null) {
        missing.add(id);
      } else {
        _identities['$org:$id'] = ref;
        found[id] = ref;
      }
    }
    for (var at = 0; at < missing.length; at += maxIdentityBatch) {
      final chunk = missing.sublist(
        at,
        at + maxIdentityBatch > missing.length
            ? missing.length
            : at + maxIdentityBatch,
      );
      try {
        final json = await _client.getJson(
          host: AdoHost.vssps,
          org: org,
          path: '_apis/identities',
          apiVersion: identitiesApiVersion,
          query: {'identityIds': chunk.join(',')},
        );
        for (final row in _asMaps(json['value'])) {
          final ref = identityFromIdentity(row);
          final id = ref.id?.trim().toLowerCase();
          if (id == null || id.isEmpty) continue;
          await rememberIdentity(org, ref);
          found[id] = ref;
        }
        for (final id in chunk) {
          if (!found.containsKey(id)) _unknown.add('$org:$id');
        }
      } on AdoAuthException catch (e) {
        debugPrint('identities: sign-in needed (${e.message})');
      } on AdoNetworkException catch (e) {
        debugPrint('identities: offline (${e.message})');
      } on AdoException catch (e) {
        debugPrint('identities: ${e.message}');
        for (final id in chunk) {
          _unknown.add('$org:$id');
        }
      }
    }
    return found;
  }

  /// Seeds the identity cache from a person the app already has in hand — a
  /// comment author, a reviewer, the person just picked in the mention list.
  ///
  /// Free names: a pull request's own people cover most `@<guid>` runs in its
  /// threads, so [identityById] never reaches the network for them (M9).
  /// A ref without an id or without a name is ignored.
  Future<void> rememberIdentity(String org, IdentityRef? person) async {
    if (!_seed(org, person)) return;
    final id = person!.id!.trim().toLowerCase();
    await _cache.put(identityKey(org, id), person.toJson());
  }

  /// [rememberIdentity] for a list, one cache write each.
  Future<void> rememberIdentities(String org, Iterable<IdentityRef?> people) =>
      Future.wait([for (final p in people) rememberIdentity(org, p)]);

  /// A row of `_apis/identities` → [IdentityRef].
  ///
  /// The Identities API is not the Graph: it answers `providerDisplayName`
  /// (and `customDisplayName` when the person renamed themselves) rather than
  /// `displayName`, and puts the address in `properties.Mail` /
  /// `properties.Account`, each of which is a `{$type, $value}` pair. The
  /// Graph subject descriptor is only present on newer api-versions, so it is
  /// read when it is there and left null when it is not — the avatar falls
  /// back to initials, which is what an unresolved person shows anyway.
  static IdentityRef identityFromIdentity(Map<String, dynamic> json) {
    String? property(String name) {
      final props = json['properties'];
      if (props is! Map) return null;
      final value = props[name];
      if (value is Map) return value[r'$value'] as String?;
      return value as String?;
    }

    final name =
        json['customDisplayName'] as String? ??
        json['providerDisplayName'] as String? ??
        json['displayName'] as String? ??
        '';
    return IdentityRef(
      displayName: name,
      uniqueName:
          property('Mail') ??
          property('Account') ??
          json['uniqueName'] as String?,
      id: json['id'] as String?,
      descriptor: json['subjectDescriptor'] as String?,
    );
  }

  /// Forgets every resolved and failed identity (sign-out, or a pull-to-
  /// refresh that should re-ask for a name that was missing).
  void clearIdentityMemory() {
    _identities.clear();
    _unknown.clear();
  }

  // ------------------------------------------------------------- private

  /// Memory only — [teamMembers] and [searchPeople] answers are already
  /// cached as lists, so writing a row per person would duplicate them.
  /// Returns whether the ref was worth keeping.
  bool _seed(String org, IdentityRef? person) {
    final id = person?.id?.trim().toLowerCase();
    if (person == null || id == null || id.isEmpty) return false;
    if (person.displayName.trim().isEmpty) return false;
    _identities['$org:$id'] = person;
    _unknown.remove('$org:$id');
    return true;
  }

  static IdentityRef? _identityOf(Object? json) {
    if (json is! Map) return null;
    try {
      final ref = IdentityRef.fromJson(json.cast<String, dynamic>());
      return ref.id == null ? null : ref;
    } catch (_) {
      return null;
    }
  }

  Future<T> _cached<T>(
    String key,
    Future<Object> Function() fetch,
    T Function(Object? json) parse, {
    bool refresh = false,
    Duration maxAge = cacheTtl,
  }) async {
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null && DateTime.now().difference(hit.fetchedAt) < maxAge) {
        final parsed = _tryParse(hit.json, parse);
        if (parsed != null) return parsed.$1;
      }
    }
    try {
      final raw = await fetch();
      await _cache.put(key, raw);
      return parse(raw);
    } on AdoAuthException {
      // Sign-in is needed; never mask that with a stale copy.
      rethrow;
    } on AdoException {
      final stale = await _cache.get(key);
      final parsed = stale == null ? null : _tryParse(stale.json, parse);
      if (parsed != null) return parsed.$1;
      rethrow;
    }
  }

  static (T,)? _tryParse<T>(Object? json, T Function(Object? json) parse) {
    try {
      return (parse(json),);
    } catch (_) {
      return null;
    }
  }

  Future<T?> _maybeValue<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on AdoException {
      return null;
    }
  }

  static List<Map<String, dynamic>> _list(Map<String, dynamic> json) =>
      _asMaps(json['value']);

  static List<Map<String, dynamic>> _asMaps(Object? value) => [
    for (final v in (value as List?) ?? const [])
      if (v is Map) v.cast<String, dynamic>(),
  ];
}
