import '../demo_backend.dart';
import '../demo_world.dart';
import 'pipelines/pipeline_logs.dart';
import 'pipelines/pipeline_plans.dart';

/// Pipelines: build definitions with their latest builds, the run lists
/// (project-wide and per definition, both query orders), one run with its
/// timeline and logs, pending environment approvals, and the writes the
/// app makes (queue, cancel, retry stage, approve / reject), which change
/// this backend's state for the rest of the session.
///
/// The screenshot runs: `boardhop-release` [DemoPipelines.featuredReleaseRunId]
/// waits for Kelly's approval before "Release to App Store"; `relay-deploy`
/// 3214 failed its health check; `boardhop-ci` 3217 is running.
void registerPipelineFixtures(DemoBackend b) {
  final state = _PipelineState();
  final p = '(?:${DemoWorld.project}|${DemoWorld.projectId})';
  final base = 'dev\\.azure\\.com/${DemoWorld.org}/$p/_apis';

  // --- Definitions ----------------------------------------------------------

  b.get('$base/build/definitions', (_) {
    final defs = [
      for (final d in DemoPipelines.definitions) state.definitionJson(d),
    ];
    return {'count': defs.length, 'value': defs};
  });

  b.get('$base/build/definitions/(\\d+)', (r) {
    final id = int.parse(r.group(1));
    final d = DemoPipelines.definitions.where((d) => d.id == id).firstOrNull;
    return d == null ? null : state.definitionJson(d);
  });

  b.get('$base/pipelines', (_) {
    final list = [
      for (final d in DemoPipelines.definitions) state.pipelineJson(d),
    ];
    return {'count': list.length, 'value': list};
  });

  // --- Runs -------------------------------------------------------------------

  b.get('$base/build/builds', (r) {
    final q = r.query;
    final top = int.tryParse(q[r'$top'] ?? '') ?? 1000;
    final defs = (q['definitions'] ?? '')
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
    final statusFilter = q['statusFilter'];
    final resultFilter = q['resultFilter'];
    final branch = q['branchName'];
    var builds = [
      for (final run in state.allRuns)
        if (defs.isEmpty || defs.contains(run.definition.id))
          state.buildJson(run),
    ];
    builds = [
      for (final build in builds)
        if ((statusFilter == null ||
                statusFilter.split(',').contains(build['status'])) &&
            (resultFilter == null ||
                resultFilter.split(',').contains(build['result'])) &&
            (branch == null || build['sourceBranch'] == branch))
          build,
    ];
    if (q['queryOrder'] == 'finishTimeDescending') {
      // Unfinished runs have no finish time; the service lists them last.
      builds.sort((a, b) {
        final fa = a['finishTime'] as String?;
        final fb = b['finishTime'] as String?;
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fb.compareTo(fa);
      });
    } else if (q['queryOrder'] == 'queueTimeAscending') {
      builds.sort(
        (a, b) =>
            (a['queueTime'] as String).compareTo(b['queueTime'] as String),
      );
    } else {
      builds.sort(
        (a, b) =>
            (b['queueTime'] as String).compareTo(a['queueTime'] as String),
      );
    }
    final page = builds.take(top).toList();
    return {'count': page.length, 'value': page};
  });

  b.get('$base/build/builds/(\\d+)', (r) {
    final run = state.run(int.parse(r.group(1)));
    return run == null ? null : state.buildJson(run);
  });

  b.get('$base/build/builds/(\\d+)/timeline(?:/[^/]+)?', (r) {
    final run = state.run(int.parse(r.group(1)));
    if (run == null) return null;
    final sim = state.simulate(run);
    return {
      'records': sim.records,
      'lastChangedBy': '00000002-0000-8888-8000-000000000000',
      'lastChangedOn': DemoWorld.iso(sim.finishTime ?? DemoWorld.now),
      'id': demoGuid('timeline:${run.id}'),
      'changeId': sim.records.length,
      'url':
          '${DemoWorld.projectUrl}/_apis/build/builds/${run.id}/Timeline/'
          '${demoGuid('timeline:${run.id}')}',
    };
  });

  b.get('$base/build/builds/(\\d+)/logs', (r) {
    final run = state.run(int.parse(r.group(1)));
    if (run == null) return null;
    final sim = state.simulate(run);
    final logs = [
      for (final log in sim.logs.values)
        {
          'lineCount': demoLogLines(run, log).length,
          'createdOn': DemoWorld.iso(log.start),
          'lastChangedOn': DemoWorld.iso(log.finish),
          'id': log.id,
          'type': 'Container',
          'url':
              '${DemoWorld.projectUrl}/_apis/build/builds/${run.id}/logs/${log.id}',
        },
    ];
    return {'count': logs.length, 'value': logs};
  });

  b.get('$base/build/builds/(\\d+)/logs/(\\d+)', (r) {
    final run = state.run(int.parse(r.group(1)));
    if (run == null) return null;
    final log = state.simulate(run).logs[int.parse(r.group(2))];
    if (log == null) return null;
    var lines = demoLogLines(run, log);
    // startLine / endLine are 1-based and inclusive.
    final start = int.tryParse(r.query['startLine'] ?? '');
    final end = int.tryParse(r.query['endLine'] ?? '');
    if (start != null || end != null) {
      final from = ((start ?? 1) - 1).clamp(0, lines.length);
      final to = (end ?? lines.length).clamp(from, lines.length);
      lines = lines.sublist(from, to);
    }
    return {'count': lines.length, 'value': lines};
  });

  b.get('$base/build/builds/(\\d+)/changes', (r) {
    final run = state.run(int.parse(r.group(1)));
    if (run == null) return null;
    final change = {
      'id': run.sha,
      'message': run.message ?? 'Update',
      'type': 'TfsGit',
      'author': run.requestedFor.identity(),
      'timestamp': DemoWorld.iso(run.queued),
      'location':
          '${DemoWorld.projectUrl}/_apis/git/repositories/${run.definition.repo.id}/commits/${run.sha}',
      'displayUri': '${run.definition.repo.url}/commit/${run.sha}',
    };
    return {
      'count': 1,
      'value': [change],
    };
  });

  b.get('$base/build/builds/(\\d+)/artifacts', (r) {
    final run = state.run(int.parse(r.group(1)));
    if (run == null) return null;
    final names = switch (run.definition.name) {
      'boardhop-release' => ['ipa', 'aab', 'test-results'],
      'boardhop-ci' => ['test-results'],
      'relay-deploy' => ['relay-image'],
      _ => ['vsix'],
    };
    final sim = state.simulate(run);
    final list = [
      if (sim.logs.isNotEmpty)
        for (final (i, n) in names.indexed)
          {
            'id': i + 1,
            'name': n,
            'source': demoGuid('artifact-source:${run.id}:$n'),
            'resource': {
              'type': 'PipelineArtifact',
              'data': demoHex('artifact:${run.id}:$n', 40),
              'downloadUrl':
                  '${DemoWorld.baseUrl}/${DemoWorld.projectId}/_apis/build/builds/${run.id}/artifacts?artifactName=$n&api-version=7.1&%24format=zip',
            },
          },
    ];
    return {'count': list.length, 'value': list};
  });

  // --- Writes -----------------------------------------------------------------

  b.post('$base/pipelines/(\\d+)/runs', (r) {
    final id = int.parse(r.group(1));
    final def = DemoPipelines.definitions.where((d) => d.id == id).firstOrNull;
    if (def == null) return null;
    final body = r.body;
    var branch = 'refs/heads/main';
    if (body is Map) {
      final ref =
          ((((body['resources'] as Map?)?['repositories'] as Map?)?['self']
                  as Map?)?['refName'])
              as String?;
      if (ref != null && ref.isNotEmpty) branch = ref;
    }
    final run = state.queue(def, branch);
    return {
      'id': run.id,
      'name': state.buildNumber(run),
      'state': 'inProgress',
      'createdDate': DemoWorld.iso(run.queued),
      'pipeline': state.pipelineJson(def),
      'url': '${DemoWorld.projectUrl}/_apis/pipelines/${def.id}/runs/${run.id}',
    };
  });

  b.patch('$base/build/builds/(\\d+)', (r) {
    final run = state.run(int.parse(r.group(1)));
    if (run == null) return null;
    final body = r.body;
    if (body is Map && body['status'] == 'cancelling') state.cancel(run.id);
    return state.buildJson(state.run(run.id)!);
  });

  b.patch('$base/build/builds/(\\d+)/stages/([^/]+)', (r) {
    final run = state.run(int.parse(r.group(1)));
    return run == null ? null : const DemoResponse(204);
  });

  // --- Approvals and environments ------------------------------------------

  b.get('$base/pipelines/approvals', (r) {
    final wanted = (r.query['state'] ?? 'pending').split(',');
    final expand = (r.query[r'$expand'] ?? '').contains('steps');
    final list = [
      for (final a in state.pendingApprovals())
        if (wanted.contains('pending') || wanted.contains('all'))
          state.approvalJson(a, steps: expand),
    ];
    return {'count': list.length, 'value': list};
  });

  b.get('$base/pipelines/approvals/([^/]+)', (r) {
    final id = r.group(1);
    final a = state.pendingApprovals().where((a) => a.id == id).firstOrNull;
    if (a == null) return null;
    return state.approvalJson(a, steps: true);
  });

  b.patch('$base/pipelines/approvals', (r) {
    final body = r.body;
    if (body is! List) return const DemoResponse(400);
    final updated = <Object>[];
    for (final u in body.whereType<Map>()) {
      final id = u['approvalId'] as String?;
      final a = state.pendingApprovals().where((a) => a.id == id).firstOrNull;
      if (a == null) continue;
      final approved = u['status'] == 'approved';
      state.decide(a, approved: approved, comment: u['comment'] as String?);
      updated.add({
        ...state.approvalJson(a, steps: true),
        'status': approved ? 'approved' : 'rejected',
      });
    }
    return {'count': updated.length, 'value': updated};
  });

  b.get('$base/distributedtask/environments', (_) {
    final list = [
      for (final (i, name) in const [
        'app-store',
        'boardhop-relay-1',
        'marketplace',
      ].indexed)
        {
          'id': i + 3,
          'name': name,
          'description': '',
          'createdBy': DemoWorld.kelly.identity(),
          'createdOn': DemoWorld.iso(DemoWorld.daysAgo(120 - i * 20)),
          'lastModifiedBy': DemoWorld.kelly.identity(),
          'lastModifiedOn': DemoWorld.iso(DemoWorld.daysAgo(30)),
          'project': {'id': DemoWorld.projectId},
        },
    ];
    return {'count': list.length, 'value': list};
  });
}

