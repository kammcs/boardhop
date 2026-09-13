/// The five commands of `tool/hooks.dart`, one method each.
///
/// Every method takes its HTTP from [HooksHttp] (whose `http.Client` the caller
/// injects) and writes through the [out] sink, so `test/tool_hooks_test.dart`
/// can run `create` and `delete` end to end against a fake client.
library;

import 'dart:io';

import 'hooks_lib.dart';

/// Runs one command. Construct, call, done; nothing is cached between commands.
class HooksRunner {
  HooksRunner({required this.config, required this.http, required this.out});

  final HooksConfig config;
  final HooksHttp http;

  /// Where the tool's own output goes. One line at a time, never a secret.
  final void Function(String line) out;

  // --------------------------------------------------------------- plan

  /// Prints the planned set without calling anything.
  void plan({required String org, required String project}) {
    out('Plan for org "$org", project "$project" → ${hookUrlFor(config.relayUrl, org)}');
    out('');
    out(planTable());
  }

  // ------------------------------------------------------------- secret

  /// Generates a hook secret, registers its hash with the relay and writes the
  /// plaintext to [outPath]. The secret is never printed.
  Future<void> secret({required String org, required String outPath}) async {
    config.require(['RELAY_URL', 'RELAY_ADMIN_SECRET']);
    final value = generateHookSecret();
    final path = '/v1/admin/orgs/$org/hook-secret';
    final response = await http.relay('PUT', path, body: {'secret': value});
    if (!response.ok) {
      throw http.failureFor('could not store the hook secret', '${config.relayUrl}$path', response);
    }

    final file = File(outPath);
    file.writeAsStringSync('$value\n', flush: true);
    final restricted = _restrict(file);
    out('Hook secret for "$org" stored on the relay (hash only) and written to ${file.path}');
    out(restricted ? 'File mode set to 600.' : 'Could not set the file mode here; keep the file out of git yourself.');
    out('The plaintext is in that file and nowhere else — the relay keeps a sha256 hash only.');
  }

  // ------------------------------------------------------------- create

  /// Creates the missing subscriptions for one project and registers the whole
  /// set with the relay, merging with the rows other projects already have.
  Future<void> create({required String org, required String project, required String secretFile}) async {
    // The write guard first: before the project id, before any network call.
    config.guardProject(project);
    config.require(['ADO_ORG_URL', 'ADO_PAT', 'RELAY_URL', 'RELAY_ADMIN_SECRET']);

    final hookSecret = _readSecretFile(secretFile);
    final url = hookUrlFor(config.relayUrl, org);
    final projectId = await _resolveProjectId(project);
    out('Project "$project" is $projectId; subscriptions will post to $url');
    out('');

    final existing = await _adoSubscriptions();
    final rows = <RegistryRow>[];
    var created = 0;
    var skipped = 0;

    for (final planned in plannedSubscriptions) {
      Map<String, Object?>? match;
      for (final sub in existing) {
        if (matchesPlan(sub, planned, projectId: projectId, url: url)) {
          match = sub;
          break;
        }
      }
      if (match != null) {
        final subId = (match['id'] as String?) ?? '';
        skipped++;
        out('exists   ${planned.kind.label.padRight(22)} $subId');
        rows.add(_row(planned, subId, projectId, project));
        continue;
      }
      final body = subscriptionBody(plan: planned, projectId: projectId, url: url, secret: hookSecret);
      final response = await http.ado('POST', '/_apis/hooks/subscriptions', body: body);
      if (!response.ok) {
        throw http.failureFor(
          'could not create ${planned.eventType} (${planned.kind.label})',
          '${config.orgUrl}/_apis/hooks/subscriptions',
          response,
        );
      }
      final subId = (response.object['id'] as String?) ?? '';
      if (subId.isEmpty) throw HooksFailure('Azure DevOps returned no subscription id for ${planned.eventType}');
      created++;
      out('created  ${planned.kind.label.padRight(22)} $subId');
      rows.add(_row(planned, subId, projectId, project));
    }

    out('');
    out('$created created, $skipped already there, ${rows.length} in the set.');
    await _register(org: org, projectId: projectId, rows: rows);
  }

