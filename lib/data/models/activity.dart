import 'package:equatable/equatable.dart';

import 'pipeline.dart';
import 'pull_request.dart';
import 'work_item.dart';

enum ActivityKind { prReview, prMine, workItem, build }

/// One row of the Activity feed, flattened so it can be cached as JSON and
/// rendered without the source models.
class ActivityItem extends Equatable {
  const ActivityItem({
    required this.kind,
    required this.key,
    required this.title,
    required this.subtitle,
    required this.route,
    this.time,
    this.project,
    this.status,
    this.result,
    this.actor,
  });

  factory ActivityItem.fromPullRequest(
    String org,
    PullRequest pr, {
    required bool mine,
  }) => ActivityItem(
    kind: mine ? ActivityKind.prMine : ActivityKind.prReview,
    key: 'pr:${pr.id}',
    title: pr.title,
    subtitle:
        '${pr.projectName} / ${pr.repositoryName} · !${pr.id} · '
        '${mine ? pr.overallVote.label : pr.createdBy.displayName}',
    route: '/orgs/${Uri.encodeComponent(org)}/pull-requests/${pr.id}',
    time: pr.creationDate,
    project: pr.projectName,
    status: pr.isDraft ? 'draft' : pr.status,
    result: pr.overallVote.name,
    actor: pr.createdBy.displayName,
  );

  factory ActivityItem.fromWorkItem(String org, WorkItem item) => ActivityItem(
    kind: ActivityKind.workItem,
    key: 'wi:${item.id}',
    title: item.title,
    subtitle:
        '${item.type} ${item.id} · ${item.state}'
        '${item.changedBy == null ? '' : ' · ${item.changedBy!.displayName}'}',
    route:
        '/orgs/${Uri.encodeComponent(org)}/projects/'
        '${Uri.encodeComponent(item.teamProject)}/work-items/${item.id}',
    time: item.changedDate,
    project: item.teamProject,
    status: item.state,
    result: item.type,
    actor: item.changedBy?.displayName,
  );

  factory ActivityItem.fromBuild(String org, BuildRun run) => ActivityItem(
    kind: ActivityKind.build,
    key: 'build:${run.id}',
    title: '${run.definitionName} · ${run.buildNumber}',
    subtitle:
        '${run.projectName ?? ''} · ${run.branch}'
        '${run.requestedFor == null ? '' : ' · ${run.requestedFor!.displayName}'}',
    route:
        '/orgs/${Uri.encodeComponent(org)}/projects/'
        '${Uri.encodeComponent(run.projectName ?? '')}/pipelines/runs/${run.id}',
    time: run.finishTime ?? run.startTime ?? run.queueTime,
    project: run.projectName,
    status: run.status,
    result: run.result,
    actor: run.requestedFor?.displayName,
  );

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    kind: ActivityKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ActivityKind.workItem,
    ),
    key: json['key'] as String,
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    route: json['route'] as String? ?? '',
    time: DateTime.tryParse(json['time'] as String? ?? ''),
    project: json['project'] as String?,
    status: json['status'] as String?,
    result: json['result'] as String?,
    actor: json['actor'] as String?,
  );

  final ActivityKind kind;

  /// `pr:8319`, `wi:15503`, `build:4242`: stable across refreshes.
  final String key;
  final String title;
  final String subtitle;
  final String route;
  final DateTime? time;
  final String? project;

  /// PR status / work item state / build status.
  final String? status;

  /// PR overall vote name / work item type / build result.
  final String? result;
  final String? actor;

  bool isNewSince(DateTime? seen) =>
      seen != null && time != null && time!.isAfter(seen);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'key': key,
    'title': title,
    'subtitle': subtitle,
    'route': route,
    'time': ?time?.toUtc().toIso8601String(),
    'project': ?project,
    'status': ?status,
    'result': ?result,
    'actor': ?actor,
  };

  @override
  List<Object?> get props => [key, kind, time, status, result];
}
