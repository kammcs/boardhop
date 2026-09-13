import '../../features/notifications/push_registrar.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/push_prefs.dart';

/// `GET/PUT /v1/prefs?org=` on the relay (research/14 §6, decision D5), with a
/// cached copy so Settings opens offline with the last document it saw.
///
/// The auth is the same as `/v1/devices`: the account's own Azure DevOps
/// access token as the bearer, fetched fresh per call, never stored and never
/// logged — which is why this goes through the same [RelayCall] and the same
/// [relayUrlFor] the registrar uses rather than the Azure DevOps client.
class PushPrefsRepository {
  PushPrefsRepository({
    required this.accountId,
    required this.accessToken,
    RelayCall? call,
    AppDatabase? db,
    String Function(String org)? relayUrl,
  }) : _call = call ?? dioRelayCall(),
       _relayUrl = relayUrl ?? relayUrlFor,
       _cache = JsonCache(db, namespace: accountId);

  final String accountId;

  /// The account's Azure DevOps access token.
  final Future<String> Function() accessToken;

  final RelayCall _call;
  final String Function(String org) _relayUrl;
  final JsonCache _cache;

  static String cacheKey(String org) => 'push:prefs:$org';

  /// The last document this account saw for [org], or null.
  Future<PushPrefs?> cached(String org) async {
    final entry = await _cache.get(cacheKey(org));
    final json = entry?.json;
    if (json is! Map) return null;
    return PushPrefs.fromJson(json.cast<String, Object?>());
  }

  /// `GET /v1/prefs?org=`. A relay too old to know the route answers 404, and
  /// the screen says so rather than pretending the defaults are in force.
  Future<PushPrefsResult> fetch(String org) async {
    final response = await _send('GET', org, null);
    if (response == null) {
      return PushPrefsResult(
        status: PushPrefsStatus.failed,
        prefs: await cached(org),
        fromCache: true,
      );
    }
    if (response.statusCode == 404) {
      return const PushPrefsResult(status: PushPrefsStatus.unavailable);
    }
    if (!response.ok) {
      return PushPrefsResult(
        status: PushPrefsStatus.failed,
        prefs: await cached(org),
        fromCache: true,
      );
    }
    final prefs = PushPrefs.fromJson(response.body);
    await _cache.put(cacheKey(org), prefs.toJson());
    return PushPrefsResult(status: PushPrefsStatus.ok, prefs: prefs);
  }

  /// `PUT /v1/prefs?org=`. The relay answers with the stored document, which
  /// is what is cached — a key the relay normalised differently is what the
  /// screen should show next time.
  Future<PushPrefsResult> save(String org, PushPrefs prefs) async {
    final response = await _send('PUT', org, prefs.toJson(forWrite: true));
    if (response == null) {
      return const PushPrefsResult(status: PushPrefsStatus.failed);
    }
    if (response.statusCode == 404) {
      return const PushPrefsResult(status: PushPrefsStatus.unavailable);
    }
    if (!response.ok) {
      return const PushPrefsResult(status: PushPrefsStatus.failed);
    }
    final stored = response.body.isEmpty
        ? prefs
        : PushPrefs.fromJson(response.body);
    await _cache.put(cacheKey(org), stored.toJson());
    return PushPrefsResult(status: PushPrefsStatus.ok, prefs: stored);
  }

  Future<RelayResponse?> _send(
    String method,
    String org,
    Map<String, Object?>? body,
  ) async {
    String bearer;
    try {
      bearer = await accessToken();
    } catch (_) {
      return null;
    }
    try {
      return await _call(
        method,
        Uri.parse(
          '${_relayUrl(org)}/v1/prefs?org=${Uri.encodeQueryComponent(org)}',
        ),
        bearer: bearer,
        body: body,
      );
    } catch (_) {
      return null;
    }
  }
}

enum PushPrefsStatus {
  ok,

  /// The relay has no `/v1/prefs` (404): an older deployment.
  unavailable,

  /// Offline, refused, or a token that could not be acquired.
  failed,
}

class PushPrefsResult {
  const PushPrefsResult({
    required this.status,
    this.prefs,
    this.fromCache = false,
  });

  final PushPrefsStatus status;

  /// What to show: the relay's document, or the cached one on a failure.
  final PushPrefs? prefs;

  /// True when [prefs] came from the local copy rather than the relay.
  final bool fromCache;

  bool get ok => status == PushPrefsStatus.ok;
}