  // --------------------------------------------------------------- list

  /// Azure DevOps and the relay registry side by side.
  Future<void> list({required String org, String? project}) async {
    config.require(['ADO_ORG_URL', 'ADO_PAT', 'RELAY_URL', 'RELAY_ADMIN_SECRET']);
    final prefix = hookUrlPrefix(config.relayUrl);
    final projectId = project == null ? null : await _resolveProjectId(project);

    final all = await _adoSubscriptions();
    final mine = [
      for (final sub in all)
        if ((consumerUrlOf(sub) ?? '').startsWith(prefix) && (projectId == null || projectIdOf(sub) == projectId)) sub,
    ];
    final registry = await _relayRegistry(org);
    final byId = {for (final row in registry) row.subId: row};

    out('Azure DevOps subscriptions posting to $prefix… (${mine.length})');
    out('');
    var mismatches = 0;
    for (final sub in mine) {
      final subId = (sub['id'] as String?) ?? '';
      final eventType = (sub['eventType'] as String?) ?? '';
      final inputs = publisherInputsOf(sub);
      final notificationType = inputs['notificationType'] as String?;
      final kind = kindLabelFor(eventType, notificationType);
      final row = byId[subId];
      final notes = <String>[
        if (row == null) 'NOT REGISTERED with the relay',
        if (row != null && row.kind != kind) 'kind mismatch: relay says ${row.kind}, event says $kind',
        if (row != null && row.projectId != projectIdOf(sub)) 'project mismatch: relay says ${row.projectId}',
        if (kind == null) 'no HookKind for this event: the relay would drop it',
      ];
      if (notes.isNotEmpty) mismatches++;
      out('$subId  ${(kind ?? eventType).padRight(22)} ${sub['status'] ?? ''}  ${notes.join('; ')}'.trimRight());
    }

    final adoIds = {for (final sub in mine) sub['id'] as String? ?? ''};
    final orphans = [
      for (final row in registry)
        if (!adoIds.contains(row.subId) && (projectId == null || row.projectId == projectId)) row,
    ];
    out('');
    out('Relay registry for "$org": ${registry.length} row(s).');
    for (final row in orphans) {
      mismatches++;
      out('${row.subId}  ${row.kind.padRight(22)} REGISTERED but no matching Azure DevOps subscription');
    }
    out('');
    out(mismatches == 0 ? 'In step.' : '$mismatches mismatch(es) above.');
    if (mismatches > 0) throw HooksFailure('the Azure DevOps subscriptions and the relay registry disagree');
  }

  // ------------------------------------------------------------- delete

  /// Deletes only this org's ingest subscriptions for one project, then takes
  /// those rows out of the relay registry.
  Future<void> delete({required String org, required String project}) async {
    config.guardProject(project);
    config.require(['ADO_ORG_URL', 'ADO_PAT', 'RELAY_URL', 'RELAY_ADMIN_SECRET']);

    final url = hookUrlFor(config.relayUrl, org);
    final projectId = await _resolveProjectId(project);
    final all = await _adoSubscriptions();
    final mine = [
      for (final sub in all)
        if (consumerUrlOf(sub) == url && projectIdOf(sub) == projectId) sub,
    ];
    out('Deleting ${mine.length} subscription(s) on $url for project "$project".');

    final removed = <String>{};
    for (final sub in mine) {
      final subId = (sub['id'] as String?) ?? '';
      // Belt and braces, the way w22 does it: the url and the project, or it is
      // not touched.
      if (subId.isEmpty || consumerUrlOf(sub) != url || projectIdOf(sub) != projectId) continue;
      final path = '/_apis/hooks/subscriptions/$subId';
      final response = await http.ado('DELETE', path);
      if (!response.ok && response.status != 404) {
        throw http.failureFor('could not delete $subId', '${config.orgUrl}$path', response);
      }
      removed.add(subId);
      out('deleted  ${sub['eventType']}  $subId');
    }

    final registry = await _relayRegistry(org);
    final kept = removeFromRegistry(existing: registry, subIds: removed);
    await _putRegistry(org, kept);
    out('');
    out('${removed.length} deleted; relay registry now holds ${kept.length} row(s) for "$org".');
  }

