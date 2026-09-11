import 'package:equatable/equatable.dart';

/// A Git repository as `GET {project}/_apis/git/repositories` returns it.
/// Azure DevOps repositories carry no description and no language (spike
/// s17); the language comes from [RepoLanguage] and the project analysis
/// API.
class GitRepository extends Equatable {
  const GitRepository({
    required this.id,
    required this.name,
    required this.projectId,
    required this.projectName,
    this.defaultBranch,
    this.size,
    this.isDisabled = false,
    this.isInMaintenance = false,
    this.isFork = false,
    this.parentRepositoryName,
    this.webUrl,
    this.remoteUrl,
  });

  factory GitRepository.fromJson(Map<String, dynamic> json) {
    final project = json['project'];
    final parent = json['parentRepository'];
    return GitRepository(
      id: json['id'] as String,
      name: json['name'] as String,
      projectId: project is Map ? project['id'] as String? ?? '' : '',
      projectName: project is Map ? project['name'] as String? ?? '' : '',
      defaultBranch: json['defaultBranch'] as String?,
      size: (json['size'] as num?)?.toInt(),
      isDisabled: json['isDisabled'] == true,
      isInMaintenance: json['isInMaintenance'] == true,
      isFork: json['isFork'] == true,
      parentRepositoryName: parent is Map ? parent['name'] as String? : null,
      webUrl: json['webUrl'] as String?,
      remoteUrl: json['remoteUrl'] as String?,
    );
  }

  final String id;
  final String name;
  final String projectId;
  final String projectName;

  /// Full ref (`refs/heads/main`); null for an empty repository.
  final String? defaultBranch;
  final int? size;
  final bool isDisabled;
  final bool isInMaintenance;
  final bool isFork;
  final String? parentRepositoryName;
  final String? webUrl;
  final String? remoteUrl;

  /// `main` for `refs/heads/main`; null for an empty repository.
  String? get defaultBranchName => shortRef(defaultBranch);

  bool get isEmpty => defaultBranch == null;

  /// Usable for browsing: neither disabled nor in maintenance.
  bool get isActive => !isDisabled && !isInMaintenance;

  static String? shortRef(String? ref) {
    if (ref == null) return null;
    for (final prefix in const ['refs/heads/', 'refs/tags/']) {
      if (ref.startsWith(prefix)) return ref.substring(prefix.length);
    }
    return ref;
  }

  @override
  List<Object?> get props => [id];
}

/// One language of a repository's breakdown from
/// `projectanalysis/languagemetrics`, biggest share first.
class RepoLanguage extends Equatable {
  const RepoLanguage({required this.name, required this.percentage});

  factory RepoLanguage.fromJson(Map<String, dynamic> json) => RepoLanguage(
    name: json['name'] as String? ?? '',
    percentage: (json['filesPercentage'] as num?)?.toDouble() ?? 0,
  );

  final String name;
  final double percentage;

  /// Real languages only: the service also lists extensions such as
  /// `.lock` or `.editorconfig` and an `Unknown` bucket.
  bool get isLanguage =>
      name.isNotEmpty && !name.startsWith('.') && name != 'Unknown';

  @override
  List<Object?> get props => [name, percentage];
}

/// A branch with its standing against the default branch, from
/// `stats/branches`.
class GitBranch extends Equatable {
  const GitBranch({
    required this.name,
    required this.aheadCount,
    required this.behindCount,
    required this.isDefault,
    this.commitId,
    this.authorName,
    this.date,
    this.comment,
  });

  /// [defaultBranch] is the repository's default branch name; the service's
  /// `isBaseVersion` is also true for any branch at the same commit, so it
  /// cannot mark the default on its own.
  factory GitBranch.fromJson(
    Map<String, dynamic> json, {
    String? defaultBranch,
  }) {
    final commit = json['commit'];
    final author = commit is Map ? commit['author'] : null;
    final name = json['name'] as String? ?? '';
    return GitBranch(
      name: name,
      aheadCount: (json['aheadCount'] as num?)?.toInt() ?? 0,
      behindCount: (json['behindCount'] as num?)?.toInt() ?? 0,
      isDefault: defaultBranch == null
          ? json['isBaseVersion'] == true
          : name == defaultBranch,
      commitId: commit is Map ? commit['commitId'] as String? : null,
      authorName: author is Map ? author['name'] as String? : null,
      date: author is Map
          ? DateTime.tryParse(author['date'] as String? ?? '')
          : null,
      comment: commit is Map ? commit['comment'] as String? : null,
    );
  }

  final String name;
  final int aheadCount;
  final int behindCount;
  final bool isDefault;
  final String? commitId;
  final String? authorName;
  final DateTime? date;
  final String? comment;

  /// First line of the tip commit's message.
  String get subject {
    final c = comment ?? '';
    final nl = c.indexOf('\n');
    return (nl < 0 ? c : c.substring(0, nl)).trim();
  }

  @override
  List<Object?> get props => [name, commitId];
}
