import '../../core/http/ado_client.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/pipeline.dart';

/// A list with where it came from.
typedef CachedList<T> = ({List<T> items, DateTime fetchedAt});

/// Pipelines (milestone 3): definitions with their latest builds, run lists
/// through the Build API, the timeline tree and logs of one run, queue /
/// cancel / retry, and YAML environment approvals (research/01 §5).
class PipelineRepository {
  PipelineRepository(this._client, [AppDatabase? db]) : _cache = JsonCache(db);

  final AdoClient _client;
  final JsonCache _cache;

  static const apiVersion = '7.1';

  static String definitionsKey(String org, String project) =>
      'pipelines:definitions:$org:$project';
  static String runsKey(String org, String project) =>
      'pipelines:runs:$org:$project';

  List<Map<String, dynamic>> _value(Map<String, dynamic> json) =>
      ((json['value'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  Future<List<PipelineDefinition>> definitions(
    String org,
    String project,
  ) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/build/definitions',
      apiVersion: apiVersion,
      query: {'includeLatestBuilds': 'true', r'$top': '500'},
    );
    final raw = _value(json);
    await _cache.put(definitionsKey(org, project), raw);
    return _definitions(raw);
  }

  Future<CachedList<PipelineDefinition>?> cachedDefinitions(
    String org,
    String project,
  ) async {
    final cached = await _cache.get(definitionsKey(org, project));
    if (cached == null || cached.json is! List) return null;
    return (
      items: _definitions(_value({'value': cached.json})),
      fetchedAt: cached.fetchedAt,
    );
  }

  List<PipelineDefinition> _definitions(List<Map<String, dynamic>> raw) =>
      raw.map(PipelineDefinition.fromJson).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Recent builds, newest queued first, optionally for one definition.
  Future<List<BuildRun>> runs(
    String org,
    String project, {
    int? definitionId,
    int top = 50,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/build/builds',
      apiVersion: apiVersion,
      query: {
        r'$top': '$top',
        'queryOrder': 'queueTimeDescending',
        'definitions': ?definitionId?.toString(),
      },
    );
    final raw = _value(json);
    if (definitionId == null) await _cache.put(runsKey(org, project), raw);
    return raw.map(BuildRun.fromJson).toList();
  }

  Future<CachedList<BuildRun>?> cachedRuns(String org, String project) async {
    final cached = await _cache.get(runsKey(org, project));
    if (cached == null || cached.json is! List) return null;
    return (
      items: _value({'value': cached.json}).map(BuildRun.fromJson).toList(),
      fetchedAt: cached.fetchedAt,
    );
  }

  Future<BuildRun> run(String org, String project, int id) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/build/builds/$id',
      apiVersion: apiVersion,
    );
    return BuildRun.fromJson(json);
  }

  Future<Timeline> timeline(String org, String project, int id) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/build/builds/$id/timeline',
      apiVersion: apiVersion,
    );
    return Timeline.fromJson(json);
  }

  /// Log lines of one timeline record (`build/builds/{id}/logs/{logId}`
  /// answers a JSON string array when asked for JSON).
  Future<List<String>> log(
    String org,
    String project,
    int buildId,
    int logId, {
    int? startLine,
    int? endLine,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/build/builds/$buildId/logs/$logId',
      apiVersion: apiVersion,
      query: {
        'startLine': ?startLine?.toString(),
        'endLine': ?endLine?.toString(),
      },
    );
    final value = json['value'];
    if (value is List) return value.map((l) => l.toString()).toList();
    if (value is String) return value.split('\n');
    return const [];
  }

  /// Queues a run of [pipelineId] on [branch] (`refs/heads/…`) and returns
  /// the new build. `runId` and `buildId` are the same integer.
  Future<BuildRun> queue(
    String org,
    String project,
    int pipelineId, {
    required String branch,
  }) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: project,
      path: '_apis/pipelines/$pipelineId/runs',
      apiVersion: apiVersion,
      body: {
        'resources': {
          'repositories': {
            'self': {'refName': branch},
          },
        },
      },
    );
    return run(org, project, (json['id'] as num).toInt());
  }

  /// `"status": "cancelling"`, two Ls (research/01 §5.1).
  Future<BuildRun> cancel(String org, String project, int id) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: project,
      path: '_apis/build/builds/$id',
      apiVersion: apiVersion,
      body: {'status': 'cancelling'},
    );
    return BuildRun.fromJson(json);
  }

  /// Retries a failed or canceled stage of a completed run in place.
  Future<void> retryStage(
    String org,
    String project,
    int id,
    String stageIdentifier, {
    bool forceRetryAllJobs = false,
  }) => _client.send(
    method: 'PATCH',
    org: org,
    project: project,
    path: '_apis/build/builds/$id/stages/$stageIdentifier',
    apiVersion: apiVersion,
    body: {'state': 'retry', 'forceRetryAllJobs': forceRetryAllJobs},
  );

  Future<List<PipelineApproval>> approvals(
    String org,
    String project, {
    String state = 'pending',
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/pipelines/approvals',
      apiVersion: apiVersion,
      query: {'state': state, r'$expand': 'steps'},
    );
    return _value(json).map(PipelineApproval.fromJson).toList();
  }

  Future<void> resolveApproval(
    String org,
    String project,
    String approvalId, {
    required bool approve,
    String? comment,
  }) => _client.send(
    method: 'PATCH',
    org: org,
    project: project,
    path: '_apis/pipelines/approvals',
    apiVersion: apiVersion,
    body: [
      {
        'approvalId': approvalId,
        'status': approve ? 'approved' : 'rejected',
        'comment': ?comment,
      },
    ],
  );
}
