import 'package:equatable/equatable.dart';

import 'work_item.dart';

/// Vote values from the Reviewers API.
enum PrVote {
  approved(10, 'Approved'),
  approvedWithSuggestions(5, 'Approved with suggestions'),
  none(0, 'No vote'),
  waitingForAuthor(-5, 'Waiting for author'),
  rejected(-10, 'Rejected');

  const PrVote(this.value, this.label);

  final int value;
  final String label;

  static PrVote fromValue(int? v) => switch (v) {
    10 => approved,
    5 => approvedWithSuggestions,
    -5 => waitingForAuthor,
    -10 => rejected,
    _ => none,
  };
}

class PrReviewer extends Equatable {
  const PrReviewer({
    required this.id,
    required this.displayName,
    required this.vote,
    this.isRequired = false,
    this.isContainer = false,
    this.hasDeclined = false,
    this.isFlagged = false,
    this.votedFor = const [],
    this.uniqueName,
    this.imageUrl,
    this.descriptor,
  });

  factory PrReviewer.fromJson(Map<String, dynamic> json) {
    // Reviewers carry no `descriptor` field (spike s23); it has to come
    // from the `_links.avatar` MemberAvatars link, which is exactly what
    // `IdentityRef.fromJson` does. Reading `json['descriptor']` raw left
    // every reviewer on the 401 image url, so the row showed initials.
    final identity = IdentityRef.fromJson(json);
    return PrReviewer(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      vote: PrVote.fromValue((json['vote'] as num?)?.toInt()),
      isRequired: json['isRequired'] as bool? ?? false,
      isContainer: json['isContainer'] as bool? ?? false,
      hasDeclined: json['hasDeclined'] as bool? ?? false,
      isFlagged: json['isFlagged'] as bool? ?? false,
      // A person's `votedFor` lists the teams their vote rolled up to;
      // a team's is empty (spike w39 §3).
      votedFor: ((json['votedFor'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => IdentityRef.fromJson(m.cast<String, dynamic>()))
          .toList(),
      uniqueName: json['uniqueName'] as String?,
      imageUrl: identity.imageUrl,
      descriptor: identity.descriptor,
    );
  }

  final String id;
  final String displayName;
  final PrVote vote;
  final bool isRequired;
  final bool isContainer;
  final bool hasDeclined;

  /// The reviewer asked for the author's attention (`PATCH reviewers/{id}`).
  final bool isFlagged;

  /// Teams whose review this person's vote counted for.
  final List<IdentityRef> votedFor;
  final String? uniqueName;
  final String? imageUrl;
  final String? descriptor;

  IdentityRef get identity => IdentityRef(
    displayName: displayName,
    id: id,
    uniqueName: uniqueName,
    imageUrl: imageUrl,
    descriptor: descriptor,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'vote': vote.value,
    'isRequired': isRequired,
    'isContainer': isContainer,
    'hasDeclined': hasDeclined,
    'isFlagged': isFlagged,
    if (votedFor.isNotEmpty) 'votedFor': [for (final v in votedFor) v.toJson()],
    if (uniqueName != null) 'uniqueName': uniqueName,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (descriptor != null) 'descriptor': descriptor,
  };

  PrReviewer copyWith({
    bool? isRequired,
    bool? isFlagged,
    bool? hasDeclined,
    PrVote? vote,
  }) => PrReviewer(
    id: id,
    displayName: displayName,
    vote: vote ?? this.vote,
    isRequired: isRequired ?? this.isRequired,
    isContainer: isContainer,
    hasDeclined: hasDeclined ?? this.hasDeclined,
    isFlagged: isFlagged ?? this.isFlagged,
    votedFor: votedFor,
    uniqueName: uniqueName,
    imageUrl: imageUrl,
    descriptor: descriptor,
  );

  @override
  List<Object?> get props => [id, vote, isRequired, isFlagged, hasDeclined];
}

/// One pull request from the org-level or project-level list, or a get.
class PullRequest extends Equatable {
  const PullRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.repositoryId,
    required this.repositoryName,
    required this.projectId,
    required this.projectName,
    required this.sourceRefName,
    required this.targetRefName,
    required this.createdBy,
    this.description,
    this.isDraft = false,
    this.creationDate,
    this.closedDate,
    this.mergeStatus,
    this.lastMergeSourceCommit,
    this.lastMergeTargetCommit,
    this.reviewers = const [],
    this.codeReviewId,
    this.autoCompleteSetBy,
    this.completionOptions,
    this.closedBy,
    this.mergeFailureType,
    this.mergeFailureMessage,
    this.hasMultipleMergeBases = false,
    this.labels = const [],
  });

