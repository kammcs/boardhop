/// The pure half of `tool/hooks.dart` (research/14 §9, R2.8).
///
/// Everything here is either a constant (the planned subscription set), a pure
/// function over JSON (the subscription body, the registry merge, redaction) or
/// a thin HTTP wrapper that takes its `http.Client` from the caller, so the
/// whole tool is testable from `test/tool_hooks_test.dart` without a network.
///
/// Nothing in this file prints. The CLI owns stdout; the runner writes through
/// the sink it is given, and no code path ever puts the PAT, the hook secret or
/// the admin secret into a string that leaves the process.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:http/http.dart' as http;

/// The Azure DevOps API version every call in this tool pins (CLAUDE.md).
const apiVersion = '7.1';

/// The basic-auth username every subscription is created with; it has to match
/// [HookIngest.hookUsername] on the receiving side.
const hookUsername = 'hook';

/// Where the relay lives unless `RELAY_URL` says otherwise.
const defaultRelayUrl = 'https://boardhop.relay.kammcs.com';

/// One subscription the beta wants to exist, before it has an id.
///
/// [filters] are the publisher inputs other than `projectId`: the ones that
/// actually narrow the event carry a value, and every other input the publisher
/// exposes is sent as an empty string, which is what the Azure DevOps web UI
/// does for "any" (proven by w21, used by w22 and w24).
class PlannedSubscription {
  const PlannedSubscription({
    required this.publisherId,
    required this.eventType,
    required this.resourceVersion,
    required this.filters,
  });

  final String publisherId;
  final String eventType;
  final String resourceVersion;
  final Map<String, String> filters;