class _PipelineState {
  final Map<String, DemoDecision> decisions = {};
  final Set<int> canceled = {};
  final List<DemoRun> queued = [];

  List<DemoRun> get allRuns => [
    for (final r in [...DemoPipelines.runs, ...queued])
      canceled.contains(r.id) ? _canceledCopy(r) : r,
  ];

  DemoRun? run(int id) => allRuns.where((r) => r.id == id).firstOrNull;

  DemoRun _canceledCopy(DemoRun r) => DemoRun(
    id: r.id,
    definition: r.definition,
    queued: r.queued,
    requestedFor: r.requestedFor,
    reason: r.reason,
    stages: r.stages,
    branch: r.branch,
    message: r.message,
    pr: r.pr,
    prBranch: r.prBranch,
    waitSeconds: r.waitSeconds,
    canceled: true,
  );

  DemoSimulation simulate(DemoRun run) =>
      simulateRun(run, decisions: decisions);

  List<DemoPendingApproval> pendingApprovals() => [
    for (final r in allRuns.reversed) ...simulate(r).pending,
  ];

  void decide(
    DemoPendingApproval a, {
    required bool approved,
    String? comment,
  }) {
    decisions[a.id] = DemoDecision(
      approved: approved,
      // The app reloads right away; the next stage is already under way.
      at: DemoWorld.now.subtract(const Duration(seconds: 30)),
      by: DemoWorld.me,
      comment: comment,
    );
  }

