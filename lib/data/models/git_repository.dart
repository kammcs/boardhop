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

/// One entry of a folder listing or a single file from the Items API.
/// Listings (`recursionLevel=OneLevel`) carry no content metadata; a
/// single-item read with `includeContentMetadata=true` fills [isBinary],
/// [isImage], [contentType] and [encoding].
class GitItem extends Equatable {
  const GitItem({
    required this.path,
    required this.isFolder,
    this.objectId,
    this.commitId,
    this.isBinary,
    this.isImage,
    this.contentType,
    this.encoding,
  });

  factory GitItem.fromJson(Map<String, dynamic> json) {
    final meta = json['contentMetadata'];
    final m = meta is Map ? meta.cast<String, dynamic>() : null;
    return GitItem(
      path: json['path'] as String? ?? '/',
      isFolder: json['isFolder'] == true || json['gitObjectType'] == 'tree',
      objectId: json['objectId'] as String?,
      commitId: json['commitId'] as String?,
      isBinary: m == null ? null : m['isBinary'] == true,
      isImage: m == null ? null : m['isImage'] == true,
      contentType: m?['contentType'] as String?,
      encoding: (m?['encoding'] as num?)?.toInt(),
    );
  }

  final String path;
  final bool isFolder;
  final String? objectId;
  final String? commitId;
  final bool? isBinary;
  final bool? isImage;
  final String? contentType;
  final int? encoding;

