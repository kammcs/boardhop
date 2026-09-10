import 'package:boardhop/core/util/format.dart';
import 'package:boardhop/data/models/pipeline.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortRef and durations', () {
    expect(shortRef('refs/heads/main'), 'main');
    expect(shortRef('refs/pull/8319/merge'), 'PR 8319');
    expect(shortRef('refs/tags/v1.2'), 'v1.2');
    expect(formatDuration(const Duration(seconds: 42)), '42s');
    expect(formatDuration(const Duration(minutes: 3, seconds: 5)), '3m 05s');
    expect(formatDuration(const Duration(hours: 1, minutes: 12)), '1h 12m');
    expect(formatDuration(null), '');
  });

  test('BuildRun parses the Build API shape', () {
    final run = BuildRun.fromJson({
      'id': 4242,
      'buildNumber': '20260910.3',
      'status': 'completed',
      'result': 'partiallySucceeded',
      'queueTime': '2026-09-10T10:00:00Z',
      'startTime': '2026-09-10T10:01:00Z',
      'finishTime': '2026-09-10T10:04:30Z',
      'sourceBranch': 'refs/heads/feature/x',
      'sourceVersion': '0123456789abcdef',
      'definition': {'id': 7, 'name': 'ci-main', 'path': '\\'},
      'requestedFor': {'displayName': 'Kelly Kamm', 'id': 'k'},
      'reason': 'individualCI',
      'triggerInfo': {'ci.message': 'Fix the thing\n\nDetails'},
      '_links': {
        'web': {
          'href': 'https://dev.azure.com/x/y/_build/results?buildId=4242',
        },
      },
    });
    expect(run.definitionName, 'ci-main');
    expect(run.branch, 'feature/x');
    expect(run.shortCommit, '01234567');
    expect(run.isCompleted, isTrue);
    expect(run.isActive, isFalse);
    expect(run.duration, const Duration(minutes: 3, seconds: 30));
    expect(run.triggerMessage, startsWith('Fix the thing'));
    expect(run.requestedFor?.displayName, 'Kelly Kamm');
    expect(
      BuildRun.fromJson({'id': 1, 'status': 'inProgress'}).isActive,
      isTrue,
    );
  });

  test('PipelineDefinition carries its latest builds', () {
    final d = PipelineDefinition.fromJson({
      'id': 7,
      'name': 'ci-main',
      'path': '\\Mobile',
      'queueStatus': 'enabled',
      'latestBuild': {'id': 2, 'status': 'inProgress', 'result': 'none'},
      'latestCompletedBuild': {
        'id': 1,
        'status': 'completed',
        'result': 'succeeded',
      },
    });
    expect(d.isRootFolder, isFalse);
    expect(d.latestBuild?.isActive, isTrue);
    expect(d.latestCompletedBuild?.result, 'succeeded');
    expect(
      PipelineDefinition.fromJson({'id': 1, 'name': 'x'}).isRootFolder,
      isTrue,
    );
  });

  group('Timeline', () {
    Map<String, dynamic> rec(
      String id,
      String? parent,
      String type,
      String name,
      int order, {
      String state = 'completed',
      String? result = 'succeeded',
      List<Map<String, dynamic>> issues = const [],
    }) => {
      'id': id,
      'parentId': parent,
      'type': type,
      'name': name,
      'order': order,
      'identifier': '$type.$name',
      'state': state,
      'result': result,
      'issues': issues,
      'log': type == 'Task' ? {'id': 9} : null,
    };

    test('flattens the Phase wrapper and sorts siblings by order', () {
      final t = Timeline.fromJson({
        'records': [
          rec(
            't2',
            'j1',
            'Task',
            'Test',
            2,
            result: 'failed',
            issues: [
              {'type': 'error', 'message': 'boom'},
            ],
          ),
          rec('t1', 'j1', 'Task', 'Build', 1),
          rec('j1', 'p1', 'Job', 'Job A', 1, result: 'failed'),
          rec('p1', 's2', 'Phase', 'Job A', 1, result: 'failed'),
          rec('s2', null, 'Stage', 'Deploy', 2, state: 'pending', result: null),
          rec('s1', null, 'Stage', 'Build', 1),
          rec(
            'c1',
            's2',
            'Checkpoint',
            'Checkpoint',
            0,
            state: 'inProgress',
            result: null,
          ),
        ],
      });
      expect(t.stages.map((s) => s.name), ['Build', 'Deploy']);
      final deploy = t.stages[1];
      expect(t.jobsOf(deploy).map((j) => j.name), ['Checkpoint', 'Job A']);
      final job = t.jobsOf(deploy)[1];
      expect(job.isJob, isTrue);
      expect(t.tasksOf(job).map((x) => x.name), ['Build', 'Test']);
      expect(t.tasksOf(job)[1].issues.single.message, 'boom');
      expect(t.tasksOf(job)[1].logId, 9);
      expect(t.tasksOf(job)[1].needsAttention, isTrue);
      expect(t.isLeafSection(deploy), isFalse);
      expect(t.jobsOf(deploy)[0].isCheckpoint, isTrue);
    });

    test('classic builds put tasks straight under the root job', () {
      final t = Timeline.fromJson({
        'records': [
          rec('j', null, 'Job', 'Job', 1),
          rec('t', 'j', 'Task', 'Checkout', 1),
        ],
      });
      expect(t.stages.single.name, 'Job');
      expect(t.isLeafSection(t.stages.single), isTrue);
      expect(t.tasksOf(t.stages.single).single.name, 'Checkout');
    });
  });

  test('PipelineApproval reads the run from pipeline.owner', () {
    final a = PipelineApproval.fromJson({
      'id': 'ap-1',
      'status': 'pending',
      'createdOn': '2026-09-10T10:00:00Z',
      'instructions': 'Check the smoke test',
      'minRequiredApprovers': 1,
      'steps': [
        {
          'assignedApprover': {'displayName': 'Kelly Kamm', 'id': 'k'},
          'status': 'pending',
          'order': 1,
        },
        {
          'assignedApprover': {'displayName': 'Other', 'id': 'o'},
          'status': 'approved',
          'comment': 'ok',
        },
      ],
      'pipeline': {
        'id': 7,
        'name': 'deploy',
        'owner': {'id': 4242, 'name': '20260910.3'},
      },
    });
    expect(a.isPending, isTrue);
    expect(a.runId, 4242);
    expect(a.runName, '20260910.3');
    expect(a.pipelineName, 'deploy');
    expect(a.awaits('k'), isTrue);
    expect(a.awaits('o'), isFalse);
    expect(a.awaits(null), isFalse);
  });

  test('cache keys', () {
    expect(
      PipelineRepository.runsKey('puremedia', 'DevOps Mobile App'),
      'pipelines:runs:puremedia:DevOps Mobile App',
    );
    expect(
      PipelineRepository.definitionsKey('o', 'p'),
      'pipelines:definitions:o:p',
    );
  });
}
