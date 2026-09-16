import '../../demo_world.dart';

/// The demo's pipelines as plans (stages → jobs → tasks with durations) and
/// runs of them. A run's timeline is not stored: [simulateRun] lays the
/// plan out from the run's start time and reads every record's state off
/// the clock ([DemoWorld.now]), so durations, states, results, log ids and
/// the run's own status always agree with each other.

class DemoTask {
  const DemoTask(this.name, this.seconds, {this.fails = false, this.log});

  final String name;
  final int seconds;

  /// Completes as failed, with the plan's failure issues.
  final bool fails;

  /// Which log body the task writes (see pipeline_logs.dart).
  final String? log;
}

class DemoJob {
  const DemoJob(
    this.name,
    this.id,
    this.tasks, {
    this.after = const [],
    this.worker = 'Azure Pipelines 4',
    this.issues = const [],
  });

  final String name;

  /// YAML job name, the identifier's middle part.
  final String id;
  final List<DemoTask> tasks;

  /// Job ids in the same stage this one waits for.
  final List<String> after;
  final String worker;

  /// Issues the failing task reports (error messages).
  final List<String> issues;
}

/// An environment approval in front of a stage's jobs.
class DemoGate {
  const DemoGate({
    required this.environment,
    required this.approvers,
    required this.instructions,
    this.decidedAfter,
    this.decidedBy,
  });

  final String environment;
  final List<DemoPerson> approvers;
  final String instructions;

  /// For finished runs: how long the approval waited before [decidedBy]
  /// approved it. Null leaves it pending.
  final Duration? decidedAfter;
  final DemoPerson? decidedBy;

  DemoGate decided(Duration after, DemoPerson by) => DemoGate(
    environment: environment,
    approvers: approvers,
    instructions: instructions,
    decidedAfter: after,
    decidedBy: by,
  );
}

class DemoStage {
  const DemoStage(this.name, this.id, this.jobs, {this.gate});

  final String name;
  final String id;
  final List<DemoJob> jobs;
  final DemoGate? gate;
}

class DemoDefinition {
  const DemoDefinition({
    required this.id,
    required this.name,
    required this.repo,
    required this.yaml,
    required this.revision,
  });

  final int id;
  final String name;
  final DemoRepo repo;
  final String yaml;
  final int revision;
}

class DemoRun {
  const DemoRun({
    required this.id,
    required this.definition,
    required this.queued,
    required this.requestedFor,
    required this.reason,
    required this.stages,
    this.branch = 'refs/heads/main',
    this.message,
    this.pr,
    this.prBranch,
    this.waitSeconds = 20,
    this.canceled = false,
  });

  final int id;
  final DemoDefinition definition;
  final DateTime queued;
  final DemoPerson requestedFor;

  /// `individualCI | pullRequest | manual | schedule`.
  final String reason;
  final List<DemoStage> stages;
  final String branch;

  /// The commit message (CI) or pull request title (PR builds).
  final String? message;
  final int? pr;
  final String? prBranch;

  /// Queue time to agent pickup.
  final int waitSeconds;
  final bool canceled;

  DateTime get started => queued.add(Duration(seconds: waitSeconds));

  String get sha => demoHex('commit:$id:${definition.name}', 40);
}

/// An approval decided in this session (Approve / Reject in the app).
class DemoDecision {
  const DemoDecision({
    required this.approved,
    required this.at,
    required this.by,
    this.comment,
  });

  final bool approved;
  final DateTime at;
  final DemoPerson by;
  final String? comment;
}

// --- Identifiers ------------------------------------------------------------