  /// `main.dart` for `/lib/main.dart`; the repository name is the root.
  String get name {
    final p = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  /// Lower-case extension without the dot, or empty.
  String get extension {
    final n = name;
    final dot = n.lastIndexOf('.');
    return dot <= 0 ? '' : n.substring(dot + 1).toLowerCase();
  }

  /// Folders first, then files, each alphabetically and case-insensitive,
  /// which is how the web and every desktop client order a tree.
  static int compare(GitItem a, GitItem b) {
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  @override
  List<Object?> get props => [path, objectId];
}

/// Path helpers for repository paths (`/`-rooted, no trailing slash).
abstract final class RepoPaths {
  /// Parent of [path]; `/` for a top-level entry and for the root.
  static String parent(String path) {
    final p = normalize(path);
    if (p == '/') return '/';
    final i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.substring(0, i);
  }

  /// Always starts with `/`, never ends with one (except the root).
  static String normalize(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// Segments of [path] for a breadcrumb: `/a/b` → `[a, b]`.
  static List<String> segments(String path) =>
      normalize(path).split('/').where((s) => s.isNotEmpty).toList();

  /// Path made of the first [count] segments of [path].
  static String prefix(String path, int count) {
    final segs = segments(path).take(count);
    return segs.isEmpty ? '/' : '/${segs.join('/')}';
  }

  /// Resolves a Markdown-style relative link against the folder holding
  /// [from]: `./x`, `../x`, `x` and `/x` all become repository paths.
  /// Returns null for links with a scheme or an empty target.
  static String? resolve(String from, String href) {
    var h = href.trim();
    final hash = h.indexOf('#');
    if (hash >= 0) h = h.substring(0, hash);
    final q = h.indexOf('?');
    if (q >= 0) h = h.substring(0, q);
    if (h.isEmpty || Uri.tryParse(h)?.hasScheme == true) return null;
    final base = h.startsWith('/') ? const <String>[] : segments(parent(from));
    final out = List<String>.of(base);
    for (final seg in h.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(Uri.decodeComponent(seg));
    }
    return out.isEmpty ? '/' : '/${out.join('/')}';
  }
}

/// Web links matching what the browser shows, for "Open in browser" and
/// "Copy link".
abstract final class RepoWebUrls {
  static String? folder(GitRepository repo, String path, String ref) =>
      _item(repo, path, ref);

  static String? file(GitRepository repo, String path, String ref) =>
      _item(repo, path, ref);

  static String? _item(GitRepository repo, String path, String ref) {
    final base = repo.webUrl;
    if (base == null) return null;
    final p = RepoPaths.normalize(path);
    return '$base?path=${Uri.encodeQueryComponent(p)}'
        '&version=GB${Uri.encodeQueryComponent(ref)}';
  }

  static String? commit(GitRepository repo, String commitId) {
    final base = repo.webUrl;
    return base == null ? null : '$base/commit/$commitId';
  }
}

/// How a ref string maps to an Items/Commits `versionDescriptor`: a 40-hex
/// string is a commit, `refs/tags/x` a tag, anything else a branch name.
abstract final class GitVersion {
  static final _sha = RegExp(r'^[0-9a-f]{40}$');

  static Map<String, String> query(
    String ref, {
    String prefix = 'versionDescriptor',
  }) {
    if (_sha.hasMatch(ref)) {
      return {'$prefix.version': ref, '$prefix.versionType': 'commit'};
    }
    if (ref.startsWith('refs/tags/')) {
      return {
        '$prefix.version': ref.substring('refs/tags/'.length),
        '$prefix.versionType': 'tag',
      };
    }
    return {'$prefix.version': ref, '$prefix.versionType': 'branch'};
  }

  static bool isCommit(String ref) => _sha.hasMatch(ref);

  /// `main`, `v1.2` or `a1b2c3d` for display.
  static String label(String ref) => isCommit(ref)
      ? ref.substring(0, 7)
      : (GitRepository.shortRef(ref) ?? ref);
}

/// One commit from the Commits API (list, single, batch).
class GitCommit extends Equatable {
  const GitCommit({
    required this.id,
    required this.comment,
    this.commentTruncated = false,
    this.authorName,
    this.authorEmail,
    this.authorDate,
    this.committerName,
    this.committerDate,
    this.parents = const [],
    this.added,
    this.edited,
    this.deleted,
    this.workItemIds = const [],
    this.remoteUrl,
  });

  factory GitCommit.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final committer = json['committer'];
    final counts = json['changeCounts'];
    final work = json['workItems'];
    return GitCommit(
      id: json['commitId'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      commentTruncated: json['commentTruncated'] == true,
      authorName: author is Map ? author['name'] as String? : null,
      authorEmail: author is Map ? author['email'] as String? : null,
      authorDate: author is Map
          ? DateTime.tryParse(author['date'] as String? ?? '')
          : null,
      committerName: committer is Map ? committer['name'] as String? : null,
      committerDate: committer is Map
          ? DateTime.tryParse(committer['date'] as String? ?? '')
          : null,
      parents: [
        for (final p in (json['parents'] as List?) ?? const []) p.toString(),
      ],
      added: counts is Map ? (counts['Add'] as num?)?.toInt() : null,
      edited: counts is Map ? (counts['Edit'] as num?)?.toInt() : null,
      deleted: counts is Map ? (counts['Delete'] as num?)?.toInt() : null,
      workItemIds: [
        for (final w in (work is List ? work : const []))
          if (w is Map && int.tryParse('${w['id']}') != null)
            int.parse('${w['id']}'),
      ],
      remoteUrl: json['remoteUrl'] as String?,
    );
  }

  final String id;
  final String comment;
  final bool commentTruncated;
  final String? authorName;
  final String? authorEmail;
  final DateTime? authorDate;
  final String? committerName;
  final DateTime? committerDate;
  final List<String> parents;
  final int? added;
  final int? edited;
  final int? deleted;
  final List<int> workItemIds;
  final String? remoteUrl;

  String get shortId => id.length > 7 ? id.substring(0, 7) : id;

  /// First line of the message.
  String get subject {
    final nl = comment.indexOf('\n');
    return (nl < 0 ? comment : comment.substring(0, nl)).trim();
  }

  /// Everything after the first line, trimmed; empty for one-liners.
  String get body {
    final nl = comment.indexOf('\n');
    return nl < 0 ? '' : comment.substring(nl + 1).trim();
  }

  bool get isMerge => parents.length > 1;

  bool get hasCounts => added != null || edited != null || deleted != null;

  @override
  List<Object?> get props => [id];
}

/// One changed path of a commit or of a branch comparison.
class GitChange extends Equatable {
  const GitChange({
    required this.path,
    required this.changeType,
    required this.isFolder,
    this.originalPath,
    this.objectId,
    this.originalObjectId,
  });

  factory GitChange.fromJson(Map<String, dynamic> json) {
    final item = json['item'];
    final m = item is Map
        ? item.cast<String, dynamic>()
        : const <String, dynamic>{};
    return GitChange(
      path: m['path'] as String? ?? '',
      changeType: json['changeType'] as String? ?? 'edit',
      isFolder: m['isFolder'] == true || m['gitObjectType'] == 'tree',
      originalPath: json['sourceServerItem'] as String?,
      objectId: m['objectId'] as String?,
      originalObjectId: m['originalObjectId'] as String?,
    );
  }

  final String path;

  /// `add`, `edit`, `delete`, `rename`, `edit, rename`, …
  final String changeType;
  final bool isFolder;
  final String? originalPath;
  final String? objectId;
  final String? originalObjectId;

  bool get isAdd => changeType.contains('add');
  bool get isDelete => changeType.contains('delete');
  bool get isRename => changeType.contains('rename');

  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  @override
  List<Object?> get props => [path, changeType];
}

/// A tag with the commit it points at (annotated tags are peeled).
class GitTag extends Equatable {
  const GitTag({
    required this.name,
    required this.commitId,
    this.creatorName,
    this.isAnnotated = false,
  });

  factory GitTag.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'];
    final peeled = json['peeledObjectId'] as String?;
    return GitTag(
      name: GitRepository.shortRef(json['name'] as String? ?? '') ?? '',
      commitId: peeled ?? json['objectId'] as String? ?? '',
      creatorName: creator is Map ? creator['displayName'] as String? : null,
      isAnnotated: peeled != null,
    );
  }

  final String name;
  final String commitId;
  final String? creatorName;
  final bool isAnnotated;

  String get ref => 'refs/tags/$name';

  @override
  List<Object?> get props => [name, commitId];
}

/// `diffs/commits` between two versions: standing plus the changed paths.
class GitCompare extends Equatable {
  const GitCompare({
    required this.aheadCount,
    required this.behindCount,
    required this.commonCommit,
    required this.baseCommit,
    required this.targetCommit,
    required this.changes,
    required this.allChangesIncluded,
  });

  factory GitCompare.fromJson(Map<String, dynamic> json) => GitCompare(
    aheadCount: (json['aheadCount'] as num?)?.toInt() ?? 0,
    behindCount: (json['behindCount'] as num?)?.toInt() ?? 0,
    commonCommit: json['commonCommit'] as String? ?? '',
    baseCommit: json['baseCommit'] as String? ?? '',
    targetCommit: json['targetCommit'] as String? ?? '',
    changes: [
      for (final c in (json['changes'] as List?) ?? const [])
        if (c is Map) GitChange.fromJson(c.cast<String, dynamic>()),
    ],
    allChangesIncluded: json['allChangesIncluded'] != false,
  );

  final int aheadCount;
  final int behindCount;
  final String commonCommit;
  final String baseCommit;
  final String targetCommit;
  final List<GitChange> changes;
  final bool allChangesIncluded;

  List<GitChange> get files => changes.where((c) => !c.isFolder).toList();

  @override
  List<Object?> get props => [commonCommit, targetCommit, changes.length];
}

/// One hit of the code search service. The service returns no snippets
/// (spike s17), only where the term occurs and how many times.
class CodeSearchHit extends Equatable {
  const CodeSearchHit({
    required this.fileName,
    required this.path,
    required this.repositoryName,
    required this.repositoryId,
    required this.projectName,
    this.branch,
    this.contentMatches = 0,
    this.fileNameMatches = 0,
  });

  factory CodeSearchHit.fromJson(Map<String, dynamic> json) {
    final repo = json['repository'];
    final project = json['project'];
    final versions = json['versions'];
    final matches = json['matches'];
    int count(Object? v) => v is List ? v.length : (v as num?)?.toInt() ?? 0;
    String? branch;
    if (versions is List && versions.isNotEmpty && versions.first is Map) {
      branch = (versions.first as Map)['branchName'] as String?;
    }
    return CodeSearchHit(
      fileName: json['fileName'] as String? ?? '',
      path: json['path'] as String? ?? '',
      repositoryName: repo is Map ? repo['name'] as String? ?? '' : '',
      repositoryId: repo is Map ? repo['id'] as String? ?? '' : '',
      projectName: project is Map ? project['name'] as String? ?? '' : '',
      branch: branch,
      contentMatches: matches is Map ? count(matches['content']) : 0,
      fileNameMatches: matches is Map ? count(matches['fileName']) : 0,
    );
  }

  final String fileName;
  final String path;
  final String repositoryName;
  final String repositoryId;
  final String projectName;
  final String? branch;
  final int contentMatches;
  final int fileNameMatches;

  /// Folder of the hit without the file name.
  String get folder => RepoPaths.parent(path);

  @override
  List<Object?> get props => [repositoryId, path, branch];
}

/// A page of code search results with the service's status code.
class CodeSearchResults extends Equatable {
  const CodeSearchResults({
    required this.count,
    required this.hits,
    required this.infoCode,
  });

  factory CodeSearchResults.fromJson(Map<String, dynamic> json) =>
      CodeSearchResults(
        count: (json['count'] as num?)?.toInt() ?? 0,
        hits: [
          for (final r in (json['results'] as List?) ?? const [])
            if (r is Map) CodeSearchHit.fromJson(r.cast<String, dynamic>()),
        ],
        infoCode: (json['infoCode'] as num?)?.toInt() ?? 0,
      );

  final int count;
  final List<CodeSearchHit> hits;
  final int infoCode;

  /// Plain-language reason when the service could not run the search.
  String? get problem => switch (infoCode) {
    0 => null,
    1 || 6 || 7 || 12 =>
      'The code index for this organization is still being built. '
          'Try again in a while.',
    2 => 'Code search has not started indexing this organization yet.',
    3 => 'That query is not valid for code search.',
    4 => 'A wildcard cannot start a term.',
    5 => 'Multiple words are not supported with a code facet.',
    _ => 'Code search returned status $infoCode.',
  };

  @override
  List<Object?> get props => [count, hits, infoCode];
}
