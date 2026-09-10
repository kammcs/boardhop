import 'package:boardhop/data/models/activity.dart';
import 'package:boardhop/data/models/pipeline.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pr = PullRequest.fromJson({
    'pullRequestId': 8319,
    'title': 'Spike PR',
    'status': 'active',
    'creationDate': '2026-09-10T10:00:00Z',
    'sourceRefName': 'refs/heads/f',
    'targetRefName': 'refs/heads/main',
    'createdBy': {'displayName': 'Kelly Kamm', 'id': 'me'},
    'repository': {
      'id': 'r',
      'name': 'repo',
      'project': {'id': 'p', 'name': 'DevOps Mobile App'},
    },
    'reviewers': [
      {'id': 'x', 'displayName': 'X', 'vote': 5},
    ],
  });
  final workItem = WorkItem.fromJson({
    'id': 15503,
    'rev': 4,
    'fields': {
      'System.Title': 'Task title',
      'System.WorkItemType': 'Task',
      'System.State': 'New',
      'System.TeamProject': 'DevOps Mobile App',
      'System.ChangedDate': '2026-09-10T12:00:00Z',
      'System.ChangedBy': {'displayName': 'Kelly Kamm', 'id': 'me'},
    },
  });
  final build = BuildRun.fromJson({
    'id': 4242,
    'buildNumber': '20260910.3',
    'status': 'completed',
    'result': 'failed',
    'queueTime': '2026-09-10T11:00:00Z',
    'finishTime': '2026-09-10T11:30:00Z',
    'sourceBranch': 'refs/heads/main',
    'definition': {'id': 7, 'name': 'ci'},
    'project': {'name': 'CloudCover 2.0'},
  });

  test('items flatten their sources with routes and times', () {
    final review = ActivityItem.fromPullRequest('puremedia', pr, mine: false);
    expect(review.kind, ActivityKind.prReview);
    expect(review.route, '/orgs/puremedia/pull-requests/8319');
    expect(review.time, DateTime.utc(2026, 9, 10, 10));
    final mine = ActivityItem.fromPullRequest('puremedia', pr, mine: true);
    expect(mine.result, 'approvedWithSuggestions');
    expect(mine.subtitle, contains('Approved with suggestions'));

    final wi = ActivityItem.fromWorkItem('puremedia', workItem);
    expect(
      wi.route,
      '/orgs/puremedia/projects/DevOps%20Mobile%20App/work-items/15503',
    );
    expect(wi.subtitle, 'Task 15503 · New · Kelly Kamm');

    final b = ActivityItem.fromBuild('puremedia', build);
    expect(
      b.route,
      '/orgs/puremedia/projects/CloudCover%202.0/pipelines/runs/4242',
    );
    expect(b.time, DateTime.utc(2026, 9, 10, 11, 30));
    expect(b.status, 'completed');
    expect(b.result, 'failed');
  });

  test('json round trip keeps every field', () {
    final b = ActivityItem.fromBuild('puremedia', build);
    final back = ActivityItem.fromJson(b.toJson());
    expect(back, b);
    expect(back.subtitle, b.subtitle);
    expect(back.route, b.route);
    expect(back.actor, b.actor);
  });

  test('merge drops duplicates and sorts newest first', () {
    final review = ActivityItem.fromPullRequest('o', pr, mine: false);
    final mine = ActivityItem.fromPullRequest('o', pr, mine: true);
    final merged = ActivityRepository.merge([
      review,
      ActivityItem.fromBuild('o', build),
      mine,
      ActivityItem.fromWorkItem('o', workItem),
    ]);
    expect(merged.map((i) => i.key), ['wi:15503', 'build:4242', 'pr:8319']);
    expect(merged.last.kind, ActivityKind.prReview);
  });

  test('new-since marking', () {
    final wi = ActivityItem.fromWorkItem('o', workItem);
    expect(wi.isNewSince(DateTime.utc(2026, 9, 10, 11)), isTrue);
    expect(wi.isNewSince(DateTime.utc(2026, 9, 10, 13)), isFalse);
    expect(wi.isNewSince(null), isFalse);
  });

  test('wiql and keys', () {
    expect(ActivityRepository.workItemsWiql(), contains('@Today - 14'));
    expect(ActivityRepository.feedKey('puremedia'), 'activity:puremedia');
    expect(ActivityRepository.seenKey('puremedia'), 'activity:seen:puremedia');
  });
}