int _fnv(String s, int seed) {
  var h = 0x811c9dc5 ^ seed;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Stable hex of [length] digits for [key].
String demoHex(String key, int length) {
  final b = StringBuffer();
  var i = 0;
  while (b.length < length) {
    b.write(_fnv(key, i++ * 7919).toRadixString(16).padLeft(8, '0'));
  }
  return b.toString().substring(0, length);
}

/// A stable GUID for [key].
String demoGuid(String key) {
  final h = demoHex(key, 32);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-'
      'a${h.substring(17, 20)}-${h.substring(20)}';
}

// --- Plans --------------------------------------------------------------------

abstract final class DemoPipelines {
  static const ci = DemoDefinition(
    // The id the pull requests' build policy names.
    id: 7,
    name: 'boardhop-ci',
    repo: DemoWorld.appRepo,
    yaml: 'pipelines/ci.yml',
    revision: 31,
  );
  static const release = DemoDefinition(
    id: 14,
    name: 'boardhop-release',
    repo: DemoWorld.appRepo,
    yaml: 'pipelines/release.yml',
    revision: 18,
  );
  static const relay = DemoDefinition(
    id: 17,
    name: 'relay-deploy',
    repo: DemoWorld.relayRepo,
    yaml: 'pipelines/deploy.yml',
    revision: 9,
  );
  static const extension = DemoDefinition(
    id: 21,
    name: 'extension-publish',
    repo: DemoWorld.extensionRepo,
    yaml: 'pipelines/publish.yml',
    revision: 6,
  );

  static const definitions = [ci, release, relay, extension];

  static List<DemoTask> _setup(String repo, {int flutter = 30}) => [
    const DemoTask('Initialize job', 3),
    DemoTask('Checkout $repo@main to s', 6),
    if (flutter > 0) DemoTask('Install Flutter 3.47.2', flutter),
  ];

  static const _finish = [
    DemoTask('Post-job: Checkout boardhop@main to s', 1),
    DemoTask('Finalize Job', 2),
  ];

  /// 3m 12s.
  static DemoJob analyzeAndTest() => DemoJob('Analyze & test', 'analyze', [
    ..._setup('boardhop'),
    const DemoTask('flutter pub get', 18, log: 'pubget'),
    const DemoTask('dart run build_runner build', 29, log: 'build_runner'),
    const DemoTask('flutter analyze', 24, log: 'analyze'),
    const DemoTask('flutter test', 75, log: 'test'),
    const DemoTask('Publish test results', 4),
    ..._finish,
  ], worker: 'Azure Pipelines 7');

  static List<DemoStage> ciPlan({bool failLint = false}) => [
    DemoStage('Validate', 'Validate', [
      analyzeAndTest(),
      DemoJob('Golden tests', 'goldens', [
        ..._setup('boardhop'),
        const DemoTask('flutter pub get', 18, log: 'pubget'),
        const DemoTask('flutter test --tags golden', 64, log: 'goldens'),
        const DemoTask('Publish test results', 4),
        ..._finish,
      ], worker: 'Azure Pipelines 3'),
      DemoJob(
        'Android lint',
        'lint',
        [
          ..._setup('boardhop'),
          const DemoTask('Use Java 17', 11),
          const DemoTask('flutter pub get', 18, log: 'pubget'),
          DemoTask(
            './gradlew lint',
            failLint ? 88 : 96,
            fails: failLint,
            log: failLint ? 'lint_failed' : 'lint',
          ),
          ..._finish,
        ],
        worker: 'Azure Pipelines 6',
        issues: const [
          'AndroidManifest.xml:14: Error: POST_NOTIFICATIONS must be '
              'requested at runtime on API 33 and up '
              '[NotificationPermission]',
          'Lint found 1 error, 0 warnings.',
        ],
      ),
    ]),
  ];

  static const appStoreGate = DemoGate(
    environment: 'app-store',
    approvers: [DemoWorld.kelly, DemoWorld.jonah],
    instructions:
        'Install build 18 from TestFlight and run the release checklist '
        'before it goes to App Review.',
  );

  static List<DemoStage> releasePlan({DemoGate gate = appStoreGate}) => [
    DemoStage('Build', 'Build', [
      analyzeAndTest(),
      DemoJob(
        'Build iOS',
        'ios',
        [
          ..._setup('boardhop', flutter: 31),
          const DemoTask('Install Apple distribution certificate', 6),
          const DemoTask('Install provisioning profile', 3),
          const DemoTask('flutter pub get', 22, log: 'pubget'),
          const DemoTask('flutter build ipa', 600, log: 'ipa'),
          const DemoTask('Validate IPA', 18),
          const DemoTask('Publish artifact: ipa', 9),
          const DemoTask('Post-job: Checkout boardhop@main to s', 1),
          const DemoTask('Finalize Job', 1),
        ],
        after: const ['analyze'],
        worker: 'Azure Pipelines 11',
      ),
      DemoJob(
        'Build Android',
        'android',
        [
          ..._setup('boardhop'),
          const DemoTask('Use Java 17', 11),
          const DemoTask('flutter pub get', 19, log: 'pubget'),
          const DemoTask('flutter build appbundle', 386, log: 'aab'),
          const DemoTask('Publish artifact: aab', 8),
          const DemoTask('Post-job: Checkout boardhop@main to s', 1),
          const DemoTask('Finalize Job', 1),
        ],
        after: const ['analyze'],
        worker: 'Azure Pipelines 5',
      ),
    ]),
    const DemoStage('Beta', 'Beta', [
      DemoJob('Upload to TestFlight', 'testflight', [
        DemoTask('Initialize job', 3),
        DemoTask('Download artifact: ipa', 12),
        DemoTask('Upload build 18 to TestFlight', 250, log: 'testflight'),
        DemoTask('Finalize Job', 1),
      ], worker: 'Azure Pipelines 9'),
      DemoJob('Upload to Play internal', 'play', [
        DemoTask('Initialize job', 3),
        DemoTask('Download artifact: aab', 9),
        DemoTask('fastlane supply --track internal', 158),
        DemoTask('Finalize Job', 1),
      ], worker: 'Azure Pipelines 2'),
    ]),
    DemoStage('Release to App Store', 'AppStore', const [
      DemoJob('Submit for review', 'submit', [
        DemoTask('Initialize job', 3),
        DemoTask('Download artifact: ipa', 10),
        DemoTask('Submit build 18 for App Review', 46),
        DemoTask('Finalize Job', 1),
      ], worker: 'Azure Pipelines 6'),
    ], gate: gate),
    const DemoStage('Tag release', 'Tag', [
      DemoJob('Tag and publish notes', 'tag', [
        DemoTask('Initialize job', 3),
        DemoTask('Checkout boardhop@main to s', 6),
        DemoTask('git tag v1.4.0+18', 5),
        DemoTask('Publish release notes to the wiki', 12),
        DemoTask('Finalize Job', 1),
      ], worker: 'Azure Pipelines 1'),
    ]),
  ];

  static List<DemoStage> relayPlan({bool failHealth = false}) => [
    const DemoStage('Build', 'Build', [
      DemoJob('Build relay image', 'image', [
        DemoTask('Initialize job', 3),
        DemoTask('Checkout boardhop-relay@main to s', 5),
        DemoTask('dart test', 48, log: 'dart_test'),
        DemoTask('docker build', 96),
        DemoTask('docker push', 31),
        DemoTask('Finalize Job', 1),
      ], worker: 'Azure Pipelines 8'),
    ]),
    DemoStage('Deploy', 'Deploy', [
      DemoJob(
        'Deploy to boardhop-relay-1',
        'deploy',
        [
          const DemoTask('Initialize job', 3),
          const DemoTask('Download image manifest', 4),
          const DemoTask('docker compose pull', 22),
          const DemoTask('docker compose up -d', 14),
          DemoTask(
            'Health check /healthz',
            failHealth ? 64 : 9,
            fails: failHealth,
            log: failHealth ? 'health_failed' : 'health',
          ),
          const DemoTask('Finalize Job', 1),
        ],
        worker: 'boardhop-relay-1',
        issues: const [
          'Health check failed: https://boardhop.relay.kammcs.com/healthz '
              'answered 503 six times in 60 s (apns: signing key not loaded).',
          'Bash exited with code \'1\'.',
        ],
      ),
    ]),
  ];

  static const extensionPlan = [
    DemoStage('Publish', 'Publish', [
      DemoJob('Package and publish', 'publish', [
        DemoTask('Initialize job', 3),
        DemoTask('Checkout boardhop-extension@main to s', 5),
        DemoTask('npm ci', 27),
        DemoTask('npm run build', 9),
        DemoTask('tfx extension publish', 41, log: 'tfx'),
        DemoTask('Finalize Job', 1),
      ], worker: 'Azure Pipelines 4'),
    ]),
  ];

  /// The release run the store screenshot opens.
  static const featuredReleaseRunId = 3216;

  /// Every run, oldest first. Ids grow with queue time.
  static final List<DemoRun> runs = _runs();

  static DemoRun? run(int id) => runs.where((r) => r.id == id).firstOrNull;

  static List<DemoRun> _runs() {
    DateTime ago(num minutes) => DemoWorld.minutesAgo(minutes);
    final recent = <DemoRun>[
      DemoRun(
        id: 3208,
        definition: release,
        queued: ago(26 * 60 + 12),
        requestedFor: DemoWorld.kelly,
        reason: 'manual',
        stages: releasePlan(
          gate: appStoreGate.decided(
            const Duration(minutes: 14),
            DemoWorld.kelly,
          ),
        ),
      ),
      DemoRun(
        id: 3209,
        definition: ci,
        queued: ago(7 * 60 + 4),
        reason: 'pullRequest',
        requestedFor: DemoWorld.jonah,
        branch: 'refs/pull/414/merge',
        pr: 414,
        prBranch: 'refs/heads/feature/approve-from-push',
        message: 'Approve a waiting stage from the notification',
        stages: ciPlan(failLint: true),
      ),
      DemoRun(
        id: 3210,
        definition: relay,
        queued: ago(6 * 60 + 31),
        requestedFor: DemoWorld.jonah,
        reason: 'individualCI',
        message: 'Merge PR 408: Rate-limit hook retries per subscription',
        stages: relayPlan(),
      ),
      DemoRun(
        id: 3211,
        definition: ci,
        queued: ago(5 * 60 + 2),
        requestedFor: DemoWorld.sofia,
        reason: 'individualCI',
        message: 'Merge PR 407: Dark mode chips keep their contrast',
        stages: ciPlan(),
      ),
      DemoRun(
        id: 3212,
        definition: extension,
        queued: ago(3 * 60 + 33),
        requestedFor: DemoWorld.aiko,
        reason: 'manual',
        stages: extensionPlan,
      ),
      DemoRun(
        id: 3213,
        definition: ci,
        queued: ago(2 * 60 + 41),
        requestedFor: DemoWorld.kelly,
        reason: 'pullRequest',
        branch: 'refs/pull/417/merge',
        pr: 417,
        prBranch: 'refs/heads/feature/glass-rail',
        message: 'Floating liquid glass rail on iPad',
        stages: ciPlan(),
      ),
      DemoRun(
        id: 3214,
        definition: relay,
        queued: ago(110),
        requestedFor: DemoWorld.aiko,
        reason: 'individualCI',
        message: 'Merge PR 410: Load the APNs signing key from secrets/',
        stages: relayPlan(failHealth: true),
      ),
      DemoRun(
        id: 3215,
        definition: ci,
        queued: ago(58),
        requestedFor: DemoWorld.marcus,
        reason: 'pullRequest',
        branch: 'refs/pull/412/merge',
        pr: 412,
        prBranch: 'refs/heads/feature/side-by-side-diff',
        message: 'Side-by-side diff on iPad',
        stages: ciPlan(),
      ),
      DemoRun(
        id: featuredReleaseRunId,
        definition: release,
        queued: ago(47),
        waitSeconds: 25,
        requestedFor: DemoWorld.kelly,
        reason: 'individualCI',
        message: 'Merge PR 403: Offline cache for boards',
        stages: releasePlan(),
      ),
      DemoRun(
        id: 3217,
        definition: ci,
        queued: ago(2.8),
        waitSeconds: 18,
        requestedFor: DemoWorld.sofia,
        reason: 'pullRequest',
        branch: 'refs/pull/409/merge',
        pr: 409,
        prBranch: 'refs/heads/fix/burndown-last-day',
        message: 'Include the last working day in the burndown',
        stages: ciPlan(),
      ),
    ];

    // Quieter history for the Build History widget and the per-pipeline
    // filter: a CI run every half day or so, relay and extension now and
    // then, all green.
    final older = <DemoRun>[];
    var id = 3190;
    const who = [
      DemoWorld.marcus,
      DemoWorld.priya,
      DemoWorld.kelly,
      DemoWorld.sofia,
      DemoWorld.jonah,
      DemoWorld.aiko,
    ];
    const messages = [
      'Merge PR 396: Pull request inbox across repositories',
      'Merge PR 397: Work item form keeps unsaved edits',
      'Merge PR 398: Live log tail for running jobs',
      'Merge PR 399: Stage graph spacing on tablets',
      'Merge PR 400: Pipeline approvals from the Activity feed',
      'Merge PR 401: Sprint picker remembers the last team',
    ];
    for (var i = 0; i < 18; i++) {
      final hours = 30 + (17 - i) * 7.5;
      final def = i % 6 == 2
          ? relay
          : i % 9 == 4
          ? extension
          : i == 7
          ? release
          : ci;
      older.add(
        DemoRun(
          id: id++,
          definition: def,
          queued: ago(hours * 60),
          requestedFor: who[i % who.length],
          reason: def == release || def == extension
              ? 'manual'
              : 'individualCI',
          message: def == release || def == extension
              ? null
              : messages[i % messages.length],
          waitSeconds: 12 + i % 5 * 7,
          stages: def == ci
              ? ciPlan()
              : def == relay
              ? relayPlan()
              : def == extension
              ? extensionPlan
              : releasePlan(
                  gate: appStoreGate.decided(
                    const Duration(minutes: 31),
                    DemoWorld.jonah,
                  ),
                ),
        ),
      );
    }
    return [...older, ...recent];
  }
}

// --- Simulation ----------------------------------------------------------------

/// A pending approval the simulation found.
class DemoPendingApproval {
  DemoPendingApproval(this.id, this.run, this.stage, this.gate, this.createdOn);

  final String id;
  final DemoRun run;
  final DemoStage stage;
  final DemoGate gate;
  final DateTime createdOn;
}

/// A log the simulation assigned to a completed task.
class DemoLog {
  DemoLog(this.id, this.name, this.kind, this.start, this.finish, this.failed);

  final int id;
  final String name;
  final String? kind;
  final DateTime start;
  final DateTime finish;
  final bool failed;
}

class DemoSimulation {
  DemoSimulation(this.run);

  final DemoRun run;
  final List<Map<String, dynamic>> records = [];
  final List<DemoPendingApproval> pending = [];
  final Map<int, DemoLog> logs = {};
  String status = 'inProgress';
  String result = 'none';
  DateTime? finishTime;
}

String approvalIdFor(DemoRun run, DemoStage stage) =>
    demoGuid('approval:${run.id}:${stage.id}');

/// Lays [run] out against [clock]. [decisions] holds approvals decided in
/// this session, by approval id.
DemoSimulation simulateRun(
  DemoRun run, {
  DateTime? clock,
  Map<String, DemoDecision> decisions = const {},
}) {
  final now = clock ?? DemoWorld.now;
  final sim = DemoSimulation(run);
  var logId = 1;
  var cursor = run.started;
  var failedBefore = false;
  var openBefore = false;

  String rid(String path) => demoGuid('record:${run.id}:$path');
  Map<String, dynamic> record({
    required String id,
    String? parentId,
    required String type,
    required String name,
    required int order,
    required String identifier,
    required String state,
    String? result,
    DateTime? start,
    DateTime? finish,
    String? worker,
    int? log,
    List<String> errors = const [],
    Map<String, dynamic>? task,
  }) => {
    'previousAttempts': const [],
    'id': id,
    'parentId': parentId,
    'type': type,
    'name': name,
    'startTime': start == null ? null : DemoWorld.iso(start),
    'finishTime': finish == null ? null : DemoWorld.iso(finish),
    'currentOperation': null,
    'percentComplete': state == 'completed' ? 100 : 0,
    'state': state,
    'result': result,
    'resultCode': result == 'failed' ? 'Error' : null,
    'changeId': order + 1,
    'lastModified': DemoWorld.iso(finish ?? start ?? run.queued),
    'workerName': worker,
    'order': order,
    'details': null,
    'errorCount': errors.length,
    'warningCount': 0,
    'url': null,
    'log': log == null
        ? null
        : {
            'id': log,
            'type': 'Container',
            'url':
                '${DemoWorld.projectUrl}/_apis/build/builds/${run.id}/logs/$log',
          },
    'task': task,
    'attempt': 1,
    'identifier': identifier,
    'issues': [
      for (final e in errors)
        {
          'type': 'error',
          'category': 'General',
          'message': e,
          'data': {'type': 'error', 'logFileLineNumber': '38'},
        },
    ],
  };

  for (final (si, stage) in run.stages.indexed) {
    final stageId = rid(stage.id);
    final stageStart = cursor.add(const Duration(seconds: 5));
    final children = <Map<String, dynamic>>[];
    var jobsStart = stageStart;
    String stageState;
    String? stageResult;
    DateTime? stageFinish;

    if (failedBefore || openBefore || run.canceled) {
      final skipped = failedBefore || run.canceled;
      sim.records.add(
        record(
          id: stageId,
          type: 'Stage',
          name: stage.name,
          order: si + 1,
          identifier: stage.id,
          state: skipped ? 'completed' : 'pending',
          result: skipped ? 'skipped' : null,
        ),
      );
      if (!skipped) {
        for (final (ji, job) in stage.jobs.indexed) {
          final phaseId = rid('${stage.id}.${job.id}.phase');
          sim.records
            ..add(
              record(
                id: phaseId,
                parentId: stageId,
                type: 'Phase',
                name: job.name,
                order: ji + 1,
                identifier: '${stage.id}.${job.id}',
                state: 'pending',
              ),
            )
            ..add(
              record(
                id: rid('${stage.id}.${job.id}'),
                parentId: phaseId,
                type: 'Job',
                name: job.name,
                order: 1,
                identifier: '${stage.id}.${job.id}.__default',
                state: 'pending',
              ),
            );
        }
      }
      continue;
    }

    final gate = stage.gate;
    var gateOpen = false;
    var gateRejected = false;
    if (gate != null) {
      final approvalId = approvalIdFor(run, stage);
      final checkpointId = rid('${stage.id}.checkpoint');
      final decision =
          decisions[approvalId] ??
          (gate.decidedAfter == null
              ? null
              : DemoDecision(
                  approved: true,
                  at: stageStart.add(gate.decidedAfter!),
                  by: gate.decidedBy ?? DemoWorld.kelly,
                ));
      final decided = decision != null && !decision.at.isAfter(now);
      if (decided) {
        gateRejected = !decision.approved;
        jobsStart = decision.at.add(const Duration(seconds: 5));
      } else {
        gateOpen = true;
        sim.pending.add(
          DemoPendingApproval(approvalId, run, stage, gate, stageStart),
        );
      }
      final cpState = decided ? 'completed' : 'inProgress';
      final cpResult = decided
          ? (decision.approved ? 'succeeded' : 'failed')
          : null;
      children
        ..add(
          record(
            id: checkpointId,
            parentId: stageId,
            type: 'Checkpoint',
            name: 'Checkpoint',
            order: 0,
            identifier: 'Checkpoint.${stage.id}',
            state: cpState,
            result: cpResult,
            start: stageStart,
            finish: decided ? decision.at : null,
          ),
        )
        ..add(
          record(
            id: approvalId,
            parentId: checkpointId,
            type: 'Checkpoint.Approval',
            name: 'Checkpoint.Approval',
            order: 1,
            identifier: approvalId,
            state: cpState,
            result: cpResult,
            start: stageStart,
            finish: decided ? decision.at : null,
          ),
        );
    }

    if (gateOpen || gateRejected) {
      for (final (ji, job) in stage.jobs.indexed) {
        final phaseId = rid('${stage.id}.${job.id}.phase');
        final state = gateRejected ? 'completed' : 'pending';
        final result = gateRejected ? 'skipped' : null;
        children
          ..add(
            record(
              id: phaseId,
              parentId: stageId,
              type: 'Phase',
              name: job.name,
              order: ji + 1,
              identifier: '${stage.id}.${job.id}',
              state: state,
              result: result,
            ),
          )
          ..add(
            record(
              id: rid('${stage.id}.${job.id}'),
              parentId: phaseId,
              type: 'Job',
              name: job.name,
              order: 1,
              identifier: '${stage.id}.${job.id}.__default',
              state: state,
              result: result,
            ),
          );
      }
      if (gateRejected) {
        stageState = 'completed';
        stageResult = 'failed';
        stageFinish = children.first['finishTime'] == null
            ? null
            : DateTime.parse(children.first['finishTime'] as String);
        failedBefore = true;
      } else {
        stageState = 'pending';
        openBefore = true;
      }
      sim.records.add(
        record(
          id: stageId,
          type: 'Stage',
          name: stage.name,
          order: si + 1,
          identifier: stage.id,
          state: stageState,
          result: stageResult,
          start: gateOpen ? null : stageStart,
          finish: stageFinish,
        ),
      );
      sim.records.addAll(children);
      if (stageFinish != null) cursor = stageFinish;
      continue;
    }

    // Jobs.
    final jobFinish = <String, DateTime?>{};
    final jobFailed = <String>{};
    var anyOpen = false;
    var anyFailed = false;
    var anyStarted = false;
    DateTime? lastFinish;
    for (final (ji, job) in stage.jobs.indexed) {
      final phaseId = rid('${stage.id}.${job.id}.phase');
      final jobId = rid('${stage.id}.${job.id}');
      final depFailed = job.after.any(jobFailed.contains);
      final depOpen = job.after.any((d) => jobFinish[d] == null);
      final taskRecords = <Map<String, dynamic>>[];
      String jobState;
      String? jobResult;
      DateTime? jobStart;
      DateTime? jobEnd;
      var errors = const <String>[];
      if (depFailed) {
        jobState = 'completed';
        jobResult = 'skipped';
        jobFailed.add(job.id);
        jobFinish[job.id] = null;
      } else if (depOpen) {
        jobState = 'pending';
        anyOpen = true;
      } else {
        var start = jobsStart;
        for (final d in job.after) {
          final f = jobFinish[d]!;
          if (f.isAfter(start)) start = f;
        }
        start = start.add(const Duration(seconds: 8));
        jobStart = start;
        var t = start;
        var failed = false;
        var open = false;
        for (final (ti, task) in job.tasks.indexed) {
          final taskId = rid('${stage.id}.${job.id}.$ti');
          final always = task.name == 'Finalize Job';
          if (failed && !always) {
            taskRecords.add(
              record(
                id: taskId,
                parentId: jobId,
                type: 'Task',
                name: task.name,
                order: ti + 1,
                identifier: '${stage.id}.${job.id}.__default.$ti',
                state: 'completed',
                result: 'skipped',
                worker: job.worker,
              ),
            );
            continue;
          }
          final end = t.add(
            Duration(seconds: always && failed ? 1 : task.seconds),
          );
          if (open || t.isAfter(now)) {
            open = true;
            taskRecords.add(
              record(
                id: taskId,
                parentId: jobId,
                type: 'Task',
                name: task.name,
                order: ti + 1,
                identifier: '${stage.id}.${job.id}.__default.$ti',
                state: 'pending',
              ),
            );
          } else if (end.isAfter(now)) {
            open = true;
            taskRecords.add(
              record(
                id: taskId,
                parentId: jobId,
                type: 'Task',
                name: task.name,
                order: ti + 1,
                identifier: '${stage.id}.${job.id}.__default.$ti',
                state: 'inProgress',
                start: t,
                worker: job.worker,
              ),
            );
          } else {
            final log = logId++;
            final taskFailed = task.fails;
            sim.logs[log] = DemoLog(
              log,
              task.name,
              task.log,
              t,
              end,
              taskFailed,
            );
            taskRecords.add(
              record(
                id: taskId,
                parentId: jobId,
                type: 'Task',
                name: task.name,
                order: ti + 1,
                identifier: '${stage.id}.${job.id}.__default.$ti',
                state: 'completed',
                result: taskFailed ? 'failed' : 'succeeded',
                start: t,
                finish: end,
                worker: job.worker,
                log: log,
                errors: taskFailed ? job.issues : const [],
                task: {
                  'id': demoGuid('task:${task.name}'),
                  'name': task.name.contains(' ') ? 'CmdLine' : task.name,
                  'version': '2.250.1',
                },
              ),
            );
            if (taskFailed) {
              failed = true;
              errors = job.issues;
            }
          }
          t = end;
        }
        if (open) {
          jobState = 'inProgress';
          anyOpen = true;
          jobFinish[job.id] = null;
        } else {
          jobState = 'completed';
          jobResult = failed ? 'failed' : 'succeeded';
          jobEnd = t;
          jobFinish[job.id] = t;
          if (failed) jobFailed.add(job.id);
          if (lastFinish == null || t.isAfter(lastFinish)) lastFinish = t;
        }
        anyStarted = true;
        if (failed) anyFailed = true;
      }
      final jobLog = jobState == 'completed' && jobResult != 'skipped'
          ? logId++
          : null;
      if (jobLog != null) {
        sim.logs[jobLog] = DemoLog(
          jobLog,
          job.name,
          'job',
          jobStart!,
          jobEnd!,
          jobResult == 'failed',
        );
      }
      children
        ..add(
          record(
            id: phaseId,
            parentId: stageId,
            type: 'Phase',
            name: job.name,
            order: ji + 1,
            identifier: '${stage.id}.${job.id}',
            state: jobState,
            result: jobResult,
            start: jobStart,
            finish: jobEnd,
          ),
        )
        ..add(
          record(
            id: jobId,
            parentId: phaseId,
            type: 'Job',
            name: job.name,
            order: 1,
            identifier: '${stage.id}.${job.id}.__default',
            state: jobState,
            result: jobResult,
            start: jobStart,
            finish: jobEnd,
            worker: jobState == 'completed' ? job.worker : null,
            log: jobLog,
            errors: errors,
          ),
        )
        ..addAll(taskRecords);
    }
    if (anyOpen) {
      stageState = anyStarted ? 'inProgress' : 'pending';
      openBefore = true;
    } else {
      stageState = 'completed';
      stageResult = anyFailed ? 'failed' : 'succeeded';
      stageFinish = lastFinish;
      if (anyFailed) failedBefore = true;
      if (lastFinish != null) cursor = lastFinish;
    }
    sim.records.add(
      record(
        id: stageId,
        type: 'Stage',
        name: stage.name,
        order: si + 1,
        identifier: stage.id,
        state: stageState,
        result: stageResult,
        start: stageStart,
        finish: stageFinish,
      ),
    );
    sim.records.addAll(children);
  }

  if (run.canceled) {
    sim
      ..status = 'completed'
      ..result = 'canceled'
      ..finishTime = run.started;
  } else if (openBefore) {
    sim.status = 'inProgress';
  } else {
    sim
      ..status = 'completed'
      ..result = failedBefore ? 'failed' : 'succeeded'
      ..finishTime = cursor;
  }
  return sim;
}