  factory PullRequest.fromJson(Map<String, dynamic> json) {
    final repo =
        (json['repository'] as Map?)?.cast<String, dynamic>() ?? const {};
    final project =
        (repo['project'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PullRequest(
      id: json['pullRequestId'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'active',
      isDraft: json['isDraft'] as bool? ?? false,
      repositoryId: repo['id'] as String? ?? '',
      repositoryName: repo['name'] as String? ?? '',
      projectId: project['id'] as String? ?? '',
      projectName: project['name'] as String? ?? '',
      sourceRefName: json['sourceRefName'] as String? ?? '',
      targetRefName: json['targetRefName'] as String? ?? '',
      createdBy:
          IdentityRef.fromField(json['createdBy']) ??
          const IdentityRef(displayName: '?'),
      creationDate: DateTime.tryParse(json['creationDate'] as String? ?? ''),
      closedDate: DateTime.tryParse(json['closedDate'] as String? ?? ''),
      mergeStatus: json['mergeStatus'] as String?,
      lastMergeSourceCommit:
          (json['lastMergeSourceCommit'] as Map?)?['commitId'] as String?,
      lastMergeTargetCommit:
          (json['lastMergeTargetCommit'] as Map?)?['commitId'] as String?,
      reviewers: ((json['reviewers'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => PrReviewer.fromJson(m.cast<String, dynamic>()))
          .toList(),
      codeReviewId: json['codeReviewId'] as int?,
      // Only present while auto-complete is set; the options outlive a
      // cancel and are the sheet's remembered choices (spike w39 §2).
      autoCompleteSetBy: IdentityRef.fromField(json['autoCompleteSetBy']),
      completionOptions: switch (json['completionOptions']) {
        final Map m => PrCompletionOptions.fromJson(m.cast<String, dynamic>()),
        _ => null,
      },
      closedBy: IdentityRef.fromField(json['closedBy']),
      mergeFailureType: json['mergeFailureType'] as String?,
      mergeFailureMessage: json['mergeFailureMessage'] as String?,
      hasMultipleMergeBases: json['hasMultipleMergeBases'] as bool? ?? false,
      // Filled on every list route and never on `GET pullRequests/{id}`
      // (spikes s65 §A, w40): the detail merges the labels sub-resource.
      labels: PrLabel.listFrom(json['labels']),
    );
  }

  final int id;
  final String title;
  final String? description;

  /// `active`, `completed`, `abandoned`.
  final String status;
  final bool isDraft;
  final String repositoryId;
  final String repositoryName;
  final String projectId;
  final String projectName;
  final String sourceRefName;
  final String targetRefName;
  final IdentityRef createdBy;
  final DateTime? creationDate;
  final DateTime? closedDate;
  final String? mergeStatus;
  final String? lastMergeSourceCommit;
  final String? lastMergeTargetCommit;
  final List<PrReviewer> reviewers;
  final int? codeReviewId;

  /// Who set auto-complete, present only while it is set.
  final IdentityRef? autoCompleteSetBy;

  /// The merge choices, remembered by the service across a cancel.
  final PrCompletionOptions? completionOptions;
  final IdentityRef? closedBy;

  /// Why the merge failed, when `mergeStatus` is `failure`.
  final String? mergeFailureType;
  final String? mergeFailureMessage;
  final bool hasMultipleMergeBases;

  /// Labels, from a list route or the labels sub-resource.
  final List<PrLabel> labels;

  bool get isAutoCompleteSet => autoCompleteSetBy != null;

  /// `https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}`,
  /// the link Share and the browser fall back to.
  String webUrl(String org) =>
      'https://dev.azure.com/${Uri.encodeComponent(org)}/'
      '${Uri.encodeComponent(projectName)}/_git/'
      '${Uri.encodeComponent(repositoryName)}/pullrequest/$id';

  PullRequest withLabels(List<PrLabel> labels) => PullRequest(
    id: id,
    title: title,
    description: description,
    status: status,
    isDraft: isDraft,
    repositoryId: repositoryId,
    repositoryName: repositoryName,
    projectId: projectId,
    projectName: projectName,
    sourceRefName: sourceRefName,
    targetRefName: targetRefName,
    createdBy: createdBy,
    creationDate: creationDate,
    closedDate: closedDate,
    mergeStatus: mergeStatus,
    lastMergeSourceCommit: lastMergeSourceCommit,
    lastMergeTargetCommit: lastMergeTargetCommit,
    reviewers: reviewers,
    codeReviewId: codeReviewId,
    autoCompleteSetBy: autoCompleteSetBy,
    completionOptions: completionOptions,
    closedBy: closedBy,
    mergeFailureType: mergeFailureType,
    mergeFailureMessage: mergeFailureMessage,
    hasMultipleMergeBases: hasMultipleMergeBases,
    labels: labels,
  );

  static String branch(String ref) =>
      ref.startsWith('refs/heads/') ? ref.substring('refs/heads/'.length) : ref;

  String get sourceBranch => branch(sourceRefName);
  String get targetBranch => branch(targetRefName);
  bool get isActive => status == 'active';

  /// The lowest vote wins for the summary glyph: a rejection outranks
  /// approvals, then waiting, then approvals, then none.
  PrVote get overallVote {
    var worst = PrVote.none;
    var best = PrVote.none;
    for (final r in reviewers) {
      if (r.isContainer) continue;
      if (r.vote.value < worst.value) worst = r.vote;
      if (r.vote.value > best.value) best = r.vote;
    }
    return worst.value < 0 ? worst : best;
  }

  PrReviewer? reviewer(String? id) {
    if (id == null) return null;
    for (final r in reviewers) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The list shape again, so a pull request can be written into a JSON
  /// cache and read back with [PullRequest.fromJson] unchanged (the search
  /// results cache; `_links` and other fields the app never reads are not
  /// re-emitted because nothing reads them back).
  Map<String, dynamic> toJson() => {
    'pullRequestId': id,
    'title': title,
    if (description != null) 'description': description,
    'status': status,
    'isDraft': isDraft,
    'repository': {
      'id': repositoryId,
      'name': repositoryName,
      'project': {'id': projectId, 'name': projectName},
    },
    'sourceRefName': sourceRefName,
    'targetRefName': targetRefName,
    'createdBy': createdBy.toJson(),
    if (creationDate != null) 'creationDate': creationDate!.toIso8601String(),
    if (closedDate != null) 'closedDate': closedDate!.toIso8601String(),
    if (mergeStatus != null) 'mergeStatus': mergeStatus,
    if (lastMergeSourceCommit != null)
      'lastMergeSourceCommit': {'commitId': lastMergeSourceCommit},
    if (lastMergeTargetCommit != null)
      'lastMergeTargetCommit': {'commitId': lastMergeTargetCommit},
    if (reviewers.isNotEmpty)
      'reviewers': [for (final r in reviewers) r.toJson()],
    if (codeReviewId != null) 'codeReviewId': codeReviewId,
    if (autoCompleteSetBy != null)
      'autoCompleteSetBy': autoCompleteSetBy!.toJson(),
    if (completionOptions != null)
      'completionOptions': completionOptions!.toJson(),
    if (closedBy != null) 'closedBy': closedBy!.toJson(),
    if (mergeFailureType != null) 'mergeFailureType': mergeFailureType,
    if (mergeFailureMessage != null) 'mergeFailureMessage': mergeFailureMessage,
    if (hasMultipleMergeBases) 'hasMultipleMergeBases': true,
    if (labels.isNotEmpty) 'labels': [for (final l in labels) l.toJson()],
  };

  @override
  List<Object?> get props => [
    id,
    status,
    title,
    isDraft,
    reviewers,
    lastMergeSourceCommit,
    autoCompleteSetBy,
    labels,
  ];
}

/// How the service merges a completed pull request. The wire names are what
/// `completionOptions.mergeStrategy` carries; the legacy `squashMerge: true`
/// flag is still echoed beside `squash` and is read as a fallback.
enum MergeStrategy {
  noFastForward('noFastForward', 'Merge (no fast-forward)'),
  squash('squash', 'Squash commit'),
  rebase('rebase', 'Rebase and fast-forward'),
  rebaseMerge('rebaseMerge', 'Semi-linear merge');

  const MergeStrategy(this.wire, this.label);

  final String wire;
  final String label;

  static MergeStrategy? fromWire(Object? wire) {
    if (wire is! String) return null;
    for (final s in MergeStrategy.values) {
      if (s.wire.toLowerCase() == wire.toLowerCase()) return s;
    }
    return null;
  }
}

/// The merge choices a completion or an auto-complete carries.
///
/// The service remembers them across a cancel, so a cancelled pull request
/// still answers with the options last set (spike w39 §2); the completion
/// sheet opens on them.
class PrCompletionOptions extends Equatable {
  const PrCompletionOptions({
    this.mergeStrategy,
    this.deleteSourceBranch = false,
    this.transitionWorkItems = false,
    this.mergeCommitMessage,
    this.bypassPolicy = false,
    this.bypassReason,
    this.autoCompleteIgnoreConfigIds = const <int>[],
  });

  factory PrCompletionOptions.fromJson(Map<String, dynamic> json) =>
      PrCompletionOptions(
        mergeStrategy:
            MergeStrategy.fromWire(json['mergeStrategy']) ??
            (json['squashMerge'] == true ? MergeStrategy.squash : null),
        deleteSourceBranch: json['deleteSourceBranch'] as bool? ?? false,
        transitionWorkItems: json['transitionWorkItems'] as bool? ?? false,
        mergeCommitMessage: json['mergeCommitMessage'] as String?,
        bypassPolicy: json['bypassPolicy'] as bool? ?? false,
        bypassReason: json['bypassReason'] as String?,
        autoCompleteIgnoreConfigIds:
            ((json['autoCompleteIgnoreConfigIds'] as List?) ?? const [])
                .map((v) => int.tryParse('$v') ?? 0)
                .where((id) => id > 0)
                .toList(),
      );

  final MergeStrategy? mergeStrategy;
  final bool deleteSourceBranch;
  final bool transitionWorkItems;
  final String? mergeCommitMessage;
  final bool bypassPolicy;
  final String? bypassReason;

  /// Non-blocking policies auto-complete should not wait for (R3's "wait for
  /// optional policies too" toggle, inverted).
  final List<int> autoCompleteIgnoreConfigIds;

  Map<String, dynamic> toJson() => {
    if (mergeStrategy != null) 'mergeStrategy': mergeStrategy!.wire,
    'deleteSourceBranch': deleteSourceBranch,
    'transitionWorkItems': transitionWorkItems,
    if (mergeCommitMessage != null && mergeCommitMessage!.isNotEmpty)
      'mergeCommitMessage': mergeCommitMessage,
    if (bypassPolicy) 'bypassPolicy': true,
    if (bypassPolicy && bypassReason != null && bypassReason!.isNotEmpty)
      'bypassReason': bypassReason,
    if (autoCompleteIgnoreConfigIds.isNotEmpty)
      'autoCompleteIgnoreConfigIds': autoCompleteIgnoreConfigIds,
  };

  PrCompletionOptions copyWith({
    MergeStrategy? mergeStrategy,
    bool? deleteSourceBranch,
    bool? transitionWorkItems,
    String? mergeCommitMessage,
    bool? bypassPolicy,
    String? bypassReason,
    List<int>? autoCompleteIgnoreConfigIds,
  }) => PrCompletionOptions(
    mergeStrategy: mergeStrategy ?? this.mergeStrategy,
    deleteSourceBranch: deleteSourceBranch ?? this.deleteSourceBranch,
    transitionWorkItems: transitionWorkItems ?? this.transitionWorkItems,
    mergeCommitMessage: mergeCommitMessage ?? this.mergeCommitMessage,
    bypassPolicy: bypassPolicy ?? this.bypassPolicy,
    bypassReason: bypassReason ?? this.bypassReason,
    autoCompleteIgnoreConfigIds:
        autoCompleteIgnoreConfigIds ?? this.autoCompleteIgnoreConfigIds,
  );

  @override
  List<Object?> get props => [
    mergeStrategy,
    deleteSourceBranch,
    transitionWorkItems,
    mergeCommitMessage,
    bypassPolicy,
    bypassReason,
    autoCompleteIgnoreConfigIds,
  ];
}

/// One label (`{id, name, active}`), which shares the project's `wit/tags`
/// pool. A list route sometimes carries bare strings, so both shapes parse.
class PrLabel extends Equatable {
  const PrLabel({required this.name, this.id, this.active = true});

  factory PrLabel.fromJson(Object? value) {
    if (value is String) return PrLabel(name: value);
    if (value is Map) {
      final m = value.cast<String, dynamic>();
      return PrLabel(
        name: m['name'] as String? ?? '',
        id: m['id'] as String?,
        active: m['active'] as bool? ?? true,
      );
    }
    return const PrLabel(name: '');
  }

  static List<PrLabel> listFrom(Object? value) => value is List
      ? [
          for (final v in value)
            if (PrLabel.fromJson(v) case final l when l.name.isNotEmpty) l,
        ]
      : const [];

  final String name;
  final String? id;
  final bool active;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (id != null) 'id': id,
    'active': active,
  };

  @override
  List<Object?> get props => [name, id, active];
}

/// One unresolved merge conflict (`GET {pr}/conflicts`, undocumented but
/// 7.1; spike w39 §6).
class PrConflict extends Equatable {
  const PrConflict({
    required this.conflictId,
    required this.conflictType,
    required this.path,
    this.resolutionStatus,
    this.resolvedBy,
  });

  factory PrConflict.fromJson(Map<String, dynamic> json) => PrConflict(
    conflictId: (json['conflictId'] as num?)?.toInt() ?? 0,
    conflictType: json['conflictType'] as String? ?? '',
    path:
        json['conflictPath'] as String? ??
        ((json['conflictPath'] as Map?)?['path'] as String?) ??
        '',
    resolutionStatus: json['resolutionStatus'] as String?,
    resolvedBy: IdentityRef.fromField(json['resolvedBy']),
  );

  final int conflictId;

  /// `editEdit`, `editDelete`, `addAdd`, `deleteEdit`, `rename1to2`…
  final String conflictType;
  final String path;
  final String? resolutionStatus;
  final IdentityRef? resolvedBy;

  bool get isResolved => resolutionStatus == 'resolved';

  String get typeLabel => switch (conflictType) {
    'editEdit' => 'Edited on both sides',
    'editDelete' => 'Edited here, deleted there',
    'deleteEdit' => 'Deleted here, edited there',
    'addAdd' => 'Added on both sides',
    'rename1to2' => 'Renamed differently',
    'rename2to1' => 'Renamed onto the same path',
    'directoryFile' || 'fileDirectory' => 'File and folder clash',
    '' => 'Conflict',
    _ => conflictType,
  };

  @override
  List<Object?> get props => [conflictId, conflictType, path, resolutionStatus];
}

/// One branch policy configuration from
/// `git/policy/configurations?repositoryId=&refName=` (spike s65 §B).
class PrPolicy extends Equatable {
  const PrPolicy({
    required this.id,
    required this.type,
    required this.displayName,
    this.isBlocking = false,
    this.isEnabled = true,
    this.refName,
    this.matchKind,
    this.allowedStrategies = const <MergeStrategy>{},
    this.minimumApproverCount = 0,
    this.creatorVoteCounts = false,
    this.requiredReviewerIds = const <String>[],
  });

  factory PrPolicy.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] as Map?)?.cast<String, dynamic>() ?? const {};
    final settings =
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final scope = ((settings['scope'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .firstOrNull;
    final typeId = (type['id'] as String? ?? '').toLowerCase();
    final strategies = <MergeStrategy>{
      if (settings['allowNoFastForward'] == true) MergeStrategy.noFastForward,
      if (settings['allowSquash'] == true) MergeStrategy.squash,
      if (settings['allowRebase'] == true) MergeStrategy.rebase,
      if (settings['allowRebaseMerge'] == true) MergeStrategy.rebaseMerge,
    };
    return PrPolicy(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: typeId,
      displayName: type['displayName'] as String? ?? '',
      // A deleted configuration is still listed; treat it as off.
      isBlocking: json['isBlocking'] as bool? ?? false,
      isEnabled:
          (json['isEnabled'] as bool? ?? true) && json['isDeleted'] != true,
      refName: scope?['refName'] as String?,
      matchKind: scope?['matchKind'] as String?,
      allowedStrategies: strategies,
      minimumApproverCount:
          (settings['minimumApproverCount'] as num?)?.toInt() ?? 0,
      creatorVoteCounts: settings['creatorVoteCounts'] as bool? ?? false,
      requiredReviewerIds:
          ((settings['requiredReviewerIds'] as List?) ?? const [])
              .map((v) => '$v')
              .where((v) => v.isNotEmpty)
              .toList(),
    );
  }

  /// `Minimum number of reviewers`.
  static const minimumReviewersType = 'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd';

  /// `Require a merge strategy`.
  static const mergeStrategyType = 'fa4e907d-c16b-4a4c-9dfa-4916e5d171ab';

  /// `Required reviewers`.
  static const requiredReviewersType = 'fd2167ab-b0be-447a-8ec8-39368250530e';

  final int id;

  /// The policy type GUID, lower-cased.
  final String type;
  final String displayName;
  final bool isBlocking;
  final bool isEnabled;
  final String? refName;

  /// `exact` or `prefix`.
  final String? matchKind;
  final Set<MergeStrategy> allowedStrategies;
  final int minimumApproverCount;
  final bool creatorVoteCounts;
  final List<String> requiredReviewerIds;

  bool get isMergeStrategy => type == mergeStrategyType;
  bool get isMinimumReviewers => type == minimumReviewersType;
  bool get isRequiredReviewers => type == requiredReviewersType;

  /// Whether the policy's scope covers [targetRefName].
  bool covers(String targetRefName) {
    final ref = refName;
    if (ref == null || ref.isEmpty) return true;
    return matchKind?.toLowerCase() == 'prefix'
        ? targetRefName.toLowerCase().startsWith(ref.toLowerCase())
        : targetRefName.toLowerCase() == ref.toLowerCase();
  }

  @override
  List<Object?> get props => [
    id,
    type,
    isBlocking,
    isEnabled,
    refName,
    matchKind,
    allowedStrategies,
    minimumApproverCount,
    creatorVoteCounts,
    requiredReviewerIds,
  ];
}

/// The policies that apply to one target branch, with the questions the
/// merge box asks of them.
class PrPolicySet extends Equatable {
  const PrPolicySet(this.policies);

  /// The enabled policies of [all] whose scope covers [targetRefName]. The
  /// git-scoped read is already filtered by `refName`, so this is the guard
  /// for a project-wide read and for a cached answer read back for another
  /// branch.
  factory PrPolicySet.forTarget(Iterable<PrPolicy> all, String targetRefName) =>
      PrPolicySet([
        for (final p in all)
          if (p.isEnabled && p.covers(targetRefName)) p,
      ]);

  factory PrPolicySet.fromJson(Object? json, String targetRefName) {
    final value = json is Map ? json['value'] : json;
    return PrPolicySet.forTarget([
      for (final m in (value as List? ?? const []).whereType<Map>())
        PrPolicy.fromJson(m.cast<String, dynamic>()),
    ], targetRefName);
  }

  final List<PrPolicy> policies;

  List<Map<String, dynamic>> toJson() => [
    for (final p in policies)
      {
        'id': p.id,
        'type': {'id': p.type, 'displayName': p.displayName},
        'isBlocking': p.isBlocking,
        'isEnabled': p.isEnabled,
        'settings': {
          if (p.refName != null)
            'scope': [
              {'refName': p.refName, 'matchKind': p.matchKind},
            ],
          if (p.allowedStrategies.contains(MergeStrategy.noFastForward))
            'allowNoFastForward': true,
          if (p.allowedStrategies.contains(MergeStrategy.squash))
            'allowSquash': true,
          if (p.allowedStrategies.contains(MergeStrategy.rebase))
            'allowRebase': true,
          if (p.allowedStrategies.contains(MergeStrategy.rebaseMerge))
            'allowRebaseMerge': true,
          if (p.minimumApproverCount > 0)
            'minimumApproverCount': p.minimumApproverCount,
          if (p.creatorVoteCounts) 'creatorVoteCounts': true,
          if (p.requiredReviewerIds.isNotEmpty)
            'requiredReviewerIds': p.requiredReviewerIds,
        },
      },
  ];

  /// The web's rule for offering auto-complete at all: without a blocking
  /// policy the service merges the moment it is set (research/22 §1).
  bool get hasBlocking => policies.any((p) => p.isBlocking);

  /// The strategies the target allows: the intersection of every blocking
  /// "Require a merge strategy" policy, and all four when there is none.
  /// A strategy the policy forbids is still accepted by `PATCH` and then
  /// evaluated as rejected, so the filtering has to happen here.
  Set<MergeStrategy> get allowedStrategies {
    Set<MergeStrategy>? allowed;
    for (final p in policies) {
      if (!p.isBlocking || !p.isMergeStrategy) continue;
      allowed = allowed == null
          ? {...p.allowedStrategies}
          : allowed.intersection(p.allowedStrategies);
    }
    return allowed ?? MergeStrategy.values.toSet();
  }

  /// The highest minimum approver count any blocking policy asks for.
  int get minimumApproverCount => policies
      .where((p) => p.isBlocking && p.isMinimumReviewers)
      .fold(
        0,
        (a, p) => p.minimumApproverCount > a ? p.minimumApproverCount : a,
      );

  bool get creatorVoteCounts => policies.any(
    (p) => p.isBlocking && p.isMinimumReviewers && p.creatorVoteCounts,
  );

  /// Identity ids every blocking "Required reviewers" policy names, in the
  /// order they were read and without repeats.
  List<String> get requiredReviewerIds {
    final out = <String>[];
    for (final p in policies) {
      if (!p.isRequiredReviewers) continue;
      for (final id in p.requiredReviewerIds) {
        if (!out.contains(id)) out.add(id);
      }
    }
    return out;
  }

  @override
  List<Object?> get props => [policies];
}