  // ------------------------------------------------------------ helpers

  RegistryRow _row(PlannedSubscription planned, String subId, String projectId, String projectName) => RegistryRow(
    subId: subId,
    eventType: planned.eventType,
    kind: planned.kind.label,
    projectId: projectId,
    projectName: projectName,
  );

  /// `GET /_apis/projects/{name}` — and the answer has to be the project asked
  /// for, or the guard above would have been checking a different thing.
  Future<String> _resolveProjectId(String project) async {
    final path = '/_apis/projects/${Uri.encodeComponent(project)}';
    final response = await http.ado('GET', path);
    if (!response.ok) throw http.failureFor('could not resolve project "$project"', '${config.orgUrl}$path', response);
    final name = response.object['name'] as String?;
    final id = response.object['id'] as String?;
    if (name != project) throw HooksFailure('Azure DevOps answered with project "$name", not "$project"');
    if (id == null || id.isEmpty) throw HooksFailure('project "$project" has no id in the response');
    return id;
  }

  Future<List<Map<String, Object?>>> _adoSubscriptions() async {
    const path = '/_apis/hooks/subscriptions';
    final response = await http.ado('GET', path);
    if (!response.ok) throw http.failureFor('could not list subscriptions', '${config.orgUrl}$path', response);
    final value = response.object['value'];
    return [
      for (final entry in value is List ? value : const [])
        if (entry is Map) entry.cast<String, Object?>(),
    ];
  }

  Future<List<RegistryRow>> _relayRegistry(String org) async {
    final path = '/v1/admin/orgs/$org/subscriptions';
    final response = await http.relay('GET', path);
    if (!response.ok) {
      throw http.failureFor('could not read the relay registry', '${config.relayUrl}$path', response);
    }
    final value = response.object['subscriptions'];
    return [
      for (final entry in value is List ? value : const [])
        if (entry is Map) RegistryRow.fromJson(entry.cast<String, Object?>()),
    ];
  }

  Future<void> _putRegistry(String org, List<RegistryRow> rows) async {
    final path = '/v1/admin/orgs/$org/subscriptions';
    final response = await http.relay('PUT', path, body: [for (final row in rows) row.toJson()]);
    if (!response.ok) {
      throw http.failureFor('could not register the subscriptions', '${config.relayUrl}$path', response);
    }
  }

  /// GET the registry, replace this project's rows only, PUT the union.
  Future<void> _register({required String org, required String projectId, required List<RegistryRow> rows}) async {
    final existing = await _relayRegistry(org);
    final merged = mergeRegistry(existing: existing, projectId: projectId, rows: rows);
    await _putRegistry(org, merged);
    final others = merged.length - rows.length;
    out('Relay registry for "$org": ${merged.length} row(s) — ${rows.length} for this project, $others kept.');
  }

  String _readSecretFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw HooksFailure('no secret file at $path; run `hooks.dart secret --org <org>` first');
    }
    final value = file.readAsStringSync().trim();
    if (value.length < 16 || value.length > 512) {
      throw HooksFailure('the secret in $path is ${value.length} characters; the relay wants 16 to 512');
    }
    return value;
  }

  /// `chmod 600` where there is a chmod. Returns false on Windows (and if the
  /// call fails), which the caller says out loud.
  bool _restrict(File file) {
    if (Platform.isWindows) return false;
    try {
      return Process.runSync('chmod', ['600', file.path]).exitCode == 0;
    } on Object {
      return false;
    }
  }
}
