import 'package:equatable/equatable.dart';

import 'work_item.dart';

/// `refs/heads/main` → `main`, `refs/pull/123/merge` → `PR 123`,
/// `refs/tags/v1` → `v1`.
String shortRef(String ref) {
  if (ref.startsWith('refs/heads/')) return ref.substring(11);
  if (ref.startsWith('refs/tags/')) return ref.substring(10);
  final pr = RegExp(r'^refs/pull/(\d+)/').firstMatch(ref);
  if (pr != null) return 'PR ${pr.group(1)}';
  return ref;
}

/// One build (a pipeline run) from `_apis/build/builds`. The Build API is
/// used for lists because the Pipelines API has no filters and no
/// `partiallySucceeded` (research/01 §5.1).
class BuildRun extends Equatable {
  const BuildRun({
    required this.id,
    required this.buildNumber,
    required this.definitionId,
    required this.definitionName,
    required this.status,
    required this.result,
    required this.sourceBranch,
    this.sourceVersion,
    this.queueTime,
    this.startTime,
    this.finishTime,
    this.requestedFor,
    this.reason,
    this.triggerMessage,
    this.webUrl,
    this.projectName,
  });

  factory BuildRun.fromJson(Map<String, dynamic> json) {
    final definition =
        (json['definition'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trigger =
        (json['triggerInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
    final links = (json['_links'] as Map?)?.cast<String, dynamic>();
    return BuildRun(
      id: (json['id'] as num).toInt(),
      buildNumber: json['buildNumber'] as String? ?? '${json['id']}',
      definitionId: (definition['id'] as num?)?.toInt() ?? 0,
      definitionName: definition['name'] as String? ?? '',
      status: json['status'] as String? ?? 'none',
      result: json['result'] as String? ?? 'none',
      sourceBranch: json['sourceBranch'] as String? ?? '',
      sourceVersion: json['sourceVersion'] as String?,
      queueTime: DateTime.tryParse(json['queueTime'] as String? ?? ''),
      startTime: DateTime.tryParse(json['startTime'] as String? ?? ''),
      finishTime: DateTime.tryParse(json['finishTime'] as String? ?? ''),
      requestedFor: IdentityRef.fromField(json['requestedFor']),
      reason: json['reason'] as String?,
      triggerMessage:
          trigger['ci.message'] as String? ?? trigger['pr.title'] as String?,
      webUrl: (links?['web'] as Map?)?['href'] as String?,
      projectName: (json['project'] as Map?)?['name'] as String?,
    );
  }

  final int id;
  final String buildNumber;
  final int definitionId;
  final String definitionName;
  final String? projectName;

  /// `none | inProgress | completed | cancelling | postponed | notStarted`.
  final String status;

  /// `none | succeeded | partiallySucceeded | failed | canceled`.
  final String result;
  final String sourceBranch;
  final String? sourceVersion;
  final DateTime? queueTime;
  final DateTime? startTime;
  final DateTime? finishTime;
  final IdentityRef? requestedFor;

  /// `manual | individualCI | batchedCI | schedule | pullRequest | …`.
  final String? reason;
  final String? triggerMessage;
  final String? webUrl;

  String get branch => shortRef(sourceBranch);
  String get shortCommit => (sourceVersion ?? '').length >= 8
      ? sourceVersion!.substring(0, 8)
      : sourceVersion ?? '';
  bool get isCompleted => status == 'completed';
  bool get isActive =>
      status == 'inProgress' ||
      status == 'notStarted' ||
      status == 'cancelling' ||
      status == 'postponed';

  /// Wall time so far, or total once finished.
  Duration? get duration {
    final start = startTime;
    if (start == null) return null;
    return (finishTime ?? DateTime.now()).difference(start);
  }

  @override
  List<Object?> get props => [id, status, result, finishTime];
}

/// A build definition with its latest builds (`build/definitions?
/// includeLatestBuilds=true`).
class PipelineDefinition extends Equatable {
  const PipelineDefinition({
    required this.id,
    required this.name,
    this.folder = '\\',
    this.queueStatus,
    this.latestBuild,
    this.latestCompletedBuild,
  });

  factory PipelineDefinition.fromJson(Map<String, dynamic> json) {
    BuildRun? build(Object? v) =>
        v is Map ? BuildRun.fromJson(v.cast<String, dynamic>()) : null;
    return PipelineDefinition(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      folder: json['path'] as String? ?? '\\',
      queueStatus: json['queueStatus'] as String?,
      latestBuild: build(json['latestBuild']),
      latestCompletedBuild: build(json['latestCompletedBuild']),
    );
  }

  final int id;
  final String name;
  final String folder;

  /// `enabled | paused | disabled`.
  final String? queueStatus;
  final BuildRun? latestBuild;
  final BuildRun? latestCompletedBuild;

  bool get isRootFolder => folder == '\\' || folder.isEmpty;

  @override
  List<Object?> get props => [id, name, latestBuild];
}

class TimelineIssue extends Equatable {
  const TimelineIssue({required this.type, required this.message});

  factory TimelineIssue.fromJson(Map<String, dynamic> json) => TimelineIssue(
    type: json['type'] as String? ?? 'error',
    message: json['message'] as String? ?? '',
  );

  /// `error | warning`.
  final String type;
  final String message;

  bool get isError => type == 'error';

  @override
  List<Object?> get props => [type, message];
}

/// One node of a build timeline: stage, phase, job, task or checkpoint.
class TimelineRecord extends Equatable {
  const TimelineRecord({
    required this.id,
    required this.parentId,
    required this.type,
    required this.name,
    required this.order,
    required this.identifier,
    required this.state,
    required this.result,
    this.startTime,
    this.finishTime,
    this.percentComplete,
    this.currentOperation,
    this.logId,
    this.issues = const [],
    this.errorCount = 0,
    this.warningCount = 0,
    this.attempt = 1,
    this.workerName,
  });

  factory TimelineRecord.fromJson(Map<String, dynamic> json) => TimelineRecord(
    id: json['id'] as String? ?? '',
    parentId: json['parentId'] as String?,
    type: json['type'] as String? ?? '',
    name: json['name'] as String? ?? '',
    order: (json['order'] as num?)?.toInt() ?? 0,
    identifier: json['identifier'] as String? ?? json['id'] as String? ?? '',
    state: json['state'] as String? ?? 'pending',
    result: json['result'] as String?,
    startTime: DateTime.tryParse(json['startTime'] as String? ?? ''),
    finishTime: DateTime.tryParse(json['finishTime'] as String? ?? ''),
    percentComplete: (json['percentComplete'] as num?)?.toInt(),
    currentOperation: json['currentOperation'] as String?,
    logId: ((json['log'] as Map?)?['id'] as num?)?.toInt(),
    issues: ((json['issues'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => TimelineIssue.fromJson(m.cast<String, dynamic>()))
        .toList(),
    errorCount: (json['errorCount'] as num?)?.toInt() ?? 0,
    warningCount: (json['warningCount'] as num?)?.toInt() ?? 0,
    attempt: (json['attempt'] as num?)?.toInt() ?? 1,
    workerName: json['workerName'] as String?,
  );

  final String id;
  final String? parentId;

  /// `Stage | Phase | Job | Task | Checkpoint | Checkpoint.Approval | …`
  /// (free-form).
  final String type;
  final String name;
  final int order;

  /// Stable across attempts; the list key.
  final String identifier;

  /// `pending | inProgress | completed`.
  final String state;

  /// `succeeded | succeededWithIssues | failed | canceled | skipped |
  /// abandoned`, null until completed.
  final String? result;
  final DateTime? startTime;
  final DateTime? finishTime;
  final int? percentComplete;
  final String? currentOperation;
  final int? logId;
  final List<TimelineIssue> issues;
  final int errorCount;
  final int warningCount;
  final int attempt;
  final String? workerName;

  bool get isStage => type == 'Stage';
  bool get isPhase => type == 'Phase';
  bool get isJob => type == 'Job';
  bool get isTask => type == 'Task';
  bool get isCheckpoint => type.startsWith('Checkpoint');
  bool get isCompleted => state == 'completed';
  bool get isInProgress => state == 'inProgress';
  bool get isSkipped => result == 'skipped';
  bool get failed => result == 'failed';
  bool get needsAttention =>
      isInProgress || failed || result == 'succeededWithIssues';

  Duration? get duration {
    final start = startTime;
    if (start == null) return null;
    return (finishTime ?? DateTime.now()).difference(start);
  }

  @override
  List<Object?> get props => [id, state, result, finishTime, attempt];
}

/// The whole run tree in one read (`build/builds/{id}/timeline`).
class Timeline {
  Timeline(this.records) {
    for (final r in records) {
      _children.putIfAbsent(r.parentId, () => []).add(r);
    }
    for (final list in _children.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }
  }

  factory Timeline.fromJson(Map<String, dynamic> json) => Timeline([
    for (final r in ((json['records'] as List?) ?? const []).whereType<Map>())
      TimelineRecord.fromJson(r.cast<String, dynamic>()),
  ]);

  final List<TimelineRecord> records;
  final Map<String?, List<TimelineRecord>> _children = {};

  List<TimelineRecord> children(String? parentId) =>
      _children[parentId] ?? const [];

  List<TimelineRecord> get roots => children(null);

  /// Top-level sections: the stages of a YAML run, or, for a classic build
  /// with no stage records, the roots themselves.
  List<TimelineRecord> get stages => roots;

  /// Jobs and checkpoints under a section, with the `Phase` wrapper the
  /// service inserts between stage and job flattened away.
  List<TimelineRecord> jobsOf(TimelineRecord section) => [
    for (final c in children(section.id))
      if (c.isPhase) ...children(c.id) else if (!c.isTask) c,
  ];

  List<TimelineRecord> tasksOf(TimelineRecord job) => [
    for (final c in children(job.id))
      if (c.isTask) c,
  ];

  /// Direct task children of a section that is itself a job (classic
  /// builds put tasks under the root phase/job).
  bool isLeafSection(TimelineRecord section) =>
      children(section.id).any((c) => c.isTask) &&
      !children(section.id).any((c) => c.isPhase || c.isJob);
}

class ApprovalStep extends Equatable {
  const ApprovalStep({
    required this.assignedApprover,
    required this.status,
    this.actualApprover,
    this.comment,
    this.lastModifiedOn,
    this.order = 0,
  });

  factory ApprovalStep.fromJson(Map<String, dynamic> json) => ApprovalStep(
    assignedApprover: IdentityRef.fromField(json['assignedApprover']),
    actualApprover: IdentityRef.fromField(json['actualApprover']),
    status: json['status'] as String? ?? 'pending',
    comment: json['comment'] as String?,
    lastModifiedOn: DateTime.tryParse(json['lastModifiedOn'] as String? ?? ''),
    order: (json['order'] as num?)?.toInt() ?? 0,
  );

  final IdentityRef? assignedApprover;
  final IdentityRef? actualApprover;

  /// `pending | approved | rejected | skipped | canceled | timedOut |
  /// uninitiated`.
  final String status;
  final String? comment;
  final DateTime? lastModifiedOn;
  final int order;

  @override
  List<Object?> get props => [assignedApprover, status, comment];
}

/// A YAML environment approval (`_apis/pipelines/approvals`).
class PipelineApproval extends Equatable {
  const PipelineApproval({
    required this.id,
    required this.status,
    required this.steps,
    this.pipelineId,
    this.pipelineName,
    this.runId,
    this.runName,
    this.instructions,
    this.createdOn,
    this.minRequiredApprovers = 1,
    this.executionOrder,
  });

  factory PipelineApproval.fromJson(Map<String, dynamic> json) {
    final pipeline =
        (json['pipeline'] as Map?)?.cast<String, dynamic>() ?? const {};
    final owner =
        (pipeline['owner'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PipelineApproval(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      steps: ((json['steps'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => ApprovalStep.fromJson(m.cast<String, dynamic>()))
          .toList(),
      pipelineId: (pipeline['id'] as num?)?.toInt(),
      pipelineName: pipeline['name'] as String?,
      runId: (owner['id'] as num?)?.toInt(),
      runName: owner['name'] as String?,
      instructions: json['instructions'] as String?,
      createdOn: DateTime.tryParse(json['createdOn'] as String? ?? ''),
      minRequiredApprovers:
          (json['minRequiredApprovers'] as num?)?.toInt() ?? 1,
      executionOrder: json['executionOrder'] as String?,
    );
  }

  final String id;

  /// `pending | approved | rejected | canceled | timedOut | …`.
  final String status;
  final List<ApprovalStep> steps;
  final int? pipelineId;
  final String? pipelineName;

  /// The run (build id and number) waiting on this approval.
  final int? runId;
  final String? runName;
  final String? instructions;
  final DateTime? createdOn;
  final int minRequiredApprovers;
  final String? executionOrder;

  bool get isPending => status == 'pending';

  /// Whether [userId] is one of the approvers who has not acted yet.
  bool awaits(String? userId) =>
      userId != null &&
      steps.any(
        (s) => s.status == 'pending' && s.assignedApprover?.id == userId,
      );

  @override
  List<Object?> get props => [id, status, steps];
}