  /// The `notificationType` filter, for the four PR update kinds only.
  String? get notificationType {
    final value = filters['notificationType'];
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The routing label the relay stores. Derived from [HookKind] so the tool
  /// and the receiver can never drift apart.
  HookKind get kind {
    final resolved = HookKind.fromEventTypeAndFilter(eventType, notificationType);
    if (resolved == null) {
      throw StateError('no HookKind for $eventType / $notificationType');
    }
    return resolved;
  }

  /// The non-empty filters, for the plan table and the `list` output.
  Map<String, String> get activeFilters => {
    for (final entry in filters.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  };

  String get filterSummary {
    final active = activeFilters;
    if (active.isEmpty) return '—';
    return active.entries.map((e) => '${e.key}=${e.value}').join(', ');
  }
}

/// Filter inputs shared by the four git PR events that take reviewers.
const _prInputs = {'repository': '', 'branch': '', 'pullrequestCreatedBy': '', 'pullrequestReviewersContains': ''};

/// The four values `git.pullrequest.updated` accepts (s41), in the order
/// research/14 §1.2 lists them.
const prNotificationTypes = [
  'PushNotification',
  'ReviewersUpdateNotification',
  'StatusUpdateNotification',
  'ReviewerVoteNotification',
];

/// The beta's subscription set: **14 subscriptions over 11 distinct event ids**
/// (`git.pullrequest.updated` is subscribed four times, once per
/// `notificationType`, because the body does not say what changed).
///
/// research/14 §1 counts "thirteen" by listing one row per event id *including*
/// `stage-state-changed`, which that same table marks "later"; drop it and the
/// eleven ids below are what the beta actually subscribes to.
///
/// `ms.vss-pipelines.stage-state-changed-event` is deliberately absent: research/14
/// §1 leaves it for later.
final List<PlannedSubscription> plannedSubscriptions = List.unmodifiable([
  const PlannedSubscription(
    publisherId: 'tfs',
    eventType: 'git.pullrequest.created',
    resourceVersion: '1.0',
    filters: _prInputs,
  ),
  for (final notificationType in prNotificationTypes)
    PlannedSubscription(
      publisherId: 'tfs',
      eventType: 'git.pullrequest.updated',
      resourceVersion: '1.0',
      filters: {..._prInputs, 'notificationType': notificationType},
    ),
  const PlannedSubscription(
    publisherId: 'tfs',
    eventType: 'ms.vss-code.git-pullrequest-comment-event',
    resourceVersion: '2.0',
    filters: {'repository': '', 'branch': ''},
  ),
  // w24: it fires on every merge *attempt*, so only the failures are wanted.
  const PlannedSubscription(
    publisherId: 'tfs',
    eventType: 'git.pullrequest.merged',
    resourceVersion: '1.0',
    filters: {..._prInputs, 'mergeResult': 'Unsuccessful'},
  ),
  const PlannedSubscription(
    publisherId: 'tfs',
    eventType: 'workitem.created',
    resourceVersion: '1.0',
    filters: {'areaPath': '', 'workItemType': ''},
  ),
  const PlannedSubscription(
    publisherId: 'tfs',
    eventType: 'workitem.updated',
    resourceVersion: '1.0',
    filters: {'areaPath': '', 'workItemType': '', 'changedFields': ''},
  ),
  // Subscribed, then dropped by the relay: the body names nobody by id, so the
  // matching `workitem.updated` is what notifies (research/14 §5.2 rule 3).
  const PlannedSubscription(
    publisherId: 'tfs',
    eventType: 'workitem.commented',
    resourceVersion: '1.0',
    filters: {'areaPath': '', 'workItemType': ''},
  ),
  const PlannedSubscription(
    publisherId: 'tfs',
    eventType: 'build.complete',
    resourceVersion: '2.0',
    filters: {'definitionName': '', 'buildStatus': ''},
  ),
  // Never notifies: it is the only event that gives the run's requester as an
  // identity, which the approval events need (research/14 §1.4).
  const PlannedSubscription(
    publisherId: 'pipelines',
    eventType: 'ms.vss-pipelines.run-state-changed-event',
    resourceVersion: '5.1-preview.1',
    filters: {'pipelineId': '', 'runStateId': '', 'runResultId': ''},
  ),
  const PlannedSubscription(
    publisherId: 'pipelines',
    eventType: 'ms.vss-pipelinechecks-events.approval-pending',
    resourceVersion: '5.1-preview.1',
    filters: {'pipelineId': '', 'stageName': '', 'environmentName': ''},
  ),
  const PlannedSubscription(
    publisherId: 'pipelines',
    eventType: 'ms.vss-pipelinechecks-events.approval-completed',
    resourceVersion: '5.1-preview.1',
    filters: {'pipelineId': '', 'stageName': '', 'environmentName': ''},
  ),
]);

/// How many distinct Azure DevOps event ids the plan covers (11 for 14 rows).
int get plannedEventIdCount => plannedSubscriptions.map((p) => p.eventType).toSet().length;

/// The plan as a fixed-width table. Pure: `plan` prints exactly this.
String planTable() {
  final rows = <List<String>>[
    ['publisher', 'event', 'version', 'filter', 'kind'],
    for (final plan in plannedSubscriptions)
      [plan.publisherId, plan.eventType, plan.resourceVersion, plan.filterSummary, plan.kind.label],
  ];
  final widths = List<int>.generate(
    5,
    (column) => rows.map((row) => row[column].length).reduce((a, b) => a > b ? a : b),
  );
  final lines = <String>[];
  for (var i = 0; i < rows.length; i++) {
    lines.add([for (var c = 0; c < 5; c++) rows[i][c].padRight(widths[c])].join('  ').trimRight());
    if (i == 0) lines.add([for (var c = 0; c < 5; c++) '-' * widths[c]].join('  '));
  }
  lines.add('');
  lines.add(
    '${plannedSubscriptions.length} subscriptions over $plannedEventIdCount distinct event ids '
    '(git.pullrequest.updated is subscribed ${prNotificationTypes.length} times, once per notificationType).',
  );
  return lines.join('\n');
}

/// The create body, shaped exactly like the one w22/w24 proved works.
Map<String, Object?> subscriptionBody({
  required PlannedSubscription plan,
  required String projectId,
  required String url,
  required String secret,
}) => {
  'publisherId': plan.publisherId,
  'eventType': plan.eventType,
  'resourceVersion': plan.resourceVersion,
  'consumerId': 'webHooks',
  'consumerActionId': 'httpRequest',
  'publisherInputs': {'projectId': projectId, ...plan.filters},
  'consumerInputs': {
    'url': url,
    'basicAuthUsername': hookUsername,
    'basicAuthPassword': secret,
    'resourceDetailsToSend': 'all',
    'messagesToSend': 'text',
    'detailedMessagesToSend': 'text',
  },
};

/// `{relayUrl}/hooks/{org}` with no trailing slash, whatever `RELAY_URL` ends with.
String hookUrlFor(String relayUrl, String org) => '${relayUrl.replaceAll(RegExp(r'/+$'), '')}/hooks/$org';

/// The prefix `list` matches on: every org's ingest url starts with it.
String hookUrlPrefix(String relayUrl) => '${relayUrl.replaceAll(RegExp(r'/+$'), '')}/hooks/';

String? _string(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

Map<String, Object?> _map(Object? value) => value is Map ? value.cast<String, Object?>() : const {};

/// The publisher inputs of an Azure DevOps subscription JSON.
Map<String, Object?> publisherInputsOf(Map<String, Object?> sub) => _map(sub['publisherInputs']);

/// The consumer inputs of an Azure DevOps subscription JSON.
Map<String, Object?> consumerInputsOf(Map<String, Object?> sub) => _map(sub['consumerInputs']);

String? projectIdOf(Map<String, Object?> sub) => _string(publisherInputsOf(sub)['projectId']);

String? consumerUrlOf(Map<String, Object?> sub) => _string(consumerInputsOf(sub)['url']);

/// True when [sub] is already the subscription [plan] would create: same event,
/// same `notificationType`/`mergeResult` filter, same project, same url.
///
/// Only the filters the plan actually narrows on are compared — an existing
/// subscription created by hand with `repository` left unset is still the same
/// subscription for the relay's purposes.
bool matchesPlan(Map<String, Object?> sub, PlannedSubscription plan, {required String projectId, required String url}) {
  if (_string(sub['eventType']) != plan.eventType) return false;
  if (projectIdOf(sub) != projectId) return false;
  if (consumerUrlOf(sub) != url) return false;
  final inputs = publisherInputsOf(sub);
  for (final entry in plan.activeFilters.entries) {
    if (_string(inputs[entry.key]) != entry.value) return false;
  }
  // A plan with no narrowing filter must not match a subscription that *is*
  // narrowed (an unfiltered pr.updated is not the same thing as the vote one).
  for (final key in const ['notificationType', 'mergeResult']) {
    if (!plan.activeFilters.containsKey(key) && _string(inputs[key]) != null) return false;
  }
  return true;
}

/// One row of the relay's registry (`PUT /v1/admin/orgs/{org}/subscriptions`).
class RegistryRow {
  const RegistryRow({
    required this.subId,
    required this.eventType,
    required this.kind,
    this.projectId,
    this.projectName,
  });

  factory RegistryRow.fromJson(Map<String, Object?> json) => RegistryRow(
    subId: _string(json['subId']) ?? '',
    eventType: _string(json['eventType']) ?? '',
    kind: _string(json['kind']) ?? '',
    projectId: _string(json['projectId']),
    projectName: _string(json['projectName']),
  );

  final String subId;
  final String eventType;
  final String kind;
  final String? projectId;
  final String? projectName;

  Map<String, Object?> toJson() => {
    'subId': subId,
    'eventType': eventType,
    'kind': kind,
    if (projectId != null) 'projectId': projectId,
    if (projectName != null) 'projectName': projectName,
  };

  @override
  String toString() => 'RegistryRow($subId, $eventType, $kind, $projectId)';
}

/// Replace one project's rows and keep every other project's, so provisioning a
/// second project never unregisters the first (the relay's PUT replaces the
/// whole org set in one transaction).
///
/// Rows are kept when their `projectId` differs from [projectId]; a row with no
/// project belongs to no project and is kept too. A `subId` that appears in
/// [rows] is always taken from [rows], whatever project the old row claimed.
List<RegistryRow> mergeRegistry({
  required List<RegistryRow> existing,
  required String projectId,
  required List<RegistryRow> rows,
}) {
  final incoming = {for (final row in rows) row.subId};
  return [
    for (final row in existing)
      if (row.projectId != projectId && !incoming.contains(row.subId)) row,
    ...rows,
  ];
}

/// The registry without [subIds] — what `delete` puts back.
List<RegistryRow> removeFromRegistry({required List<RegistryRow> existing, required Set<String> subIds}) => [
  for (final row in existing)
    if (!subIds.contains(row.subId)) row,
];

/// Replaces every secret in [text] with a placeholder.
///
/// Applied to every byte this tool prints that came from a network response or
/// an exception, so a PAT echoed back in an error body cannot reach the
/// terminal, a log or a spike result file.
String redactSecrets(String text, Iterable<String> secrets) {
  var out = text;
  for (final secret in secrets) {
    if (secret.length < 8) continue;
    out = out.replaceAll(secret, '<redacted>');
    // The PAT also travels base64-encoded in the Authorization header, and
    // Azure DevOps sometimes echoes a request header back in an error.
    out = out.replaceAll(base64Encode(utf8.encode(':$secret')), '<redacted>');
    out = out.replaceAll(base64Encode(utf8.encode(secret)), '<redacted>');
  }
  return out;
}

/// A response body cut to [max] characters, whitespace collapsed, secrets gone.
String bodyExcerpt(String body, Iterable<String> secrets, {int max = 200}) {
  final flat = redactSecrets(body, secrets).replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

/// A failure the CLI turns into a message and a non-zero exit code.
class HooksFailure implements Exception {
  HooksFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything the tool reads out of the environment.
class HooksConfig {
  HooksConfig({
    required this.orgUrl,
    required this.pat,
    required this.relayUrl,
    required this.adminSecret,
    required this.allowProject,
  });

  /// Reads the environment, defaulting `RELAY_URL`. Missing values stay empty;
  /// each command asks for the ones it needs through [require].
  factory HooksConfig.fromEnvironment(Map<String, String> env) => HooksConfig(
    orgUrl: (env['ADO_ORG_URL'] ?? '').trim().replaceAll(RegExp(r'/+$'), ''),
    pat: (env['ADO_PAT'] ?? '').trim(),
    relayUrl: ((env['RELAY_URL'] ?? '').trim().isEmpty ? defaultRelayUrl : env['RELAY_URL']!.trim()).replaceAll(
      RegExp(r'/+$'),
      '',
    ),
    adminSecret: (env['RELAY_ADMIN_SECRET'] ?? '').trim(),
    allowProject: (env['HOOKS_ALLOW_PROJECT'] ?? '').trim(),
  );

  final String orgUrl;
  final String pat;
  final String relayUrl;
  final String adminSecret;

  /// The write guard: `create` and `delete` refuse any project but this one.
  final String allowProject;

  /// Every secret that must never appear in output.
  List<String> get secrets => [
    for (final s in [pat, adminSecret])
      if (s.isNotEmpty) s,
  ];

  void require(List<String> names) {
    final missing = [
      for (final name in names)
        if (_valueOf(name).isEmpty) name,
    ];
    if (missing.isNotEmpty) throw HooksFailure('set ${missing.join(', ')} in the environment');
  }

  String _valueOf(String name) => switch (name) {
    'ADO_ORG_URL' => orgUrl,
    'ADO_PAT' => pat,
    'RELAY_URL' => relayUrl,
    'RELAY_ADMIN_SECRET' => adminSecret,
    'HOOKS_ALLOW_PROJECT' => allowProject,
    _ => '',
  };

  /// The write guard of R2.8: Azure DevOps writes go only to the project named
  /// by `HOOKS_ALLOW_PROJECT` (CLAUDE.md hard rule 1). Checked before any
  /// network call, so a wrong `--project` never even resolves an id.
  void guardProject(String project) {
    if (allowProject.isEmpty) {
      throw HooksFailure(
        'HOOKS_ALLOW_PROJECT is not set; this command writes to Azure DevOps and refuses to run without the guard',
      );
    }
    if (project != allowProject) {
      throw HooksFailure('refusing to write to project "$project": HOOKS_ALLOW_PROJECT allows "$allowProject" only');
    }
  }
}

/// A response the tool has already decoded and already redacted.
class HooksResponse {
  HooksResponse(this.status, this.body, this.json);

  final int status;
  final String body;
  final Object? json;

  bool get ok => status >= 200 && status < 300;

  Map<String, Object?> get object => json is Map ? (json! as Map).cast<String, Object?>() : const {};

  List<Object?> get list => json is List ? json! as List : const [];
}

/// The HTTP half: one `http.Client`, sequential calls, one retry on 429.
class HooksHttp {
  HooksHttp({required this.config, required this.client, Future<void> Function(Duration)? sleep})
    : _sleep = sleep ?? Future<void>.delayed;

  final HooksConfig config;

  /// Injected so the tests can answer without a socket.
  final http.Client client;
  final Future<void> Function(Duration) _sleep;

  /// Longest a `Retry-After` is honoured before the tool gives up instead.
  static const maxRetryAfter = Duration(seconds: 60);

  String get _adoAuth => 'Basic ${base64Encode(utf8.encode(':${config.pat}'))}';

  Future<HooksResponse> ado(String method, String path, {Object? body, Map<String, String>? query}) {
    final url = Uri.parse('${config.orgUrl}$path').replace(queryParameters: {'api-version': apiVersion, ...?query});
    return _send(method, url, {'Authorization': _adoAuth, 'Accept': 'application/json'}, body);
  }

  Future<HooksResponse> relay(String method, String path, {Object? body}) {
    config.require(['RELAY_ADMIN_SECRET']);
    return _send(method, Uri.parse('${config.relayUrl}$path'), {
      'Authorization': 'Bearer ${config.adminSecret}',
      'Accept': 'application/json',
    }, body);
  }

  Future<HooksResponse> _send(String method, Uri url, Map<String, String> headers, Object? body) async {
    var response = await _once(method, url, headers, body);
    if (response.statusCode == 429) {
      final wait = _retryAfter(response.headers['retry-after']);
      if (wait != null) {
        await _sleep(wait);
        response = await _once(method, url, headers, body);
      }
    }
    final text = response.body;
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    return HooksResponse(response.statusCode, text, decoded);
  }

  Future<http.Response> _once(String method, Uri url, Map<String, String> headers, Object? body) async {
    final request = http.Request(method, url);
    request.headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(await client.send(request));
    } on Object catch (error) {
      throw HooksFailure('$method ${_safeUrl(url)} failed: ${redactSecrets('$error', config.secrets)}');
    }
  }

  Duration? _retryAfter(String? header) {
    final seconds = int.tryParse((header ?? '').trim());
    if (seconds == null || seconds < 0) return const Duration(seconds: 5);
    final wait = Duration(seconds: seconds);
    return wait > maxRetryAfter ? null : wait;
  }

  /// The url with its query dropped: nothing secret travels in one today, but a
  /// future `?token=` must not leak through an error message.
  String _safeUrl(Uri url) => redactSecrets(url.replace(query: '').toString(), config.secrets);

  /// The one place an unexpected status becomes a message: status plus a
  /// 200-character body excerpt, with every secret replaced.
  HooksFailure failureFor(String what, String url, HooksResponse response) =>
      HooksFailure('$what: HTTP ${response.status} $url — ${bodyExcerpt(response.body, config.secrets)}');

  void close() => client.close();
}

/// The routing label a subscription for [eventType] with this `notificationType`
/// filter would carry, or null when the relay has no kind for it (which means
/// the relay would refuse the post). Thin wrapper over [HookKind] so `list` has
/// only one place to look the label up.
String? kindLabelFor(String eventType, String? notificationType) =>
    HookKind.fromEventTypeAndFilter(eventType, notificationType)?.label;

/// 32 random bytes as 64 lowercase hex characters, from the platform CSPRNG.
String generateHookSecret([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