  void cancel(int id) => canceled.add(id);

  DemoRun queue(DemoDefinition def, String branch) {
    final last = allRuns.map((r) => r.id).fold(0, (a, b) => a > b ? a : b);
    final run = DemoRun(
      id: last + 1,
      definition: def,
      queued: DemoWorld.now,
      requestedFor: DemoWorld.me,
      reason: 'manual',
      branch: branch,
      // Queued after the demo's clock: no agent has picked it up.
      waitSeconds: 3600,
      stages: switch (def.name) {
        'boardhop-ci' => DemoPipelines.ciPlan(),
        'boardhop-release' => DemoPipelines.releasePlan(),
        'relay-deploy' => DemoPipelines.relayPlan(),
        _ => DemoPipelines.extensionPlan,
      },
    );
    queued.add(run);
    return run;
  }

  /// `yyyyMMdd.r`, r counting that pipeline's runs queued the same UTC day.
  String buildNumber(DemoRun run) {
    final day = _day(run.queued);
    final rev = allRuns
        .where(
          (r) =>
              r.definition.id == run.definition.id &&
              _day(r.queued) == day &&
              r.id <= run.id,
        )
        .length;
    return '$day.$rev';
  }

  static String _day(DateTime t) =>
      '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> get _projectRef => {
    'id': DemoWorld.projectId,
    'name': DemoWorld.project,
    'description': DemoWorld.projectDescription,
    'url': '${DemoWorld.baseUrl}/_apis/projects/${DemoWorld.projectId}',
    'state': 'wellFormed',
    'revision': 412,
    'visibility': 'private',
    'lastUpdateTime': DemoWorld.iso(DemoWorld.hoursAgo(3)),
  };

  Map<String, dynamic> _definitionRef(DemoDefinition d) => {
    'drafts': const [],
    'id': d.id,
    'name': d.name,
    'url':
        '${DemoWorld.projectUrl}/_apis/build/Definitions/${d.id}?revision=${d.revision}',
    'uri': 'vstfs:///Build/Definition/${d.id}',
    'path': '\\',
    'type': 'build',
    'queueStatus': 'enabled',
    'revision': d.revision,
    'project': _projectRef,
  };

  Map<String, dynamic> _repository(DemoRepo repo) => {
    'id': repo.id,
    'type': 'TfsGit',
    'name': repo.name,
    'url': repo.url,
    'clean': null,
    'checkoutSubmodules': false,
  };

  Map<String, dynamic> definitionJson(DemoDefinition d) {
    final runs = allRuns.where((r) => r.definition.id == d.id).toList()
      ..sort((a, b) => b.queued.compareTo(a.queued));
    final builds = [for (final r in runs) buildJson(r)];
    final latest = builds.firstOrNull;
    final completed = builds
        .where((b) => b['status'] == 'completed')
        .firstOrNull;
    return {
      ..._definitionRef(d),
      '_links': {
        'self': {
          'href': '${DemoWorld.projectUrl}/_apis/build/Definitions/${d.id}',
        },
        'web': {
          'href':
              '${DemoWorld.baseUrl}/${DemoWorld.projectId}/_build/definition?definitionId=${d.id}',
        },
      },
      'quality': 'definition',
      'authoredBy': DemoWorld.kelly.identity(),
      'queue': _queue,
      'process': {'yamlFilename': d.yaml, 'type': 2},
      'repository': _repository(d.repo),
      'createdDate': DemoWorld.iso(DemoWorld.daysAgo(140 - d.id)),
      'latestBuild': ?latest,
      'latestCompletedBuild': ?completed,
    };
  }

  Map<String, dynamic> pipelineJson(DemoDefinition d) => {
    '_links': {
      'self': {
        'href':
            '${DemoWorld.projectUrl}/_apis/pipelines/${d.id}?revision=${d.revision}',
      },
      'web': {
        'href':
            '${DemoWorld.baseUrl}/${DemoWorld.projectId}/_build/definition?definitionId=${d.id}',
      },
    },
    'url':
        '${DemoWorld.projectUrl}/_apis/pipelines/${d.id}?revision=${d.revision}',
    'id': d.id,
    'revision': d.revision,
    'name': d.name,
    'folder': '\\',
  };

  static final Map<String, dynamic> _queue = {
    'id': 9,
    'name': 'Azure Pipelines',
    'pool': {'id': 9, 'name': 'Azure Pipelines', 'isHosted': true},
  };

  Map<String, dynamic> buildJson(DemoRun run) {
    final sim = simulate(run);
    final web =
        '${DemoWorld.baseUrl}/${DemoWorld.projectId}/_build/results?buildId=${run.id}';
    final repo = run.definition.repo;
    final started = run.started.isAfter(DemoWorld.now) ? null : run.started;
    final status = started == null && !run.canceled ? 'notStarted' : sim.status;
    return {
      '_links': {
        'self': {
          'href': '${DemoWorld.projectUrl}/_apis/build/Builds/${run.id}',
        },
        'web': {'href': web},
        'sourceVersionDisplayUri': {
          'href':
              '${DemoWorld.projectUrl}/_apis/build/builds/${run.id}/sources',
        },
        'timeline': {
          'href':
              '${DemoWorld.projectUrl}/_apis/build/builds/${run.id}/Timeline',
        },
        'badge': {
          'href':
              '${DemoWorld.projectUrl}/_apis/build/status/${run.definition.id}',
        },
      },
      'properties': const {},
      'tags': const [],
      'validationResults': const [],
      'plans': [
        {'planId': demoGuid('plan:${run.id}')},
      ],
      'templateParameters': const {},
      'triggerInfo': _triggerInfo(run),
      'id': run.id,
      'buildNumber': buildNumber(run),
      'status': status,
      'result': status == 'completed' ? sim.result : null,
      'queueTime': DemoWorld.iso(run.queued),
      'startTime': started == null ? null : DemoWorld.iso(started),
      'finishTime': sim.finishTime == null
          ? null
          : DemoWorld.iso(sim.finishTime!),
      'url': '${DemoWorld.projectUrl}/_apis/build/Builds/${run.id}',
      'definition': _definitionRef(run.definition),
      'buildNumberRevision': int.parse(buildNumber(run).split('.').last),
      'project': _projectRef,
      'uri': 'vstfs:///Build/Build/${run.id}',
      'sourceBranch': run.branch,
      'sourceVersion': run.sha,
      'queue': _queue,
      'priority': 'normal',
      'reason': run.reason,
      'requestedFor': run.requestedFor.identity(),
      'requestedBy': run.reason == 'individualCI' || run.reason == 'pullRequest'
          ? {
              'displayName': 'Microsoft.VisualStudio.Services.TFS',
              'id': '00000002-0000-8888-8000-000000000000',
              'uniqueName': '00000002-0000-8888-8000-000000000000@2c895908-04e0-4952-89fd-54b0046d6288',
            }
          : run.requestedFor.identity(),
      'lastChangedDate': DemoWorld.iso(sim.finishTime ?? DemoWorld.now),
      'lastChangedBy': run.requestedFor.identity(),
      'orchestrationPlan': {'planId': demoGuid('plan:${run.id}')},
      'logs': {
        'id': 0,
        'type': 'Container',
        'url': '${DemoWorld.projectUrl}/_apis/build/builds/${run.id}/logs',
      },
      'repository': _repository(repo),
      'retainedByRelease': false,
      'triggeredByBuild': null,
      'appendCommitMessageToRunName': true,
    };
  }

  Map<String, dynamic> _triggerInfo(DemoRun run) {
    final repo = run.definition.repo;
    if (run.reason == 'pullRequest') {
      return {
        'pr.number': '${run.pr}',
        'pr.isFork': 'False',
        'pr.triggerRepository': repo.id,
        'pr.triggerRepository.Type': 'TfsGit',
        'pr.sourceBranch': run.prBranch ?? 'refs/heads/topic',
        'pr.sourceSha': run.sha,
        'pr.id': '${run.pr}',
        'pr.title': run.message ?? '',
        'pr.draft': 'False',
      };
    }
    if (run.reason == 'individualCI' || run.reason == 'batchedCI') {
      return {
        'ci.sourceBranch': run.branch,
        'ci.sourceSha': run.sha,
        'ci.message': run.message ?? '',
        'ci.triggerRepository': repo.id,
      };
    }
    return const {};
  }

  Map<String, dynamic> approvalJson(
    DemoPendingApproval a, {
    required bool steps,
  }) {
    final run = a.run;
    return {
      'id': a.id,
      if (steps)
        'steps': [
          for (final (i, person) in a.gate.approvers.indexed)
            {
              'assignedApprover': person.identity(),
              'status': 'pending',
              'comment': null,
              'initiatedOn': DemoWorld.iso(a.createdOn),
              'order': i + 1,
            },
        ],
      'status': 'pending',
      'createdOn': DemoWorld.iso(a.createdOn),
      'lastModifiedOn': DemoWorld.iso(a.createdOn),
      'instructions': a.gate.instructions,
      'minRequiredApprovers': 1,
      'executionOrder': 'anyOrder',
      'blockedApprovers': const [],
      'pipeline': {
        'owner': {
          '_links': {
            'web': {
              'href':
                  '${DemoWorld.baseUrl}/${DemoWorld.projectId}/_build/results?buildId=${run.id}',
            },
          },
          'id': run.id,
          'name': buildNumber(run),
        },
        'id': '${run.definition.id}',
        'name': run.definition.name,
      },
      '_links': {
        'self': {
          'href': '${DemoWorld.projectUrl}/_apis/pipelines/approvals/${a.id}',
        },
      },
    };
  }
}
