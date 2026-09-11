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
    this.uniqueName,
    this.imageUrl,
    this.descriptor,
  });

  factory PrReviewer.fromJson(Map<String, dynamic> json) => PrReviewer(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    vote: PrVote.fromValue((json['vote'] as num?)?.toInt()),
    isRequired: json['isRequired'] as bool? ?? false,
    isContainer: json['isContainer'] as bool? ?? false,
    hasDeclined: json['hasDeclined'] as bool? ?? false,
    uniqueName: json['uniqueName'] as String?,
    imageUrl: IdentityRef.fromJson(json).imageUrl,
    descriptor: json['descriptor'] as String?,
  );

  final String id;
  final String displayName;
  final PrVote vote;
  final bool isRequired;
  final bool isContainer;
  final bool hasDeclined;
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

  @override
  List<Object?> get props => [id, vote, isRequired];
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

  @override
  List<Object?> get props => [
    id,
    status,
    title,
    reviewers,
    lastMergeSourceCommit,
  ];
}
