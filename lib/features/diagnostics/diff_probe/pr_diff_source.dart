import '../../../core/http/ado_client.dart';

/// Read-only access to what the diff viewer needs from a pull request:
/// iterations, changed files, file content at a commit, and threads read for
/// the iteration pair on screen (research/00 §6a).
class PrRef {
  const PrRef({
    required this.org,
    required this.id,
    required this.projectId,
    required this.repositoryId,
    required this.title,
    required this.sourceBranch,
    required this.targetBranch,
  });

  final String org;
  final int id;
  final String projectId;
  final String repositoryId;
  final String title;
  final String sourceBranch;
  final String targetBranch;
}

class PrIteration {
  const PrIteration({
    required this.id,
    required this.sourceCommit,
    required this.commonCommit,
    required this.description,
  });

  final int id;
  final String sourceCommit;

  /// Merge base with the target branch; the "old" side of the full PR diff.
  final String commonCommit;
  final String description;
}

class PrFileChange {
  const PrFileChange({
    required this.path,
    required this.changeType,
    required this.changeTrackingId,
    this.originalPath,
  });

  final String path;
  final String changeType;
  final int changeTrackingId;
  final String? originalPath;

  bool get isAdd => changeType.contains('add');
  bool get isDelete => changeType.contains('delete');
}

class PrComment {
  const PrComment({required this.author, required this.content});

  final String author;
  final String content;
}

class PrThread {
  const PrThread({
    required this.id,
    required this.status,
    required this.filePath,
    required this.rightLine,
    required this.leftLine,
    required this.comments,
    required this.trackedFromLine,
  });

  final int id;
  final String status;
  final String? filePath;
  final int? rightLine;
  final int? leftLine;
  final List<PrComment> comments;

  /// Line the thread was posted on, when the service moved it.
  final int? trackedFromLine;
}

class PrDiffSource {
  PrDiffSource(this._client);

  final AdoClient _client;

  Future<PrRef> pullRequest(String org, int id) async {
    final json = await _client.getJson(
      org: org,
      path: '_apis/git/pullrequests/$id',
      apiVersion: '7.1',
    );
    final repo = json['repository'] as Map<String, dynamic>;
    return PrRef(
      org: org,
      id: id,
      projectId: (repo['project'] as Map<String, dynamic>)['id'] as String,
      repositoryId: repo['id'] as String,
      title: json['title'] as String? ?? '',
      sourceBranch: json['sourceRefName'] as String? ?? '',
      targetBranch: json['targetRefName'] as String? ?? '',
    );
  }

  String _prPath(PrRef pr, String tail) =>
      '_apis/git/repositories/${pr.repositoryId}/pullRequests/${pr.id}/$tail';

  Future<List<PrIteration>> iterations(PrRef pr) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: _prPath(pr, 'iterations'),
      apiVersion: '7.1',
    );
    final value = (json['value'] as List?) ?? const [];
    return [
      for (final it in value.cast<Map<String, dynamic>>())
        PrIteration(
          id: it['id'] as int,
          sourceCommit:
              (it['sourceRefCommit'] as Map<String, dynamic>)['commitId']
                  as String,
          commonCommit:
              (it['commonRefCommit'] as Map<String, dynamic>)['commitId']
                  as String,
          description: it['description'] as String? ?? '',
        ),
    ];
  }

  Future<List<PrFileChange>> changes(PrRef pr, int iteration) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: _prPath(pr, 'iterations/$iteration/changes'),
      apiVersion: '7.1',
      query: {r'$top': '2000'},
    );
    final entries = (json['changeEntries'] as List?) ?? const [];
    return [
      for (final e in entries.cast<Map<String, dynamic>>())
        if (((e['item'] as Map<String, dynamic>?)?['gitObjectType'] ??
                'blob') ==
            'blob')
          PrFileChange(
            path: (e['item'] as Map<String, dynamic>)['path'] as String,
            changeType: e['changeType'] as String? ?? '',
            changeTrackingId: e['changeTrackingId'] as int? ?? 0,
            originalPath: e['originalPath'] as String?,
          ),
    ];
  }

  /// File content at a commit through the Items API (JSON with content).
  Future<String> fileAt(PrRef pr, String path, String commit) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: '_apis/git/repositories/${pr.repositoryId}/items',
      apiVersion: '7.1',
      query: {
        'path': path,
        'versionDescriptor.version': commit,
        'versionDescriptor.versionType': 'commit',
        'includeContent': 'true',
      },
    );
    return json['content'] as String? ?? '';
  }

  /// Threads positioned for the diff between [baseIteration] and
  /// [iteration], which is the only read whose line numbers match what is
  /// on screen.
  Future<List<PrThread>> threads(
    PrRef pr, {
    required int iteration,
    required int baseIteration,
  }) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: _prPath(pr, 'threads'),
      apiVersion: '7.1',
      query: {
        r'$iteration': '$iteration',
        r'$baseIteration': '$baseIteration',
      },
    );
    final value = (json['value'] as List?) ?? const [];
    final out = <PrThread>[];
    for (final t in value.cast<Map<String, dynamic>>()) {
      if (t['isDeleted'] == true) continue;
      final ctx = t['threadContext'] as Map<String, dynamic>?;
      final comments = ((t['comments'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .where((c) => c['isDeleted'] != true && c['commentType'] != 'system')
          .map(
            (c) => PrComment(
              author:
                  ((c['author'] as Map<String, dynamic>?)?['displayName']
                      as String?) ??
                  '?',
              content: c['content'] as String? ?? '',
            ),
          )
          .toList();
      if (comments.isEmpty) continue;
      final tracking =
          (t['pullRequestThreadContext'] as Map<String, dynamic>?)
                  ?['trackingCriteria']
              as Map<String, dynamic>?;
      out.add(
        PrThread(
          id: t['id'] as int,
          status: t['status'] as String? ?? 'unknown',
          filePath: ctx?['filePath'] as String?,
          rightLine:
              (ctx?['rightFileStart'] as Map<String, dynamic>?)?['line']
                  as int?,
          leftLine:
              (ctx?['leftFileStart'] as Map<String, dynamic>?)?['line']
                  as int?,
          comments: comments,
          trackedFromLine:
              (tracking?['origRightFileStart'] as Map<String, dynamic>?)?['line']
                  as int?,
        ),
      );
    }
    return out;
  }
}
