import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/util/format.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/demo/demo_backend.dart';
import 'package:boardhop/demo/demo_fixtures.dart';
import 'package:boardhop/demo/demo_world.dart';
import 'package:boardhop/demo/fixtures/pipelines/pipeline_plans.dart';
import 'package:boardhop/features/pipelines/pipeline_run_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_harness.dart';

const org = DemoWorld.org;
const project = DemoWorld.project;
const releaseRun = DemoPipelines.featuredReleaseRunId;

void main() {
  late PipelineRepository repo;
  late DemoBackend backend;

  setUp(() {
    final h = demoHarness();
    backend = h.backend;
    repo = PipelineRepository(h.client, h.db, DemoWorld.me.id);
    addTearDown(h.db.close);
  });

  test('the runs list mixes pipelines and outcomes', () async {
    final runs = await repo.runs(org, project);
    expect(runs.length, greaterThanOrEqualTo(10));
    final recent = runs.take(10).toList();
    expect(
      recent.map((r) => r.definitionName).toSet(),
      containsAll([
        'boardhop-ci',
        'boardhop-release',
        'relay-deploy',
        'extension-publish',
      ]),
    );
    // Newest queued first.
    for (var i = 1; i < runs.length; i++) {
      expect(
        runs[i - 1].queueTime!.isBefore(runs[i].queueTime!),
        isFalse,
        reason: 'run ${runs[i].id} out of order',
      );
    }
    // relay-deploy's health check in the first screenful; the PR 414
    // validation build the pull request's checks call failed, further down.
    final failed = runs.where((r) => r.result == 'failed').toList();
    expect(failed.map((r) => r.id), [3214, 3209]);
    expect(runs.indexWhere((r) => r.id == 3214), lessThan(5));
    final active = recent.where((r) => r.isActive).toList();
    expect(active.map((r) => r.id), containsAll([3217, releaseRun]));
    expect(recent.first.id, 3217);
    expect(recent.first.branch, 'PR 409');
    expect(recent.first.triggerMessage, DemoWorld.pullRequest(409).title);
    expect(
      recent.where((r) => r.result == 'succeeded').length,
      greaterThanOrEqualTo(6),
    );

    final release = runs.firstWhere((r) => r.id == releaseRun);
    expect(release.triggerMessage, 'Merge PR 403: Offline cache for boards');
    expect(release.requestedFor?.displayName, 'Kelly Kamm');
    expect(release.branch, 'main');
    expect(release.shortCommit, hasLength(8));
    expect(release.buildNumber, matches(RegExp(r'^\d{8}\.\d+$')));

    // Per pipeline and in the Build History widget's order.
    final relay = await repo.runs(org, project, definitionId: 17);
    expect(relay.every((r) => r.definitionName == 'relay-deploy'), isTrue);
    final history = await repo.runs(
      org,
      project,
      definitionId: DemoPipelines.ci.id,
      top: 20,
      queryOrder: PipelineRepository.finishTimeDescending,
    );
    expect(history, hasLength(greaterThan(8)));
    expect(history.first.finishTime, isNotNull);

    // The cache the Activity feed and the tab read first.
    expect(
      (await repo.cachedRuns(org, project))!.items,
      hasLength(runs.length),
    );
    expect(backend.misses, isEmpty);
  });

  test(
    'definitions carry their latest builds; approvals await Kelly',
    () async {
      final defs = await repo.definitions(org, project);
      expect(defs.map((d) => d.name), [
        'boardhop-ci',
        'boardhop-release',
        'extension-publish',
        'relay-deploy',
      ]);
      final release = defs.firstWhere((d) => d.name == 'boardhop-release');
      expect(release.latestBuild?.id, releaseRun);
      expect(release.latestCompletedBuild?.result, 'succeeded');
      expect(
        defs.firstWhere((d) => d.name == 'relay-deploy').latestBuild?.result,
        'failed',
      );

      final approvals = await repo.approvals(org, project);
      final a = approvals.single;
      expect(a.runId, releaseRun);
      expect(a.pipelineName, 'boardhop-release');
      expect(a.runName, release.latestBuild?.buildNumber);
      expect(a.awaits(DemoWorld.me.id), isTrue);
      expect(a.steps.map((s) => s.assignedApprover?.displayName), [
        'Kelly Kamm',
        'Jonah Whitfield',
      ]);
      expect(a.instructions, contains('TestFlight'));
      expect(backend.misses, isEmpty);
    },
  );

  test('the release run: built, uploaded, waiting for approval', () async {
    final run = await repo.run(org, project, releaseRun);
    expect(run.status, 'inProgress');
    final t = await repo.timeline(org, project, releaseRun);
    expect(t.stages.map((s) => s.name), [
      'Build',
      'Beta',
      'Release to App Store',
      'Tag release',
    ]);

    final build = t.stages[0];
    expect(build.result, 'succeeded');
    final jobs = t.jobsOf(build);
    expect(jobs.map((j) => j.name), [
      'Analyze & test',
      'Build iOS',
      'Build Android',
    ]);
    expect(jobs.every((j) => j.result == 'succeeded'), isTrue);
    expect(formatDuration(jobs[0].duration), '3m 12s');
    expect(formatDuration(jobs[1].duration), '11m 40s');
    expect(jobs[1].startTime!.isBefore(jobs[0].finishTime!), isFalse);
    expect(t.tasksOf(jobs[0]).every((x) => x.logId != null), isTrue);

    expect(t.stages[1].result, 'succeeded');

    final gate = t.stages[2];
    final checkpoint = t.jobsOf(gate).first;
    expect(checkpoint.isCheckpoint, isTrue);
    expect(t.checkpointReason(checkpoint), 'waiting for approval');
    expect(t.jobsOf(gate)[1].state, 'pending');
    expect(t.stages[3].state, 'pending');

    // The approval hangs off the checkpoint with the same id.
    final approval = (await repo.approvals(org, project)).single;
    expect(t.children(checkpoint.id).single.id, approval.id);

    // Log of flutter test.
    final testTask = t
        .tasksOf(jobs[0])
        .firstWhere((x) => x.name == 'flutter test');
    final lines = await repo.log(org, project, releaseRun, testTask.logId!);
    expect(lines.length, greaterThan(100));
    final stamp = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{7}Z ');
    expect(lines.every(stamp.hasMatch), isTrue);
    expect(lines.first, contains('##[section]Starting: flutter test'));
    expect(lines.any((l) => l.contains('All tests passed!')), isTrue);
    expect(lines.last, contains('##[section]Finishing: flutter test'));
    expect(lines.any((l) => l.contains('##[error]')), isFalse);
    final times = [for (final l in lines) DateTime.parse(l.substring(0, 28))];
    for (var i = 1; i < times.length; i++) {
      expect(times[i].isBefore(times[i - 1]), isFalse);
    }
    expect(times.first.isBefore(testTask.startTime!), isFalse);

    final ipa = t
        .tasksOf(jobs[1])
        .firstWhere((x) => x.name == 'flutter build ipa');
    expect(
      (await repo.log(org, project, releaseRun, ipa.logId!)).length,
      greaterThan(100),
    );
    // Screenshot routes in the report.
    // ignore: avoid_print
    print(
      'flutter test log: runs/$releaseRun/logs/${testTask.logId}, '
      'flutter build ipa log: runs/$releaseRun/logs/${ipa.logId}',
    );
    expect(backend.misses, isEmpty);
  });

  test('every run opens with a timeline and readable logs', () async {
    final runs = await repo.runs(org, project, top: 100);
    for (final run in runs) {
      final detail = await repo.run(org, project, run.id);
      final t = await repo.timeline(org, project, run.id);
      expect(t.stages, isNotEmpty, reason: '${run.id}');
      // A sample of logs: each request waits out the demo latency.
      final logged = t.records.where((r) => r.logId != null).toList();
      for (final r in {?logged.firstOrNull, ?logged.lastOrNull}) {
        final lines = await repo.log(org, project, run.id, r.logId!);
        expect(lines, isNotEmpty, reason: '${run.id} ${r.name}');
      }
      if (detail.result == 'failed') {
        final failed = t.records.where((r) => r.isTask && r.failed).single;
        expect(failed.name, anyOf('Health check /healthz', './gradlew lint'));
        expect(failed.issues, isNotEmpty);
        final log = await repo.log(org, project, run.id, failed.logId!);
        expect(log.where((l) => l.contains('##[error]')), isNotEmpty);
      }
      if (run.id == 3217) {
        expect(detail.isActive, isTrue);
        expect(t.records.where((r) => r.isInProgress && r.isTask), isNotEmpty);
      }
    }
    expect(backend.misses, isEmpty);
  });

  test('approving starts the stage and empties the approvals', () async {
    final a = (await repo.approvals(org, project)).single;
    await repo.resolveApproval(org, project, a.id, approve: true);
    expect(await repo.approvals(org, project), isEmpty);
    final t = await repo.timeline(org, project, releaseRun);
    final gate = t.stages[2];
    expect(t.jobsOf(gate).first.result, 'succeeded');
    expect(gate.state, 'inProgress');
    expect(backend.misses, isEmpty);
  });

  testWidgets('the run page shows the approval in the first screenful', (
    tester,
  ) async {
    // iPhone 17 Pro Max: 440 x 956 pt.
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final backend = buildDemoBackend();
    final client = AdoClient(
      tokenProvider: ({tenantId, accountId}) async => 'demo',
      // Synchronous JSON decoding: no isolate inside the fake clock.
      dio: Dio()
        ..httpClientAdapter = backend
        ..transformer = SyncTransformer(),
    );
    final repo = PipelineRepository(client);

    await tester.pumpWidget(
      RepositoryProvider<PipelineRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: BoardhopTheme.light(),
          builder: (context, child) =>
              AccountScope(accountId: DemoWorld.me.id, child: child!),
          home: const PipelineRunPage(
            org: org,
            project: project,
            id: releaseRun,
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Build iOS'), findsOneWidget);
    expect(find.text('Release to App Store'), findsOneWidget);
    final waiting = find.textContaining('waiting for approval');
    expect(waiting, findsOneWidget);
    expect(tester.getBottomLeft(waiting).dy, lessThan(956));
    expect(tester.takeException(), isNull);
    expect(backend.misses, isEmpty);

    // Dispose the page so its poll timer goes with it.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
